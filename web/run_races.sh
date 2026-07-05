#!/usr/bin/env bash
# Continuous stratum-race runner: races in fixed-length sessions, then
# re-aggregates the public leaderboard after every session.
set -u

REPO_DIR="${REPO_DIR:-/opt/stratum-race}"
DATA_DIR="${DATA_DIR:-/var/lib/stratum-race/sessions}"
WEB_ROOT="${WEB_ROOT:-/var/www/stratumrace}"
POOLS="${POOLS:-$REPO_DIR/web/pools/web-pools.json}"
SESSION_SECS="${SESSION_SECS:-1800}"
FIRST_SESSION_SECS="${FIRST_SESSION_SECS:-900}"
KEEP_DAYS="${KEEP_DAYS:-14}"
VANTAGE="${VANTAGE:-}"

mkdir -p "$DATA_DIR" "$WEB_ROOT/data"

aggregate() {
  python3 "$REPO_DIR/web/aggregate.py" \
    --sessions "$DATA_DIR" \
    --out "$WEB_ROOT/data/leaderboard.json" \
    --vantage "$VANTAGE" || echo "aggregate failed" >&2
}

# Publish something immediately so the site renders before the first session ends.
aggregate

dur="$FIRST_SESSION_SECS"
while true; do
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  out="$DATA_DIR/session-$ts.json"
  echo "starting race session: duration=${dur}s out=$out"

  # Hard timeout well past the session length in case the racer wedges.
  timeout --signal=INT $((dur + 900)) \
    python3 "$REPO_DIR/str_race.py" \
      --pools "$POOLS" \
      --duration "$dur" \
      --tag-block-miners \
      --json-out "$out" \
    || echo "race session exited nonzero" >&2

  aggregate

  # Drop sessions older than KEEP_DAYS so the aggregate window stays bounded.
  find "$DATA_DIR" -name 'session-*.json' -mtime +"$KEEP_DAYS" -delete 2>/dev/null

  dur="$SESSION_SECS"
  sleep 5
done
