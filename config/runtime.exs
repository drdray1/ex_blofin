import Config

config :ex_blofin,
  http: [
    max_retries: 3,
    retry_base_delay_ms: 500
  ],
  websocket: [
    ping_interval_ms: 25_000,
    reconnect_base_delay_ms: 1_000,
    reconnect_max_delay_ms: 30_000,
    max_reconnect_attempts: 10
  ]
