# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0]

Trues the library up against the current BloFin API documentation.

### Added

- `ExBlofin.MarketData.get_position_tiers/2` — `GET /api/v1/market/position-tiers`.
  Returns maximum leverage per position-size bracket, which previously had no
  representation in the library at all.
- `ExBlofin.Asset.get_currencies/2` — `GET /api/v1/asset/currencies`. Supported
  chains, withdrawal fees and minimums, deposit/withdrawal availability.
- `ExBlofin.Account.get_positions_history/2` — `GET /api/v1/account/positions-history`.
  Closed positions with realized PnL; only live positions were reachable before.
- `ExBlofin.Paths` and automatic documented/legacy path resolution. See *Changed*.
- `ExBlofin.Client.resolved_paths/0`, reporting which spelling of each diverging
  endpoint your account is actually served.
- Delegates for 13 module functions that existed but were never exposed on the
  `ExBlofin` facade, across `CopyTrading`, `Affiliate` and `Tax`.

### Changed

- Nine endpoint paths now use their currently-documented spelling, e.g.
  `/api/v1/trade/order-history` → `/api/v1/trade/orders-history` and
  `/api/v1/user/api-key-info` → `/api/v1/user/query-apikey`.

  Because BloFin answers HTTP 401 for *every* unrouted path, it is not possible
  to verify from the outside which spelling is live. `ExBlofin.Client.get/3`
  therefore tries the documented path first and falls back to the previous path
  when the documented one appears unrouted, caching the winner per host. **No
  call that worked before should stop working.** Successful fallbacks log a
  warning; pin the outcome to skip the extra request:

  ```elixir
  config :ex_blofin, api_path_mode: :documented  # or :legacy
  ```

  Per-client opt-out: `ExBlofin.Client.new(k, s, p, path_fallback: false)`.

### Fixed

- **`ExBlofin.get_order_price_range/1` raised `UndefinedFunctionError`.** The
  delegate defaulted its second argument, generating an arity-1 clause with no
  counterpart in `ExBlofin.Trading`. It is now `get_order_price_range/2`, taking
  an instrument id.
- **`ExBlofin.market_order/5` and `ExBlofin.limit_order/6` crashed on every
  call.** Both delegates declared `position_side` in the argument position where
  `ExBlofin.Trading` expects `size`, so the order was sent with `"size" => "net"`
  and the real size was passed to `Keyword.get/3`. The facade signatures now
  match their targets: `market_order(client, inst_id, side, size, opts \\ [])`
  and `limit_order(client, inst_id, side, size, price, opts \\ [])`.

  This is a breaking change for any caller that had worked around the old
  argument order — but the previous forms could not have succeeded.
- **`ExBlofin.Auth`'s docs described the wrong timestamp format.** The moduledoc
  claimed `ACCESS-TIMESTAMP` was "ISO 8601 UTC timestamp with milliseconds", and
  a test asserted the same. Both were wrong: BloFin rejects anything but a
  millisecond epoch with error 152410. The implementation was already correct;
  the docs and the test now match it.

### Testing

- Test count went from 168 to 444; line coverage from 28% to 92%.
- `mix test --cover` now fails below 88%. `ExBlofin.Terminal.*` is excluded from
  the measurement: it is the interactive TUI behind the demo scripts (~3,350
  lines of ANSI rendering and polling loops), not part of the API client.
- New coverage of note: every facade delegate is now called at least once, the
  WebSocket login handshake and reconnect/backoff logic are unit-tested against
  a stand-in socket, and `Client`'s error normalisation is covered exhaustively.

### Notes

- The five `/api/v1/tax/*` paths in `ExBlofin.Tax` are left untouched and are
  **unverified**. The current docs have no `tax/*` namespace, covering the same
  ground via `/asset/*` and `/trade/fills-history`. Those read as different
  resources rather than renames, so remapping them could silently change
  response shapes; they are deliberately excluded from path resolution.
- `ExBlofin.CopyTrading` is unchanged. Its paths diverge from the docs by a
  whole-namespace restructure (`/copytrading/order` →
  `/copytrading/trade/place-order`) and roughly nine documented endpoints are
  still missing. Deferred to a follow-up release.

## [0.1.6]

- Allow `decimal ~> 3.0`.

## [0.1.5]

- WebSocket: exponential reconnect backoff with a 10s floor on HTTP 429.
- Fix `cancel_tpsl_order` to send an array body per the BloFin API spec.
- Fix WebSocket disconnect killing parent processes.
