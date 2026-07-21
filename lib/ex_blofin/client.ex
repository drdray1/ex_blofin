defmodule ExBlofin.Client do
  @moduledoc """
  HTTP client for the BloFin API.

  Handles HMAC-SHA256 authentication and request/response formatting.
  All private requests are signed using the API key, secret key, and passphrase.

  ## Usage

      client = ExBlofin.Client.new("api_key", "secret_key", "passphrase")
      {:ok, data} = ExBlofin.MarketData.get_instruments(client)

      # Demo trading mode
      client = ExBlofin.Client.new("api_key", "secret_key", "passphrase", demo: true)

      # Public-only (no auth needed)
      client = ExBlofin.Client.new(nil, nil, nil)

  ## Endpoint path resolution

  Some endpoint paths in the current BloFin docs disagree with the paths this
  library historically used, and BloFin returns HTTP 401 for every unrouted
  path, so the live spelling cannot be determined from the outside. `get/3`
  therefore resolves such paths at runtime:

    - The documented path is tried first.
    - If it responds 401, 404, or 405 — the only statuses that can indicate an
      unrouted path — the legacy path from `ExBlofin.Paths` is tried.
    - The fallback result is used **only** if it is a definitive success (HTTP
      2xx with `"code" => "0"`). Otherwise the original response is returned
      unchanged, so bad credentials still surface as `{:error, :unauthorized}`
      rather than a confusing fallback error.
    - The winner is cached per `{base_url, path}`, so the probe costs one extra
      request per diverging path per node, not per call.

  Successful fallbacks emit a `Logger.warning` naming both paths. Once you know
  which spelling your account is served, pin it and skip probing entirely:

      config :ex_blofin, api_path_mode: :documented   # or :legacy

  Per-client opt-out: `ExBlofin.Client.new(k, s, p, path_fallback: false)`.
  """

  require Logger

  alias ExBlofin.Paths

  @type client :: Req.Request.t()
  @type response :: {:ok, term()} | {:error, term()}

  @path_cache :ex_blofin_path_cache

  # Statuses that can mean "this route does not exist". 401 is included because
  # it is BloFin's catch-all for unrouted paths; the definitive-success rule in
  # `fallback/4` is what keeps genuine auth failures from being masked.
  @unrouted_statuses [401, 404, 405]

  @doc """
  Creates a new BloFin API client with HMAC-SHA256 authentication.

  ## Parameters

    - `api_key` - BloFin API key (nil for public-only endpoints)
    - `secret_key` - BloFin secret key (nil for public-only endpoints)
    - `passphrase` - BloFin API passphrase (nil for public-only endpoints)

  ## Options

    - `:demo` - Use demo trading environment (default: false)
    - `:plug` - Test plug for `Req.Test` (default: nil)
    - `:path_fallback` - Try the legacy path when a documented path appears
      unrouted (default: true). See the module docs.
    - `:path_cache` - Force path-resolution caching on or off. Defaults to
      automatic: on, except when `:plug` is set, so `Req.Test`-based tests stay
      isolated. Mainly a testing seam.

  ## Examples

      client = ExBlofin.Client.new("api_key", "secret_key", "passphrase")

      # Demo trading mode
      client = ExBlofin.Client.new("api_key", "secret_key", "passphrase", demo: true)

      # Testing with Req.Test
      client = ExBlofin.Client.new("key", "secret", "pass", plug: {Req.Test, MyStub})
  """
  @spec new(String.t() | nil, String.t() | nil, String.t() | nil, keyword()) :: client()
  def new(api_key, secret_key, passphrase, opts \\ []) do
    demo = Keyword.get(opts, :demo, false)
    plug = Keyword.get(opts, :plug)

    req_opts =
      [
        base_url: base_url(demo),
        headers: [{"content-type", "application/json"}],
        retry: :transient,
        max_retries: 3,
        retry_delay: fn attempt -> 500 * Integer.pow(2, attempt) end
      ]
      |> maybe_add_plug(plug)

    Req.new(req_opts)
    |> Req.Request.register_options([:blofin_path_fallback, :blofin_path_cache])
    |> Req.Request.merge_options(
      blofin_path_fallback: Keyword.get(opts, :path_fallback, true),
      blofin_path_cache: Keyword.get(opts, :path_cache)
    )
    |> ExBlofin.Auth.attach(api_key, secret_key, passphrase)
  end

  @doc """
  Issues a GET request, resolving documented/legacy path divergences.

  Drop-in replacement for `Req.get(client, url: path, ...)` that adds the
  fallback behaviour described in the module docs. Paths with no alias in
  `ExBlofin.Paths` are dispatched directly with no extra work.

  Returns the raw `Req` result; pipe into `handle_response/1` as usual.

      client
      |> ExBlofin.Client.get("/api/v1/trade/orders-history", params: params)
      |> ExBlofin.Client.handle_response()
  """
  @spec get(client(), String.t(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def get(client, path, opts \\ []) do
    case resolve(client, path) do
      {:pinned, resolved} ->
        dispatch(client, resolved, opts)

      {:probe, documented, legacy} ->
        result = dispatch(client, documented, opts)

        if unrouted?(result) do
          fallback(client, path, {documented, result}, legacy, opts)
        else
          if definitive_success?(result), do: cache_put(client, path, :documented)
          result
        end
    end
  end

  @doc """
  Creates the ETS table backing path resolution. Called by `ExBlofin.Application`.
  """
  @spec init_path_cache() :: :ok
  def init_path_cache do
    if :ets.whereis(@path_cache) == :undefined do
      :ets.new(@path_cache, [:named_table, :public, :set, read_concurrency: true])
    end

    :ok
  end

  @doc """
  Returns the paths resolved so far, as `%{path => :documented | :legacy}`.

  Empty until a diverging endpoint has been called at least once. Useful for
  confirming which spelling your account is served before pinning
  `:api_path_mode`.
  """
  @spec resolved_paths() :: %{String.t() => :documented | :legacy}
  def resolved_paths do
    if :ets.whereis(@path_cache) == :undefined do
      %{}
    else
      @path_cache
      |> :ets.tab2list()
      |> Map.new(fn {{_base_url, path}, verdict} -> {path, verdict} end)
    end
  end

  defp resolve(client, path) do
    legacy = Paths.legacy_for(path)

    cond do
      is_nil(legacy) -> {:pinned, path}
      client.options[:blofin_path_fallback] == false -> {:pinned, path}
      true -> resolve_by_mode(client, path, legacy)
    end
  end

  defp resolve_by_mode(client, path, legacy) do
    case Application.get_env(:ex_blofin, :api_path_mode, :auto) do
      :documented -> {:pinned, path}
      :legacy -> {:pinned, legacy}
      _auto -> resolve_from_cache(client, path, legacy)
    end
  end

  defp resolve_from_cache(client, path, legacy) do
    case cache_get(client, path) do
      :documented -> {:pinned, path}
      :legacy -> {:pinned, legacy}
      nil -> {:probe, path, legacy}
    end
  end

  # The fallback must re-enter through `dispatch/3` rather than rewriting the
  # URL of the already-signed request: `ExBlofin.Auth` signs over
  # `request.url.path`, so a mutated-and-resent request would carry a signature
  # for the documented path while requesting the legacy one — a guaranteed 401
  # that would make this fallback silently useless.
  defp fallback(client, path, {documented, primary_result}, legacy, opts) do
    legacy_result = dispatch(client, legacy, opts)

    if definitive_success?(legacy_result) do
      cache_put(client, path, :legacy)

      Logger.warning("""
      ExBlofin: documented path #{documented} is not routed; \
      using legacy #{legacy}. Pin this to skip the extra request:

          config :ex_blofin, api_path_mode: :legacy
      """)

      legacy_result
    else
      # Error preservation: the legacy attempt told us nothing useful, so the
      # caller sees the original response. Bad credentials stay :unauthorized.
      primary_result
    end
  end

  defp dispatch(client, path, opts), do: Req.get(client, [url: path] ++ opts)

  defp unrouted?({:ok, %Req.Response{status: status}}), do: status in @unrouted_statuses
  defp unrouted?(_), do: false

  defp definitive_success?({:ok, %Req.Response{status: status, body: %{"code" => "0"}}})
       when status in 200..299,
       do: true

  defp definitive_success?(_), do: false

  # Cache is skipped under `:plug` so `Req.Test`-based tests stay deterministic
  # and isolated regardless of execution order. `:path_cache` overrides that
  # either way, which is how the caching itself gets tested.
  defp cache_enabled?(client) do
    table? = :ets.whereis(@path_cache) != :undefined

    case client.options[:blofin_path_cache] do
      true ->
        table?

      false ->
        false

      _auto ->
        is_nil(client.options[:plug]) and
          Application.get_env(:ex_blofin, :cache_resolved_paths, true) and
          table?
    end
  end

  defp cache_get(client, path) do
    if cache_enabled?(client) do
      case :ets.lookup(@path_cache, cache_key(client, path)) do
        [{_key, verdict}] -> verdict
        [] -> nil
      end
    end
  end

  # Only ever called with a definitive outcome. Caching a "both attempts failed"
  # verdict would let one run with a stale API key permanently mis-route a node.
  defp cache_put(client, path, verdict) do
    if cache_enabled?(client) do
      :ets.insert(@path_cache, {cache_key(client, path), verdict})
    end

    :ok
  end

  defp cache_key(client, path), do: {client.options[:base_url], path}

  @doc """
  Returns the base URL based on environment configuration.
  """
  @spec base_url(boolean()) :: String.t()
  def base_url(demo \\ false) do
    config = Application.get_env(:ex_blofin, :config, [])

    if demo do
      Keyword.get(config, :demo_url, "https://demo-trading-openapi.blofin.com")
    else
      Keyword.get(config, :base_url, "https://openapi.blofin.com")
    end
  end

  @doc """
  Returns the public WebSocket URL.
  """
  @spec ws_public_url(boolean()) :: String.t()
  def ws_public_url(demo \\ false) do
    config = Application.get_env(:ex_blofin, :config, [])

    if demo do
      Keyword.get(config, :demo_ws_public_url, "wss://demo-trading-openapi.blofin.com/ws/public")
    else
      Keyword.get(config, :ws_public_url, "wss://openapi.blofin.com/ws/public")
    end
  end

  @doc """
  Returns the private WebSocket URL.
  """
  @spec ws_private_url(boolean()) :: String.t()
  def ws_private_url(demo \\ false) do
    config = Application.get_env(:ex_blofin, :config, [])

    if demo do
      Keyword.get(
        config,
        :demo_ws_private_url,
        "wss://demo-trading-openapi.blofin.com/ws/private"
      )
    else
      Keyword.get(config, :ws_private_url, "wss://openapi.blofin.com/ws/private")
    end
  end

  @doc """
  Returns the copy trading WebSocket URL.
  """
  @spec ws_copy_trading_url() :: String.t()
  def ws_copy_trading_url do
    config = Application.get_env(:ex_blofin, :config, [])

    Keyword.get(
      config,
      :ws_copy_trading_url,
      "wss://openapi.blofin.com/ws/copytrading/private"
    )
  end

  @doc """
  Verifies credentials by testing the API connection.

  Makes a request to `/api/v1/account/config` to validate the API key.
  """
  @spec verify_credentials(String.t(), String.t(), String.t(), boolean()) :: response()
  def verify_credentials(api_key, secret_key, passphrase, demo \\ false) do
    client = new(api_key, secret_key, passphrase, demo: demo)

    case Req.get(client, url: "/api/v1/account/config") do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        case body do
          %{"code" => "0"} -> {:ok, body}
          %{"code" => code, "msg" => msg} -> {:error, {:api_error, code, msg}}
          _ -> {:ok, body}
        end

      {:ok, %Req.Response{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:api_error, status, extract_error_message(body)}}

      {:error, reason} ->
        {:error, {:connection_error, reason}}
    end
  end

  @doc """
  Handles API response and normalizes to standard format.

  BloFin wraps all responses in `{"code": "0", "msg": "", "data": [...]}`.
  On success (code "0"), this unwraps and returns just the `data` field.
  """
  @spec handle_response({:ok, Req.Response.t()} | {:error, term()}) :: response()
  def handle_response({:ok, %Req.Response{status: status, body: body}}) when status in 200..299 do
    case body do
      %{"code" => "0", "data" => data} -> {:ok, data}
      %{"code" => "0"} -> {:ok, body}
      %{"code" => code, "msg" => msg} -> {:error, {:api_error, code, msg}}
      _ -> {:ok, body}
    end
  end

  def handle_response({:ok, %Req.Response{status: 401}}) do
    {:error, :unauthorized}
  end

  def handle_response({:ok, %Req.Response{status: 403}}) do
    {:error, :forbidden}
  end

  def handle_response({:ok, %Req.Response{status: 404}}) do
    {:error, :not_found}
  end

  def handle_response({:ok, %Req.Response{status: 429}}) do
    {:error, :rate_limited}
  end

  def handle_response({:ok, %Req.Response{status: status, body: body}}) when status >= 400 do
    {:error, {:api_error, status, extract_error_message(body)}}
  end

  def handle_response({:error, reason}) do
    {:error, {:connection_error, reason}}
  end

  @doc """
  Performs a health check by validating credentials.
  """
  @spec healthcheck(client()) :: :ok | {:error, term()}
  def healthcheck(client) do
    case Req.get(client, url: "/api/v1/account/config") do
      {:ok, %Req.Response{status: status, body: %{"code" => "0"}}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %Req.Response{status: 403}} ->
        {:error, :forbidden}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec extract_error_message(map() | term()) :: String.t()
  defp extract_error_message(%{"msg" => msg}) when is_binary(msg) and msg != "", do: msg
  defp extract_error_message(%{"message" => message}) when is_binary(message), do: message
  defp extract_error_message(%{"error" => error}) when is_binary(error), do: error
  defp extract_error_message(_), do: "Unknown error"

  defp maybe_add_plug(opts, nil), do: opts
  defp maybe_add_plug(opts, plug), do: Keyword.put(opts, :plug, plug)
end
