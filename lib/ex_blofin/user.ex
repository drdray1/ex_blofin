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
    |> Client.get("/api/v1/user/query-apikey")
    |> Client.handle_response()
  end
end
