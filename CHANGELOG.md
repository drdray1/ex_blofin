# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed — terminal UI

- **The funding rate monitor never received a live update.** It matched the
  atom `:"funding-rate"` while `ExBlofin.WebSocket.Message` emits
  `:funding_rate`, so every event fell through to the catch-all. The pane
  re-rendered once a second showing the REST snapshot taken at startup, with a
  countdown frozen at `00:00:00`. Regression-tested.
- **Sub-cent prices rendered as `0.00`.** Fifteen call sites hardcoded two
  decimals, so DOGE, SHIB, PEPE and most of the long tail were unreadable —
  worst in the Market Scanner, which iterates every instrument by design.
  Precision is now chosen from the value's magnitude. Sizes are no longer
  rounded to integers either, which had shown fractional contracts as `0`.
- **Batched order book messages were silently dropped.** The handler matched a
  single-element list `[book]`; anything longer hit the catch-all and vanished
  while the display kept showing a green "Live" indicator.
- **A reconnect could corrupt the order book indefinitely.** `action` is `nil`
  when the payload arrives as a JSON array, and that defaulted to *incremental*,
  so the snapshot BloFin re-sends after reconnecting was merged into the stale
  book instead of replacing it. Only an explicit `"update"` is now treated as a
  delta.
- **Duplicate price levels.** Delta matching compared price *strings*, so
  `"50000.0"` and `"50000.00"` became two rows that sorted adjacently and
  double-counted depth. Compared numerically now.
- **The scanner's refresh countdown was frozen**, because rendering was gated on
  a `dirty` flag that only data could set. It now renders every tick.
- **EMA overlays drew false flat lines.** Values outside the visible price range
  were clamped to the top or bottom row rather than omitted. The EMA maths
  itself was correct and is unchanged.
- **Column alignment broke on coloured text.** Padding measured raw string
  length, counting ANSI escape bytes as visible characters.

### Changed — terminal UI

- **Rendering now diffs frames.** Each pane previously rewrote the entire screen
  on every tick. `ExBlofin.Terminal.Screen.write_frame/2` compares against the
  previous frame and emits only the rows that changed. Measured on a live
  28-row scanner frame with one row ticking: **3,467 bytes to 44, a 98.7%
  reduction**; an unchanged frame now writes nothing at all. Frames are built as
  iodata rather than joined into a binary, and a resize forces a full repaint.
- Extracted `ExBlofin.Terminal.Format` and `ExBlofin.Terminal.Screen` from the
  eight panes, which each carried their own copies. `parse_float/1` alone
  existed 18 times with divergent clauses — one copy crashed on inputs the
  others handled. These two modules are pure, directly tested, and included in
  the coverage gate.

### Notes

Still outstanding in the TUI, from the same audit: grid layout math on narrow
terminals (instruments are silently dropped when the terminal is too short),
missing checksum validation on order book merges, no `SIGWINCH` handling in
four panes, ANSI emitted even when output is not a TTY, and a world-writable
state file in `scripts/dashboard.sh` that allows local command injection
through `control.exs`.

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
