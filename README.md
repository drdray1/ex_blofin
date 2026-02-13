# ExBlofin

Elixir client for the [BloFin](https://blofin.com) cryptocurrency derivatives exchange API.

Covers the full REST API (perpetual futures trading, copy trading, account management, market data) and real-time WebSocket streaming.

## Installation

Add `ex_blofin` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_blofin, git: "https://github.com/drdray1/ex_blofin.git", tag: "0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Create a client with API credentials
client = ExBlofin.new("api_key", "secret_key", "passphrase")

# Demo trading mode
client = ExBlofin.new("api_key", "secret_key", "passphrase", demo: true)

# Public-only (no auth needed)
client = ExBlofin.new(nil, nil, nil)
```

### Market Data

```elixir
{:ok, instruments} = ExBlofin.get_instruments(client)
{:ok, tickers} = ExBlofin.get_tickers(client, instId: "BTC-USDT")
{:ok, candles} = ExBlofin.get_candles(client, "BTC-USDT", bar: "1H")
{:ok, books} = ExBlofin.get_books(client, instId: "BTC-USDT")
```

### Account

```elixir
{:ok, balance} = ExBlofin.get_balance(client)
{:ok, positions} = ExBlofin.get_positions(client)
{:ok, config} = ExBlofin.get_config(client)
```

### Trading

```elixir
# Market order
{:ok, result} = ExBlofin.market_order(client, "BTC-USDT", "buy", "net", "10")

# Limit order
{:ok, result} = ExBlofin.limit_order(client, "BTC-USDT", "buy", "net", "10", "50000.0")

# Full order params
{:ok, result} = ExBlofin.place_order(client, %{
  "instId" => "BTC-USDT",
  "marginMode" => "cross",
  "positionSide" => "net",
  "side" => "buy",
  "orderType" => "limit",
  "price" => "50000.0",
  "size" => "10"
})

# Cancel order
{:ok, _} = ExBlofin.cancel_order(client, %{"orderId" => "12345", "instId" => "BTC-USDT"})
```

### WebSocket Streaming

```elixir
# Public market data
{:ok, pid} = ExBlofin.WebSocket.PublicConnection.start_link()
ExBlofin.WebSocket.PublicConnection.add_subscriber(pid, self())
ExBlofin.WebSocket.PublicConnection.subscribe(pid, [
  %{"channel" => "trades", "instId" => "BTC-USDT"},
  %{"channel" => "tickers", "instId" => "ETH-USDT"}
])

receive do
  {:blofin_event, :trades, [%ExBlofin.WebSocket.Message.TradeEvent{} = event]} ->
    IO.inspect(event)
end

# Private (orders, positions, account)
{:ok, pid} = ExBlofin.WebSocket.PrivateConnection.start_link(
  api_key: "key",
  secret_key: "secret",
  passphrase: "pass"
)
ExBlofin.WebSocket.PrivateConnection.add_subscriber(pid, self())
ExBlofin.WebSocket.PrivateConnection.subscribe(pid, [
  %{"channel" => "orders"},
  %{"channel" => "positions"}
])
```

## Modules

| Module | Description |
|--------|-------------|
| `ExBlofin` | Top-level facade with delegates |
| `ExBlofin.Client` | HTTP client (Req) with auth and response handling |
| `ExBlofin.Auth` | HMAC-SHA256 Req plugin |
| `ExBlofin.MarketData` | Public market data (instruments, tickers, books, candles) |
| `ExBlofin.Account` | Account balance, positions, margin, leverage |
| `ExBlofin.Trading` | Order management, TPSL, algo orders |
| `ExBlofin.Asset` | Asset balances, transfers, bills |
| `ExBlofin.CopyTrading` | Copy trading endpoints |
| `ExBlofin.Affiliate` | Affiliate/referral endpoints |
| `ExBlofin.User` | API key info |
| `ExBlofin.Tax` | Tax history endpoints |
| `ExBlofin.WebSocket.Message` | WS message builder/parser + event structs |
| `ExBlofin.WebSocket.Client` | WebSockex wrapper |
| `ExBlofin.WebSocket.PublicConnection` | Public WS GenServer |
| `ExBlofin.WebSocket.PrivateConnection` | Private WS GenServer (auth) |
| `ExBlofin.WebSocket.CopyTradingConnection` | Copy trading WS GenServer (auth) |

## Configuration

All configuration is optional. Sensible defaults are provided:

```elixir
# config/config.exs
config :ex_blofin,
  config: [
    base_url: "https://openapi.blofin.com",
    demo_url: "https://demo-trading-openapi.blofin.com",
    ws_public_url: "wss://openapi.blofin.com/ws/public",
    ws_private_url: "wss://openapi.blofin.com/ws/private",
    ws_copy_trading_url: "wss://openapi.blofin.com/ws/copytrading/private"
  ]
```

## Authentication

BloFin uses HMAC-SHA256 signatures with 5 headers:

- `ACCESS-KEY` - API key
- `ACCESS-SIGN` - Base64(Hex(HMAC-SHA256(secret, prehash)))
- `ACCESS-TIMESTAMP` - ISO 8601 timestamp
- `ACCESS-NONCE` - Random hex string
- `ACCESS-PASSPHRASE` - API passphrase

Authentication is handled automatically by `ExBlofin.Auth` as a Req plugin.

## Testing

```bash
mix test       # Run all tests
mix credo      # Linter
mix format     # Format code
```

Tests use `Req.Test` stubs with no external HTTP calls.

## License

MIT
