#!/bin/sh
# Pearl Miner V2: bounded, opt-in decisions; no group-level API credentials.
V2_STARTED=$(date +%s)
REALLOC_LAST=0
REALLOC_ATTEMPTS=0
REALLOC_ACCEPTED=0

v2_config() {
  REALLOCATE_MODE=${REALLOCATE_MODE:-preview}
  REALLOCATE_COOLDOWN=${REALLOCATE_COOLDOWN:-1800}
  REALLOCATE_MAX_ATTEMPTS=${REALLOCATE_MAX_ATTEMPTS:-2}
  PROFIT_MODE=${PROFIT_MODE:-off}
  PROFIT_WINDOW=${PROFIT_WINDOW:-300}
  PROFIT_WARMUP=${PROFIT_WARMUP:-300}
  PROFIT_GRACE=${PROFIT_GRACE:-3}
  PROFIT_MAX_AGE=${PROFIT_MAX_AGE:-900}
  PROFIT_MIN_USD_HOUR=${PROFIT_MIN_USD_HOUR:-0}
  PROFIT_POOL_FEE_PCT=${PROFIT_POOL_FEE_PCT:-1}
  PROFIT_FILE=${PROFIT_FILE:-/tmp/pearl-profit-window.log}
  case "$REALLOCATE_MODE:$PROFIT_MODE" in
    preview:off|preview:monitor|preview:reallocate|enabled:off|enabled:monitor|enabled:reallocate) ;;
    *) echo 'ERROR: invalid reallocation/profit mode' >&2; exit 1 ;;
  esac
  for value in "$REALLOCATE_COOLDOWN" "$REALLOCATE_MAX_ATTEMPTS" "$PROFIT_WINDOW" "$PROFIT_WARMUP" "$PROFIT_GRACE" "$PROFIT_MAX_AGE"; do
    if ! printf '%s\n' "$value" | grep -Eq '^[1-9][0-9]{0,6}$'; then
      echo 'ERROR: timing and count controls must be positive integers (max 7 digits)' >&2; exit 1
    fi
  done
  for value in "$PROFIT_MIN_USD_HOUR" "$PROFIT_POOL_FEE_PCT"; do
    if ! printf '%s\n' "$value" | grep -Eq '^[0-9]+([.][0-9]+)?$'; then
      echo 'ERROR: profit threshold and pool fee must be nonnegative numbers' >&2; exit 1
    fi
  done
  awk -v f="$PROFIT_POOL_FEE_PCT" 'BEGIN {exit !(f < 100)}' || { echo 'ERROR: fee must be below 100%' >&2; exit 1; }
  if [ "$PROFIT_MODE" != off ]; then
    if ! printf '%s\n' "${PROFIT_COST_USD_HOUR:-}" | grep -Eq '^[0-9]+([.][0-9]+)?$'; then
      echo 'ERROR: monitoring needs explicit all-in PROFIT_COST_USD_HOUR' >&2; exit 1
    fi
    case "${PROFIT_RATE_URL:-}" in ''|https://*) ;; *) echo 'ERROR: rate feed must use HTTPS' >&2; exit 1 ;; esac
  fi
  echo "=== Pearl Miner V2: payout=${PAYOUT_MODE:-prl}, profitability=$PROFIT_MODE, reallocation=$REALLOCATE_MODE ==="
}

reallocation_allowed() {
  if [ "${REALLOCATE_MODE:-preview}" != enabled ]; then
    echo '=== reallocation preview: request blocked; enable only after deployment approval ==='; return 1
  fi
  [ "$REALLOC_ACCEPTED" = 0 ] || return 1
  _ra_now=$(date +%s)
  if [ "$REALLOC_ATTEMPTS" -ge "$REALLOCATE_MAX_ATTEMPTS" ] ||
     [ $((_ra_now - V2_STARTED)) -lt "$REALLOCATE_COOLDOWN" ] ||
     { [ "$REALLOC_LAST" -gt 0 ] && [ $((_ra_now - REALLOC_LAST)) -lt "$REALLOCATE_COOLDOWN" ]; }; then
    echo '=== reallocation suppressed: startup hold, cooldown or attempt budget ==='; return 1
  fi
  REALLOC_LAST=$_ra_now
  REALLOC_ATTEMPTS=$((REALLOC_ATTEMPTS + 1))
}

