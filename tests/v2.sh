#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. ./common.sh
. ./v2.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export PROFIT_FILE="$tmp/window"
export POOL=stratum+ssl://prl.kryptex.network:8048
export PAYOUT_MODE=btc KRYPTEX_USERNAME=krx123456
check_wallet
[ "$WALLET" = krx123456 ]
POOL_HOSTPORT=prl.kryptex.network:8048 KRIG_HOSTPORT=prl.kryptex.network:8048 SRB_TLS=--tls
for miner in srb bz krig; do miner_cmd "$miner" | grep -q krx123456; done
if (POOL=stratum+ssl://prl.kryptex.network.evil:8048; check_wallet) >/dev/null 2>&1; then exit 1; fi
if (KRYPTEX_USERNAME='krx123;id'; check_wallet) >/dev/null 2>&1; then exit 1; fi
if (PROFIT_WINDOW=0; check_wallet) >/dev/null 2>&1; then exit 1; fi
if (PAYOUT_MODE=invalid; check_wallet) >/dev/null 2>&1; then exit 1; fi
if (PROFIT_MODE=monitor; unset PROFIT_COST_USD_HOUR; check_wallet) >/dev/null 2>&1; then exit 1; fi
NOW=10000
date() { echo "$NOW"; }
V2_STARTED=10000
REALLOCATE_MODE=preview
if reallocation_allowed; then exit 1; fi
REALLOCATE_MODE=enabled
if reallocation_allowed; then exit 1; fi
NOW=11800
reallocation_allowed
if reallocation_allowed; then exit 1; fi
NOW=13600
reallocation_allowed
NOW=15400
if reallocation_allowed; then exit 1; fi
REALLOC_ATTEMPTS=0 REALLOC_ACCEPTED=1
if reallocation_allowed; then exit 1; fi
echo 'ok: BTC configuration and central reallocation guard'

PROFIT_MODE=monitor PROFIT_COST_USD_HOUR=1 PROFIT_WARMUP=10 PROFIT_WINDOW=10 PROFIT_GRACE=2 PROFIT_MAX_AGE=100
PROFIT_RATE_TIMESTAMP=10000 PROFIT_USD_PER_THS_DAY=0.24
NOW=10000
profit_reset
printf 'pearl hashrate 10.00th\npearl hashrate 10.00th\npearl hashrate 10.00th\n' > "$tmp/miner"
profit_tick bz 0 "$tmp/miner"
NOW=10020
profit_tick bz 0 "$tmp/miner"
[ "$PF_BAD" = 1 ]
NOW=10030
profit_tick bz 0 "$tmp/miner"
[ "$PF_BAD" = 2 ]
PROFIT_RATE_TIMESTAMP=1
NOW=10040
profit_tick bz 0 "$tmp/miner"
[ "$PF_BAD" = 0 ]
PROFIT_RATE_TIMESTAMP=10050 PROFIT_USD_PER_THS_DAY=240
NOW=10050
profit_tick bz 0 "$tmp/miner"
[ "$PF_BAD" = 0 ]
PROFIT_USD_PER_THS_DAY=NaN
NOW=10060
profit_tick bz 0 "$tmp/miner"
[ "$PF_BAD" = 0 ]
PROFIT_USD_PER_THS_DAY=0.24 PROFIT_RATE_TIMESTAMP=20000
NOW=10070
profit_tick bz 0 "$tmp/miner"
[ "$PF_BAD" = 0 ]
PROFIT_RATE_TIMESTAMP=10080
: > "$tmp/miner"
NOW=10080
profit_tick bz 0 "$tmp/miner"
[ "$PF_BAD" = 0 ]
echo 'ok: loss windows, recovery, stale/future/malformed rates and missing samples'

# Exercise the real reallocation function with a fake HTTP client, never IMDS.
curl() { echo called >> "$tmp/calls"; printf 200; }
ship_flush() { :; }
REALLOCATE_MODE=preview
if salad_reallocate test; then exit 1; fi
[ ! -e "$tmp/calls" ]
REALLOCATE_MODE=enabled REALLOC_ACCEPTED=0 REALLOC_ATTEMPTS=0 REALLOC_LAST=0 V2_STARTED=1
salad_reallocate test
[ "$(wc -l < "$tmp/calls")" -eq 1 ]
if salad_reallocate test; then exit 1; fi
[ "$(wc -l < "$tmp/calls")" -eq 1 ]
echo 'ok: preview never posts; successful request is latched'
