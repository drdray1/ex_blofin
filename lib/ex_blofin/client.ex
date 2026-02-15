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
  """

  @type client :: Req.Request.t()
  @type response :: {:ok, term()} | {:error, term()}

  @doc """
  Creates a new BloFin API client with HMAC-SHA256 authentication.

  ## Parameters

    - `api_key` - BloFin API key (nil for public-only endpoints)
    - `secret_key` - BloFin secret key (nil for public-only endpoints)
    - `passphrase` - BloFin API passphrase (nil for public-only endpoints)

  ## Options

    - `:demo` - Use demo trading environment (default: false)
    - `:plug` - Test plug for `Req.Test` (default: nil)

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

    http_config = Application.fetch_env!(:ex_blofin, :http)
    max_retries = Keyword.fetch!(http_config, :max_retries)
    retry_base_delay_ms = Keyword.fetch!(http_config, :retry_base_delay_ms)

    req_opts =
      [
        base_url: base_url(demo),
        headers: [{"content-type", "application/json"}],
        retry: :transient,
        max_retries: max_retries,
        retry_delay: fn attempt -> retry_base_delay_ms * Integer.pow(2, attempt) end
      ]
      |> maybe_add_plug(plug)

    Req.new(req_opts)
    |> ExBlofin.Auth.attach(api_key, secret_key, passphrase)
  end

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
