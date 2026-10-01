#!/usr/bin/env bash
# ------------------------------------------------------------
#  AloneX Helper - one-shot setup script (Ubuntu/Debian VPS)
#
#  Usage:
#     bash setup.sh              # install everything
#     bash setup.sh --node       # also install Node.js 18 (via nvm)
#     bash setup.sh --run        # install, then start the bot
#     bash setup.sh --node --run
#
#  Run it from inside the repo folder.
# ------------------------------------------------------------
set -euo pipefail

VENV_DIR="AloneXRobot"
WITH_NODE=false
RUN_AFTER=false

for arg in "$@"; do
  case "$arg" in
    --node) WITH_NODE=true ;;
    --run)  RUN_AFTER=true ;;
    -h|--help)
      sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[x] %s\033[0m\n' "$*"; exit 1; }

# Always work from the script's own directory (the repo root)
cd "$(dirname "$(readlink -f "$0")")"
[ -f requirements.txt ] || die "requirements.txt not found. Run this script from the repo root."

# Use sudo only when not root
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || die "Run as root or install sudo."
  SUDO="sudo"
fi

# ---------- 1. System packages ----------
log "Updating system & installing packages"
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -y
$SUDO apt-get install -y --no-install-recommends \
  git curl nano tmux \
  python3 python3-pip python3-venv \
  ffmpeg libgl1 libglx-mesa0 \
  build-essential python3-dev libffi-dev libssl-dev
$SUDO apt-get clean

# Disk space check (need roughly 3 GB free)
FREE_MB="$(df -Pm . | awk 'NR==2{print $4}')"
if [ "$FREE_MB" -lt 3000 ]; then
  die "Only ${FREE_MB} MB free. Free up space first (pip cache purge; apt-get clean)."
fi

# ---------- 2. Python version check (repo wants 3.12) ----------
WANT_PY="$(tr -d '[:space:]' < .python-version 2>/dev/null || echo 3.12)"
HAVE_PY="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
if [ "${HAVE_PY}" != "${WANT_PY%.*}" ] && [[ "$WANT_PY" != "$HAVE_PY"* ]]; then
  warn "Repo targets Python ${WANT_PY}, but system has ${HAVE_PY}. Usually fine; if install fails, install Python ${WANT_PY} (deadsnakes PPA)."
fi

# ---------- 3. Optional Node.js ----------
if $WITH_NODE; then
  log "Installing Node.js 18 via nvm"
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  fi
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  nvm install 18
fi

# ---------- 4. Virtual environment ----------
log "Creating virtual environment: ${VENV_DIR}"
[ -d "$VENV_DIR" ] || python3 -m venv "$VENV_DIR"
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

# ---------- 5. Python dependencies ----------
log "Installing Python requirements"
pip install --no-cache-dir -U pip wheel setuptools
pip install --no-cache-dir -U -r requirements.txt
pip cache purge >/dev/null 2>&1 || true

# ---------- 6. .env file ----------
if [ ! -f .env ]; then
  log "Creating .env template"
  cat > .env <<'EOF'
TOKEN=
DB_URL=
DB_URL2=
API_ID=
API_HASH=
GROQ_API_KEY=
GEMINI_API_KEY=
ALONE_OWNER_ID=
LOG_GROUP_ID=
SUPPORT_CHAT=
UPDATE_CHANNEL=
EOF
  chmod 600 .env
  warn "Fill in your values:  nano .env"
else
  log ".env already exists - leaving it untouched"
fi

# Quick check for required values
missing=()
for key in TOKEN DB_URL API_ID API_HASH ALONE_OWNER_ID; do
  val="$(grep -E "^${key}=" .env | head -n1 | cut -d= -f2- | tr -d '"' | tr -d "'" || true)"
  [ -n "$val" ] || missing+=("$key")
done
if [ "${#missing[@]}" -gt 0 ]; then
  warn "Empty in .env: ${missing[*]}"
  warn "Edit with 'nano .env' (Ctrl+X, Y, Enter to save), then start the bot."
fi

# ---------- 7. Done ----------
log "Setup complete"
cat <<EOF

To start the bot:
    tmux new -s alonex                # keeps it running after you close SSH
    source ${VENV_DIR}/bin/activate
    python3 -m AloneX

Detach tmux: Ctrl+B then D    |    Re-attach: tmux attach -t alonex
EOF

if $RUN_AFTER; then
  if [ "${#missing[@]}" -gt 0 ]; then
    die "Not starting: fill the missing .env values first."
  fi
  log "Starting the bot"
  exec python3 -m AloneX
fi
