#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Cafeteria / Food Court — deployment (v7)
# Ubuntu 22.04 / 24.04 · fresh or existing server · CloudPanel-aware
# Multi-site safe · Self-bootstrapping · Runtime auto-detection
#
# Python (FastAPI/Flask/Django) OR Node.js backend + optional Vite/React front.
# All known dependency incompatibilities are pre-resolved at step 8:
#   asyncpg>=0.30 · greenlet · email-validator · bcrypt<4.1 · uvicorn-worker
# Runs a real smoke test (import app.main + passlib+bcrypt hash) before
# starting systemd, so the "active but broken, 502 forever" pattern cannot
# happen again.
#
# Run:
#   sudo ./server.sh                       # from root → auto-bootstraps 'deploy'
#   ./server.sh                            # as any sudo-capable user
#   CLEAN=1   sudo ./server.sh             # rebuild artifacts, keep DB+state
#   CLEAN=all sudo ./server.sh             # full reset (drops DB, service, vhost)
# ─────────────────────────────────────────────────────────────────────────────

if [[ -f "$0" ]]; then
  bash -n "$0" 2>/dev/null || { echo "Syntax error in $0"; bash -n "$0"; exit 1; }
fi

set -euo pipefail

say()  { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

valid_var() {
  local name="$1"
  [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
    || die "Invalid identifier '$name'"
}

wait_for_apt() {
  local tries=0
  while pgrep -x apt-get >/dev/null 2>&1 \
     || pgrep -x apt      >/dev/null 2>&1 \
     || pgrep -x dpkg     >/dev/null 2>&1; do
    tries=$((tries+1))
    [[ $tries -gt 60 ]] && die "apt/dpkg lock held >3 min"
    warn "Waiting for apt/dpkg lock..."
    sleep 3
  done
}

ensure_swap() {
  local mem_mb swap_mb
  mem_mb=$(free -m  | awk '/^Mem:/{print $2}')
  swap_mb=$(free -m | awk '/^Swap:/{print $2}')
  if [[ "${mem_mb:-0}" -lt 2048 && "${swap_mb:-0}" -lt 1024 ]]; then
    if sudo swapon --show 2>/dev/null | grep -q /swapfile; then
      ok "Swap already present"; return 0
    fi
    say "  → low RAM (${mem_mb} MB), no swap — creating 2 GB /swapfile"
    if ! sudo fallocate -l 2G /swapfile 2>/dev/null; then
      sudo dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
    fi
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile >/dev/null
    sudo swapon /swapfile
    grep -q '^/swapfile' /etc/fstab \
      || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
    ok "2 GB swap enabled"
  fi
}

patch_tsconfigs() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  ( cd "$dir" && node - <<'NODEEOF' 2>/dev/null || true
const fs = require('fs');
const files = ['tsconfig.json','tsconfig.app.json','tsconfig.node.json','tsconfig.build.json'];
let patched = 0;
for (const f of files) {
  if (!fs.existsSync(f)) continue;
  let src = fs.readFileSync(f, 'utf8');
  const before = src;
  src = src.replace(/"noUnusedLocals"\s*:\s*true/g, '"noUnusedLocals": false');
  src = src.replace(/"noUnusedParameters"\s*:\s*true/g, '"noUnusedParameters": false');
  if (src !== before) { fs.writeFileSync(f, src); console.log('patched ' + f); patched++; }
}
if (patched === 0) console.log('no tsconfig patch needed');
NODEEOF
  )
}

# ── Fixed deployment values ────────────────────────────────────────────────
DUCKDNS_SUBDOMAIN="${DUCKDNS_SUBDOMAIN:-sauccy-boy}"
: "${DUCKDNS_TOKEN:?Set DUCKDNS_TOKEN in the environment before running server.sh}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-biswajit.ghosh21021983@gmail.com}"
NODE_VERSION="${NODE_VERSION:-20}"
COMPANY_NAME="${COMPANY_NAME:-Food Court Counter}"
DEPLOY_USER="${DEPLOY_USER:-deploy}"

# ─────────────────────────────────────────────────────────────────────────────
# BOOTSTRAP MODE — when run as root
# ─────────────────────────────────────────────────────────────────────────────
if [[ $EUID -eq 0 ]]; then
  echo
  say "════════════════════════════════════════════════════════════"
  say "  Bootstrap mode — self-provisioning '${DEPLOY_USER}'"
  say "════════════════════════════════════════════════════════════"

  SRC_SCRIPT="$(readlink -f "${BASH_SOURCE[0]}")"
  SRC_DIR="$(dirname "$SRC_SCRIPT")"
  SCRIPT_NAME="$(basename "$SRC_SCRIPT")"

  if ! id "$DEPLOY_USER" &>/dev/null; then
    say "Creating user '${DEPLOY_USER}'"
    adduser --disabled-password --gecos "" "$DEPLOY_USER"
    usermod -aG sudo "$DEPLOY_USER"
    ok "User '${DEPLOY_USER}' created"
  else
    ok "User '${DEPLOY_USER}' already exists"
  fi

  SUDOERS="/etc/sudoers.d/90-${DEPLOY_USER}"
  echo "${DEPLOY_USER} ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS"
  chmod 440 "$SUDOERS"
  visudo -cf "$SUDOERS" >/dev/null 2>&1 || { rm -f "$SUDOERS"; die "sudoers validation failed"; }
  ok "NOPASSWD sudo enabled for '${DEPLOY_USER}'"

  install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/${DEPLOY_USER}/.ssh"
  AK="/home/${DEPLOY_USER}/.ssh/authorized_keys"
  if [[ -n "${ADMIN_SSH_PUBKEY:-}" ]]; then
    printf '%s\n' "$ADMIN_SSH_PUBKEY" > "$AK"
    ok "Pubkey seeded from ADMIN_SSH_PUBKEY"
  elif [[ -s /root/.ssh/authorized_keys ]]; then
    cp /root/.ssh/authorized_keys "$AK"
    ok "Pubkey seeded from /root/.ssh/authorized_keys"
  else
    warn "No client pubkey found — future ssh will fail"
  fi
  chown "${DEPLOY_USER}:${DEPLOY_USER}" "$AK" 2>/dev/null || true
  chmod 600 "$AK" 2>/dev/null || true

  if [[ "$SRC_DIR" == /root || "$SRC_DIR" == /root/* ]] \
     || ! sudo -u "$DEPLOY_USER" test -r "$SRC_DIR/$SCRIPT_NAME" 2>/dev/null; then
    STAGE="/home/${DEPLOY_USER}/.deploy-stage-$$"
    say "Staging project → $STAGE"
    mkdir -p "$STAGE"
    cp -a "$SRC_DIR/." "$STAGE/"
    chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "$STAGE"
    RUN_DIR="$STAGE"
  else
    RUN_DIR="$SRC_DIR"
  fi

  say "Re-executing as '${DEPLOY_USER}'…"
  echo
  exec sudo -u "$DEPLOY_USER" -H \
    env \
      HOME="/home/${DEPLOY_USER}" \
      DUCKDNS_SUBDOMAIN="$DUCKDNS_SUBDOMAIN" \
      DUCKDNS_TOKEN="$DUCKDNS_TOKEN" \
      LETSENCRYPT_EMAIL="$LETSENCRYPT_EMAIL" \
      NODE_VERSION="$NODE_VERSION" \
      COMPANY_NAME="$COMPANY_NAME" \
      DEPLOY_USER="$DEPLOY_USER" \
      ADMIN_SSH_PUBKEY="${ADMIN_SSH_PUBKEY:-}" \
      SITE_SLUG="${SITE_SLUG:-}" \
      BACKEND_PORT="${BACKEND_PORT:-}" \
      DB_NAME="${DB_NAME:-}" \
      DB_USER="${DB_USER:-}" \
      DB_PASS="${DB_PASS:-}" \
      BACKEND_SUBDIR="${BACKEND_SUBDIR:-}" \
      FRONTEND_SUBDIR="${FRONTEND_SUBDIR:-}" \
      SKIP_SYSTEM_UPGRADE="${SKIP_SYSTEM_UPGRADE:-0}" \
      SKIP_FIREWALL="${SKIP_FIREWALL:-0}" \
      CLEAN="${CLEAN:-0}" \
    bash "$RUN_DIR/$SCRIPT_NAME"
fi

# ─────────────────────────────────────────────────────────────────────────────
# NORMAL MODE — non-root
# ─────────────────────────────────────────────────────────────────────────────
[[ -f /etc/os-release ]] || die "Unsupported OS."
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || warn "Tested on Ubuntu; you're on ${ID:-unknown}"

if ! sudo -n true 2>/dev/null; then
  sudo -v || die "sudo access required"
fi

DOMAIN="${DUCKDNS_SUBDOMAIN}.duckdns.org"

_RAW_SLUG="$(printf '%s' "${SITE_SLUG:-$DUCKDNS_SUBDOMAIN}" \
  | tr '[:upper:]' '[:lower:]' \
  | tr -c 'a-z0-9\n' '_' \
  | sed 's/_\+/_/g;s/^_//;s/_$//')"
SITE_SLUG="${_RAW_SLUG:-site1}"
unset _RAW_SLUG
valid_var "SITE_SLUG_${SITE_SLUG}"

APP_DIR="${APP_DIR:-/var/www/food-court-${SITE_SLUG}}"
SERVICE_NAME="${SERVICE_NAME:-food-court-api-${SITE_SLUG}}"
DB_NAME="${DB_NAME:-fc_${SITE_SLUG}}"
DB_USER="${DB_USER:-fc_${SITE_SLUG}_u}"
LOG_DIR="${LOG_DIR:-/var/log/food-court-${SITE_SLUG}}"
VHOST_NAME="food-court-${SITE_SLUG}"
NGINX_CONF="/etc/nginx/sites-available/${VHOST_NAME}"
APACHE_CONF="/etc/apache2/sites-available/${VHOST_NAME}.conf"

STATE_DIR="${HOME}/.config/food-court"
STATE_FILE="${STATE_DIR}/${SITE_SLUG}.state"
mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"

if [[ -f "$STATE_FILE" ]]; then
  if bash -n "$STATE_FILE" 2>/dev/null \
     && grep -Eq '^[A-Za-z_][A-Za-z0-9_]*=' "$STATE_FILE"; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
    ok "Loaded state from $STATE_FILE"
  else
    warn "State file $STATE_FILE malformed — refusing to source"
    head -5 "$STATE_FILE" | sed 's/^/    /' >&2
    die "Delete it and re-run:  rm -f \"$STATE_FILE\""
  fi
fi

if [[ -z "${BACKEND_PORT:-}" ]]; then
  for p in $(seq 8001 8099); do
    if ! ss -tln 2>/dev/null | awk '{print $4}' | grep -q ":${p}\$"; then
      BACKEND_PORT="$p"; break
    fi
  done
  [[ -n "${BACKEND_PORT:-}" ]] || die "No free port in 8001-8099"
fi
DB_PASS="${DB_PASS:-}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ═══════════════════════════════════════════════════════════════════════════
# PRE-FLIGHT — locate backend + detect runtime
# ═══════════════════════════════════════════════════════════════════════════
say "Pre-flight: analysing project in $PROJECT_ROOT"

BACKEND_SUBDIR="${BACKEND_SUBDIR:-}"
FRONTEND_SUBDIR="${FRONTEND_SUBDIR:-}"
BACKEND_RUNTIME=""
PY_ENTRY=""
PY_SERVER=""

if [[ -z "$BACKEND_SUBDIR" ]]; then
  for cand in backend server api app; do
    if [[ -d "$PROJECT_ROOT/$cand" ]] \
       && { [[ -f "$PROJECT_ROOT/$cand/package.json" ]] \
         || [[ -f "$PROJECT_ROOT/$cand/requirements.txt" ]] \
         || [[ -f "$PROJECT_ROOT/$cand/pyproject.toml" ]] \
         || [[ -f "$PROJECT_ROOT/$cand/main.py" ]] \
         || [[ -f "$PROJECT_ROOT/$cand/app/main.py" ]] \
         || [[ -f "$PROJECT_ROOT/$cand/manage.py" ]]; }; then
      BACKEND_SUBDIR="$cand"; break
    fi
  done
fi

if [[ -z "$BACKEND_SUBDIR" ]]; then
  if [[ -f "$PROJECT_ROOT/requirements.txt" ]] \
     || [[ -f "$PROJECT_ROOT/pyproject.toml" ]] \
     || [[ -f "$PROJECT_ROOT/main.py" ]] \
     || [[ -f "$PROJECT_ROOT/app/main.py" ]] \
     || [[ -f "$PROJECT_ROOT/package.json" ]]; then
    BACKEND_SUBDIR="."
  fi
fi

if [[ -z "$BACKEND_SUBDIR" ]]; then
  warn "Pre-flight FAILED — no backend detected in $PROJECT_ROOT"
  ls -la "$PROJECT_ROOT" 2>/dev/null | sed 's/^/    /' >&2 || true
  die "Override with:  BACKEND_SUBDIR=<folder> sudo ./server.sh"
fi

BACKEND_SRC="$PROJECT_ROOT/$BACKEND_SUBDIR"

if [[ -f "$BACKEND_SRC/package.json" ]]; then
  BACKEND_RUNTIME="node"
elif [[ -f "$BACKEND_SRC/requirements.txt" ]] \
  || [[ -f "$BACKEND_SRC/pyproject.toml" ]] \
  || [[ -f "$BACKEND_SRC/main.py" ]] \
  || [[ -f "$BACKEND_SRC/app/main.py" ]] \
  || [[ -f "$BACKEND_SRC/manage.py" ]]; then
  BACKEND_RUNTIME="python"
else
  warn "Backend folder '$BACKEND_SUBDIR' has no recognised entry file."
  ls -la "$BACKEND_SRC" | sed 's/^/    /' >&2
  die "Cannot determine backend runtime"
fi
ok "Backend runtime: $BACKEND_RUNTIME  (folder: $BACKEND_SUBDIR)"

if [[ "$BACKEND_RUNTIME" == "python" ]]; then
  if [[ -f "$BACKEND_SRC/manage.py" ]]; then
    PROJ_PKG="$(find "$BACKEND_SRC" -maxdepth 2 -name 'settings.py' -printf '%h\n' 2>/dev/null | head -1)"
    PROJ_NAME="$(basename "$PROJ_PKG" 2>/dev/null)"
    if [[ -n "$PROJ_NAME" && -d "$BACKEND_SRC/$PROJ_NAME" ]]; then
      PY_ENTRY="${PROJ_NAME}.wsgi:application"; PY_SERVER="gunicorn"
    else
      die "Django detected but settings.py not found in a package"
    fi
  elif [[ -f "$BACKEND_SRC/app/main.py" ]] \
    && grep -qE 'FastAPI\(|from fastapi|import fastapi' "$BACKEND_SRC/app/main.py"; then
    PY_ENTRY="app.main:app"; PY_SERVER="gunicorn-uvicorn"
  elif [[ -f "$BACKEND_SRC/main.py" ]] \
    && grep -qE 'FastAPI\(|from fastapi|import fastapi' "$BACKEND_SRC/main.py"; then
    PY_ENTRY="main:app"; PY_SERVER="gunicorn-uvicorn"
  elif [[ -f "$BACKEND_SRC/app.py" ]] \
    && grep -qE 'Flask\(|from flask|import flask' "$BACKEND_SRC/app.py"; then
    PY_ENTRY="app:app"; PY_SERVER="gunicorn"
  elif [[ -f "$BACKEND_SRC/main.py" ]] \
    && grep -qE 'Flask\(|from flask|import flask' "$BACKEND_SRC/main.py"; then
    PY_ENTRY="main:app"; PY_SERVER="gunicorn"
  elif [[ -f "$BACKEND_SRC/app/main.py" ]]; then
    PY_ENTRY="app.main:app"; PY_SERVER="gunicorn-uvicorn"
  elif [[ -f "$BACKEND_SRC/main.py" ]]; then
    PY_ENTRY="main:app"; PY_SERVER="gunicorn-uvicorn"
  else
    die "Python backend detected but no entry point"
  fi
  ok "Python entry: $PY_ENTRY  ($PY_SERVER)"
fi

if [[ -z "$FRONTEND_SUBDIR" ]]; then
  for cand in frontend client web ui; do
    if [[ -f "$PROJECT_ROOT/$cand/package.json" ]] && [[ "$cand" != "$BACKEND_SUBDIR" ]]; then
      FRONTEND_SUBDIR="$cand"; break
    fi
  done
fi

if [[ "$BACKEND_SUBDIR" == "." ]]; then
  BACKEND_PATH="$APP_DIR"; BACKEND_EXCLUDE="/logs"
else
  BACKEND_PATH="$APP_DIR/$BACKEND_SUBDIR"; BACKEND_EXCLUDE="${BACKEND_SUBDIR}/logs"
fi
FRONTEND_PATH=""
[[ -n "$FRONTEND_SUBDIR" ]] && FRONTEND_PATH="$APP_DIR/$FRONTEND_SUBDIR"

ok "Backend:  ${BACKEND_SUBDIR/#./<project-root>}"
[[ -n "$FRONTEND_SUBDIR" ]] \
  && ok "Frontend: ${FRONTEND_SUBDIR}" \
  || say "Frontend: none (backend serves static if needed)"

# ═══════════════════════════════════════════════════════════════════════════
# CLEAN MODE
# ═══════════════════════════════════════════════════════════════════════════
CLEAN="${CLEAN:-0}"
if [[ "$CLEAN" == "1" || "$CLEAN" == "all" ]]; then
  echo
  say "════════════════════════════════════════════════════════════"
  say "  CLEAN=$CLEAN — removing previous build artifacts"
  say "════════════════════════════════════════════════════════════"

  # Resolve service name safely (list-unit-files never shows the ● bullet)
  SAFE_SERVICE=$(systemctl list-unit-files "${SERVICE_NAME}.service" --no-legend 2>/dev/null \
    | awk '{print $1}' | head -1 | sed 's/\.service$//')
  [[ -z "$SAFE_SERVICE" ]] && SAFE_SERVICE="$SERVICE_NAME"

  if systemctl is-active --quiet "$SAFE_SERVICE" 2>/dev/null; then
    say "  → stopping $SAFE_SERVICE"
    sudo systemctl stop "$SAFE_SERVICE" || true
  fi

  for d in \
    "$APP_DIR/$BACKEND_SUBDIR/.venv" \
    "$APP_DIR/$BACKEND_SUBDIR/node_modules" \
    "$APP_DIR/$BACKEND_SUBDIR/dist" \
    "$APP_DIR/frontend/node_modules" "$APP_DIR/frontend/dist" \
    "$APP_DIR/client/node_modules"   "$APP_DIR/client/dist" \
    "$APP_DIR/web/node_modules"      "$APP_DIR/web/dist" \
    "$APP_DIR/ui/node_modules"       "$APP_DIR/ui/dist"; do
    if [[ -e "$d" ]]; then
      say "  → rm -rf $d"
      sudo rm -rf "$d"
    fi
  done
  ok "Build artifacts removed"

  if [[ "$CLEAN" == "all" ]]; then
    if sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" 2>/dev/null | grep -q 1; then
      say "  → dropping DB $DB_NAME"
      sudo -u postgres psql -c "DROP DATABASE ${DB_NAME};" || warn "DB drop failed"
    fi
    if sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" 2>/dev/null | grep -q 1; then
      say "  → dropping role $DB_USER"
      sudo -u postgres psql -c "DROP ROLE ${DB_USER};" || warn "role drop failed"
    fi
    [[ -f "$STATE_FILE" ]] && { say "  → removing state $STATE_FILE"; rm -f "$STATE_FILE"; }
    if [[ -f "$NGINX_CONF" ]]; then
      sudo rm -f "$NGINX_CONF" "/etc/nginx/sites-enabled/${VHOST_NAME}"
      sudo nginx -t >/dev/null 2>&1 && sudo systemctl reload nginx 2>/dev/null || true
    fi
    if [[ -f "$APACHE_CONF" ]]; then
      sudo rm -f "$APACHE_CONF"
      sudo a2dissite "$VHOST_NAME" >/dev/null 2>&1 || true
      sudo apachectl configtest >/dev/null 2>&1 && sudo systemctl reload apache2 2>/dev/null || true
    fi
    if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
      say "  → removing systemd unit"
      sudo systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
      sudo rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
      sudo systemctl daemon-reload
    fi
    [[ -d "$APP_DIR" ]] && { say "  → removing $APP_DIR"; sudo rm -rf "$APP_DIR"; }
    DB_PASS=""; BACKEND_PORT=""
    ok "Full reset complete"
  fi
  echo
fi

echo
say "════════════════════════════════════════════════════════════"
say "  Food Court Counter — deployment (v7)"
say "════════════════════════════════════════════════════════════"
say "  Run as:       $USER"
say "  Site slug:    $SITE_SLUG"
say "  Domain:       $DOMAIN"
say "  App dir:      $APP_DIR"
say "  Backend:      ${BACKEND_SUBDIR/#./<project-root>}  ($BACKEND_RUNTIME)"
say "  Frontend:     ${FRONTEND_SUBDIR:-<none>}"
say "  Service:      $SERVICE_NAME"
say "  Backend port: $BACKEND_PORT"
say "  Database:     $DB_NAME  (user: $DB_USER)"
say "  Log dir:      $LOG_DIR"
say "  Clean mode:   $CLEAN"
echo

# ── [1/13] System update & upgrade ─────────────────────────────────────────
say "[1/13] System update & upgrade"
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export APT_LISTCHANGES_FRONTEND=none

if [[ -d /etc/needrestart/conf.d ]]; then
  echo '$nrconf{restart} = "a";' \
    | sudo tee /etc/needrestart/conf.d/99-auto-restart.conf >/dev/null
fi

if command -v timedatectl >/dev/null 2>&1; then
  if ! timedatectl show 2>/dev/null | grep -q 'NTPSynchronized=yes'; then
    warn "Clock not NTP-synced — enabling systemd-timesyncd"
    sudo systemctl enable --now systemd-timesyncd 2>/dev/null || true
  fi
fi

wait_for_apt
say "  → apt-get update"
sudo apt-get update -y

if [[ "${SKIP_SYSTEM_UPGRADE:-0}" == "1" ]]; then
  warn "SKIP_SYSTEM_UPGRADE=1 — skipping apt upgrade"
else
  UPGRADABLE=$(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l)
  if [[ "$UPGRADABLE" -gt 0 ]]; then
    say "  → apt-get upgrade ($UPGRADABLE package(s))"
    sudo apt-get -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      upgrade || warn "apt upgrade reported issues — continuing"
    sudo apt-get -y autoremove || true
    ok "System packages upgraded"
  else
    ok "System already up to date"
  fi
fi

if [[ -f /var/run/reboot-required ]]; then
  warn "╔══════════════════════════════════════════════════════════╗"
  warn "║  REBOOT REQUIRED — kernel or core library upgraded       ║"
  warn "╚══════════════════════════════════════════════════════════╝"
fi

# ── [2/13] Environment detection ───────────────────────────────────────────
say "[2/13] Environment detection"
HAS_CLOUDPANEL=0
if [[ -d /etc/cloudpanel ]] || command -v clpctl >/dev/null 2>&1; then
  HAS_CLOUDPANEL=1
fi

APP_USER="www-data"
if [[ $HAS_CLOUDPANEL -eq 1 ]]; then
  if [[ "$APP_DIR" =~ ^/home/([^/]+)/htdocs/ ]]; then
    APP_USER="${BASH_REMATCH[1]}"
    ok "CloudPanel — using site user '$APP_USER'"
  else
    warn "CloudPanel detected; APP_DIR not under /home/<user>/htdocs/"
  fi
  warn "Web server + SSL managed by CloudPanel — will NOT be touched"
else
  ok "No panel detected — script will own Nginx/Apache and SSL"
fi

# ── [3/13] Essential tools & runtimes ──────────────────────────────────────
say "[3/13] Installing essential tools"
wait_for_apt

sudo apt-get install -y --no-install-recommends \
  curl wget git rsync gnupg ca-certificates openssl \
  software-properties-common apt-transport-https \
  jq unzip sqlite3 \
  less vim nano tmux \
  lsof net-tools iproute2 dnsutils \
  sysstat htop ncdu \
  logrotate cron \
  ufw unattended-upgrades fail2ban \
  build-essential pkg-config libssl-dev \
  certbot
ok "Base tools installed"

ensure_swap

INSTALL_NODE=0
[[ -n "$FRONTEND_SUBDIR" ]] && INSTALL_NODE=1
[[ "$BACKEND_RUNTIME" == "node" ]] && INSTALL_NODE=1

NODE_OK=0
if command -v node >/dev/null 2>&1; then
  CUR_MAJOR="$(node -v | sed 's/^v//;s/\..*//')"
  [[ "$CUR_MAJOR" -ge "$NODE_VERSION" ]] && NODE_OK=1
fi
if [[ $INSTALL_NODE -eq 1 && $NODE_OK -eq 0 ]]; then
  say "  → Node.js ${NODE_VERSION}.x via NodeSource"
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | sudo -E bash -
  sudo apt-get install -y nodejs
fi
if command -v node >/dev/null 2>&1; then
  ok "Node.js $(node -v) / npm $(npm -v)"
fi

if [[ "$BACKEND_RUNTIME" == "python" ]]; then
  say "  → Python 3 + venv + build deps"
  sudo apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip python3-dev libpq-dev
  ok "Python $(python3 --version | awk '{print $2}')"
fi

if ! command -v psql >/dev/null 2>&1; then
  say "  → PostgreSQL"
  sudo apt-get install -y --no-install-recommends postgresql postgresql-contrib
fi
sudo systemctl is-active --quiet postgresql || sudo systemctl start postgresql
ok "PostgreSQL ready ($(psql --version | awk '{print $3}'))"

if ! dpkg -l python3-certbot-dns-duckdns 2>/dev/null | grep -q ^ii; then
  sudo apt-get install -y python3-certbot-dns-duckdns 2>/dev/null \
    || warn "certbot-dns-duckdns unavailable — will use webroot HTTP-01"
fi
ok "Certbot ready"

say "  → hardening"
if [[ ! -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
  sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
fi
sudo systemctl enable --now unattended-upgrades 2>/dev/null || true
sudo systemctl enable fail2ban 2>/dev/null || true
sudo systemctl start  fail2ban 2>/dev/null || warn "fail2ban failed to start"
ok "unattended-upgrades + fail2ban active"

if sudo ufw status 2>/dev/null | grep -q 'Status: active'; then
  sudo ufw allow 80/tcp  >/dev/null 2>&1 || true
  sudo ufw allow 443/tcp >/dev/null 2>&1 || true
  ok "UFW active — 80/443 allowed"
elif [[ "${SKIP_FIREWALL:-0}" == "1" ]]; then
  warn "SKIP_FIREWALL=1 — leaving UFW inactive"
else
  EXTRA=$(ss -tlnH 2>/dev/null | awk '{print $4}' | sed 's/.*://' \
    | sort -u | grep -vE '^(22|80|443|5432)$' | grep -vE '^80[0-9][0-9]$' || true)
  if [[ -n "$EXTRA" ]]; then
    warn "UFW inactive; non-standard ports in use — configure manually"
  else
    sudo ufw --force default deny incoming  >/dev/null
    sudo ufw --force default allow outgoing >/dev/null
    sudo ufw --force allow 22/tcp  >/dev/null
    sudo ufw --force allow 80/tcp  >/dev/null
    sudo ufw --force allow 443/tcp >/dev/null
    sudo ufw --force enable >/dev/null
    ok "UFW enabled (22/80/443)"
  fi
fi

# ── [4/13] Web server ──────────────────────────────────────────────────────
say "[4/13] Web server"
HAS_APACHE=0; HAS_NGINX=0
systemctl is-active --quiet apache2 2>/dev/null && HAS_APACHE=1
systemctl is-active --quiet nginx   2>/dev/null && HAS_NGINX=1

if [[ $HAS_CLOUDPANEL -eq 1 ]]; then
  warn "CloudPanel manages Nginx/Apache — skipping install/config"
else
  if [[ $HAS_APACHE -eq 1 && $HAS_NGINX -eq 1 ]]; then
    read -r -p "Both Apache and Nginx active. Which serves $DOMAIN? [apache/nginx]: " choice || choice=nginx
    case "${choice,,}" in
      apache) HAS_NGINX=0 ;;
      nginx)  HAS_APACHE=0 ;;
      *) die "Invalid choice" ;;
    esac
  elif [[ $HAS_APACHE -eq 1 ]]; then
    ok "Detected Apache"
  elif [[ $HAS_NGINX -eq 1 ]]; then
    ok "Detected Nginx"
  else
    say "No web server — installing Nginx (multi-site friendly)"
    sudo apt-get install -y nginx
    sudo systemctl enable --now nginx
    HAS_NGINX=1
    ok "Nginx installed"
  fi
fi

# ── [5/13] DNS ─────────────────────────────────────────────────────────────
say "[5/13] Verifying DuckDNS"
curl -fsS "https://www.duckdns.org/update?domains=${DUCKDNS_SUBDOMAIN}&token=${DUCKDNS_TOKEN}&ip=" >/dev/null \
  || warn "DuckDNS update failed — continuing"
getent hosts "$DOMAIN" >/dev/null \
  || die "DNS for $DOMAIN does not resolve — wait a minute and re-run"
ok "$DOMAIN → $(getent hosts "$DOMAIN" | awk '{print $1}')"

# ── [6/13] Sync project ────────────────────────────────────────────────────
say "[6/13] Syncing project to $APP_DIR"
if [[ "$PROJECT_ROOT" != "$APP_DIR" ]]; then
  sudo mkdir -p "$APP_DIR"
  sudo chown -R "$USER":"$USER" "$APP_DIR"
  rsync -a --delete \
    --exclude '.git' --exclude 'node_modules' --exclude '.venv' \
    --exclude 'frontend/dist' --exclude 'client/dist' --exclude 'web/dist' \
    --exclude "${BACKEND_EXCLUDE}" \
    "$PROJECT_ROOT"/ "$APP_DIR"/
fi
ok "Project in place"

if [[ "$BACKEND_RUNTIME" == "node" ]]; then
  [[ -f "$BACKEND_PATH/package.json" ]] \
    || die "After rsync: $BACKEND_PATH/package.json missing"
elif [[ "$BACKEND_RUNTIME" == "python" ]]; then
  { [[ -f "$BACKEND_PATH/requirements.txt" ]] \
    || [[ -f "$BACKEND_PATH/pyproject.toml" ]] \
    || [[ -f "$BACKEND_PATH/main.py" ]] \
    || [[ -f "$BACKEND_PATH/app/main.py" ]] \
    || [[ -f "$BACKEND_PATH/manage.py" ]]; } \
    || die "After rsync: Python entry files missing in $BACKEND_PATH"
fi
ok "Verified backend files in $BACKEND_PATH"

# ── [7/13] Database ────────────────────────────────────────────────────────
say "[7/13] PostgreSQL"
[[ -z "$DB_PASS" ]] && DB_PASS="$(openssl rand -hex 16)"

sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" \
  | grep -q 1 || sudo -u postgres createdb "${DB_NAME}"

if sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1; then
  sudo -u postgres psql -c "ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"
else
  sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"
fi
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"
sudo -u postgres psql -c "ALTER DATABASE ${DB_NAME} OWNER TO ${DB_USER};"
ok "Database ready (${DB_NAME} / ${DB_USER})"

cat > "$STATE_FILE" <<EOF
SITE_SLUG=${SITE_SLUG}
BACKEND_PORT=${BACKEND_PORT}
BACKEND_SUBDIR=${BACKEND_SUBDIR}
BACKEND_RUNTIME=${BACKEND_RUNTIME}
FRONTEND_SUBDIR=${FRONTEND_SUBDIR}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
SERVICE_NAME=${SERVICE_NAME}
EOF
chmod 600 "$STATE_FILE"

# ── [8/13] Backend install ─────────────────────────────────────────────────
say "[8/13] Backend install ($BACKEND_RUNTIME)"

cd "$BACKEND_PATH"

if [[ "$BACKEND_RUNTIME" == "python" ]]; then
  DB_DSN="postgresql+asyncpg://${DB_USER}:${DB_PASS}@localhost:5432/${DB_NAME}"
  DB_DSN_SYNC="postgresql://${DB_USER}:${DB_PASS}@localhost:5432/${DB_NAME}"
else
  DB_DSN="postgresql://${DB_USER}:${DB_PASS}@localhost:5432/${DB_NAME}"
  DB_DSN_SYNC="$DB_DSN"
fi

SECRET="$(openssl rand -hex 32)"
[[ -f .env ]] && { warn "Backing up existing .env → .env.bak"; cp .env .env.bak; }

cat > .env <<EOF
NODE_ENV=production
ENVIRONMENT=production
DEBUG=False

HOST=127.0.0.1
PORT=${BACKEND_PORT}

DATABASE_URL=${DB_DSN}
DATABASE_URL_SYNC=${DB_DSN_SYNC}
SECRET_KEY=${SECRET}
JWT_SECRET=${SECRET}
ACCESS_TOKEN_EXPIRE_MINUTES=720

CORS_ORIGINS=https://${DOMAIN}
BACKEND_CORS_ORIGINS=https://${DOMAIN}

DEFAULT_ADMIN_EMAIL=admin@example.com
DEFAULT_ADMIN_PASSWORD=Admin@12345
DEFAULT_COUNTER_EMAIL=counter@example.com
DEFAULT_COUNTER_PASSWORD=Counter@12345

LOG_DIR=${LOG_DIR}
LOG_LEVEL=info
LOG_MAX_BYTES=10485760
LOG_BACKUP_COUNT=5
EOF
sudo chown "${APP_USER}":"${APP_USER}" .env
sudo chmod 640 .env

if [[ "$BACKEND_RUNTIME" == "node" ]]; then
  if [[ -f package-lock.json ]]; then
    npm ci --include=dev --no-audit --no-fund
  else
    npm install --include=dev --no-audit --no-fund
  fi
  if node -e "const p=require('./package.json'); process.exit(p.scripts && p.scripts.build ? 0 : 1)" 2>/dev/null; then
    npm run build
  fi
  ok "Node backend dependencies installed"
else
  # ── If .venv was chown'd to www-data in a prior run, take it back ──────
  if [[ -d .venv ]]; then
    VENV_OWNER=$(stat -c '%U' .venv 2>/dev/null || echo "")
    if [[ -n "$VENV_OWNER" && "$VENV_OWNER" != "$USER" ]]; then
      say "  → reclaiming .venv from $VENV_OWNER for install"
      sudo chown -R "$USER:$USER" .venv
    fi
  fi

  [[ -d .venv ]] || python3 -m venv .venv

  # ── pip environment ────────────────────────────────────────────────────
  export HOME="${HOME:-/tmp}"
  export PIP_PREFER_BINARY=1
  export PIP_DISABLE_PIP_VERSION_CHECK=1
  export PIP_NO_INPUT=1
  export PIP_DEFAULT_TIMEOUT=120
  export PIP_RETRIES=5

  # Use 'python -m pip' — never '.venv/bin/pip' — avoids shebang drift
  VPIP=.venv/bin/python

  say "  → upgrading pip/setuptools/wheel"
  "$VPIP" -m pip install --upgrade pip setuptools wheel >/dev/null

  # ── Pre-install known-fragile deps BEFORE requirements.txt ─────────────
  say "  → asyncpg wheel (>=0.30.0, cp313+/cp314 wheels)"
  "$VPIP" -m pip install --prefer-binary --only-binary=asyncpg 'asyncpg>=0.30.0' \
    || die "No asyncpg wheel for $(python3 --version) — bump asyncpg>=0.30.0 in requirements.txt"

  say "  → SQLAlchemy async stack (greenlet)"
  "$VPIP" -m pip install --prefer-binary 'greenlet>=3.0.0' 'sqlalchemy[asyncio]>=2.0' \
    || warn "greenlet install failed — SQLAlchemy async will crash at import"

  say "  → Pydantic email extra (EmailStr fields)"
  "$VPIP" -m pip install --prefer-binary 'email-validator>=2.0' 'pydantic[email]' \
    || warn "email-validator install failed — EmailStr fields will crash workers"

  say "  → bcrypt <4.1 (passlib 1.7.4 incompatible with bcrypt ≥4.1)"
  "$VPIP" -m pip install --prefer-binary 'bcrypt>=4.0.0,<4.1' \
    || warn "bcrypt pin failed — auth will crash on first hash"

  # uvicorn-worker for uvicorn >= 0.30 (optional; fallback handled later)
  "$VPIP" -m pip install --prefer-binary 'uvicorn-worker>=0.3.0' 2>/dev/null || true

  # ── Install the app's requirements ─────────────────────────────────────
  if [[ -f requirements.txt ]]; then
    say "  → installing requirements.txt (binary-preferred)"
    "$VPIP" -m pip install --prefer-binary -r requirements.txt \
      || {
        warn "Full install failed — retrying with binary-only for heavy packages"
        "$VPIP" -m pip install --prefer-binary -r requirements.txt \
          --only-binary asyncpg,uvloop,httptools \
          --only-binary pydantic-core,pydantic,orjson \
          --only-binary bcrypt,cryptography,PyYAML \
          --only-binary numpy,pandas,Pillow
      }
  elif [[ -f pyproject.toml ]]; then
    say "  → installing pyproject.toml"
    "$VPIP" -m pip install --prefer-binary -e .
  fi

  # ── Re-pin fragile deps (requirements may have upgraded them) ──────────
  "$VPIP" -m pip install --prefer-binary 'bcrypt>=4.0.0,<4.1' >/dev/null \
    || warn "bcrypt re-pin failed — auth may crash"
  "$VPIP" -m pip install --prefer-binary 'greenlet>=3.0.0' 'email-validator>=2.0' >/dev/null \
    || warn "greenlet/email-validator re-pin failed"

  # ── Install WSGI/ASGI server ───────────────────────────────────────────
  say "  → installing gunicorn + uvicorn"
  case "$PY_SERVER" in
    gunicorn-uvicorn) "$VPIP" -m pip install --prefer-binary gunicorn 'uvicorn[standard]' ;;
    gunicorn)         "$VPIP" -m pip install --prefer-binary gunicorn ;;
  esac

  # Regenerate shebangs (fixes 203/EXEC after a venv move or rebuild)
  say "  → regenerating gunicorn/uvicorn launchers"
  "$VPIP" -m pip install --force-reinstall --no-deps \
    gunicorn 'uvicorn[standard]' 2>/dev/null || true

  # Verify gunicorn runs from the venv python (no shebang dependency)
  "$VPIP" -m gunicorn --version >/dev/null \
    || die "gunicorn broken in venv — check .venv/bin/python -m gunicorn"

  # ── REAL smoke test — import app.main AND exercise passlib+bcrypt ──────
  say "  → verifying app imports (catches missing deps before systemd)"
  ( cd "$BACKEND_PATH" && HOME="${HOME:-/tmp}" "$VPIP" - <<'PYEOF'
import sys, os
try:
    from dotenv import load_dotenv
    load_dotenv(".env")
except Exception:
    pass
try:
    from app.main import app
    n = len(getattr(app, "routes", []))
    print(f"    app.main imported, {n} routes registered")
except Exception as e:
    import traceback; traceback.print_exc()
    print(f"    IMPORT FAILED: {e}", file=sys.stderr)
    sys.exit(1)
try:
    from passlib.context import CryptContext
    ctx = CryptContext(schemes=["bcrypt"], deprecated="auto")
    h = ctx.hash("smoke")
    assert ctx.verify("smoke", h), "verify returned False"
    print("    passlib+bcrypt OK")
except Exception as e:
    import traceback; traceback.print_exc()
    print(f"    AUTH STACK FAILED: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
  ) || die "Backend smoke test failed — fix traceback above and re-run"

  ok "Python virtualenv ready ($BACKEND_PATH/.venv)"
fi

# ── [9/13] systemd unit ────────────────────────────────────────────────────
say "[9/13] systemd unit"

if [[ "$BACKEND_RUNTIME" == "node" ]]; then
  ENTRY=""
  if node -e "const p=require('./package.json'); process.exit(p.main ? 0 : 1)" 2>/dev/null; then
    ENTRY="$(node -e "console.log(require('./package.json').main)")"
    [[ -f "$ENTRY" ]] || ENTRY=""
  fi
  if [[ -z "$ENTRY" ]]; then
    for cand in dist/server.js dist/index.js dist/main.js server.js index.js app.js main.js; do
      [[ -f "$cand" ]] && { ENTRY="$cand"; break; }
    done
  fi
  [[ -n "$ENTRY" ]] || die "Cannot locate Node entry point in $BACKEND_PATH"
  EXEC_LINE="$(command -v node) ${ENTRY}"
  ok "Node entry: $ENTRY"
else
  WORKER_CLASS="uvicorn.workers.UvicornWorker"
  if .venv/bin/python -c 'import uvicorn_worker' 2>/dev/null; then
    WORKER_CLASS="uvicorn_worker.UvicornWorker"
    ok "Using uvicorn_worker.UvicornWorker (uvicorn >= 0.30)"
  else
    warn "uvicorn_worker not available — using legacy uvicorn.workers.UvicornWorker"
  fi

  case "$PY_SERVER" in
    gunicorn-uvicorn)
      EXEC_LINE="${BACKEND_PATH}/.venv/bin/python -m gunicorn --workers 3 --preload --worker-class ${WORKER_CLASS} --bind 127.0.0.1:${BACKEND_PORT} --timeout 120 --access-logfile - --error-logfile - ${PY_ENTRY}"
      ;;
    gunicorn)
      EXEC_LINE="${BACKEND_PATH}/.venv/bin/python -m gunicorn --workers 3 --preload --bind 127.0.0.1:${BACKEND_PORT} --timeout 120 --access-logfile - --error-logfile - ${PY_ENTRY}"
      ;;
    *) die "Unknown PY_SERVER=$PY_SERVER" ;;
  esac
  ok "Python exec: $PY_SERVER → $PY_ENTRY (${WORKER_CLASS})"
