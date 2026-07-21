defmodule ExBlofin.FacadeDelegatesTest do
  @moduledoc """
  Exercises every HTTP-backed delegate on the `ExBlofin` facade.

  `defdelegate` only checks arity, so a delegate can forward to the wrong
  function or the wrong argument position and still compile. Calling each one
  against a catch-all stub proves the whole surface is at least wired to
  something that exists and accepts the arguments the facade advertises.

  Behavioural assertions for the delegates that were actually broken live in
  `ExBlofin.FacadeTest`; this file is about breadth.
  """
  use ExUnit.Case, async: true

  alias ExBlofin.Fixtures

  @stub :facade_delegates_stub

  @order_params %{
    "instId" => "BTC-USDT",
    "side" => "buy",
    "orderType" => "market",
    "size" => "1"
  }

  # {function, args after `client`}. Both arities of every optional-opts
  # delegate are listed so the generated default clause is covered too.
  @market_data [
    {:get_instruments, []},
    {:get_instruments, [[]]},
    {:get_tickers, []},
    {:get_tickers, [[instId: "BTC-USDT"]]},
    {:get_mark_price, []},
    {:get_mark_price, [[]]},
    {:get_position_tiers, []},
    {:get_position_tiers, [[marginMode: "cross"]]},
    {:get_funding_rate, []},
    {:get_funding_rate, [[]]},
    {:get_books, ["BTC-USDT"]},
    {:get_books, ["BTC-USDT", []]},
    {:get_trades, ["BTC-USDT"]},
    {:get_trades, ["BTC-USDT", []]},
    {:get_candles, ["BTC-USDT"]},
    {:get_candles, ["BTC-USDT", [bar: "1H"]]},
    {:get_index_candles, ["BTC-USDT"]},
    {:get_index_candles, ["BTC-USDT", []]},
    {:get_mark_price_candles, ["BTC-USDT"]},
    {:get_mark_price_candles, ["BTC-USDT", []]},
    {:get_funding_rate_history, ["BTC-USDT"]},
    {:get_funding_rate_history, ["BTC-USDT", []]}
  ]

  @account [
    {:get_balance, []},
    {:get_balance, [[]]},
    {:get_positions, []},
    {:get_positions, [[]]},
    {:get_positions_history, []},
    {:get_positions_history, [[]]},
    {:get_margin_mode, []},
    {:get_margin_mode, [[]]},
    {:get_position_mode, []},
    {:get_position_mode, [[]]},
    {:get_batch_leverage_info, []},
    {:get_batch_leverage_info, [[]]},
    {:get_config, []},
    {:set_margin_mode, [%{"instId" => "BTC-USDT", "marginMode" => "cross"}]},
    {:set_position_mode, [%{"positionMode" => "net_mode"}]},
    {:set_leverage, [%{"instId" => "BTC-USDT", "lever" => "10"}]}
  ]

  @asset [
    {:get_balances, []},
    {:get_balances, [[]]},
    {:get_currencies, []},
    {:get_currencies, [[]]},
    {:get_bills, []},
    {:get_bills, [[]]},
    {:get_withdrawal_history, []},
    {:get_withdrawal_history, [[]]},
    {:get_deposit_history, []},
    {:get_deposit_history, [[]]},
    {:apply_demo_money, []},
    {:transfer, [%{"currency" => "USDT", "amount" => "10"}]}
  ]

  @trading [
    {:get_pending_orders, []},
    {:get_pending_orders, [[]]},
    {:get_order_detail, []},
    {:get_order_detail, [[]]},
    {:get_order_history, []},
    {:get_order_history, [[]]},
    {:get_tpsl_orders, []},
    {:get_tpsl_orders, [[]]},
    {:get_tpsl_order_detail, []},
    {:get_tpsl_order_detail, [[]]},
    {:get_tpsl_order_history, []},
    {:get_tpsl_order_history, [[]]},
    {:get_algo_orders, []},
    {:get_algo_orders, [[]]},
    {:get_algo_order_history, []},
    {:get_algo_order_history, [[]]},
    {:get_trade_history, []},
    {:get_trade_history, [[]]},
    {:get_order_price_range, ["BTC-USDT"]},
    {:place_order, [@order_params]},
    {:place_batch_orders, [[@order_params]]},
    {:place_tpsl_order, [%{"instId" => "BTC-USDT"}]},
    {:place_algo_order, [%{"instId" => "BTC-USDT"}]},
    {:cancel_order, [%{"orderId" => "1"}]},
    {:cancel_batch_orders, [[%{"orderId" => "1"}]]},
    {:cancel_tpsl_order, [[%{"tpslId" => "1"}]]},
    {:cancel_algo_order, [[%{"algoId" => "1"}]]},
    {:close_position, [%{"instId" => "BTC-USDT"}]},
    {:market_order, ["BTC-USDT", "buy", "1"]},
    {:market_order, ["BTC-USDT", "buy", "1", []]},
    {:limit_order, ["BTC-USDT", "buy", "1", "50000"]},
    {:limit_order, ["BTC-USDT", "buy", "1", "50000", []]}
  ]

  @copy_trading [
    {:get_copy_trading_instruments, []},
    {:get_copy_trading_instruments, [[]]},
    {:get_copy_trading_account_config, []},
    {:get_copy_trading_balance, []},
    {:get_copy_trading_balance, [[]]},
    {:get_copy_trading_positions_by_order, []},
    {:get_copy_trading_positions_by_order, [[]]},
    {:get_copy_trading_positions_by_contract, []},
    {:get_copy_trading_positions_by_contract, [[]]},
    {:get_copy_trading_position_mode, []},
    {:get_copy_trading_leverage, []},
    {:get_copy_trading_leverage, [[]]},
    {:set_copy_trading_position_mode, [%{"positionMode" => "net_mode"}]},
    {:set_copy_trading_leverage, [%{"instId" => "BTC-USDT", "lever" => "5"}]},
    {:place_copy_trading_order, [@order_params]},
    {:cancel_copy_trading_order, [%{"orderId" => "1"}]},
    {:place_copy_trading_tpsl_by_contract, [%{"instId" => "BTC-USDT"}]},
    {:close_copy_trading_position, [%{"instId" => "BTC-USDT"}]}
  ]

  @affiliate_user_tax [
    {:get_affiliate_info, []},
    {:get_referral_code, []},
    {:get_invitees, []},
    {:get_invitees, [[]]},
    {:get_sub_invitees, []},
    {:get_sub_invitees, [[]]},
    {:get_sub_affiliates, []},
    {:get_sub_affiliates, [[]]},
    {:get_commission, []},
    {:get_commission, [[]]},
    {:get_api_key_info, []},
    {:get_tax_deposit_history, []},
    {:get_tax_deposit_history, [[]]},
    {:get_tax_withdraw_history, []},
    {:get_tax_withdraw_history, [[]]},
    {:get_tax_futures_trade_history, []},
    {:get_tax_futures_trade_history, [[]]},
    {:get_tax_spot_trade_history, []},
    {:get_tax_spot_trade_history, [[]]},
    {:get_tax_funds_transfer_history, []},
    {:get_tax_funds_transfer_history, [[]]}
  ]

  for {group, delegates} <- [
        market_data: @market_data,
        account: @account,
        asset: @asset,
        trading: @trading,
        copy_trading: @copy_trading,
        affiliate_user_tax: @affiliate_user_tax
      ] do
    describe "#{group} delegates" do
      for {fun, args} <- delegates do
        test "ExBlofin.#{fun}/#{length(args) + 1} forwards to its target" do
          Req.Test.stub(@stub, fn conn ->
            Req.Test.json(conn, Fixtures.success_response([]))
          end)

          client = Fixtures.test_client(@stub)

          assert {:ok, _} =
                   apply(ExBlofin, unquote(fun), [client | unquote(Macro.escape(args))])
        end
      end
    end
  end

  describe "non-HTTP delegates" do
    test "new/3 and new/4 build a client" do
      assert %Req.Request{} = ExBlofin.new("k", "s", "p")
      assert %Req.Request{} = ExBlofin.new("k", "s", "p", demo: true)
    end

    test "validate_order_params/1 accepts a complete order" do
      params = Map.put(@order_params, "marginMode", "cross")
      assert {:ok, ^params} = ExBlofin.validate_order_params(params)
    end

    test "validate_order_params/1 reports every missing field" do
      assert {:error, errors} = ExBlofin.validate_order_params(%{})

      assert "instId is required" in errors
      assert "marginMode is required" in errors
      assert "side is required" in errors
      assert "orderType is required" in errors
      assert "size is required" in errors
    end
  end
end
