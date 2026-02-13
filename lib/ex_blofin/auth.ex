defmodule ExBlofin.Auth do
  @moduledoc """
  Req plugin for BloFin HMAC-SHA256 authentication.

  Automatically generates and attaches authentication headers to each request
  as required by the BloFin API.

  ## Headers

  All private requests require these headers:

    - `ACCESS-KEY` - API key
    - `ACCESS-SIGN` - Base64-encoded HMAC-SHA256 signature
    - `ACCESS-TIMESTAMP` - ISO 8601 UTC timestamp with milliseconds
    - `ACCESS-NONCE` - Unique identifier (random hex)
    - `ACCESS-PASSPHRASE` - API key passphrase

  ## Signature Algorithm

  1. Build pre-hash string: `requestPath + METHOD + timestamp + nonce + body`
  2. Compute HMAC-SHA256 with secret key
  3. Hex-encode the result
  4. Base64-encode the hex string

  ## Usage

  Typically used via `ExBlofin.Client.new/4`, but can be attached manually:

      Req.new(base_url: "https://openapi.blofin.com")
      |> ExBlofin.Auth.attach("api_key", "secret_key", "passphrase")
  """

  @doc """
  Attaches HMAC-SHA256 authentication to a Req request.
  """
  @spec attach(Req.Request.t(), String.t() | nil, String.t() | nil, String.t() | nil) ::
          Req.Request.t()
  def attach(request, api_key, secret_key, passphrase) do
    request
    |> Req.Request.register_options([:blofin_api_key, :blofin_secret_key, :blofin_passphrase])
    |> Req.Request.merge_options(
      blofin_api_key: api_key,
      blofin_secret_key: secret_key,
      blofin_passphrase: passphrase
    )
    |> Req.Request.append_request_steps(blofin_auth: &sign_request/1)
  end

  @doc """
  Computes the HMAC-SHA256 signature for a given set of parameters.

  Useful for testing and for WebSocket authentication.
  """
  @spec compute_signature(String.t(), String.t(), String.t(), String.t(), String.t()) ::
          String.t()
  def compute_signature(secret_key, path, method, timestamp, nonce, body \\ "") do
    prehash = path <> method <> timestamp <> nonce <> body

    :crypto.mac(:hmac, :sha256, secret_key, prehash)
    |> Base.encode16(case: :lower)
    |> Base.encode64()
  end

  @doc """
  Computes the WebSocket login signature.

  Uses the fixed path `/users/self/verify` with `GET` method.
  """
  @spec compute_ws_signature(String.t(), String.t(), String.t()) :: String.t()
  def compute_ws_signature(secret_key, timestamp, nonce) do
    compute_signature(secret_key, "/users/self/verify", "GET", timestamp, nonce)
  end

  @doc """
  Generates a timestamp in ISO 8601 format with milliseconds.
  """
  @spec generate_timestamp() :: String.t()
  def generate_timestamp do
    DateTime.utc_now()
    |> DateTime.to_iso8601(:extended)
  end

  @doc """
  Generates a random nonce (32-character hex string).
  """
  @spec generate_nonce() :: String.t()
  def generate_nonce do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp sign_request(request) do
    api_key = request.options[:blofin_api_key]
    secret_key = request.options[:blofin_secret_key]
    passphrase = request.options[:blofin_passphrase]

    if api_key && secret_key && passphrase do
      method = request.method |> Atom.to_string() |> String.upcase()
      path = extract_path(request)
      timestamp = generate_timestamp()
      nonce = generate_nonce()
      body = extract_body(request)

      sign = compute_signature(secret_key, path, method, timestamp, nonce, body)

      request
      |> Req.Request.put_header("ACCESS-KEY", api_key)
      |> Req.Request.put_header("ACCESS-SIGN", sign)
      |> Req.Request.put_header("ACCESS-TIMESTAMP", timestamp)
      |> Req.Request.put_header("ACCESS-NONCE", nonce)
      |> Req.Request.put_header("ACCESS-PASSPHRASE", passphrase)
    else
      request
    end
  end

  defp extract_path(request) do
    case request.url do
      %URI{path: path} when is_binary(path) -> path
      _ -> "/"
    end
  end

  defp extract_body(%{body: nil}), do: ""
  defp extract_body(%{body: ""}), do: ""
  defp extract_body(%{body: body}) when is_binary(body), do: body

  defp extract_body(%{body: {:json, data}}) when is_map(data) or is_list(data),
    do: Jason.encode!(data)

  defp extract_body(_), do: ""
end