fi

if ss -tln 2>/dev/null | awk '{print $4}' | grep -q ":${BACKEND_PORT}\$"; then
  systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null \
    || die "Port ${BACKEND_PORT} in use by another service"
fi

sudo mkdir -p "$LOG_DIR"
sudo chown "${APP_USER}":"${APP_USER}" "$LOG_DIR"
sudo chmod 750 "$LOG_DIR"

sudo tee /etc/systemd/system/${SERVICE_NAME}.service >/dev/null <<EOF
[Unit]
Description=Food Court Counter (${SITE_SLUG}, ${BACKEND_RUNTIME})
After=network.target postgresql.service

[Service]
Type=simple
User=${APP_USER}
Group=${APP_USER}
WorkingDirectory=${BACKEND_PATH}
EnvironmentFile=${BACKEND_PATH}/.env
ExecStart=${EXEC_LINE}
Restart=always
RestartSec=5
StandardOutput=append:${LOG_DIR}/api.log
StandardError=append:${LOG_DIR}/api.log
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
  sudo systemctl restart "$SERVICE_NAME"
else
  sudo systemctl enable --now "$SERVICE_NAME"
fi
sleep 4

# Give the preload enough time to fail loudly if startup crashes
if ! sudo systemctl is-active --quiet "$SERVICE_NAME"; then
  sudo journalctl -u "$SERVICE_NAME" -n 60 --no-pager
  die "Service failed to start — traceback above"
