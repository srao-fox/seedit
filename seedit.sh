#!/usr/bin/env bash
# =============================================================================
# setup-all.sh - one-shot setup for a new seedbox user
#   - Python 3 (user-local, via uv) + virtualenv
#   - Playwright + browsers + common Python packages
#   - VS Code CLI + Remote Tunnel (code from browser / desktop VS Code)
# Works WITHOUT root. Uses sudo/apt automatically if available.
# Safe to re-run: anything already installed is detected and skipped.
#
# Usage:   bash setup-all.sh
# Options: PY_VERSION=3.11 BROWSERS="chromium firefox" TUNNEL_NAME=mybox bash setup-all.sh
# =============================================================================
set -euo pipefail

# ---------- Config ----------
PY_VERSION="${PY_VERSION:-3.12}"
VENV_DIR="${VENV_DIR:-$HOME/.venvs/main}"
BROWSERS="${BROWSERS:-chromium}"
EXTRA_PKGS="${EXTRA_PKGS:-requests httpx beautifulsoup4 lxml python-dotenv}"
TUNNEL_NAME="${TUNNEL_NAME:-seedbox}"
BIN="$HOME/.local/bin"

# ---------- Helpers ----------
log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
info() { printf '\033[1;36m[=]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
step() { printf '\n\033[1;35m==== %s ====\033[0m\n' "$*"; }

fetch() {  # fetch URL to stdout
  if command -v curl >/dev/null 2>&1; then curl -LsSf "$1"
  elif command -v wget >/dev/null 2>&1; then wget -qO- "$1"
  else die "Neither curl nor wget is installed."; fi
}

mkdir -p "$BIN" "$HOME/.venvs" "$HOME/.cache"
export PATH="$BIN:$PATH"

# =============================================================================
step "1/7  System check"
# =============================================================================
HAS_SUDO=0; SUDO=""
if [ "$(id -u)" -eq 0 ]; then
  HAS_SUDO=1
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  HAS_SUDO=1; SUDO="sudo"
fi
if [ "$HAS_SUDO" -eq 1 ]; then log "Root/sudo available"; else info "No root/sudo: installing everything in \$HOME"; fi
info "CPU: $(uname -m)   OS: $(uname -s)   Home: $HOME"

if [ "$HAS_SUDO" -eq 1 ] && command -v apt-get >/dev/null 2>&1; then
  log "Installing base system packages via apt..."
  $SUDO apt-get update -y
  $SUDO apt-get install -y curl wget git unzip ca-certificates build-essential screen tmux
fi

# =============================================================================
step "2/7  uv (Python manager)"
# =============================================================================
if command -v uv >/dev/null 2>&1; then
  info "uv already present: $(uv --version)"
else
  log "Installing uv..."
  fetch https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="$BIN" INSTALLER_NO_MODIFY_PATH=1 sh
  command -v uv >/dev/null 2>&1 || die "uv install failed"
  log "Installed: $(uv --version)"
fi

# =============================================================================
step "3/7  Python $PY_VERSION + virtualenv"
# =============================================================================
uv python install "$PY_VERSION"
if [ -x "$VENV_DIR/bin/python" ]; then
  info "Virtualenv already present at $VENV_DIR"
else
  log "Creating virtualenv at $VENV_DIR"
  uv venv --seed --python "$PY_VERSION" "$VENV_DIR"
fi
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
log "Python: $(python --version)"

# =============================================================================
step "4/7  Python packages"
# =============================================================================
# shellcheck disable=SC2086
uv pip install --upgrade pip playwright $EXTRA_PKGS
log "Playwright: $(python -m playwright --version)"

# =============================================================================
step "5/7  Playwright browsers ($BROWSERS)"
# =============================================================================
if [ "$HAS_SUDO" -eq 1 ]; then
  # shellcheck disable=SC2086
  python -m playwright install --with-deps $BROWSERS
else
  # shellcheck disable=SC2086
  python -m playwright install $BROWSERS
fi

# Check for missing system libraries (common on shared seedboxes)
MISSING=""
while IFS= read -r b; do
  libs=$(ldd "$b" 2>/dev/null | awk '/not found/{print $1}' || true)
  [ -n "$libs" ] && MISSING="$MISSING $libs"
done < <(find "$HOME/.cache/ms-playwright" -type f \
          \( -name chrome -o -name headless_shell -o -name chrome-headless-shell \) 2>/dev/null)
MISSING=$(echo "$MISSING" | tr ' ' '\n' | sort -u | grep -v '^$' || true)
if [ -n "$MISSING" ]; then
  warn "Browser is missing these system libraries:"
  echo "$MISSING" | sed 's/^/      /'
  warn "Ask your seedbox provider to install them."
fi

# Smoke test
PW_STATUS="skipped"
if echo "$BROWSERS" | grep -qw chromium; then
  log "Running Playwright smoke test..."
  if python - <<'PYEOF'
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    b = p.chromium.launch(headless=True, args=["--no-sandbox"])
    page = b.new_page()
    page.set_content("<title>ok</title>")
    assert page.title() == "ok"
    b.close()
PYEOF
  then PW_STATUS="OK"; log "Smoke test passed"
  else PW_STATUS="FAILED"; warn "Smoke test failed; see missing-library notes above."
  fi
fi

# =============================================================================
step "6/7  VS Code CLI + tunnel"
# =============================================================================
case "$(uname -m)" in
  x86_64)        VS_OS=cli-alpine-x64 ;;
  aarch64|arm64) VS_OS=cli-alpine-arm64 ;;
  armv7l)        VS_OS=cli-linux-armhf ;;
  *)             VS_OS="" ;;
