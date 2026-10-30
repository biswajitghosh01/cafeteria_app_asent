#!/usr/bin/env bash
# =============================================================
# Food Court Counter — Local Development Setup
#
# Default: SQLite (zero-config). Optional: local PostgreSQL.
# =============================================================
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

say()  { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Required tool not found: $1"; }

gen_secret() {
  if command -v openssl >/dev/null 2>&1; then openssl rand -hex 32
  else python3 -c 'import secrets; print(secrets.token_hex(32))'; fi
}

sed_inplace() {
  if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi
}

say "Checking prerequisites"
need python3; need node; need npm
ok "python3: $(python3 --version 2>&1)"
ok "node:    $(node --version)"
ok "npm:     $(npm  --version)"

if [[ "${SKIP_BACKEND:-0}" != "1" ]]; then
  say "Setting up backend"
  pushd backend >/dev/null
  [[ -d .venv ]] || { python3 -m venv .venv; ok "Created backend/.venv"; }
  # shellcheck disable=SC1091
  source .venv/bin/activate
  pip install --upgrade pip >/dev/null
  pip install -r requirements.txt
  ok "Installed Python dependencies"
  if [[ ! -f .env ]]; then
    cp .env.example .env
    sed_inplace "s|^SECRET_KEY=.*|SECRET_KEY=$(gen_secret)|" .env
    ok "Created backend/.env with a fresh SECRET_KEY"
  else
    ok "backend/.env already exists — leaving untouched"
  fi
  deactivate
  popd >/dev/null
fi

if [[ "${SKIP_FRONTEND:-0}" != "1" ]]; then
  say "Setting up frontend"
  pushd frontend >/dev/null
  npm install
  ok "Installed frontend dependencies"
  [[ -f .env.local ]] || { cp .env.example .env.local; ok "Created frontend/.env.local"; }
  popd >/dev/null
fi

if [[ "${SKIP_DB:-0}" != "1" ]]; then
  echo
  echo "Database choice:"
  echo "  [1] SQLite     — zero-config, recommended for development (default)"
  echo "  [2] PostgreSQL — requires a running local PostgreSQL server"
  read -r -p "Choose [1/2]: " db_choice
  case "${db_choice:-1}" in
    2)
      if ! command -v psql >/dev/null 2>&1; then
        warn "psql not found — staying on SQLite."
      else
        DB_NAME="${POSTGRES_DB:-food_court_db}"
        DB_USER="${POSTGRES_USER:-fc_user}"
        DB_PASS="${POSTGRES_PASSWORD:-$(gen_secret | cut -c1-24)}"
        if sudo -n true 2>/dev/null; then SUDO="sudo"; else SUDO=""; fi
        $SUDO -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 \
          || $SUDO -u postgres createdb "${DB_NAME}"
        $SUDO -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1 \
          && $SUDO -u postgres psql -c "ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASS}';" \
          || $SUDO -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"
        $SUDO -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"
        $SUDO -u postgres psql -c "ALTER DATABASE ${DB_NAME} OWNER TO ${DB_USER};"
        sed_inplace \
          "s|^DATABASE_URL=.*|DATABASE_URL=postgresql+asyncpg://${DB_USER}:${DB_PASS}@localhost:5432/${DB_NAME}|" \
          backend/.env
        ok "PostgreSQL configured — credentials written to backend/.env"
      fi
      ;;
    *)
      sed_inplace "s|^ENVIRONMENT=.*|ENVIRONMENT=development|" backend/.env
      ok "Using SQLite — data will live in backend/food_court_dev.db"
      ;;
  esac
fi

echo
ok "Local setup complete."
cat <<'EOM'

Next steps — open two terminals:

  ── Terminal 1: backend ─────────────────────────────────────
    cd backend
    source .venv/bin/activate
    uvicorn app.main:app --reload --port 8000

  ── Terminal 2: frontend ────────────────────────────────────
    cd frontend
    npm run dev

Open http://localhost:5173
Log in with:
  admin@example.com   / Admin@12345
  counter@example.com / Counter@12345

Change both passwords immediately via Admin Console → Users.
EOM
