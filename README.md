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
{:ok, books} = ExBlofin.get_books(client, "BTC-USDT")
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

## Terminal Tools

Real-time terminal visualizations using WebSocket streams and REST polling. No API credentials required.

### Dashboard (all-in-one)

Launch all visualizations in a single tmux session:

```bash
./scripts/dashboard.sh BTC-USDT ETH-USDT SOL-USDT
./scripts/dashboard.sh --scanner --bar 5m
./scripts/dashboard.sh --kill
```

Layout:

```
┌──────────────────┬──────────────────┐
│ Ticker Dashboard │ Candlestick Chart│
├──────────────────┤ (first inst)     │
│ Trade Tape       │                  │
├──────────────────┼──────────────────┤
│ Order Book       │ Funding Rate     │
└──────────────────┴──────────────────┘
```

![Dashboard](assets/dashboard.png)

Options: `--demo`, `--scanner` (replaces tickers with market scanner), `--bar BAR` (chart timeframe), `--kill`

### Individual Tools

**Order Book** — real-time bid/ask depth (1-4 instruments)

```bash
mix run scripts/orderbook.exs BTC-USDT
mix run scripts/orderbook.exs BTC-USDT ETH-USDT SOL-USDT DOGE-USDT
```

**Trade Tape** — scrolling time & sales

```bash
mix run scripts/trades.exs BTC-USDT ETH-USDT --max 40
```

**Ticker Dashboard** — watchlist with 24h stats

```bash
mix run scripts/tickers.exs BTC-USDT ETH-USDT SOL-USDT
```

**Funding Rate Monitor** — current/annualized rates + countdown

```bash
mix run scripts/funding.exs BTC-USDT ETH-USDT SOL-USDT
```

**Candlestick Chart** — ASCII candles with volume bars

```bash
mix run scripts/chart.exs BTC-USDT --bar 5m --height 20
```

**Market Scanner** — all instruments ranked by volume/change

```bash
mix run scripts/scanner.exs --sort volume --top 20
mix run scripts/scanner.exs --sort gainers
```

All tools support `--demo` for the sandbox environment. Press `Ctrl+C` twice to exit.

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
| `ExBlofin.Terminal.OrderBook` | Real-time order book display |
| `ExBlofin.Terminal.MultiOrderBook` | Multi-instrument order book grid |
| `ExBlofin.Terminal.TradeTape` | Scrolling trade tape |
| `ExBlofin.Terminal.TickerDashboard` | Ticker watchlist dashboard |
| `ExBlofin.Terminal.FundingMonitor` | Funding rate monitor |
| `ExBlofin.Terminal.CandlestickChart` | ASCII candlestick chart |
| `ExBlofin.Terminal.MarketScanner` | Market scanner (REST polling) |

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

## API Key Setup

1. Go to [BloFin API Management](https://blofin.com/account/api)
2. Click **+ Create API Key**
3. Select **Connect to Third-Party Applications** as usage type
4. Choose **CCXT** as the application (required — other options may not work)
5. Set a name and passphrase (4-20 chars, letters/numbers/underscores)
6. Check **Read** and **Trade** permissions
7. Add your server's public IP to the whitelist
8. **Copy the API Key, Secret Key, and Passphrase immediately** — the secret is only shown once

## Authentication

BloFin uses HMAC-SHA256 signatures with 5 headers:

- `ACCESS-KEY` - API key
- `ACCESS-SIGN` - Base64(Hex(HMAC-SHA256(secret, prehash)))
- `ACCESS-TIMESTAMP` - Millisecond epoch timestamp
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
