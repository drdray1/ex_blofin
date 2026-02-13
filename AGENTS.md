# ExBlofin - Agent Instructions

## Overview

`ex_blofin` is a standalone Elixir library wrapping the BloFin cryptocurrency derivatives exchange API. It provides REST and WebSocket access for perpetual futures trading, copy trading, account management, and market data.

## Build & Test

```bash
mix deps.get     # Install dependencies
mix test          # Run all tests (163 tests, no external HTTP)
mix credo         # Run linter
mix format        # Format code
```

## Architecture

### REST API
- **Client pattern**: `ExBlofin.Client.new/4` returns a `Req.Request.t()` (not a custom struct)
- **Auth**: `ExBlofin.Auth` is a Req plugin using HMAC-SHA256 signatures
- **Response handling**: `Client.handle_response/1` unwraps BloFin's `{"code":"0","data":[...]}` envelope
- **Module convention**: Each module accepts `client` as first arg, uses `Req.get/post`, pipes through `Client.handle_response/1`

### WebSocket
- **3-tier architecture**: Message (pure functions) -> Client (WebSockex wrapper) -> Connection (GenServer)
- **3 separate connections**: PublicConnection (no auth), PrivateConnection (login handshake), CopyTradingConnection (login handshake)
- **Ping/Pong**: Application-level text frames (`"ping"`/`"pong"`), NOT WebSocket protocol pings
- **Event format**: `{:blofin_event, channel_atom, [event_struct]}`

### Key Files
- `lib/ex_blofin.ex` - Top-level facade with `defdelegate`
- `lib/ex_blofin/client.ex` - Req factory + response handling
- `lib/ex_blofin/auth.ex` - HMAC-SHA256 Req plugin
- `lib/ex_blofin/trading.ex` - Largest module (orders, TPSL, algo)
- `lib/ex_blofin/websocket/message.ex` - WS message builder/parser + event structs
- `test/support/fixtures.ex` - All test fixtures and sample responses

## Code Style

- Standard Elixir formatting (`mix format`)
- Req for HTTP, Jason for JSON, WebSockex for WebSocket
- Tagged tuples: `{:ok, data}` or `{:error, reason}`
- Tests use `Req.Test` stubs, no external HTTP calls
- Config via `Application.get_env(:ex_blofin, :config, [])`

## Dependencies

- `req` - HTTP client
- `jason` - JSON
- `decimal` - Decimal arithmetic
- `websockex` - WebSocket client
- `plug` - Required at compile time for Req.Test
