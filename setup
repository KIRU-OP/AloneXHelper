#!/usr/bin/env bash
# One-command setup for telegram-web-player (Ubuntu / Debian)
# Usage:  bash setup.sh
set -euo pipefail

GO_VERSION="${GO_VERSION:-1.26.4}"
SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

log() { echo -e "\n\033[1;32m==> $*\033[0m"; }

cd "$(dirname "$0")"

# ---------- 1. System dependencies ----------
log "Installing system dependencies"
$SUDO apt-get update -y
$SUDO apt-get install -y ffmpeg curl wget unzip git ca-certificates tmux

# ---------- 2. yt-dlp ----------
if ! command -v yt-dlp >/dev/null 2>&1; then
  log "Installing yt-dlp"
  $SUDO wget -q https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -O /usr/local/bin/yt-dlp
  $SUDO chmod a+rx /usr/local/bin/yt-dlp
else
  log "yt-dlp already installed"
fi

# ---------- 3. Deno ----------
if ! command -v deno >/dev/null 2>&1 && [ ! -x "$HOME/.deno/bin/deno" ]; then
  log "Installing Deno"
  curl -fsSL https://deno.land/install.sh | sh -s -- -y
  grep -q 'DENO_INSTALL' "$HOME/.bashrc" 2>/dev/null || {
    echo 'export DENO_INSTALL="$HOME/.deno"' >> "$HOME/.bashrc"
    echo 'export PATH="$DENO_INSTALL/bin:$PATH"' >> "$HOME/.bashrc"
  }
else
  log "Deno already installed"
fi
export DENO_INSTALL="$HOME/.deno"
export PATH="$DENO_INSTALL/bin:$PATH"

# ---------- 4. Go ----------
export PATH="$PATH:/usr/local/go/bin"
if ! command -v go >/dev/null 2>&1; then
  case "$(uname -m)" in
    x86_64)  GO_ARCH="amd64" ;;
    aarch64|arm64) GO_ARCH="arm64" ;;
    *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
  esac
  log "Installing Go ${GO_VERSION} (${GO_ARCH})"
  wget -q "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -O /tmp/go.tar.gz
  $SUDO rm -rf /usr/local/go
  $SUDO tar -C /usr/local -xzf /tmp/go.tar.gz
  rm -f /tmp/go.tar.gz
  grep -q '/usr/local/go/bin' "$HOME/.bashrc" 2>/dev/null || \
    echo 'export PATH=$PATH:/usr/local/go/bin' >> "$HOME/.bashrc"
else
  log "Go already installed: $(go version)"
fi

# ---------- 5. .env ----------
if [ ! -f .env ]; then
  log "Creating .env from sample.env"
  cp sample.env .env
  NEED_ENV=1
else
  log ".env already exists, skipping"
  NEED_ENV=0
fi

# ---------- 6. TDLib + build ----------
log "Downloading TDLib (go generate)"
go generate

log "Building binary"
go build -o tgweb main.go

# ---------- Done ----------
echo
echo -e "\033[1;32mSetup complete!\033[0m"
if [ "$NEED_ENV" = "1" ]; then
  echo "Next: fill in your credentials ->  nano .env"
  echo "(API_ID, API_HASH, TOKEN, MONGO_URI, OWNER_ID ...)"
fi
echo "Run the bot:        ./tgweb"
echo "Run in background:  tmux new -s tgweb  (then ./tgweb, detach with Ctrl+B then D)"
