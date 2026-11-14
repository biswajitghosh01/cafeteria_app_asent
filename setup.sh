#!/usr/bin/env bash
#
# setup.sh — bootstrap the Food Court Counter app on a fresh machine.
#
# Installs missing host tooling, creates the backend virtualenv with a
# Python version the pinned dependencies actually support, installs every
# dependency, generates backend/.env, and optionally starts both servers.
#
# Usage:
#   ./setup.sh [options]
#
# Options:
#   --check          Verify prerequisites and report what is missing.
#                    Installs nothing, starts nothing.
#   --with-python    Install a compatible Python via Homebrew if needed.
#   --postgres       Configure a local PostgreSQL database instead of SQLite.
#   --no-start       Prepare everything but do not launch the servers.
#   --backend-only   Skip frontend dependency installation.
#   --frontend-only  Skip backend setup.
#   -h, --help       Show this help.
#
# Environment overrides:
#   PYTHON_BIN       Force a specific Python interpreter.
#   SKIP_BACKEND=1   Same as --backend-only.
#   SKIP_FRONTEND=1  Same as --frontend-only.
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---------------------------------------------------------------- settings
# pydantic-core and asyncpg ship no cp315 wheels, so the pinned
# requirements.txt cannot install on Python 3.15. Accept 3.10–3.14.
PYTHON_MIN_MAJOR=3
PYTHON_MIN_MINOR=10
PYTHON_MAX_MINOR=14

PYTHON_BIN="${PYTHON_BIN:-}"
BACKEND_DIR="backend"
FRONTEND_DIR="frontend"
VENV_DIR="$BACKEND_DIR/.venv"

DO_CHECK=0
WITH_PYTHON=0
USE_POSTGRES=0
NO_START=0
SKIP_BACKEND="${SKIP_BACKEND:-0}"
SKIP_FRONTEND="${SKIP_FRONTEND:-0}"

# ---------------------------------------------------------------- appearance
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[31m';   C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
  C_RESET=''; C_BOLD=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''
fi

step() { printf '%s▸%s %s\n' "$C_BLUE$C_BOLD" "$C_RESET" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$C_GREEN$C_BOLD" "$C_RESET" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_YELLOW$C_BOLD" "$C_RESET" "$*" >&2; }
die()  { printf '%s✗%s %s\n' "$C_RED$C_BOLD" "$C_RESET" "$*" >&2; exit 1; }

usage() { sed -n '3,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

# ---------------------------------------------------------------- options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)         DO_CHECK=1 ;;
    --with-python)   WITH_PYTHON=1 ;;
    --postgres)      USE_POSTGRES=1 ;;
    --no-start)      NO_START=1 ;;
    --backend-only)  SKIP_BACKEND=0; SKIP_FRONTEND=1 ;;
    --frontend-only) SKIP_BACKEND=1; SKIP_FRONTEND=0 ;;
    -h|--help)       usage ;;
    *)               die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

# ---------------------------------------------------------------- helpers
OS_RAW="$(uname -s)"
case "$OS_RAW" in
  Darwin) OS="macos" ;;
  Linux)  OS="linux" ;;
  *)      die "unsupported operating system: $OS_RAW" ;;
esac

if [[ "$OS" == "macos" ]]; then
  command -v brew >/dev/null 2>&1 && HAVE_BREW=1 || HAVE_BREW=0
else
  HAVE_BREW=0
  if command -v apt-get >/dev/null 2>&1; then PKG_MGR="apt-get"
  elif command -v dnf >/dev/null 2>&1; then PKG_MGR="dnf"
  else PKG_MGR=""; fi
fi

# Compare "major.minor" versions: returns 0 when $1 is within the supported range.
version_supported() {
  local raw="$1" major minor
  major="${raw%%.*}"; minor="${raw#*.}"; minor="${minor%%.*}"
  [[ "$major" -eq "$PYTHON_MIN_MAJOR" ]] || return 1
  (( minor >= PYTHON_MIN_MINOR && minor <= PYTHON_MAX_MINOR ))
}

# Print "major.minor" for a candidate, or fail.
python_version_of() {
  "$1" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null
}

