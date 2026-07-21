defmodule ExBlofin.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    ExBlofin.Client.init_path_cache()

    children = []
    opts = [strategy: :one_for_one, name: ExBlofin.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