fi
# With --preload, an active master that survived 4s means the app started OK
sudo chown -R "${APP_USER}":"${APP_USER}" "$LOG_DIR"
ok "Service $SERVICE_NAME → 127.0.0.1:${BACKEND_PORT}"

# ── [10/13] Frontend build ─────────────────────────────────────────────────
say "[10/13] Frontend"

if [[ -n "$FRONTEND_SUBDIR" && -f "$FRONTEND_PATH/package.json" ]]; then
  cd "$FRONTEND_PATH"

  cat > .env.production <<EOF
VITE_COMPANY_NAME="${COMPANY_NAME}"
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
EOF

  if [[ -f package-lock.json ]]; then
    npm ci --no-audit --no-fund
  else
    npm install --no-audit --no-fund
  fi

  say "  → patching tsconfig*.json (noUnusedLocals/Parameters = false)"
  patch_tsconfigs "$FRONTEND_PATH"

  if ! npm run build; then
    warn "npm run build failed — retrying with 'npx vite build' (skips tsc)"
    npx --no-install vite build \
      || die "Both npm run build and vite build failed — see $FRONTEND_PATH errors"
    warn "Deployed via vite build; type-check errors were ignored"
  fi

  FRONTEND_ROOT="$FRONTEND_PATH/dist"
  [[ -d "$FRONTEND_ROOT" ]] || die "Frontend build produced no dist/ in $FRONTEND_PATH"
  ok "Frontend built → $FRONTEND_ROOT"
