#!/bin/bash
# Idempotently add an SPDX licence header to every Swift file. Run it when no one else is editing
# (it touches every source file, so it conflicts with in-flight work).
set -euo pipefail
cd "$(dirname "$0")/.."
HEADER='// SPDX-License-Identifier: Apache-2.0'
git ls-files '*.swift' | while read -r f; do
  if ! head -1 "$f" | grep -q 'SPDX-License-Identifier'; then
    { echo "$HEADER"; cat "$f"; } > "$f.tmp" && mv "$f.tmp" "$f"
    echo "added: $f"
  fi
done
