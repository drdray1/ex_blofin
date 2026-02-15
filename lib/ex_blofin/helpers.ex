defmodule ExBlofin.Helpers do
  @moduledoc false

  @spec build_query(keyword(), [atom()]) :: keyword()
  def build_query(opts, allowed_keys) do
    opts
    |> Keyword.take(allowed_keys)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end
end
