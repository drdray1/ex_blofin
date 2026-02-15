defmodule ExBlofin.Account do
  @moduledoc """
  BloFin API - Account management endpoints.

  Provides functions for querying account balance, positions,
  margin/position modes, and leverage settings. All endpoints require authentication.

  ## Examples

      client = ExBlofin.Client.new("api_key", "secret_key", "passphrase")

      {:ok, balance} = ExBlofin.Account.get_balance(client)
      {:ok, positions} = ExBlofin.Account.get_positions(client, instId: "BTC-USDT")
  """

  alias ExBlofin.Client

  import ExBlofin.Helpers, only: [build_query: 2]

  @type client :: Req.Request.t()
  @type response :: {:ok, term()} | {:error, term()}

  @doc """
  Retrieves futures account balance details.

  ## Options

    - `:accountType` - Account type filter

  ## Examples

      {:ok, balance} = Account.get_balance(client)
  """
  @spec get_balance(client(), keyword()) :: response()
  def get_balance(client, opts \\ []) do
    params = build_query(opts, [:accountType])

    client
    |> Req.get(url: "/api/v1/account/balance", params: params)
    |> Client.handle_response()
  end

  @doc """
  Retrieves current positions.

  ## Options

    - `:instId` - Specific instrument ID

  ## Examples

      {:ok, positions} = Account.get_positions(client)
      {:ok, positions} = Account.get_positions(client, instId: "BTC-USDT")
  """
  @spec get_positions(client(), keyword()) :: response()
  def get_positions(client, opts \\ []) do
    params = build_query(opts, [:instId])

    client
    |> Req.get(url: "/api/v1/account/positions", params: params)
    |> Client.handle_response()
  end

  @doc """
  Retrieves current margin mode for an instrument.

  ## Options

    - `:instId` - Instrument ID (required)
  """
  @spec get_margin_mode(client(), keyword()) :: response()
  def get_margin_mode(client, opts \\ []) do
    params = build_query(opts, [:instId])

    client
    |> Req.get(url: "/api/v1/account/margin-mode", params: params)
    |> Client.handle_response()
  end

  @doc """
  Sets the margin mode for an instrument.

  ## Parameters

    - `:instId` - Instrument ID (required)
    - `:marginMode` - "cross" or "isolated" (required)
  """
  @spec set_margin_mode(client(), map()) :: response()
  def set_margin_mode(client, params) do
    client
    |> Req.post(url: "/api/v1/account/set-margin-mode", json: params)
    |> Client.handle_response()
  end

  @doc """
  Retrieves current position mode.
  """
  @spec get_position_mode(client(), keyword()) :: response()
  def get_position_mode(client, opts \\ []) do
    params = build_query(opts, [:instId])

    client
    |> Req.get(url: "/api/v1/account/position-mode", params: params)
    |> Client.handle_response()
  end

  @doc """
  Sets position mode (one-way or hedge).

  ## Parameters

    - `:positionMode` - "net_mode" or "long_short_mode" (required)
  """
  @spec set_position_mode(client(), map()) :: response()
  def set_position_mode(client, params) do
    client
    |> Req.post(url: "/api/v1/account/set-position-mode", json: params)
    |> Client.handle_response()
  end

  @doc """
  Retrieves leverage settings in batch.

  ## Options

    - `:instId` - Instrument ID (required)
    - `:marginMode` - "cross" or "isolated"
  """
  @spec get_batch_leverage_info(client(), keyword()) :: response()
  def get_batch_leverage_info(client, opts \\ []) do
    params = build_query(opts, [:instId, :marginMode])

    client
    |> Req.get(url: "/api/v1/account/batch-leverage-info", params: params)
    |> Client.handle_response()
  end

  @doc """
  Sets leverage level for an instrument.

  ## Parameters

    - `:instId` - Instrument ID (required)
    - `:lever` - Leverage level (required)
    - `:marginMode` - "cross" or "isolated" (required)
    - `:positionSide` - "net", "long", or "short"
  """
  @spec set_leverage(client(), map()) :: response()
  def set_leverage(client, params) do
    client
    |> Req.post(url: "/api/v1/account/set-leverage", json: params)
    |> Client.handle_response()
  end

  @doc """
  Retrieves account configuration.
  """
  @spec get_config(client()) :: response()
  def get_config(client) do
    client
    |> Req.get(url: "/api/v1/account/config")
    |> Client.handle_response()
  end
end
