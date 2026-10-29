#!/usr/bin/env bash
# Production verification driver for both maintained wideband implementations.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$here
while [ "$root" != / ] && [ ! -f "$root/Makefile" ]; do root=$(dirname "$root"); done
if [ ! -f "$root/wideband.sty" ] || [ ! -f "$root/wideband-cc.sty" ]; then
  echo "FATAL: cannot find the wideband repository above $here" >&2
  exit 2
fi

out=${WB_OUT:-/tmp/wb-driver}
export WB_BUILD_DIR="$out/stratum"
export WB_CC_BUILD_DIR="$out/continuous-column"

mkdir -p "$out"
cd "$root"

echo "== legacy stratum regression =="
./scripts/run-tests.sh

echo "== Continuous-Column production gate =="
./scripts/run-cc-tests.sh

echo
echo "ALL GREEN — both implementations passed"
echo "Visual-review PNGs: $WB_CC_BUILD_DIR/renders"