esac

TUNNEL_STATUS="not started"
if command -v code >/dev/null 2>&1; then
  info "VS Code CLI already present at $(command -v code): $(code --version | head -n1)"
elif [ -z "$VS_OS" ]; then
  warn "Unsupported CPU for VS Code CLI: $(uname -m). Skipping."
else
  log "Downloading VS Code CLI ($VS_OS)..."
  TMP="$HOME/.cache/vscode-cli.tar.gz"
  curl -Lf -o "$TMP" "https://code.visualstudio.com/sha/download?build=stable&os=$VS_OS"
  tar -xzf "$TMP" -C "$BIN"
  chmod +x "$BIN/code"
  rm -f "$TMP"
  log "Installed: $(code --version | head -n1)"
fi

if command -v code >/dev/null 2>&1; then
  CMD="code tunnel --accept-server-license-terms --name $TUNNEL_NAME"
  if command -v tmux >/dev/null 2>&1; then
    tmux kill-session -t vscode 2>/dev/null || true
    tmux new-session -d -s vscode "$CMD"
    TUNNEL_STATUS="running in tmux  (tmux attach -t vscode)"
  elif command -v screen >/dev/null 2>&1; then
    screen -S vscode -X quit 2>/dev/null || true
    screen -dmS vscode bash -c "$CMD"
    TUNNEL_STATUS="running in screen  (screen -r vscode)"
  else
    TUNNEL_STATUS="no tmux/screen; run manually:  $CMD"
  fi
fi

# =============================================================================
step "7/7  Shell config"
# =============================================================================
MARK="# >>> seedbox-setup >>>"
if grep -qF "$MARK" "$HOME/.bashrc" 2>/dev/null; then
  info "~/.bashrc already configured"
else
  log "Adding PATH + venv activation to ~/.bashrc"
  cat >> "$HOME/.bashrc" <<EOF

$MARK
export PATH="\$HOME/.local/bin:\$PATH"
[ -f "$VENV_DIR/bin/activate" ] && source "$VENV_DIR/bin/activate"
# <<< seedbox-setup <<<
EOF
fi

# =============================================================================
# Summary
# =============================================================================
cat <<EOF

$(printf '\033[1;32m')=============== SETUP COMPLETE ===============$(printf '\033[0m')
 Python      : $(python --version 2>&1)   (venv: $VENV_DIR)
 Playwright  : $PW_STATUS
 VS Code     : $(command -v code >/dev/null 2>&1 && code --version | head -n1 || echo "not installed")
 Tunnel      : $TUNNEL_STATUS

 NEXT STEPS
 1. source ~/.bashrc
 2. First time only - log in to the tunnel:
      tmux attach -t vscode      (or: screen -r vscode)
    Open the GitHub link, enter the code, then detach:
      tmux: Ctrl+B then D   |   screen: Ctrl+A then D
 3. Open:  https://vscode.dev/tunnel/$TUNNEL_NAME
 4. In VS Code: install the Python extension, then
    "Python: Select Interpreter" -> $VENV_DIR/bin/python
===============================================
EOF
