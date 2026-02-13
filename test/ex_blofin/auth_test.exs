defmodule ExBlofin.AuthTest do
  use ExUnit.Case, async: true

  alias ExBlofin.Auth

  describe "compute_signature/6" do
    test "produces consistent HMAC-SHA256 signature" do
      secret = "test-secret"
      path = "/api/v1/trade/order"
      method = "POST"
      timestamp = "2024-01-15T10:30:00.000Z"
      nonce = "abc123"
      body = ~s({"instId":"BTC-USDT","side":"buy"})

      sig1 = Auth.compute_signature(secret, path, method, timestamp, nonce, body)
      sig2 = Auth.compute_signature(secret, path, method, timestamp, nonce, body)

      assert sig1 == sig2
      assert is_binary(sig1)
      # Should be base64 encoded
      assert {:ok, _} = Base.decode64(sig1)
    end

    test "different secrets produce different signatures" do
      path = "/api/v1/trade/order"
      method = "POST"
      timestamp = "2024-01-15T10:30:00.000Z"
      nonce = "abc123"
      body = ""

      sig1 = Auth.compute_signature("secret1", path, method, timestamp, nonce, body)
      sig2 = Auth.compute_signature("secret2", path, method, timestamp, nonce, body)

      refute sig1 == sig2
    end

    test "different paths produce different signatures" do
      secret = "test-secret"
      method = "GET"
      timestamp = "2024-01-15T10:30:00.000Z"
      nonce = "abc123"

      sig1 = Auth.compute_signature(secret, "/api/v1/account/balance", method, timestamp, nonce)
      sig2 = Auth.compute_signature(secret, "/api/v1/account/positions", method, timestamp, nonce)

      refute sig1 == sig2
    end

    test "defaults to empty body" do
      secret = "test-secret"
      path = "/api/v1/account/balance"
      method = "GET"
      timestamp = "2024-01-15T10:30:00.000Z"
      nonce = "abc123"

      sig1 = Auth.compute_signature(secret, path, method, timestamp, nonce)
      sig2 = Auth.compute_signature(secret, path, method, timestamp, nonce, "")

      assert sig1 == sig2
    end

    test "prehash is path + method + timestamp + nonce + body" do
      secret = "test-secret"
      path = "/api/v1/trade/order"
      method = "POST"
      timestamp = "2024-01-15T10:30:00.000Z"
      nonce = "abc123"
      body = ~s({"key":"value"})

      # Manually compute expected signature
      prehash = path <> method <> timestamp <> nonce <> body

      expected =
        :crypto.mac(:hmac, :sha256, secret, prehash)
        |> Base.encode16(case: :lower)
        |> Base.encode64()

      actual = Auth.compute_signature(secret, path, method, timestamp, nonce, body)
      assert actual == expected
    end
  end

  describe "compute_ws_signature/3" do
    test "uses fixed path /users/self/verify with GET" do
      secret = "test-secret"
      timestamp = "1697021343571"
      nonce = "abc123"

      ws_sig = Auth.compute_ws_signature(secret, timestamp, nonce)

      # Should be same as computing with the fixed path
      expected = Auth.compute_signature(secret, "/users/self/verify", "GET", timestamp, nonce)
      assert ws_sig == expected
    end
  end

  describe "generate_timestamp/0" do
    test "returns ISO 8601 format" do
      ts = Auth.generate_timestamp()
      assert is_binary(ts)
      # Should be parseable as ISO 8601
      assert {:ok, _dt, _offset} = DateTime.from_iso8601(ts)
    end
  end

  describe "generate_nonce/0" do
    test "returns 32-character hex string" do
      nonce = Auth.generate_nonce()
      assert is_binary(nonce)
      assert String.length(nonce) == 32
      assert Regex.match?(~r/^[0-9a-f]+$/, nonce)
    end

    test "generates unique values" do
      nonce1 = Auth.generate_nonce()
      nonce2 = Auth.generate_nonce()
      refute nonce1 == nonce2
    end
  end

  describe "attach/4" do
    test "returns a Req.Request with auth step" do
      request =
        Req.new(base_url: "https://example.com")
        |> Auth.attach("api_key", "secret", "passphrase")

      assert %Req.Request{} = request
      assert request.options[:blofin_api_key] == "api_key"
      assert request.options[:blofin_secret_key] == "secret"
      assert request.options[:blofin_passphrase] == "passphrase"
    end

    test "skips signing when credentials are nil" do
      request =
        Req.new(base_url: "https://example.com")
        |> Auth.attach(nil, nil, nil)

      assert %Req.Request{} = request
      assert request.options[:blofin_api_key] == nil
    end
  end
end
