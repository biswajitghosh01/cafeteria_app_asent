#!/usr/bin/env bash
# =============================================================
# Food Court Counter — Ubuntu Production Deployment
#
#   export DOMAIN=counter.example.com
#   export LETSENCRYPT_EMAIL=admin@example.com     # optional
#   sudo -v && ./deploy/scripts/deploy-ubuntu.sh
# =============================================================
set -euo pipefail

say()  { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] && die "Do NOT run as root. Use a sudo-capable user."

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

[[ -f /etc/os-release ]] || die "Not Ubuntu."
# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}" in
  ubuntu) ok "Detected Ubuntu ${VERSION_ID}" ;;
  debian) warn "Detected Debian ${VERSION_ID} — proceeding" ;;
  *)      die "Unsupported distro: ${ID:-unknown}" ;;
esac

: "${DOMAIN:?Set DOMAIN=<your.domain> first (export DOMAIN=counter.example.com)}"
APP_DIR="${APP_DIR:-/var/www/food-court-counter}"
DB_NAME="${DB_NAME:-food_court_db}"
DB_USER="${DB_USER:-fc_user}"
DB_PASS="${DB_PASS:-$(openssl rand -hex 16)}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-admin@${DOMAIN}}"
SERVICE_NAME="food-court-api"
LOG_DIR="/var/log/food-court-counter"

say "[1/9] Installing system packages"
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  apache2 postgresql postgresql-contrib \
  python3 python3-venv python3-pip \
  nodejs npm git curl rsync openssl \
  certbot python3-certbot-apache
ok "System packages installed"

say "[2/9] Enabling Apache modules"
sudo a2enmod proxy proxy_http rewrite headers ssl deflate expires >/dev/null
sudo systemctl restart apache2
ok "Apache modules enabled"

say "[3/9] Syncing project to $APP_DIR"
sudo mkdir -p "$APP_DIR"
sudo chown -R "$USER":"$USER" "$APP_DIR"
rsync -a --delete \
  --exclude '.git' --exclude 'node_modules' --exclude '.venv' \
  --exclude 'frontend/dist' --exclude 'backend/logs' \
  --exclude 'backend/food_court_dev.db' \
  "$PROJECT_ROOT"/ "$APP_DIR"/
ok "Project synced"

say "[4/9] Setting up PostgreSQL"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" \
  | grep -q 1 || sudo -u postgres createdb "${DB_NAME}"
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" \
  | grep -q 1 \
    && sudo -u postgres psql -c "ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASS}';" \
    || sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"
sudo -u postgres psql -c "ALTER DATABASE ${DB_NAME} OWNER TO ${DB_USER};"
ok "Database ready"

say "[5/9] Writing backend/.env"
cd "$APP_DIR/backend"
SECRET="$(openssl rand -hex 32)"
cat > .env <<ENVEOF
APP_NAME="Food Court Counter API"
ENVIRONMENT=production
DEBUG=False
HOST=127.0.0.1
PORT=8000
DATABASE_URL=postgresql+asyncpg://${DB_USER}:${DB_PASS}@localhost:5432/${DB_NAME}
SECRET_KEY=${SECRET}
ACCESS_TOKEN_EXPIRE_MINUTES=720
BACKEND_CORS_ORIGINS=https://${DOMAIN}
DEFAULT_ADMIN_EMAIL=admin@example.com
DEFAULT_ADMIN_PASSWORD=Admin@12345
DEFAULT_COUNTER_EMAIL=counter@example.com
DEFAULT_COUNTER_PASSWORD=Counter@12345
LOG_DIR=${LOG_DIR}
LOG_LEVEL=INFO
LOG_MAX_BYTES=10485760
LOG_BACKUP_COUNT=5
ENVEOF
chmod 640 .env
ok "backend/.env written"

say "[6/9] Installing backend dependencies"
python3 -m venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate
pip install --upgrade pip >/dev/null
pip install -r requirements.txt
pip install gunicorn 'uvicorn[standard]'
deactivate
ok "Backend virtualenv ready"

say "[7/9] Installing systemd service"
sudo tee /etc/systemd/system/${SERVICE_NAME}.service >/dev/null <<SVCEOF
[Unit]
Description=Food Court Counter FastAPI Backend
After=network.target postgresql.service

