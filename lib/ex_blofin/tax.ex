defmodule ExBlofin.Tax do
  @moduledoc """
  BloFin API - Tax reporting endpoints.

  Provides functions for retrieving tax-related history including deposits,
  withdrawals, transfers, and trade records. All endpoints require authentication.

  > #### Unverified paths {: .warning}
  >
  > These functions call an `/api/v1/tax/*` namespace that no longer appears in
  > the BloFin documentation. The current docs cover the same ground by reusing
  > `/api/v1/asset/*` and `/api/v1/trade/fills-history`. Those are plausibly
  > *different* resources with different response shapes rather than renames, so
  > they are deliberately excluded from the `ExBlofin.Paths` alias map and no
  > automatic fallback applies here. If a call returns `{:error, :unauthorized}`
  > with credentials you know are good, the path is likely retired — reach for
  > `ExBlofin.Asset` instead.
  """

  alias ExBlofin.Client

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

  @spec build_query(keyword(), list(atom())) :: keyword()
  defp build_query(opts, allowed_keys) do
    opts
    |> Keyword.take(allowed_keys)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end
end
