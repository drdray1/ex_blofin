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

  In Multi-Position mode several entries may share an `instId` and
  `positionSide`; each carries its own `"positionId"`.

  ## Options

    - `:instId` - Specific instrument ID
    - `:positionId` - One position (Multi-Position mode)

  ## Examples

      {:ok, positions} = Account.get_positions(client)
      {:ok, positions} = Account.get_positions(client, instId: "BTC-USDT")
  """
  @spec get_positions(client(), keyword()) :: response()
  def get_positions(client, opts \\ []) do
    params = build_query(opts, [:instId, :positionId])

    client
    |> Req.get(url: "/api/v1/account/positions", params: params)
    |> Client.handle_response()
  end

  @doc """
  Retrieves closed and partially closed positions with realized PnL.

  ## Options

    - `:positionId` - One position
    - `:instId` - Instrument ID
    - `:state` - "partially_closed", "closed", "liquidated",
      "partially_liquidated" or "adl"
    - `:after` / `:before` - Pagination by `historyId`
    - `:begin` / `:end` - Millisecond timestamps
    - `:limit` - Number of results
  """
  @spec get_positions_history(client(), keyword()) :: response()
  def get_positions_history(client, opts \\ []) do
    params =
      build_query(opts, [:positionId, :instId, :state, :after, :before, :begin, :end, :limit])

    client
    |> Req.get(url: "/api/v1/account/positions-history", params: params)
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
  Retrieves the account's position mode.

  The data carries `"positionMode"` (`"net_mode"` or `"long_short_mode"`) and
  `"multiPosition"` (`"true"`/`"false"`, always `"false"` under net mode).
  `position_mode/1` returns the same as a typed map.
  """
  @spec get_position_mode(client(), keyword()) :: response()
  def get_position_mode(client, opts \\ []) do
    params = build_query(opts, [:instId])

    client
    |> Req.get(url: "/api/v1/account/position-mode", params: params)
    |> Client.handle_response()
  end

  @doc """
  Sets position mode (one-way or hedge) for every instrument.

  Refused while the account has open orders or positions; the same applies
  to switching `multiPosition`.

  ## Parameters

    - `"positionMode"` - "net_mode" or "long_short_mode" (required)
    - `"multiPosition"` - "true" or "false"; "true" only with
      "long_short_mode", otherwise the request is rejected
  """
  @spec set_position_mode(client(), map()) :: response()
  def set_position_mode(client, params) do
    client
    |> Req.post(url: "/api/v1/account/set-position-mode", json: params)
    |> Client.handle_response()
  end

  @doc """
  The account's position mode as `%{position_mode: String.t(), multi_position: boolean()}`.
  """
  @spec position_mode(client()) ::
          {:ok, %{position_mode: String.t(), multi_position: boolean()}} | {:error, term()}
  def position_mode(client) do
    case get_position_mode(client) do
      {:ok, [data | _]} -> parse_position_mode(data)
      {:ok, %{} = data} -> parse_position_mode(data)
      {:ok, other} -> {:error, {:unexpected_response, other}}
      error -> error
    end
  end

  defp parse_position_mode(%{"positionMode" => mode} = data) when is_binary(mode),
    do: {:ok, %{position_mode: mode, multi_position: data["multiPosition"] in ["true", true]}}

  defp parse_position_mode(data), do: {:error, {:unexpected_response, data}}

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
  Sets leverage for an instrument, or for one position.

  Without `"positionId"` it sets the instrument-level leverage; in
  Multi-Position mode that applies to positions opened afterwards only and may
  change while positions are held. With `"positionId"` it adjusts that one
  position. Error 110006 means pending cross orders block the change and
  110019 means orders or positions do (see `Client.error_code/1`).

  ## Parameters

    - `"instId"` - Instrument ID (required)
    - `"leverage"` - Leverage level (required)
    - `"marginMode"` - "cross" or "isolated" (required)
    - `"positionSide"` - "net", "long" or "short"; required for isolated
      margin in long/short mode
    - `"positionId"` - One position (Multi-Position mode only)
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

  @spec build_query(keyword(), list(atom())) :: keyword()
  defp build_query(opts, allowed_keys) do
    opts
    |> Keyword.take(allowed_keys)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end
end