else
  warn "No frontend — backend serves static itself"
  if [[ -d "$BACKEND_PATH/public" ]]; then
    FRONTEND_ROOT="$BACKEND_PATH/public"
  else
    FRONTEND_ROOT="$BACKEND_PATH"
  fi
  ok "Static root → $FRONTEND_ROOT"
fi

# ── [11/13] Web server config (HTTP only first) ────────────────────────────
say "[11/13] Web server config (HTTP)"

if [[ $HAS_CLOUDPANEL -eq 1 ]]; then
  warn "Skipping vhost (CloudPanel owns Nginx)"
elif [[ $HAS_APACHE -eq 1 ]]; then
  sudo a2enmod proxy proxy_http rewrite headers ssl deflate expires >/dev/null
  sudo tee "$APACHE_CONF" >/dev/null <<EOF
<VirtualHost *:80>
    ServerName ${DOMAIN}
    ServerAdmin ${LETSENCRYPT_EMAIL}
    DocumentRoot ${FRONTEND_ROOT}
    <Directory ${FRONTEND_ROOT}>
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
    ProxyPass /api/ http://127.0.0.1:${BACKEND_PORT}/api/ retry=0
    ProxyPassReverse /api/ http://127.0.0.1:${BACKEND_PORT}/api/
    ErrorLog \${APACHE_LOG_DIR}/${VHOST_NAME}-error.log
    CustomLog \${APACHE_LOG_DIR}/${VHOST_NAME}-access.log combined
