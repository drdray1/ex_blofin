#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# BloFin Terminal Dashboard
#
# Launches all terminal visualizations in a single tmux session with
# a multi-pane layout.
#
# Usage:
#   ./scripts/dashboard.sh
#   ./scripts/dashboard.sh BTC-USDT ETH-USDT
#   ./scripts/dashboard.sh --scanner --bar 5m
#   ./scripts/dashboard.sh --kill
#
# Layout:
#   ┌──────────────────┬──────────────────┐
#   │ Ticker Dashboard │ Candlestick Chart│
#   ├──────────────────┤ (first inst)     │
#   │ Trade Tape       │                  │
#   ├──────────────────┼──────────────────┤
#   │ Order Book       │ Funding Rate     │
#   └──────────────────┴──────────────────┘
#
# Press prefix+& or run --kill to stop.
# ============================================================================

SESSION="blofin-dashboard"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Defaults
INSTRUMENTS=()
BAR="1m"
DEMO=false
KILL=false
USE_SCANNER=false

# ============================================================================
# Usage
# ============================================================================

usage() {
  cat <<'EOF'
BloFin Terminal Dashboard

Usage: scripts/dashboard.sh [OPTIONS] [INSTRUMENTS...]

Arguments:
  INSTRUMENTS       Space-separated instrument IDs (default: BTC-USDT ETH-USDT SOL-USDT)

Options:
  --demo            Use demo/sandbox environment for all panes
  --kill            Kill existing dashboard session and exit
  --scanner         Replace ticker dashboard with market scanner
  --bar BAR         Chart candle timeframe (default: 1m)
  -h, --help        Show this help message

Examples:
  ./scripts/dashboard.sh
  ./scripts/dashboard.sh BTC-USDT ETH-USDT SOL-USDT DOGE-USDT
  ./scripts/dashboard.sh --scanner --bar 5m
  ./scripts/dashboard.sh --demo
  ./scripts/dashboard.sh --kill
EOF
  exit 0
}

