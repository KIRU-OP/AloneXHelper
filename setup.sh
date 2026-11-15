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

# ---------- 6. Interactive .env configuration ----------
ENV_KEYS=(TOKEN DB_URL DB_URL2 API_ID API_HASH GROQ_API_KEY GEMINI_API_KEY ALONE_OWNER_ID LOG_GROUP_ID SUPPORT_CHAT UPDATE_CHANNEL)

if [ ! -f .env ]; then
  touch .env
  chmod 600 .env
fi

log "Configure bot credentials"
cat <<'ENVHELP'

Enter your own values when prompted. Leave a field blank to keep its
current .env value (or leave it empty if it has never been configured).

TOKEN=YOUR BOT TOKEN
DB_URL=YOUR MONGO DB
DB_URL2=YOUR MONGO DB
API_ID=YOUR TELEGRAM API ID
API_HASH=YOUR TELEGRAM API HASH
GROQ_API_KEY=YOUR GROQ API KEY
GEMINI_API_KEY=YOUR GEMINI API KEY
ALONE_OWNER_ID=BOT OWNER ID
LOG_GROUP_ID=BOT LOGGER GROUP
SUPPORT_CHAT=YOUR SUPPORT GROUP
UPDATE_CHANNEL=YOUR SUPPORT CHANNEL

ENVHELP

get_env_value() {
  grep -m1 -E "^$1=" .env 2>/dev/null | cut -d= -f2- || true
}

for key in "${ENV_KEYS[@]}"; do
  current="$(get_env_value "$key")"
  if [[ "$key" == "TOKEN" || "$key" == "DB_URL" || "$key" == "DB_URL2" || "$key" == "API_HASH" || "$key" == "GROQ_API_KEY" || "$key" == "GEMINI_API_KEY" ]]; then
    if [ -n "$current" ]; then
      read -r -s -p "$key (press Enter to keep saved value): " value
      printf '\n'
    else
      read -r -s -p "$key: " value
      printf '\n'
    fi
  else
    if [ -n "$current" ]; then
      read -r -p "$key (press Enter to keep saved value): " value
    else
      read -r -p "$key: " value
    fi
  fi
  if [ -z "$value" ]; then value="$current"; fi
  export "ALONEX_ENV_$key=$value"
done

# Update only the known keys; preserve comments, unknown settings and all
# previously saved values when the user presses Enter.
python3 - <<'PYENV'
import os
from pathlib import Path

path = Path(".env")
keys = "TOKEN DB_URL DB_URL2 API_ID API_HASH GROQ_API_KEY GEMINI_API_KEY ALONE_OWNER_ID LOG_GROUP_ID SUPPORT_CHAT UPDATE_CHANNEL".split()
lines = path.read_text().splitlines() if path.exists() else []
values = {key: os.environ.get("ALONEX_ENV_" + key, "") for key in keys}
seen = set()
out = []
for line in lines:
    if "=" in line and not line.lstrip().startswith("#"):
        key = line.split("=", 1)[0].strip()
        if key in values:
            if key not in seen:
                out.append(f"{key}={values[key]}")
                seen.add(key)
            continue
    out.append(line)
for key in keys:
    if key not in seen:
        out.append(f"{key}={values[key]}")
path.write_text("\n".join(out) + "\n")
os.chmod(path, 0o600)
PYENV

missing=()
for key in "${ENV_KEYS[@]}"; do
  val="$(get_env_value "$key")"
  [ -n "$val" ] || missing+=("$key")
done
if [ "${#missing[@]}" -gt 0 ]; then
  warn "Still empty in .env: ${missing[*]}"
  warn "Run 'bash setup' again to complete these values, or edit with 'nano .env'."
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
