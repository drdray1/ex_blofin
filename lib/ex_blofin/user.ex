defmodule ExBlofin.User do
  @moduledoc """
  BloFin API - User management endpoints.
  """

  alias ExBlofin.Client

  @type client :: Req.Request.t()
  @type response :: {:ok, term()} | {:error, term()}

  @doc "Retrieves current API key details."
  @spec get_api_key_info(client()) :: response()
  def get_api_key_info(client) do
    client
    |> Req.get(url: "/api/v1/user/api-key-info")
    |> Client.handle_response()
  end
end
