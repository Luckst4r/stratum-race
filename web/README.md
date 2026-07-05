# Stratum Race — web leaderboard

A small, self-hostable website that runs `str_race.py` continuously and
publishes a live ranking of Bitcoin mining pools by how quickly they deliver
new-block stratum notifications (`mining.notify` with `clean_jobs=true`).

Live instance: **https://stratumrace.com**

Everything is dependency-free: the racer and aggregator are stdlib Python,
the site is static HTML/CSS/JS served by nginx.

## Layout

| Path | Purpose |
|------|---------|
| `pools/web-pools.json` | Pool set raced by the site: the 30 known solo pools plus major pools from [mempool.space](https://mempool.space/graphs/mining/pools) with public stratum endpoints (OCEAN, ViaBTC, F2Pool, AntPool, Binance Pool, Luxor, SpiderPool, SECPOOL, Braiins, Kano, NiceHash, EMCD, Public Pool) |
| `run_races.sh` | Loop: run a 30-minute race session, aggregate, repeat |
| `aggregate.py` | Merges all session exports into `leaderboard.json` (dedupes races by prevhash, recomputes stats across the full window) |
| `site/` | Static frontend — dark, minimal leaderboard that polls `data/leaderboard.json` |
| `deploy/` | nginx vhost, systemd unit, and an idempotent `setup.sh` |

## How rankings work

Every confirmed race (a new prevhash confirmed by multiple pools within the
confirm window) contributes one arrival offset per pool: the number of
milliseconds that pool was behind the first pool to deliver the block.
The leaderboard sorts pools by **median offset** across all races in the
observation window (default: last 14 days of sessions). Pools need at least
3 observed races to be ranked; the rest are shown as *collecting* or
*unreachable*.

**Empty templates:** some pools broadcast a coinbase-only (empty) template
the moment a block is found and only later send the full template. Ranking on
"first notify" would reward skipping transaction selection entirely, so the
leaderboard times each pool to its **first non-empty template** instead. No
pool is excluded — the *Empty 1st* column shows how often a pool led with an
empty template, and each block's earlier empty notify appears as
*Empty jump-start* in the recent-blocks table.

Wins are what **this vantage point** observed first — not global proof of
propagation victory. See the main README for methodology caveats.

**Vantage point:** all timings are measured from wherever the racer runs (the
live instance measures from San Francisco), and pools with nearby
infrastructure have a structural advantage. The site states its vantage in the
header and methodology. For a fuller picture, run racers from several regions
and compare.

## Self-hosting

On a fresh Debian/Ubuntu server with your domain's DNS already pointed at it:

```bash
git clone https://github.com/proofofmike/stratum-race.git
cd stratum-race
sudo DOMAIN=your-domain.example ./web/deploy/setup.sh
```

That installs nginx + certbot, creates a `stratumrace` system user, installs
the `stratum-racer` systemd service (15-minute sessions, re-aggregating after
each), and requests a Let's Encrypt certificate. Re-running `setup.sh`
redeploys the current checkout. Stops and restarts are graceful: the racer is
interrupted with SIGINT so the in-flight session still writes its results.

Knobs in `/etc/stratum-race/racer.env` (`SESSION_SECS`, `FIRST_SESSION_SECS`,
and `KEEP_DAYS` are rewritten by `setup.sh` on each deploy; a customized
`VANTAGE` is preserved):

```
SESSION_SECS=900         # length of each race session
FIRST_SESSION_SECS=600   # shorter first session so data shows up sooner
KEEP_DAYS=14             # aggregation window
VANTAGE=my basement, AS12345   # shown on the site's methodology section
POOLS=/opt/stratum-race/web/pools/web-pools.json
```

## Local preview

```bash
python3 web/aggregate.py --sessions /path/to/session-jsons --out web/site/data/leaderboard.json
cd web/site && python3 -m http.server 8080
```
