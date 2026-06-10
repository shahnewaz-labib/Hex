#!/usr/bin/env bash
set -euo pipefail

# install.sh — Hex Linux setup
# Installs Hex, whisper-cpp, and configures autostart.
#
# Usage:
#   chmod +x install.sh
#   ./install.sh                # Full installation
#   ./install.sh --no-daemon    # Skip hotkey daemon setup

INSTALL_PREFIX="${HOME}/.local"
WITH_DAEMON=true

while [[ $# -gt 0 ]]; do
  case $1 in
    --no-daemon) WITH_DAEMON=false ;;
    --prefix) INSTALL_PREFIX="$2"; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

echo "=== Hex Linux Installer ==="
echo ""

# 1. Check system dependencies
echo ">>> Checking dependencies..."
MISSING=""
for cmd in curl arecord xdotool xclip paplay xdg-open; do
  if ! command -v $cmd &>/dev/null; then
    MISSING="$MISSING $cmd"
  fi
done

if [ -n "$MISSING" ]; then
  echo "Missing:$MISSING"
  echo "Install with:"
  echo "  sudo apt install curl alsa-utils xdotool xclip pulseaudio-utils xdg-utils"
  exit 1
fi
echo "  OK"

# 2. Build whisper-cpp if not present
if ! command -v whisper-cpp &>/dev/null; then
  echo ""
  echo ">>> Building whisper-cpp..."
  if [ -f "scripts/build-whisper-cpp.sh" ]; then
    bash scripts/build-whisper-cpp.sh --prefix "$INSTALL_PREFIX"
  else
    echo "  scripts/build-whisper-cpp.sh not found, skipping."
    echo "  Install whisper-cpp manually: https://github.com/ggerganov/whisper.cpp"
  fi
else
  echo "  whisper-cpp already installed: $(which whisper-cpp)"
fi

# 3. Build Hex
echo ""
echo ">>> Building Hex..."
swift build -c release

# 4. Install binaries
mkdir -p "${INSTALL_PREFIX}/bin"
cp .build/release/HexLinux "${INSTALL_PREFIX}/bin/hex"
chmod +x "${INSTALL_PREFIX}/bin/hex"

if $WITH_DAEMON && [ -f .build/release/HexHotkeyDaemon ]; then
  cp .build/release/HexHotkeyDaemon "${INSTALL_PREFIX}/bin/hex-hotkeyd"
  chmod +x "${INSTALL_PREFIX}/bin/hex-hotkeyd"
  echo "  Hotkey daemon installed: ${INSTALL_PREFIX}/bin/hex-hotkeyd"
fi

echo "  Hex installed: ${INSTALL_PREFIX}/bin/hex"

# 5. Create model directory
mkdir -p "${HOME}/.local/share/hex/models"

# 6. Install desktop entry for autostart
AUTOSTART_DIR="${HOME}/.config/autostart"
mkdir -p "$AUTOSTART_DIR"

cat > "${AUTOSTART_DIR}/hex.desktop" << 'EOF'
[Desktop Entry]
Name=Hex
Comment=On-device voice-to-text
Exec=hex
Type=Application
Categories=Utility;
Keywords=voice;transcription;dictation;
Terminal=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
EOF

echo "  Autostart installed: ${AUTOSTART_DIR}/hex.desktop"

# 7. Check PATH
if ! echo "$PATH" | grep -q "${INSTALL_PREFIX}/bin"; then
  echo ""
  echo ">>> PATH"
  echo "  Add to ~/.bashrc or ~/.zshrc:"
  echo "  export PATH=\"${INSTALL_PREFIX}/bin:\$PATH\""
fi

# 8. Input group for hotkey daemon
if $WITH_DAEMON; then
  echo ""
  echo ">>> Hotkey Daemon"
  echo "  The hotkey daemon (hex-hotkeyd) reads keyboard events from /dev/input."
  echo "  For it to work, your user must be in the 'input' group:"
  echo ""
  echo "      sudo usermod -a -G input \$USER"
  echo ""
  echo "  Then log out and back in, or run: newgrp input"
  echo ""
  echo "  To use a custom hotkey, run the daemon with:"
  echo "      hex-hotkeyd /tmp/hex-hotkey.sock <key> <modifiers>"
  echo "  Example (Option key only):"
  echo "      hex-hotkeyd /tmp/hex-hotkey.sock nil option"
  echo "  Example (Cmd+A):"
  echo "      hex-hotkeyd /tmp/hex-hotkey.sock a command"
fi

echo ""
echo "=== Done ==="
echo "Run 'hex' to start. The web UI opens at http://127.0.0.1:8765"
echo "First-time: download a model via the web UI or CLI 'download ggml-tiny.en.bin'"
