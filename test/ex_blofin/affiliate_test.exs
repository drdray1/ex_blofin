defmodule ExBlofin.AffiliateTest do
  use ExUnit.Case, async: true

  alias ExBlofin.{Affiliate, Fixtures}

  @stub :affiliate_stub

  describe "get_info/1" do
    test "returns affiliate info" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/affiliate/basic"
        Req.Test.json(conn, Fixtures.sample_affiliate_info_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, [%{"uid" => _}]} = Affiliate.get_info(client)
    end
  end

  describe "get_referral_code/1" do
    test "returns referral code" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/affiliate/referral-code"
        Req.Test.json(conn, Fixtures.sample_referral_code_response())
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, [%{"referralCode" => _}]} = Affiliate.get_referral_code(client)
    end
  end

  describe "get_invitees/2" do
    test "returns invitees" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/affiliate/invitees"
        Req.Test.json(conn, Fixtures.success_response([]))
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, []} = Affiliate.get_invitees(client)
    end
  end

  describe "get_sub_invitees/2" do
    test "returns sub-affiliate invitees" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/affiliate/sub-invitees"
        Req.Test.json(conn, Fixtures.success_response([]))
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, []} = Affiliate.get_sub_invitees(client)
    end

    test "passes filters through" do
      Req.Test.expect(@stub, fn conn ->
        assert URI.decode_query(conn.query_string)["limit"] == "10"
        Req.Test.json(conn, Fixtures.success_response([]))
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, []} = Affiliate.get_sub_invitees(client, limit: "10")
    end
  end

  describe "get_sub_affiliates/2" do
    test "returns sub-affiliates" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/affiliate/sub-affiliates"
        Req.Test.json(conn, Fixtures.success_response([]))
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, []} = Affiliate.get_sub_affiliates(client)
    end
  end

  describe "get_commission/2" do
    test "returns commission data" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/affiliate/commission"
        Req.Test.json(conn, Fixtures.success_response([]))
      end)

      client = Fixtures.test_client(@stub)
      assert {:ok, []} = Affiliate.get_commission(client)
    end
  end
end