# A candidate is usable when it is a supported version and can create venvs.
python_usable() {
  local candidate="$1" ver
  command -v "$candidate" >/dev/null 2>&1 || return 1
  ver="$(python_version_of "$candidate")" || return 1
  [[ -n "$ver" ]] || return 1
  if ! version_supported "$ver"; then
    debug_reject="$ver"
    return 1
  fi
  "$candidate" -c 'import venv' >/dev/null 2>&1 || return 1
  PYTHON_FOUND="$candidate"
  PYTHON_VER="$ver"
  return 0
}

install_python() {
  step "Installing a compatible Python (3.$PYTHON_MIN_MINOR–3.$PYTHON_MAX_MINOR)"
  if [[ "$OS" == "macos" ]]; then
    [[ "$HAVE_BREW" == "1" ]] || {
      warn "installing Homebrew first"
      NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
        || return 1
      eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || brew shellenv)" 2>/dev/null || true
      HAVE_BREW=1
    }
    # Prefer the newest supported version.
    local target="python@3.$PYTHON_MAX_MINOR"
    brew install "$target" 2>&1 | sed 's/^/    /' >&2 || return 1
    return 0
  fi
  case "$PKG_MGR" in
    apt-get)
      sudo apt-get update -qq || return 1
      sudo apt-get install -y -qq "python3.${PYTHON_MAX_MINOR}" python3-venv python3-pip || return 1
      ;;
    dnf)
      sudo dnf install -y "python3.${PYTHON_MAX_MINOR}" python3-pip || return 1
      ;;
    *) return 1 ;;
  esac
  return 0
}

# --------------------------------------------------------------- preflight
step "Preflight"

[[ -f "$BACKEND_DIR/requirements.txt" ]] || die "backend/requirements.txt not found; run from the project root."
[[ -f "$FRONTEND_DIR/package.json" ]]    || die "frontend/package.json not found; run from the project root."
ok "project layout detected"

step "Checking host tools"

command -v python3 >/dev/null 2>&1 || warn "python3 not on PATH"
if command -v node >/dev/null 2>&1; then
  ok "node $(node --version)"
else
  warn "node not found; frontend setup will be skipped"
  SKIP_FRONTEND=1
fi
if command -v npm >/dev/null 2>&1; then
  ok "npm $(npm --version)"
else
  warn "npm not found; frontend setup will be skipped"
  SKIP_FRONTEND=1
fi

# ------------------------------------------------------------ python detect
step "Python interpreter"

PYTHON_FOUND=""
PYTHON_VER=""

if [[ -n "$PYTHON_BIN" ]]; then
  if python_usable "$PYTHON_BIN"; then
    ok "using PYTHON_BIN override: $PYTHON_BIN (Python $PYTHON_VER)"
  else
    die "PYTHON_BIN=$PYTHON_BIN is not a Python ${PYTHON_MIN_MAJOR}.${PYTHON_MIN_MINOR}–${PYTHON_MIN_MAJOR}.${PYTHON_MAX_MINOR} with venv support."
  fi
else
  # Only consider interpreters in the supported range.
  for candidate in python3 python3.14 python3.13 python3.12 python3.11 python3.10 python3.9 python3; do
    if python_usable "$candidate"; then
      PYTHON_FOUND="$candidate"
      break
    fi
    [[ -n "${debug_reject:-}" ]] && debug_reject=""
  done

  if [[ -z "$PYTHON_FOUND" ]]; then
    warn "no Python ${PYTHON_MIN_MAJOR}.${PYTHON_MIN_MINOR}–${PYTHON_MIN_MAJOR}.${PYTHON_MAX_MINOR} found"
    if [[ "$OS" == "macos" ]]; then
      warn "the default python3 is $(python3 --version 2>&1 | awk '{print $2}'), which has no wheels for the pinned dependencies"
    fi
    if [[ "$WITH_PYTHON" == "1" && "$DO_CHECK" == "0" ]]; then
      install_python || die "could not install a compatible Python. Install Python 3.$PYTHON_MAX_MINOR manually and set PYTHON_BIN."
      for candidate in python3.14 python3.13 python3.12 python3.11 python3.10 python3; do
        if python_usable "$candidate"; then PYTHON_FOUND="$candidate"; break; fi
      done
    fi
    [[ -n "$PYTHON_FOUND" ]] || {
      if [[ "$DO_CHECK" == "1" ]]; then
        step "Result"
        warn "environment incomplete (check mode; nothing changed)"
        exit 1
      fi
      die "no compatible Python. Install Python 3.$PYTHON_MAX_MINOR or pass PYTHON_BIN=/path/to/python3.$PYTHON_MAX_MINOR"
    }
  fi
  ok "using $(basename "$PYTHON_FOUND") (Python $PYTHON_VER)"
