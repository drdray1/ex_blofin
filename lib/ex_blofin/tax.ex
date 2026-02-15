defmodule ExBlofin.Tax do
  @moduledoc """
  BloFin API - Tax reporting endpoints.

  Provides functions for retrieving tax-related history including deposits,
  withdrawals, transfers, and trade records. All endpoints require authentication.
  """

  alias ExBlofin.Client

  import ExBlofin.Helpers, only: [build_query: 2]

  @type client :: Req.Request.t()
  @type response :: {:ok, term()} | {:error, term()}

  @doc "Retrieves deposit records for tax reporting."
  @spec get_deposit_history(client(), keyword()) :: response()
  def get_deposit_history(client, opts \\ []) do
    params = build_query(opts, [:currency, :before, :after, :limit])

    client
    |> Req.get(url: "/api/v1/tax/deposit-history", params: params)
    |> Client.handle_response()
  end

  @doc "Retrieves withdrawal records for tax reporting."
  @spec get_withdraw_history(client(), keyword()) :: response()
  def get_withdraw_history(client, opts \\ []) do
    params = build_query(opts, [:currency, :before, :after, :limit])

    client
    |> Req.get(url: "/api/v1/tax/withdraw-history", params: params)
    |> Client.handle_response()
  end

  @doc "Retrieves funds transfer history for tax reporting."
  @spec get_funds_transfer_history(client(), keyword()) :: response()
  def get_funds_transfer_history(client, opts \\ []) do
    params = build_query(opts, [:currency, :before, :after, :limit])

    client
    |> Req.get(url: "/api/v1/tax/funds-transfer-history", params: params)
    |> Client.handle_response()
  end

  @doc "Retrieves spot trading history for tax reporting."
  @spec get_spot_trade_history(client(), keyword()) :: response()
  def get_spot_trade_history(client, opts \\ []) do
    params = build_query(opts, [:instId, :before, :after, :limit])

    client
    |> Req.get(url: "/api/v1/tax/spot-trade-history", params: params)
    |> Client.handle_response()
  end

  @doc "Retrieves futures trading history for tax reporting."
  @spec get_futures_trade_history(client(), keyword()) :: response()
  def get_futures_trade_history(client, opts \\ []) do
    params = build_query(opts, [:instId, :before, :after, :limit])

    client
    |> Req.get(url: "/api/v1/tax/futures-trade-history", params: params)
    |> Client.handle_response()
  end
end
