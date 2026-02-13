defmodule ExBlofin.AffiliateTest do
  use ExUnit.Case, async: true

  alias ExBlofin.{Affiliate, Fixtures}

  @stub :affiliate_stub

  describe "get_info/1" do
    test "returns affiliate info" do
      Req.Test.expect(@stub, fn conn ->
        assert conn.request_path == "/api/v1/affiliate/info"
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
