defmodule ExBlofin.Affiliate do
  @moduledoc """
  BloFin API - Affiliate program endpoints.

  Provides functions for affiliate info, referral codes, invitees,
  and commission data. All endpoints require authentication.
  """

  alias ExBlofin.Client

  @type client :: Req.Request.t()
  @type response :: {:ok, term()} | {:error, term()}

  @doc "Retrieves affiliate account information."
  @spec get_info(client()) :: response()
  def get_info(client) do
    client
    |> Req.get(url: "/api/v1/affiliate/info")
    |> Client.handle_response()
  end

  @doc "Retrieves referral code details."
  @spec get_referral_code(client()) :: response()
  def get_referral_code(client) do
    client
    |> Req.get(url: "/api/v1/affiliate/referral-code")
    |> Client.handle_response()
  end

  @doc "Retrieves direct referrals."
  @spec get_invitees(client(), keyword()) :: response()
  def get_invitees(client, opts \\ []) do
    params = build_query(opts, [:before, :after, :limit])

    client
    |> Req.get(url: "/api/v1/affiliate/invitees", params: params)
    |> Client.handle_response()
  end

  @doc "Retrieves sub-referrals."
  @spec get_sub_invitees(client(), keyword()) :: response()
  def get_sub_invitees(client, opts \\ []) do
    params = build_query(opts, [:before, :after, :limit])

    client
    |> Req.get(url: "/api/v1/affiliate/sub-invitees", params: params)
    |> Client.handle_response()
  end

  @doc "Retrieves sub-affiliate accounts."
  @spec get_sub_affiliates(client(), keyword()) :: response()
  def get_sub_affiliates(client, opts \\ []) do
    params = build_query(opts, [:before, :after, :limit])

    client
    |> Req.get(url: "/api/v1/affiliate/sub-affiliates", params: params)
    |> Client.handle_response()
  end

  @doc "Retrieves daily commission data."
  @spec get_commission(client(), keyword()) :: response()
  def get_commission(client, opts \\ []) do
    params = build_query(opts, [:before, :after, :limit])

    client
    |> Req.get(url: "/api/v1/affiliate/commission", params: params)
    |> Client.handle_response()
  end

  @spec build_query(keyword(), list(atom())) :: keyword()
  defp build_query(opts, allowed_keys) do
    opts
    |> Keyword.take(allowed_keys)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end
end