fi

# ------------------------------------------------------------------ check
if [[ "$DO_CHECK" == "1" ]]; then
  step "Virtual environment"
  if [[ -x "$VENV_DIR/bin/python" ]]; then
    ok "backend/.venv present ($("$VENV_DIR/bin/python" --version 2>&1))"
    if "$VENV_DIR/bin/python" -c 'import fastapi, sqlalchemy' >/dev/null 2>&1; then
      ok "backend dependencies installed"
    else
      warn "backend dependencies missing or broken; run ./setup.sh"
    fi
  else
    warn "backend/.venv missing; run ./setup.sh"
  fi

  step "Configuration"
  [[ -f "$BACKEND_DIR/.env" ]] && ok "backend/.env present" || warn "backend/.env missing; run ./setup.sh"

  step "Frontend"
  if [[ -d "$FRONTEND_DIR/node_modules" ]]; then
    ok "frontend/node_modules present"
  else
    warn "frontend dependencies not installed; run ./setup.sh"
  fi

  step "Result"
  ok "check complete (nothing changed)"
  exit 0
fi

# --------------------------------------------------------------- backend
if [[ "$SKIP_BACKEND" != "1" ]]; then
  step "Backend"

  if [[ -e "$VENV_DIR" && ! -x "$VENV_DIR/bin/python" ]]; then
    BACKUP="$VENV_DIR.invalid-$(date +%Y%m%d%H%M%S)"
    mv -- "$VENV_DIR" "$BACKUP"
    warn "moved incomplete .venv to $BACKUP"
  fi

  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    "$PYTHON_FOUND" -m venv "$VENV_DIR" \
      || die "could not create $VENV_DIR. On Debian/Ubuntu install python3-venv."
    ok "created backend/.venv"
  else
    ok "backend/.venv exists"
  fi

  VENV_PYTHON="$SCRIPT_DIR/$VENV_DIR/bin/python"
  VENV_PIP="$SCRIPT_DIR/$VENV_DIR/bin/pip"

  "$VENV_PYTHON" -m pip install --upgrade pip --quiet 2>&1 | tail -2 || true
  ok "pip ready"

  # Prefer wheels; fall back to source builds only when a wheel is absent.
  step "Installing Python dependencies"
  if ! "$VENV_PIP" install --only-binary=:all: -r "$BACKEND_DIR/requirements.txt" 2>&1 | sed 's/^/    /'; then
    warn "wheel-only install failed; retrying with source builds allowed"
    "$VENV_PIP" install -r "$BACKEND_DIR/requirements.txt" 2>&1 | sed 's/^/    /' \
      || die "backend dependency installation failed."
  fi
  ok "Python dependencies installed"

  # ---------------------------------------------------------- backend/.env
  step "Backend configuration"
  if [[ ! -f "$BACKEND_DIR/.env" ]]; then
    SECRET="$("$VENV_PYTHON" -c 'import secrets; print(secrets.token_hex(32))')"
    cat > "$BACKEND_DIR/.env" <<EOF
# Local development configuration. Never commit this file.
ENVIRONMENT=development
DEBUG=true

SECRET_KEY=$SECRET
ACCESS_TOKEN_EXPIRE_MINUTES=720

# SQLite (default). For PostgreSQL, use --postgres or set:
# DATABASE_URL=postgresql+asyncpg://user:pass@localhost:5432/food_court_db
DATABASE_URL=sqlite+aiosqlite:///./food_court_dev.db

BACKEND_CORS_ORIGINS=http://localhost:5173

# Change these before using the app beyond local development.
DEFAULT_ADMIN_EMAIL=admin@example.com
DEFAULT_ADMIN_PASSWORD=Admin@12345
DEFAULT_COUNTER_EMAIL=counter@example.com
DEFAULT_COUNTER_PASSWORD=Counter@12345

