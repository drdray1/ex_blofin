defmodule ExBlofin.Paths do
  @moduledoc """
  Documented-path to legacy-path aliases for endpoints whose current BloFin
  documentation and this library's historical paths disagree.

  This library was originally built against an older revision of the BloFin
  docs. Several endpoint paths have since been renamed in the documentation,
  but BloFin returns HTTP 401 for *every* unrouted path, so it is not possible
  to determine from the outside which spelling is actually live.

  `ExBlofin.Client.get/3` therefore tries the documented path first and falls
  back to the legacy path when the documented one appears to be unrouted. See
  `ExBlofin.Client` for the resolution rules and the `:api_path_mode` config.

  Every alias here is a **GET** endpoint, which is why no POST fallback exists.

  ## Maintenance

  Once a documented path is confirmed live (watch for the fallback warning in
  your logs), delete its entry here. When the map empties, the fallback
  machinery becomes dead code and can be removed.

  Aliases are deliberately limited to pure *renames* of the same resource.
  Endpoints where the docs point at a genuinely different resource are excluded,
  because preferring the documented path could silently change the response
  shape — a change no runtime probe can detect. Currently excluded:

    - The five `/api/v1/tax/*` paths in `ExBlofin.Tax`. The docs have no `tax/*`
      namespace and instead reuse `/asset/*` and `/trade/fills-history`, which
      plausibly return different fields for tax-reporting purposes.
    - `/api/v1/affiliate/commission`, whose documented counterpart
      `/affiliate/invitees/daily/info` reads as a different report.
  """

  @legacy %{
    "/api/v1/trade/orders-history" => "/api/v1/trade/order-history",
    "/api/v1/trade/fills-history" => "/api/v1/trade/trade-history",
    "/api/v1/trade/orders-tpsl-pending" => "/api/v1/trade/orders-tpsl",
    "/api/v1/trade/orders-algo-pending" => "/api/v1/trade/orders-algo",
    "/api/v1/trade/orders-tpsl-history" => "/api/v1/trade/order-tpsl-history",
    "/api/v1/trade/orders-algo-history" => "/api/v1/trade/order-algo-history",
    "/api/v1/trade/order/price-range" => "/api/v1/trade/order-price-range",
    "/api/v1/user/query-apikey" => "/api/v1/user/api-key-info",
    "/api/v1/affiliate/basic" => "/api/v1/affiliate/info"
  }

  @doc """
  Returns the legacy path for a documented path, or `nil` when it has no alias.

  ## Examples

      iex> ExBlofin.Paths.legacy_for("/api/v1/user/query-apikey")
      "/api/v1/user/api-key-info"

      iex> ExBlofin.Paths.legacy_for("/api/v1/account/balance")
      nil
  """
  @spec legacy_for(String.t()) :: String.t() | nil
  def legacy_for(path), do: Map.get(@legacy, path)

  @doc """
  Returns the full documented-to-legacy alias map.
  """
  @spec all() :: %{String.t() => String.t()}
  def all, do: @legacy
end