profit_reset() {
  PF_START=0; PF_NEXT=0; PF_BAD=0
  : > "$PROFIT_FILE"
}

profit_tick() {
  [ "$PROFIT_MODE" != off ] || return 0
  _pf_now=$(date +%s)
  if [ "$PF_START" = 0 ]; then
    PF_START=$_pf_now; PF_NEXT=$((_pf_now + PROFIT_WARMUP + PROFIT_WINDOW))
  fi
  [ $((_pf_now - PF_START)) -ge "$PROFIT_WARMUP" ] || return 0
  cat "$3" >> "$PROFIT_FILE"
  [ "$_pf_now" -ge "$PF_NEXT" ] || return 0
  PF_NEXT=$((_pf_now + PROFIT_WINDOW))
  _pf_reading=$(parse_hashrate "$PROFIT_FILE" 0)
  : > "$PROFIT_FILE"
  _pf_rate="${PROFIT_RATE_TIMESTAMP:-} ${PROFIT_USD_PER_THS_DAY:-}"
  if [ -n "${PROFIT_RATE_URL:-}" ]; then
    _pf_rate=$(curl --fail --silent --show-error --proto '=https' --max-time 5 --max-filesize 1024 "$PROFIT_RATE_URL" 2>/dev/null) || _pf_rate=''
  fi
  # Feed is exactly: UNIX_TIMESTAMP USD_PER_THS_DAY (gross, before fees).
  # A single strict line avoids silently treating malformed/HTML responses as zero.
  _pf_calc=$(printf '%s\n' "$_pf_rate" | awk -v now="$_pf_now" -v age="$PROFIT_MAX_AGE" \
    -v reading="$_pf_reading" -v cost="$PROFIT_COST_USD_HOUR" \
    -v fee="$PROFIT_POOL_FEE_PCT" -v dev="$(miner_devfee "$1")" -v floor="$PROFIT_MIN_USD_HOUR" '
    NR == 1 && NF == 2 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+([.][0-9]+)?$/ {
      if (now-$1 < 0 || now-$1 > age || $2 <= 0) next
      split(reading, r, " "); if (r[2] < 3 || r[1] <= 0) next
      gross=r[1]*$2/24; net=gross*(1-dev/100)*(1-fee/100)-cost
      result=sprintf("%.6f %.6f %d", gross, net, net < floor); valid=1
    }
    END {if (NR == 1 && valid) print result}')
  if [ -z "$_pf_calc" ]; then
    PF_BAD=0; echo '=== profit: unknown (missing/stale rate or insufficient hashrate); no action ==='; return 0
  fi
  _pf_net=$(printf '%s\n' "$_pf_calc" | awk '{print $2}')
  echo "=== profit: GPU=${GPU_DESC:-unknown}, miner=$1, estimated net USD/hour=$_pf_net, cost=$PROFIT_COST_USD_HOUR ==="
  case "$_pf_calc" in
    *' 1') PF_BAD=$((PF_BAD + 1)) ;;
    *) PF_BAD=0 ;;
  esac
  if [ "$PF_BAD" -ge "$PROFIT_GRACE" ]; then
    echo "=== profit below threshold for $PF_BAD windows; action=$PROFIT_MODE ==="
    if [ "$PROFIT_MODE" = reallocate ] && salad_reallocate "sustained low estimated profit USD/hour=$_pf_net"; then
      kill_miner "$1" "$2"
      isleep 180
      exit 1
    fi
  fi
}
