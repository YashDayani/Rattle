#!/usr/bin/env bash
# Builds self-contained (static, Metal-embedded) whisper-cli and whisper-server so Rattle ships its own engine.
# Output: build/whisper-bin/{whisper-cli,whisper-server}. Cached; delete build/whisper-bin to rebuild.
#   RATTLE_UNIVERSAL=1   build arm64 + x86_64
set -euo pipefail
cd "$(dirname "$0")/.."
TAG="v1.9.5"
OUT=build/whisper-bin
[ -x "$OUT/whisper-cli" ] && [ -x "$OUT/whisper-server" ] && exit 0
SRC=build/whisper.cpp-src
[ -d "$SRC" ] || git clone --depth 1 --branch "$TAG" https://github.com/ggml-org/whisper.cpp.git "$SRC"
ARCHS="arm64"; [ "${RATTLE_UNIVERSAL:-0}" = "1" ] && ARCHS="arm64;x86_64"
cmake -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_OSX_ARCHITECTURES="$ARCHS" -DCMAKE_OSX_DEPLOYMENT_TARGET=14.4 \
  -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_NATIVE=OFF -DGGML_BLAS=OFF \
  -DWHISPER_BUILD_EXAMPLES=ON -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=ON
cmake --build "$SRC/build" --config Release -j "$(sysctl -n hw.ncpu)" --target whisper-cli whisper-server
mkdir -p "$OUT"
cp "$SRC/build/bin/whisper-cli" "$SRC/build/bin/whisper-server" "$OUT/"
