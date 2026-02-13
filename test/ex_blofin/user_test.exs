defmodule ExBlofin.UserTest do
  use ExUnit.Case, async: true

  alias ExBlofin.{Fixtures, User}

  @stub :user_stub

  describe "get_api_key_info/1" do
    test "returns API key info" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/user/api-key-info"
        Req.Test.json(conn, Fixtures.sample_api_key_info_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, [%{"apiKey" => _}]} = User.get_api_key_info(client)
    end
  end
end