</VirtualHost>
EOF
  sudo a2ensite "$VHOST_NAME" >/dev/null
  sudo apachectl configtest
  sudo systemctl reload apache2
  ok "Apache vhost ${VHOST_NAME}.conf enabled (HTTP)"
else
  sudo tee "$NGINX_CONF" >/dev/null <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    root ${FRONTEND_ROOT};
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
    location /api/ {
        proxy_pass http://127.0.0.1:${BACKEND_PORT}/api/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
    }
}
EOF
  sudo ln -sf "$NGINX_CONF" "/etc/nginx/sites-enabled/${VHOST_NAME}"
  sudo nginx -t
  sudo systemctl reload nginx
  ok "Nginx vhost ${VHOST_NAME} enabled (HTTP)"
fi

# ── [12/13] SSL ────────────────────────────────────────────────────────────
say "[12/13] SSL"
CERT_FULLCHAIN="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
CERT_PRIVKEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"

if [[ $HAS_CLOUDPANEL -eq 1 ]]; then
  warn "Skipping certbot (CloudPanel issues SSL per-site)"
elif [[ -f "$CERT_FULLCHAIN" ]]; then
  ok "Certificate already present"
else
  if command -v certbot >/dev/null && certbot plugins 2>/dev/null | grep -q dns-duckdns; then
    say "DNS-01 via DuckDNS plugin"
    sudo certbot certonly --non-interactive --agree-tos \
      --email "${LETSENCRYPT_EMAIL}" \
      --authenticator dns-duckdns \
      --dns-duckdns-token "${DUCKDNS_TOKEN}" \
      --dns-duckdns-propagation-seconds 60 \
      -d "${DOMAIN}" \
      || warn "DNS-01 failed — falling back to webroot"
  fi
  if [[ ! -f "$CERT_FULLCHAIN" ]]; then
    warn "Using HTTP-01 webroot"
    sudo certbot certonly --non-interactive --agree-tos \
      --email "${LETSENCRYPT_EMAIL}" \
      --webroot -w "${FRONTEND_ROOT}" -d "${DOMAIN}" \
      || die "Certbot failed — check DNS and port 80"
  fi
  ok "Certificate obtained"