# ============================================================================
# Argument Parsing
# ============================================================================

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        ;;
      --kill)
        KILL=true
        shift
        ;;
      --demo)
        DEMO=true
        shift
        ;;
      --scanner)
        USE_SCANNER=true
        shift
        ;;
      --bar)
        BAR="${2:?--bar requires a value (e.g. 1m, 5m, 1H)}"
        shift 2
        ;;
      -*)
        echo "Unknown option: $1" >&2
        echo "Run with -h for usage." >&2
        exit 1
        ;;
      *)
        INSTRUMENTS+=("$1")
        shift
        ;;
    esac
  done

  # Apply defaults if no instruments given
  if [[ ${#INSTRUMENTS[@]} -eq 0 ]]; then
    INSTRUMENTS=("BTC-USDT" "ETH-USDT" "SOL-USDT")
  fi
}

# ============================================================================
# Prerequisites
# ============================================================================

check_prereqs() {
  if ! command -v tmux &>/dev/null; then
    echo "Error: tmux is required but not installed." >&2
    echo "Install with: sudo apt install tmux" >&2
    exit 1
  fi
}

# ============================================================================
# Session Management
# ============================================================================

kill_session() {
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    tmux kill-session -t "$SESSION"
    echo "Killed session: $SESSION"
  else
    echo "No active session: $SESSION"
  fi
}

# ============================================================================
# Main
# ============================================================================

main() {
  parse_args "$@"
  check_prereqs

  # Handle --kill
  if [[ "$KILL" == true ]]; then
    kill_session
    exit 0
  fi

  # Kill existing session before recreating
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    tmux kill-session -t "$SESSION"
  fi

  # Pre-compile to avoid 5 simultaneous compilation races
  echo "Compiling project..."
  (cd "$PROJECT_DIR" && mix compile) || { echo "Compile failed" >&2; exit 1; }

  # Build command parts
  local demo_flag=""
  if [[ "$DEMO" == true ]]; then
    demo_flag="--demo"
  fi

  local inst_str="${INSTRUMENTS[*]}"
  local first="${INSTRUMENTS[0]}"

  # Commands for each pane (reduced defaults for dashboard context)
  local tickers_cmd="mix run scripts/tickers.exs ${inst_str} ${demo_flag}"
  local chart_cmd="mix run scripts/chart.exs ${first} --height 15 --width 40 --bar ${BAR} ${demo_flag}"
  local trades_cmd="mix run scripts/trades.exs ${inst_str} --max 15 ${demo_flag}"
  local orderbook_cmd="mix run scripts/orderbook.exs ${inst_str} --levels 8 ${demo_flag}"
  local funding_cmd="mix run scripts/funding.exs ${inst_str} ${demo_flag}"

  # Override tickers with scanner if requested
  local tickers_title="Tickers"
  if [[ "$USE_SCANNER" == true ]]; then
    tickers_cmd="mix run scripts/scanner.exs --top 15 ${demo_flag}"
    tickers_title="Scanner"
  fi

  echo "Starting dashboard: ${inst_str}"
  echo "Layout: ${tickers_title} | Chart [${first}] | Trades | Order Book | Funding"
  echo ""

  # ── Create tmux session and panes ──────────────────────────────────────────
  #
  # Layout:
  #   ┌──────────┬──────────┐
  #   │ Tickers  │  Chart   │  <- top row
  #   ├──────────┤          │
  #   │ Trades   │          │  <- chart gets 65% of right column
  #   ├──────────┼──────────┤
  #   │ Orderbook│ Funding  │  <- bottom row
  #   └──────────┴──────────┘

  # Create session with first pane (Tickers / Scanner)
  # Pass commands directly to avoid interactive shell (bypasses shell profile)
  local pane_tickers
  pane_tickers=$(tmux new-session -d -s "$SESSION" -c "$PROJECT_DIR" -P -F '#{pane_id}' "$tickers_cmd")

  # Split right 50% for Chart
  local pane_chart
  pane_chart=$(tmux split-window -h -t "$pane_tickers" -p 50 -c "$PROJECT_DIR" -P -F '#{pane_id}' "$chart_cmd")

  # Split Tickers vertically — bottom 67% for Trades + Orderbook
  local pane_trades
  pane_trades=$(tmux split-window -v -t "$pane_tickers" -p 67 -c "$PROJECT_DIR" -P -F '#{pane_id}' "$trades_cmd")

  # Split Trades in half — bottom becomes Orderbook
  local pane_orderbook
  pane_orderbook=$(tmux split-window -v -t "$pane_trades" -p 50 -c "$PROJECT_DIR" -P -F '#{pane_id}' "$orderbook_cmd")

  # Split Chart — bottom 35% becomes Funding
  local pane_funding
  pane_funding=$(tmux split-window -v -t "$pane_chart" -p 35 -c "$PROJECT_DIR" -P -F '#{pane_id}' "$funding_cmd")

  # ── Style the session ─────────────────────────────────────────────────────

  # Enable mouse for pane resizing/selection
  tmux set-option -t "$SESSION" mouse on

  # Status bar
  tmux set-option -t "$SESSION" status-style "bg=colour235,fg=colour39"
  tmux set-option -t "$SESSION" status-left " BloFin Dashboard "
  tmux set-option -t "$SESSION" status-right " ${inst_str} | %H:%M:%S "
  tmux set-option -t "$SESSION" status-left-length 20
  tmux set-option -t "$SESSION" status-right-length 60

  # Pane borders
  tmux set-option -t "$SESSION" pane-border-style "fg=colour238"
  tmux set-option -t "$SESSION" pane-active-border-style "fg=colour39"
  tmux set-option -t "$SESSION" pane-border-status top
  tmux set-option -t "$SESSION" pane-border-format " #{pane_title} "

  # Pane titles
  tmux select-pane -t "$pane_tickers"   -T "$tickers_title"
  tmux select-pane -t "$pane_chart"     -T "Chart [${first} ${BAR}]"
  tmux select-pane -t "$pane_trades"    -T "Trades"
  tmux select-pane -t "$pane_orderbook" -T "Order Book"
  tmux select-pane -t "$pane_funding"   -T "Funding"

  # Focus on chart pane
  tmux select-pane -t "$pane_chart"

  # ── Attach ─────────────────────────────────────────────────────────────────

  tmux attach-session -t "$SESSION"
}

main "$@"