UPLOAD_ROOT=./uploads/documents
LOG_DIR=./logs
EOF
    chmod 600 "$BACKEND_DIR/.env"
    ok "created backend/.env (chmod 600) with a fresh SECRET_KEY"
  else
    chmod 600 "$BACKEND_DIR/.env" 2>/dev/null || true
    ok "backend/.env already exists (preserved)"
  fi

  mkdir -p "$BACKEND_DIR/uploads/documents" "$BACKEND_DIR/logs"
  ok "upload and log directories ready"

  # ------------------------------------------------------------ postgres
  if [[ "$USE_POSTGRES" == "1" ]]; then
    step "PostgreSQL"
    if ! command -v psql >/dev/null 2>&1; then
      warn "psql not found; staying on SQLite"
    else
      DB_NAME="${POSTGRES_DB:-food_court_db}"
      DB_USER="${POSTGRES_USER:-fc_user}"
      DB_PASS="${POSTGRES_PASSWORD:-$("$VENV_PYTHON" -c 'import secrets; print(secrets.token_hex(12))')}"
      if sudo -n true 2>/dev/null; then SUDO="sudo"; else SUDO=""; fi

      $SUDO -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 \
        || $SUDO -u postgres createdb "${DB_NAME}"
      if $SUDO -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1; then
        $SUDO -u postgres psql -c "ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASS}';" >/dev/null
      else
        $SUDO -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';" >/dev/null
      fi
      $SUDO -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};" >/dev/null
      $SUDO -u postgres psql -c "ALTER DATABASE ${DB_NAME} OWNER TO ${DB_USER};" >/dev/null

      "$VENV_PYTHON" - "$BACKEND_DIR/.env" "postgresql+asyncpg://${DB_USER}:${DB_PASS}@localhost:5432/${DB_NAME}" <<'PY'
import sys
from pathlib import Path

path, url = Path(sys.argv[1]), sys.argv[2]
lines = path.read_text().splitlines()
out, replaced = [], False
for line in lines:
    if line.startswith("DATABASE_URL="):
        out.append(f"DATABASE_URL={url}")
        replaced = True
    else:
        out.append(line)
if not replaced:
    out.append(f"DATABASE_URL={url}")
path.write_text("\n".join(out) + "\n")
PY
      ok "PostgreSQL configured — credentials written to backend/.env"
    fi
  fi

  # ------------------------------------------------------ import verification
  step "Verifying backend imports"
  "$VENV_PYTHON" - <<'PY' || die "backend import verification failed."
import sys
try:
    import fastapi, sqlalchemy, aiosqlite, pydantic_settings  # noqa: F401
    from app.config import get_settings
    s = get_settings()
    print(f"  python {sys.version.split()[0]}")
    print(f"  database {s.resolved_database_url.split('://')[0]}")
except Exception as exc:  # noqa: BLE001
    print(f"  import failed: {exc}", file=sys.stderr)
    sys.exit(1)
PY
  ok "backend imports cleanly"
fi

# -------------------------------------------------------------- frontend
if [[ "$SKIP_FRONTEND" != "1" ]]; then
  step "Frontend"
  if [[ ! -f "$FRONTEND_DIR/package-lock.json" ]]; then
    warn "no package-lock.json; using npm install instead of npm ci"
    ( cd "$FRONTEND_DIR" && npm install --no-audit --no-fund 2>&1 | tail -5 ) || die "frontend install failed."
  else
    ( cd "$FRONTEND_DIR" && npm ci --no-audit --no-fund 2>&1 | tail -5 ) || {
      warn "npm ci failed; retrying with npm install"
      ( cd "$FRONTEND_DIR" && npm install --no-audit --no-fund 2>&1 | tail -5 ) || die "frontend install failed."
    }
  fi
  ok "frontend dependencies installed"
fi

# ------------------------------------------------------------------ start
step "Ready"

if [[ "$NO_START" == "1" ]]; then
  ok "setup complete (start scripts not launched)"
  exit 0
fi

printf '\n'
cat <<'EOM'
Start the app with two terminals:

  Terminal 1 — API:
    cd backend
    source .venv/bin/activate
    uvicorn app.main:app --reload --port 8000

  Terminal 2 — web app:
    cd frontend
    npm run dev

Open http://localhost:5173

Default sign-in credentials (change them before real use):
  admin@example.com   / Admin@12345
  counter@example.com / Counter@12345
EOM