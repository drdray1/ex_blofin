defmodule ExBlofin.PathFallbackTest do
  @moduledoc """
  Covers `ExBlofin.Client.get/3`'s documented-path-first resolution.

  `ExBlofin.User.get_api_key_info/1` is used as the subject throughout: it is a
  no-params GET with an entry in `ExBlofin.Paths`, so the assertions stay about
  routing rather than query building.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias ExBlofin.{Auth, Client, Fixtures, User}

  @stub :path_fallback_stub

  @documented "/api/v1/user/query-apikey"
  @legacy "/api/v1/user/api-key-info"

  setup do
    {:ok, calls} = Agent.start_link(fn -> [] end)
    %{calls: calls}
  end

  describe "documented path is live" do
    test "uses it and never probes the legacy path", %{calls: calls} do
      stub_paths(calls, %{@documented => {200, ok_body()}})

      assert {:ok, %{"apiKey" => "test-api-key-123"}} = User.get_api_key_info(client())
      assert paths(calls) == [@documented]
    end
  end

  describe "documented path is unrouted" do
    test "falls back to legacy on 404, in order", %{calls: calls} do
      stub_paths(calls, %{@documented => {404, err_body()}, @legacy => {200, ok_body()}})

      assert {:ok, %{"apiKey" => "test-api-key-123"}} = User.get_api_key_info(client())
      assert paths(calls) == [@documented, @legacy]
    end

    test "falls back on 401, since 401 is BloFin's unrouted catch-all", %{calls: calls} do
      stub_paths(calls, %{@documented => {401, err_body()}, @legacy => {200, ok_body()}})

      assert {:ok, _} = User.get_api_key_info(client())
      assert paths(calls) == [@documented, @legacy]
    end

    test "warns, naming both paths and the config to pin it", %{calls: calls} do
      stub_paths(calls, %{@documented => {404, err_body()}, @legacy => {200, ok_body()}})

      log = capture_log(fn -> User.get_api_key_info(client()) end)

      assert log =~ @documented
      assert log =~ @legacy
      assert log =~ "api_path_mode: :legacy"
    end
  end

  describe "error preservation" do
    test "both 401 surfaces :unauthorized, not a fallback error", %{calls: calls} do
      stub_paths(calls, %{@documented => {401, err_body()}, @legacy => {401, err_body()}})

      result = User.get_api_key_info(client())

      # The whole point of the definitive-success rule: a genuine credential
      # failure must not be reported as a routing failure.
      assert result == {:error, :unauthorized}
      refute result == {:error, :not_found}
      assert paths(calls) == [@documented, @legacy]
    end

    test "both 404 surfaces the original :not_found", %{calls: calls} do
      stub_paths(calls, %{@documented => {404, err_body()}, @legacy => {404, err_body()}})

      assert User.get_api_key_info(client()) == {:error, :not_found}
    end

    test "a 2xx legacy response with a non-zero code does not win", %{calls: calls} do
      stub_paths(calls, %{
        @documented => {404, err_body()},
        @legacy => {200, %{"code" => "152001", "msg" => "Instrument doesn't exist"}}
      })

      # Legacy answered 200 but not `code: "0"`, so it is not a definitive
      # success and the primary response stands.
      assert User.get_api_key_info(client()) == {:error, :not_found}
    end
  end

  describe "statuses that are not routing signals" do
    test "500 does not trigger a fallback", %{calls: calls} do
      stub_paths(calls, %{@documented => {500, err_body()}})

      assert {:error, {:api_error, 500, _}} = User.get_api_key_info(client())
      assert paths(calls) == [@documented]
    end

    test "429 does not trigger a fallback", %{calls: calls} do
      stub_paths(calls, %{@documented => {429, err_body()}})

      assert User.get_api_key_info(client()) == {:error, :rate_limited}
      assert paths(calls) == [@documented]
    end
  end

  describe "opt-out and pinning" do
    test "path_fallback: false issues exactly one request", %{calls: calls} do
      stub_paths(calls, %{@documented => {404, err_body()}, @legacy => {200, ok_body()}})

      client =
        Fixtures.sample_api_key()
        |> Client.new(Fixtures.sample_secret_key(), Fixtures.sample_passphrase(),
          plug: {Req.Test, @stub},
          path_fallback: false
        )
        |> Req.Request.merge_options(retry: false)

      assert User.get_api_key_info(client) == {:error, :not_found}
      assert paths(calls) == [@documented]
    end

    test "paths with no alias are dispatched directly", %{calls: calls} do
      stub_paths(calls, %{"/api/v1/account/config" => {200, %{"code" => "0", "data" => %{}}}})

      assert {:ok, _} = ExBlofin.Account.get_config(client())
      assert paths(calls) == ["/api/v1/account/config"]
    end
  end

  describe "signing" do
    test "the fallback request is signed for the legacy path, not the documented one",
         %{calls: calls} do
      # Regression guard for the highest-risk way to build this feature: if the
      # fallback rewrote the URL of the already-signed request instead of
      # re-entering the pipeline, ACCESS-SIGN would still cover the documented
      # path and BloFin would reject every fallback with a genuine 401.
      {:ok, signatures} = Agent.start_link(fn -> %{} end)

      Req.Test.stub(@stub, fn conn ->
        Agent.update(calls, &[conn.request_path | &1])

        Agent.update(signatures, fn acc ->
          Map.put(acc, conn.request_path, %{
            sign: header(conn, "access-sign"),
            timestamp: header(conn, "access-timestamp"),
            nonce: header(conn, "access-nonce")
          })
        end)

        case conn.request_path do
          @documented -> json(conn, 404, err_body())
          @legacy -> json(conn, 200, ok_body())
        end
      end)

      assert {:ok, _} = User.get_api_key_info(client())

      captured = Agent.get(signatures, & &1)
      documented_sig = captured[@documented]
      legacy_sig = captured[@legacy]

      assert documented_sig.sign != legacy_sig.sign

      assert legacy_sig.sign ==
               Auth.compute_signature(
                 Fixtures.sample_secret_key(),
                 @legacy,
                 "GET",
                 legacy_sig.timestamp,
                 legacy_sig.nonce
               )
    end
  end

  describe "cache isolation under Req.Test" do
    test "resolution is not cached when :plug is set", %{calls: calls} do
      stub_paths(calls, %{@documented => {404, err_body()}, @legacy => {200, ok_body()}})

      client = client()
      assert {:ok, _} = User.get_api_key_info(client)
      assert {:ok, _} = User.get_api_key_info(client)

      # Both calls re-probe. If the cache were live under :plug this would be 3,
      # and test outcomes would depend on execution order.
      assert paths(calls) == [@documented, @legacy, @documented, @legacy]
      assert Client.resolved_paths() == %{}
    end

    test "with caching forced on, the verdict is probed once and reused", %{calls: calls} do
      stub_paths(calls, %{@documented => {404, err_body()}, @legacy => {200, ok_body()}})
      client = caching_client()
      on_exit(fn -> :ets.delete_all_objects(:ex_blofin_path_cache) end)

      assert {:ok, _} = User.get_api_key_info(client)
      assert {:ok, _} = User.get_api_key_info(client)
      assert {:ok, _} = User.get_api_key_info(client)

      # First call probes both; the remaining two go straight to legacy.
      assert paths(calls) == [@documented, @legacy, @legacy, @legacy]
      assert Client.resolved_paths()[@documented] == :legacy
    end

    test "a documented-path success is cached too", %{calls: calls} do
      stub_paths(calls, %{@documented => {200, ok_body()}})
      client = caching_client()
      on_exit(fn -> :ets.delete_all_objects(:ex_blofin_path_cache) end)

      assert {:ok, _} = User.get_api_key_info(client)
      assert {:ok, _} = User.get_api_key_info(client)

      assert paths(calls) == [@documented, @documented]
      assert Client.resolved_paths()[@documented] == :documented
    end

    test "an inconclusive probe caches nothing", %{calls: calls} do
      # Both attempts failing must not be recorded: a single run with a stale
      # API key would otherwise mis-route the node permanently.
      stub_paths(calls, %{@documented => {401, err_body()}, @legacy => {401, err_body()}})
      client = caching_client()
      on_exit(fn -> :ets.delete_all_objects(:ex_blofin_path_cache) end)

      assert User.get_api_key_info(client) == {:error, :unauthorized}

      assert Client.resolved_paths() == %{}
    end
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp client, do: Fixtures.test_client(@stub)

  # Caching is off under `:plug` by default; `path_cache: true` opts back in so
  # the cache itself can be tested. Tests within a module run sequentially, so
  # sharing the global ETS table here is safe as long as each clears it.
  defp caching_client do
    Fixtures.sample_api_key()
    |> Client.new(Fixtures.sample_secret_key(), Fixtures.sample_passphrase(),
      plug: {Req.Test, @stub},
      path_cache: true
    )
    |> Req.Request.merge_options(retry: false)
  end

  defp stub_paths(calls, responses) do
    Req.Test.stub(@stub, fn conn ->
      Agent.update(calls, &[conn.request_path | &1])

      case Map.fetch(responses, conn.request_path) do
        {:ok, {status, body}} -> json(conn, status, body)
        :error -> json(conn, 404, err_body())
      end
    end)
  end

  defp paths(calls), do: calls |> Agent.get(& &1) |> Enum.reverse()

  defp json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  defp header(conn, name) do
    case Plug.Conn.get_req_header(conn, name) do
      [value | _] -> value
      [] -> nil
    end
  end

  defp ok_body, do: Fixtures.success_response(%{"apiKey" => Fixtures.sample_api_key()})
  defp err_body, do: %{"code" => "404", "msg" => "Not Found"}
end
