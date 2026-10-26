#!/usr/bin/env bash
set -euo pipefail
# Repository-root Vercel project. Pin the SDK used by the reviewed app.
if ! command -v flutter >/dev/null 2>&1; then
  if [ ! -x .vercel-flutter/bin/flutter ]; then
    git clone --depth 1 --branch 3.41.9 https://github.com/flutter/flutter.git .vercel-flutter
  fi
  export PATH="$PWD/.vercel-flutter/bin:$PATH"
fi
python3 deployment/build_web.py