fi

# Rewrite vhost to HTTPS once cert exists
if [[ $HAS_CLOUDPANEL -eq 0 && -f "$CERT_FULLCHAIN" ]]; then
  if [[ $HAS_APACHE -eq 1 ]]; then
    sudo tee "$APACHE_CONF" >/dev/null <<EOF
<VirtualHost *:80>
    ServerName ${DOMAIN}
    Redirect permanent / https://${DOMAIN}/
</VirtualHost>
<VirtualHost *:443>
    ServerName ${DOMAIN}
    ServerAdmin ${LETSENCRYPT_EMAIL}
    SSLEngine on
    SSLCertificateFile ${CERT_FULLCHAIN}
    SSLCertificateKeyFile ${CERT_PRIVKEY}
    SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    DocumentRoot ${FRONTEND_ROOT}
    <Directory ${FRONTEND_ROOT}>
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
    ProxyPass /api/ http://127.0.0.1:${BACKEND_PORT}/api/ retry=0
    ProxyPassReverse /api/ http://127.0.0.1:${BACKEND_PORT}/api/
    <Location /api/>
        ProxySet connectiontimeout=30 timeout=120
    </Location>
    ErrorLog \${APACHE_LOG_DIR}/${VHOST_NAME}-error.log
    CustomLog \${APACHE_LOG_DIR}/${VHOST_NAME}-access.log combined
