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
| `pools/web-pools.json` | Pool set raced by the site: the 30 known solo pools plus major pools from [mempool.space](https://mempool.space/graphs/mining/pools) with public stratum endpoints (OCEAN, ViaBTC, F2Pool, AntPool, Binance Pool, Luxor, SpiderPool, SECPOOL, Braiins, Kano, NiceHash, EMCD, BTC.com, Public Pool) |
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

Wins are what **this vantage point** observed first — not global proof of
propagation victory. See the main README for methodology caveats.

## Self-hosting

On a fresh Debian/Ubuntu server with your domain's DNS already pointed at it:

```bash
git clone https://github.com/proofofmike/stratum-race.git
cd stratum-race
sudo DOMAIN=your-domain.example ./web/deploy/setup.sh
```

That installs nginx + certbot, creates a `stratumrace` system user, installs
the `stratum-racer` systemd service (30-minute sessions, re-aggregating after
each), and requests a Let's Encrypt certificate. Re-running `setup.sh`
redeploys the current checkout.

Useful knobs in `/etc/stratum-race/racer.env`:

```
SESSION_SECS=1800        # length of each race session
FIRST_SESSION_SECS=900   # shorter first session so data shows up sooner
KEEP_DAYS=14             # aggregation window
VANTAGE=my basement, AS12345   # shown on the site's methodology section
POOLS=/opt/stratum-race/web/pools/web-pools.json
```

## Local preview

```bash
python3 web/aggregate.py --sessions /path/to/session-jsons --out web/site/data/leaderboard.json
cd web/site && python3 -m http.server 8080
```
