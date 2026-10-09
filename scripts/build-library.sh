#!/bin/bash
# Zip every pack in packs/examples (or the folder given) into dist/packs/*.twangpack and write dist/packs/library.json
# with sha256 hashes. Upload the folder anywhere that serves static files over https, then point Twang at library.json.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/packs/examples}"
BASE_URL="${PACK_BASE_URL:-https://example.com/twang/packs}"
OUT="$ROOT/dist/packs"
rm -rf "$OUT"; mkdir -p "$OUT"
entries=()
for dir in "$SRC"/*/; do
  [[ -f "$dir/pack.json" ]] || continue
  id=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["id"])' "$dir/pack.json")
  ver=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("version","1.0.0"))' "$dir/pack.json")
  "$ROOT/.build/release/Twang" --validate-pack "$dir" >/dev/null
  file="$id-$ver.twangpack"
  (cd "$dir" && zip -qr -X "$OUT/$file" . -x '.*')
  entries+=("$(python3 - "$dir/pack.json" "$OUT/$file" "$BASE_URL/$file" <<'PY'
import hashlib, json, os, sys
m = json.load(open(sys.argv[1])); data = open(sys.argv[2], "rb").read()
print(json.dumps({"id": m["id"], "name": m.get("name", m["id"]), "author": m.get("author", ""), "version": m.get("version", "1.0.0"),
  "tagline": m.get("tagline", ""), "download": sys.argv[3], "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}))
PY
)")
done
printf '%s\n' "${entries[@]}" | python3 -c 'import json,sys;print(json.dumps({"format":1,"packs":[json.loads(l) for l in sys.stdin if l.strip()]},indent=2))' > "$OUT/library.json"
echo "Wrote $OUT ($(ls "$OUT" | wc -l | tr -d ' ') files)"
