#!/usr/bin/env bash
set -euo pipefail
VERSION="${1:?version e.g. v2026.9.18}"
OUT="LocusUpdate-${VERSION}-source.zip"
rm -f "$OUT"
zip -r "$OUT" . \
  -x './.git/*' \
  -x './.github/*' \
  -x './LocusUpdate.xcodeproj/*' \
  -x './.build/*' \
  -x './DerivedData/*' \
  -x './build/*' \
  -x '*.xcuserstate' \
  -x './.DS_Store'
echo "Wrote $OUT"
