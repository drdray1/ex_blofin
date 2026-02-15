defmodule ExBlofin.CopyTrading do
  @moduledoc """
  BloFin API - Copy trading endpoints.

  Provides functions for copy trading operations including position management,
  order placement, and account configuration. All endpoints require authentication.
  """

  alias ExBlofin.Client

  import ExBlofin.Helpers, only: [build_query: 2]

  @type client :: Req.Request.t()
  @type response :: {:ok, term()} | {:error, term()}

  @doc "Lists available copy trading instruments."
  @spec get_instruments(client(), keyword()) :: response()
  def get_instruments(client, opts \\ []) do
    params = build_query(opts, [:instType, :instId])

    client
    |> Req.get(url: "/api/v1/copytrading/instruments", params: params)
    |> Client.handle_response()
  end

  @doc "Retrieves copy trading account configuration."
  @spec get_account_config(client()) :: response()
  def get_account_config(client) do
    client
    |> Req.get(url: "/api/v1/copytrading/account-config")
    |> Client.handle_response()
  end

  @doc "Retrieves copy trading account balance."
  @spec get_balance(client(), keyword()) :: response()
  def get_balance(client, opts \\ []) do
    params = build_query(opts, [:accountType])

    client
    |> Req.get(url: "/api/v1/copytrading/balance", params: params)
    |> Client.handle_response()
  end

  @doc "Retrieves positions ordered by entry."
  @spec get_positions_by_order(client(), keyword()) :: response()
  def get_positions_by_order(client, opts \\ []) do
    params = build_query(opts, [:instId, :before, :after, :limit])

    client
    |> Req.get(url: "/api/v1/copytrading/positions-by-order", params: params)
    |> Client.handle_response()
  end

  @doc "Retrieves positions by contract."
  @spec get_positions_by_contract(client(), keyword()) :: response()
  def get_positions_by_contract(client, opts \\ []) do
    params = build_query(opts, [:instId])

    client
    |> Req.get(url: "/api/v1/copytrading/positions-by-contract", params: params)
    |> Client.handle_response()
  end

  @doc "Retrieves position mode."
  @spec get_position_mode(client()) :: response()
  def get_position_mode(client) do
    client
    |> Req.get(url: "/api/v1/copytrading/position-mode")
    |> Client.handle_response()
  end

  @doc "Sets position mode."
  @spec set_position_mode(client(), map()) :: response()
  def set_position_mode(client, params) do
    client
    |> Req.post(url: "/api/v1/copytrading/position-mode", json: params)
    |> Client.handle_response()
  end

  @doc "Retrieves leverage settings."
  @spec get_leverage(client(), keyword()) :: response()
  def get_leverage(client, opts \\ []) do
    params = build_query(opts, [:instId, :marginMode])

    client
    |> Req.get(url: "/api/v1/copytrading/leverage", params: params)
    |> Client.handle_response()
  end

  @doc "Sets leverage."
  @spec set_leverage(client(), map()) :: response()
  def set_leverage(client, params) do
    client
    |> Req.post(url: "/api/v1/copytrading/leverage", json: params)
    |> Client.handle_response()
  end

  @doc "Places a copy trading order."
  @spec place_order(client(), map()) :: response()
  def place_order(client, params) do
    client
    |> Req.post(url: "/api/v1/copytrading/order", json: params)
    |> Client.handle_response()
  end

  @doc "Cancels a copy trading order."
  @spec cancel_order(client(), map()) :: response()
  def cancel_order(client, params) do
    client
    |> Req.post(url: "/api/v1/copytrading/cancel-order", json: params)
    |> Client.handle_response()
  end

  @doc "Places TP/SL by contract."
  @spec place_tpsl_by_contract(client(), map()) :: response()
  def place_tpsl_by_contract(client, params) do
    client
    |> Req.post(url: "/api/v1/copytrading/tpsl-by-contract", json: params)
    |> Client.handle_response()
  end

  @doc "Closes a copy trading position."
  @spec close_position(client(), map()) :: response()
  def close_position(client, params) do
    client
    |> Req.post(url: "/api/v1/copytrading/close-position", json: params)
    |> Client.handle_response()
  end
end