[Service]
User=www-data
Group=www-data
WorkingDirectory=${APP_DIR}/backend
Environment="PATH=${APP_DIR}/backend/.venv/bin"
Environment="LOG_DIR=${LOG_DIR}"
ExecStart=${APP_DIR}/backend/.venv/bin/gunicorn \\
    --workers 4 \\
    --worker-class uvicorn.workers.UvicornWorker \\
    --bind 127.0.0.1:8000 \\
    --timeout 120 \\
    --access-logfile - \\
    --error-logfile - \\
    app.main:app
Restart=always
RestartSec=5

LogsDirectory=food-court-counter
LogsDirectoryMode=0750

[Install]
WantedBy=multi-user.target
SVCEOF
sudo systemctl daemon-reload
sudo systemctl enable --now ${SERVICE_NAME}
sleep 2
sudo systemctl is-active --quiet ${SERVICE_NAME} \
  || { sudo journalctl -u ${SERVICE_NAME} -n 40; die "Backend failed to start"; }
ok "Backend service running"

say "[8/9] Building frontend"
cd "$APP_DIR/frontend"
cat > .env.production <<ENVEOF
VITE_COMPANY_NAME="${COMPANY_NAME:-Food Court Counter}"
VITE_COMPANY_ID="default"
VITE_TITLE_MODIFIER="Operations Console"
VITE_LOGO_URL="/assets/logo-placeholder.svg"
VITE_BRAND_IMAGE_URL="/assets/login-placeholder.svg"
VITE_FAVICON_URL="/favicon.svg"
VITE_PRIMARY_COLOR="#1e3a5f"
VITE_ACCENT_COLOR="#059669"
VITE_GSTIN=""
VITE_PAN=""
VITE_ADDRESS=""
VITE_CONTACT_EMAIL=""
VITE_CONTACT_PHONE=""
ENVEOF
npm ci --no-audit --no-fund
npm run build
ok "Frontend built"

say "[9/9] Configuring Apache"
VHOST=/etc/apache2/sites-available/food-court-counter.conf
sudo tee "$VHOST" >/dev/null <<APEOF
<VirtualHost *:80>
    ServerName ${DOMAIN}
    ServerAdmin ${LETSENCRYPT_EMAIL}
    DocumentRoot ${APP_DIR}/frontend/dist
    <Directory ${APP_DIR}/frontend/dist>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        RewriteEngine On
        RewriteBase /
        RewriteRule ^index\\.html\$ - [L]
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule . /index.html [L]
    </Directory>
    ProxyPreserveHost On
    ProxyPass /api/ http://127.0.0.1:8000/api/ retry=0
    ProxyPassReverse /api/ http://127.0.0.1:8000/api/
    <Location /api/>
        ProxySet connectiontimeout=30 timeout=120
    </Location>
    ErrorLog \${APACHE_LOG_DIR}/food-court-error.log
    CustomLog \${APACHE_LOG_DIR}/food-court-access.log combined
</VirtualHost>
APEOF
sudo a2ensite food-court-counter >/dev/null
sudo a2dissite 000-default >/dev/null 2>&1 || true
sudo apachectl configtest
sudo systemctl reload apache2
ok "Apache vhost enabled"

sudo chown -R www-data:www-data "$APP_DIR"
sudo chmod -R 755 "$APP_DIR"
sudo chmod 640 "$APP_DIR/backend/.env"
ok "Permissions adjusted"

if [[ "${SKIP_SSL:-0}" == "1" ]]; then
  warn "SKIP_SSL=1 — skipping Let's Encrypt. App is on http://${DOMAIN}"
else
  say "Requesting Let's Encrypt certificate for ${DOMAIN}"
  sudo certbot --apache --non-interactive --agree-tos \
    -m "${LETSENCRYPT_EMAIL}" -d "${DOMAIN}" --redirect \
    || warn "Certbot failed — retry: sudo certbot --apache -d ${DOMAIN}"
  ok "HTTPS configured (if certbot succeeded)"
fi

echo
ok "Deployment complete."
cat <<SUMMARY

────────────────────────────────────────────────────────────────
  Application URL:  https://${DOMAIN}/
  API base:         https://${DOMAIN}/api/
  Backend service:  systemctl status ${SERVICE_NAME}
  Backend logs:     ${LOG_DIR}/api.log
  Apache logs:      /var/log/apache2/food-court-{error,access}.log
  Database:         ${DB_NAME}  (owner: ${DB_USER})
  DB password:      ${DB_PASS}   ← save this now!

  First login:
    admin@example.com   / Admin@12345
    counter@example.com / Counter@12345
    Change both immediately via Admin Console → Users.
────────────────────────────────────────────────────────────────
SUMMARY
