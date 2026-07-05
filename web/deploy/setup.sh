#!/usr/bin/env bash
# Idempotent server setup / redeploy for the stratumrace.com leaderboard.
#
# Run as root on a fresh Debian/Ubuntu host from a checkout of this repo:
#   sudo DOMAIN=stratumrace.com ./web/deploy/setup.sh
#
# Re-running updates code, refreshes the web root, and restarts services.
# No credentials live in this script or anywhere in the repo.
set -euo pipefail

DOMAIN="${DOMAIN:-stratumrace.com}"
REPO_DIR="${REPO_DIR:-/opt/stratum-race}"
WEB_ROOT="${WEB_ROOT:-/var/www/stratumrace}"
DATA_DIR="${DATA_DIR:-/var/lib/stratum-race/sessions}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "==> installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq nginx python3 rsync certbot python3-certbot-nginx >/dev/null

echo "==> creating service user + directories"
id -u stratumrace >/dev/null 2>&1 || useradd --system --home /var/lib/stratum-race --shell /usr/sbin/nologin stratumrace
mkdir -p "$REPO_DIR" "$WEB_ROOT/data" "$DATA_DIR" /etc/stratum-race

echo "==> syncing code to $REPO_DIR"
if [ "$SRC_DIR" != "$REPO_DIR" ]; then
  rsync -a --delete --exclude '.git' "$SRC_DIR/" "$REPO_DIR/"
fi
chmod +x "$REPO_DIR/web/run_races.sh" "$REPO_DIR/web/deploy/setup.sh"

echo "==> publishing site to $WEB_ROOT"
rsync -a --delete --exclude 'data' "$REPO_DIR/web/site/" "$WEB_ROOT/"
mkdir -p "$WEB_ROOT/data"
chown -R stratumrace:stratumrace "$DATA_DIR" /var/lib/stratum-race "$WEB_ROOT/data"

echo "==> writing racer environment"
if [ ! -f /etc/stratum-race/racer.env ]; then
  REGION="$(curl -fsm 3 http://169.254.169.254/metadata/v1/region 2>/dev/null || true)"
  {
    echo "SESSION_SECS=1800"
    echo "FIRST_SESSION_SECS=900"
    [ -n "$REGION" ] && echo "VANTAGE=cloud server (${REGION})"
  } > /etc/stratum-race/racer.env
fi

echo "==> seeding leaderboard.json"
sudo -u stratumrace python3 "$REPO_DIR/web/aggregate.py" \
  --sessions "$DATA_DIR" --out "$WEB_ROOT/data/leaderboard.json" \
  --vantage "$(grep -oP '(?<=^VANTAGE=).*' /etc/stratum-race/racer.env 2>/dev/null || true)"

echo "==> installing systemd service"
cp "$REPO_DIR/web/deploy/stratum-racer.service" /etc/systemd/system/stratum-racer.service
systemctl daemon-reload
systemctl enable stratum-racer.service
systemctl restart stratum-racer.service

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  echo "==> opening firewall ports 80/443"
  ufw allow 80/tcp >/dev/null || true
  ufw allow 443/tcp >/dev/null || true
fi

echo "==> configuring nginx for $DOMAIN"
# Write the vhost only on first install: certbot rewrites this file to add
# TLS, and regenerating it on redeploy would clobber the 443 server block.
NGINX_CONF=/etc/nginx/sites-available/stratumrace.conf
if [ ! -f "$NGINX_CONF" ]; then
  sed "s/stratumrace\.com/${DOMAIN}/g" \
    "$REPO_DIR/web/deploy/nginx-stratumrace.conf" > "$NGINX_CONF"
fi
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/stratumrace.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

echo "==> requesting TLS certificate (best effort)"
if certbot certificates 2>/dev/null | grep -q "Domains:.*${DOMAIN}"; then
  echo "certificate already present"
  if ! grep -q "listen 443" "$NGINX_CONF"; then
    echo "re-attaching existing certificate to nginx config"
    certbot install --nginx --cert-name "$DOMAIN" --non-interactive --redirect \
      || echo "WARNING: certbot install failed — site may be HTTP-only"
  fi
else
  certbot --nginx --non-interactive --agree-tos --register-unsafely-without-email \
    -d "$DOMAIN" -d "www.${DOMAIN}" --redirect \
  || certbot --nginx --non-interactive --agree-tos --register-unsafely-without-email \
    -d "$DOMAIN" --redirect \
  || echo "WARNING: certbot failed — site remains HTTP-only for now"
fi

echo "==> done"
systemctl --no-pager --lines 5 status stratum-racer.service || true
echo "Site: http://${DOMAIN}/ (https if certbot succeeded)"
