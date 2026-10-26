#!/usr/bin/env bash
set -euo pipefail
# Use the reviewed SDK even when the host has an unrelated global Flutter.
if [ ! -x .vercel-flutter/bin/flutter ]; then
  git clone --depth 1 --branch 3.41.9 https://github.com/flutter/flutter.git .vercel-flutter
fi
export PATH="$PWD/.vercel-flutter/bin:$PATH"
export FLUTTER_BIN="$PWD/.vercel-flutter/bin/flutter"
python3 deployment/build_web.py