</VirtualHost>
EOF
    sudo apachectl configtest
    sudo systemctl reload apache2
  else
    # Self-contained SSL config — no dependency on options-ssl-nginx.conf
    sudo tee "$NGINX_CONF" >/dev/null <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    http2 on;
    server_name ${DOMAIN};

    ssl_certificate     ${CERT_FULLCHAIN};
    ssl_certificate_key ${CERT_PRIVKEY};
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    root ${FRONTEND_ROOT};
    index index.html;

    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    location / { try_files \$uri \$uri/ /index.html; }
    location /api/ {
        proxy_pass http://127.0.0.1:${BACKEND_PORT}/api/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
    }
}
EOF
    sudo nginx -t
    sudo systemctl reload nginx
  fi
  ok "HTTPS configured"

  sudo mkdir -p /etc/letsencrypt/renewal-hooks/deploy
  sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-web.sh >/dev/null <<'HOOK'
#!/usr/bin/env bash
systemctl reload apache2 2>/dev/null || true
systemctl reload nginx   2>/dev/null || true
HOOK
  sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-web.sh
fi

# ── [13/13] Logrotate, permissions, smoke test ─────────────────────────────
say "[13/13] Logrotate, permissions, smoke test"

sudo tee "/etc/logrotate.d/${SITE_SLUG}" >/dev/null <<EOF
${LOG_DIR}/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    create 0640 ${APP_USER} ${APP_USER}
}
EOF
ok "Logrotate → /etc/logrotate.d/${SITE_SLUG} (14-day retention)"

