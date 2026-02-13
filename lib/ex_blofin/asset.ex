defmodule ExBlofin.Asset do
  @moduledoc """
  BloFin API - Asset management endpoints.

  Provides functions for querying asset balances, transferring funds,
  and viewing transaction history. All endpoints require authentication.

  ## Examples

      client = ExBlofin.Client.new("api_key", "secret_key", "passphrase")

      {:ok, balances} = ExBlofin.Asset.get_balances(client)
      {:ok, result} = ExBlofin.Asset.transfer(client, %{...})
  """

  alias ExBlofin.Client

  @type client :: Req.Request.t()
  @type response :: {:ok, term()} | {:error, term()}

  @doc """
  Retrieves all asset balances.

  ## Options

    - `:currency` - Filter by specific currency
  """
  @spec get_balances(client(), keyword()) :: response()
  def get_balances(client, opts \\ []) do
    params = build_query(opts, [:currency])

    client
    |> Req.get(url: "/api/v1/asset/balances", params: params)
    |> Client.handle_response()
  end

  @doc """
  Transfers funds between accounts.

  ## Parameters

    - `:currency` - Currency to transfer (required)
    - `:amount` - Amount to transfer (required)
    - `:from` - Source account type (required)
    - `:to` - Destination account type (required)
  """
  @spec transfer(client(), map()) :: response()
  def transfer(client, params) do
    client
    |> Req.post(url: "/api/v1/asset/transfer", json: params)
    |> Client.handle_response()
  end

  @doc """
  Retrieves funds transfer history.

  ## Options

    - `:currency` - Filter by currency
    - `:type` - Transfer type
    - `:before` - Pagination cursor
    - `:after` - Pagination cursor
    - `:limit` - Maximum results (default: 100)
  """
  @spec get_bills(client(), keyword()) :: response()
  def get_bills(client, opts \\ []) do
    params = build_query(opts, [:currency, :type, :before, :after, :limit])

    client
    |> Req.get(url: "/api/v1/asset/bills", params: params)
    |> Client.handle_response()
  end

  @doc """
  Retrieves withdrawal history.

  ## Options

    - `:currency` - Filter by currency
    - `:before` - Pagination cursor
    - `:after` - Pagination cursor
    - `:limit` - Maximum results
  """
  @spec get_withdrawal_history(client(), keyword()) :: response()
  def get_withdrawal_history(client, opts \\ []) do
    params = build_query(opts, [:currency, :before, :after, :limit])

    client
    |> Req.get(url: "/api/v1/asset/withdrawal-history", params: params)
    |> Client.handle_response()
  end

  @doc """
  Retrieves deposit history.

  ## Options

    - `:currency` - Filter by currency
    - `:before` - Pagination cursor
    - `:after` - Pagination cursor
    - `:limit` - Maximum results
  """
  @spec get_deposit_history(client(), keyword()) :: response()
  def get_deposit_history(client, opts \\ []) do
    params = build_query(opts, [:currency, :before, :after, :limit])

    client
    |> Req.get(url: "/api/v1/asset/deposit-history", params: params)
    |> Client.handle_response()
  end

  @doc """
  Requests demo trading funds (demo environment only).
  """
  @spec apply_demo_money(client()) :: response()
  def apply_demo_money(client) do
    client
    |> Req.post(url: "/api/v1/asset/demo-apply-money", json: %{})
    |> Client.handle_response()
  end

  @spec build_query(keyword(), list(atom())) :: keyword()
  defp build_query(opts, allowed_keys) do
    opts
    |> Keyword.take(allowed_keys)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end
end
