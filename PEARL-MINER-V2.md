# Pearl Miner V2 — deployment review

Prepared on AIBRAIN. GitHub Actions builds both container targets and runs
mocked tests on GitHub-hosted Ubuntu runners. Neither CI nor this change
deploys a container group, starts mining, or updates the existing image tags.
Keep this branch unmerged until the deployment review is complete: the existing
main-branch workflow publishes `latest` on merge.

## Bundled releases

* SRBMiner 3.8.0
* BzMiner 100.50
* KRig 1.5.12

Dockerfile SHA-256 pins are the official GitHub Linux x64 asset digests.
CI downloads and verifies the archives and builds both `miner` and `bench`.
GPU performance and accepted-share validation still require an approved canary;
GitHub-hosted CI does not have an NVIDIA GPU and does not mine.

## Kryptex BTC conversion

Set `PAYOUT_MODE=btc`, `KRYPTEX_USERNAME=krx...` (your real mining username),
and `POOL=stratum+ssl://prl.kryptex.network:8048`. BTC mode substitutes the
account username for WALLET in all three miners, preserves their worker
syntax, and rejects non-Kryptex Pearl endpoints. Region probing still works.
The default `PAYOUT_MODE=prl` preserves direct Pearl payouts.

Kryptex performs conversion and credits BTC to your account. This does not
configure withdrawals or send funds to a Bitcoin address. See the official
[account mining instructions](https://pool.kryptex.com/articles/account-mining-en).
No account credentials or private keys belong in this repository.

## Profitability monitoring

Set `PROFIT_MODE=monitor` and `PROFIT_COST_USD_HOUR` to the actual all-in cost
for this container (rental or measured electricity plus overhead). Supply an
HTTPS `PROFIT_RATE_URL` returning exactly one plain-text line:

```text
UNIX_TIMESTAMP GROSS_USD_PER_THS_DAY
```

This is an operator-supplied feed contract, **not a claimed Kryptex API**.
Its publisher must refresh the gross Pearl revenue per TH/s per day from a
trusted earnings source, including conversion spread in its valuation.
Alternatively supply `PROFIT_RATE_TIMESTAMP` and `PROFIT_USD_PER_THS_DAY`
for a short-lived manual snapshot. No price or profitability is invented.
The feed defaults to expiring after 900 seconds (`PROFIT_MAX_AGE`). Failed
requests, stale/future/malformed data or fewer than three rate observations
reset the loss streak and cannot trigger reallocation.

After the first accepted share, the monitor waits `PROFIT_WARMUP=300` seconds,
then computes median aggregate miner hashrate over `PROFIT_WINDOW=300` seconds.
It logs GPU description, miner, estimated net USD/hour and cost. Fees are applied
once: miner devfee from `miner_devfee`, then `PROFIT_POOL_FEE_PCT=1`.
Net = median TH/s × gross USD/TH/day ÷ 24 × fee factors − hourly cost.
These are estimates, not account earnings; aggregate GPU output means cost
must cover the entire container, not just one device.

`PROFIT_MIN_USD_HOUR=0` is the default net threshold. Only after
`PROFIT_GRACE=3` consecutive valid low windows will `PROFIT_MODE=reallocate`
request another host. `monitor` only reports. Changing hosts cannot fix a
market-wide loss and does not change the group's GPU class or replica count.

## Controlled reallocation

Every path, including existing thermal, wrong-GPU, pool and hashrate checks,
now passes through a central gate. Default `REALLOCATE_MODE=preview` blocks
all IMDS writes. Enable it only in the reviewed deployment configuration.

With `REALLOCATE_MODE=enabled`, defaults are a 1,800-second startup hold and
cooldown (`REALLOCATE_COOLDOWN`) and at most two HTTP attempts per container
process (`REALLOCATE_MAX_ATTEMPTS`). Failed HTTP attempts consume budget.
A successful request latches the gate closed until this process exits.
These limits are process-local: restarts/new nodes reset them and impose the
startup hold again. They are **not a fleet-wide daily budget**. Existing
one-shot health checks can warn and continue when the gate blocks their
request; they are not queued for later. No change sets GPU clocks or power.

## Approval checklist

Before a canary: review passing Actions results; provide the Kryptex username,
actual hourly cost, trusted rate feed and desired limits; approve an isolated
one-replica canary with an immutable image digest and explicit preview mode.
Check actual accepted shares, account attribution, fees and estimates before
enabling reallocation or changing any existing SaladCloud group. Record the
old group's image digest/settings for rollback. This PR includes no deployment
workflow and needs no SaladCloud API key.