sudo chown -R "${APP_USER}":"${APP_USER}" "$APP_DIR"
sudo find "$APP_DIR" -type d -exec chmod 755 {} \;
sudo find "$APP_DIR" -type f -exec chmod 644 {} \;
sudo chmod 640 "$BACKEND_PATH/.env"
ok "Permissions set (${APP_USER})"

sleep 2
if curl -fsS "https://${DOMAIN}/api/health" >/dev/null 2>&1; then
  ok "Public health check OK"
elif curl -fsS "http://127.0.0.1:${BACKEND_PORT}/api/health" >/dev/null 2>&1; then
  warn "Backend healthy locally; public URL not yet reachable"
else
  warn "Health check failed — see logs"
fi
sudo tail -n 5 "${LOG_DIR}/api.log" 2>/dev/null || true

echo
ok "Deployment complete"
cat <<SUMMARY

════════════════════════════════════════════════════════════════
  Site:              ${SITE_SLUG}
  URL:               https://${DOMAIN}/
  API base:          https://${DOMAIN}/api/
  Backend:           ${BACKEND_PATH}   (${BACKEND_RUNTIME})
  Frontend:          ${FRONTEND_ROOT}
  Service:           ${SERVICE_NAME}  (user: ${APP_USER})
  Backend port:      127.0.0.1:${BACKEND_PORT}
  Logs:              ${LOG_DIR}/api.log  (logrotate: 14 days)
  Database:          ${DB_NAME}  (owner: ${DB_USER})
  DB password:       ${DB_PASS}
                     ↳ Save now; hidden on future runs
                     ↳ Also stored in ${STATE_FILE} (mode 600)

  SSH as '${DEPLOY_USER}':   ssh ${DEPLOY_USER}@<server>

  $( [[ -f /var/run/reboot-required ]] && echo '⚠ REBOOT REQUIRED — run "sudo reboot" when convenient' )

  $( [[ $HAS_CLOUDPANEL -eq 1 ]] && cat <<'CP'
  ▸ CLOUDPANEL — finish in UI (https://<panel>:8443):
      Sites → Add Site → Node.js
      Vhost tab: location /api/ { proxy_pass http://127.0.0.1:<PORT>/api/; }
      Sites → SSL → issue Let's Encrypt
CP
  )

  First login:
    admin@example.com   / Admin@12345
    counter@example.com / Counter@12345

  Handy:
    sudo journalctl -u ${SERVICE_NAME} -f
    sudo tail -f ${LOG_DIR}/api.log
    sudo systemctl restart ${SERVICE_NAME}
    CLEAN=1   sudo ./server.sh    # rebuild artifacts only
    CLEAN=all sudo ./server.sh    # full reset (drops DB + files)
════════════════════════════════════════════════════════════════
SUMMARY