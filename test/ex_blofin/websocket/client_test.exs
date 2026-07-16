defmodule ExBlofin.WebSocket.ClientTest do
  use ExUnit.Case, async: true

  alias ExBlofin.WebSocket.Client

  describe "reconnect_delay/2" do
    test "backs off exponentially from 1s" do
      assert Client.reconnect_delay(:remote_closed, 1) == 1_000
      assert Client.reconnect_delay(:remote_closed, 2) == 2_000
      assert Client.reconnect_delay(:remote_closed, 3) == 4_000
      assert Client.reconnect_delay(:remote_closed, 5) == 16_000
    end

    test "caps at 30s regardless of attempt count" do
      assert Client.reconnect_delay(:remote_closed, 6) == 30_000
      assert Client.reconnect_delay(:remote_closed, 50) == 30_000
    end

    test "rate-limit responses (429) never retry faster than 10s" do
      rate_limited = %WebSockex.RequestError{code: 429, message: "Too Many Requests"}

      assert Client.reconnect_delay(rate_limited, 1) == 10_000
      assert Client.reconnect_delay(rate_limited, 4) == 10_000
      # Once exponential exceeds the floor, it takes over (still capped).
      assert Client.reconnect_delay(rate_limited, 5) == 16_000
      assert Client.reconnect_delay(rate_limited, 10) == 30_000
    end

    test "other HTTP errors use the plain exponential curve" do
      server_error = %WebSockex.RequestError{code: 500, message: "Internal Server Error"}

      assert Client.reconnect_delay(server_error, 1) == 1_000
    end
  end
end
