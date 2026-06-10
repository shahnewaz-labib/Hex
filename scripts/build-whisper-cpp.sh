#!/usr/bin/env bash
set -euo pipefail

# build-whisper-cpp.sh
# Builds whisper.cpp with optional acceleration and installs to ~/.local
#
# Usage:
#   chmod +x build-whisper-cpp.sh
#   ./build-whisper-cpp.sh              # CPU-only build
#   ./build-whisper-cpp.sh --cuda       # With CUDA support
#   ./build-whisper-cpp.sh --openblas   # With OpenBLAS
#   ./build-whisper-cpp.sh --vulkan     # With Vulkan

ACCELERATION=""
BUILD_DIR="/tmp/whisper-cpp-build"
INSTALL_PREFIX="${HOME}/.local"
WHISPER_REPO="https://github.com/ggerganov/whisper.cpp.git"

while [[ $# -gt 0 ]]; do
  case $1 in
    --cuda)    ACCELERATION="GGML_CUDA=1" ;;
    --openblas) ACCELERATION="GGML_OPENBLAS=1" ;;
    --vulkan)  ACCELERATION="GGML_VULKAN=1" ;;
    --prefix)  INSTALL_PREFIX="$2"; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

echo "=== Building whisper.cpp ==="
echo "Acceleration: ${ACCELERATION:-CPU only}"
echo "Install prefix: ${INSTALL_PREFIX}"

# Check dependencies
for cmd in git cmake make g++; do
  if ! command -v $cmd &>/dev/null; then
    echo "Missing dependency: $cmd"
    echo "Install with: sudo apt install build-essential cmake git"
    exit 1
  fi
done

# Clone or update
if [ -d "$BUILD_DIR" ]; then
  echo "Updating existing build at ${BUILD_DIR}..."
  cd "$BUILD_DIR"
  git pull --ff-only origin master || true
else
  echo "Cloning whisper.cpp..."
  git clone --depth 1 "$WHISPER_REPO" "$BUILD_DIR"
  cd "$BUILD_DIR"
fi

# Download a small model for testing
if [ ! -f "models/ggml-tiny.en.bin" ]; then
  echo "Downloading tiny model for testing..."
  bash models/download-ggml-model.sh tiny.en
fi

# Build
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF
make -j$(nproc) whisper-cli

# Install binaries
mkdir -p "${INSTALL_PREFIX}/bin"
cp bin/whisper-cli "${INSTALL_PREFIX}/bin/whisper-cpp"
chmod +x "${INSTALL_PREFIX}/bin/whisper-cpp"

# Install shared library and headers (for C interop)
mkdir -p "${INSTALL_PREFIX}/lib" "${INSTALL_PREFIX}/include"
cp libwhisper.a "${INSTALL_PREFIX}/lib/" 2>/dev/null || true
cp ../include/whisper.h "${INSTALL_PREFIX}/include/" 2>/dev/null || true

echo ""
echo "=== Done ==="
echo "whisper-cpp installed to: ${INSTALL_PREFIX}/bin/whisper-cpp"

# Check PATH
if ! echo "$PATH" | grep -q "${INSTALL_PREFIX}/bin"; then
  echo ""
  echo "WARNING: ${INSTALL_PREFIX}/bin is not in your PATH."
  echo "Add this to your ~/.bashrc or ~/.zshrc:"
  echo "  export PATH=\"${INSTALL_PREFIX}/bin:\$PATH\""
fi

# Verify
if "${INSTALL_PREFIX}/bin/whisper-cpp" --help &>/dev/null; then
  echo ""
  echo "Quick test: record 5s of audio and transcribe:"
  echo "  arecord -f S16_LE -r 16000 -c 1 -d 5 test.raw"
  echo "  whisper-cpp -m ~/.local/share/hex/models/ggml-tiny.en.bin -f test.raw"
fi
