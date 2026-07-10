#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
build=${WB_BUILD_DIR:-"$root/build/tests"}
rm -rf "$build"
mkdir -p "$build"
cp "$root/wideband.sty" "$root/wideband.lua" "$root/tests"/*.tex "$build/"
cd "$build"

pass_tests=(
  test-wideband.tex
  test-edgecases.tex
  test-baseline.tex
  test-hyperref.tex
  test-floats.tex
  test-no-band.tex
  test-no-band-ref.tex
  test-right-column-deferral.tex
)
expected_fail_tests=(
  test-pending-error.tex
  test-oversized-error.tex
)

if grep -RniE '\\usepackage\{[^}]*lipsum|\\lipsum' -- test-*.tex test-content.tex; then
  echo "ERROR: filler text remains in the regression sources" >&2
  exit 1
fi

for f in "${pass_tests[@]}"; do
  echo "[PASS expected] $f"
  lualatex -interaction=nonstopmode -halt-on-error "$f" >/dev/null
  lualatex -interaction=nonstopmode -halt-on-error "$f" >/dev/null
done

for f in "${expected_fail_tests[@]}"; do
  echo "[FAIL expected] $f"
  if lualatex -interaction=nonstopmode -halt-on-error "$f" >/dev/null 2>&1; then
    echo "ERROR: $f unexpectedly succeeded" >&2
    exit 1
  fi
done


# Option A policy: a marker discovered in column 2 must defer intact.
if ! grep -q "Wideband request encountered in column 2" test-right-column-deferral.log; then
  echo "ERROR: right-column test did not exercise the deferral branch" >&2
  exit 1
fi
"$root/scripts/verify-token-counts.py" test-right-column-deferral.pdf \
  RIGHT-PRE-0001 RIGHT-PRE-0002 RIGHT-PRE-0003 RIGHT-PRE-0004 \
  BAND-UNIQUE-0001 \
  RIGHT-POST-0001 RIGHT-POST-0002 RIGHT-POST-0003 RIGHT-POST-0004 \
  RIGHT-REF-0001

# The package must remain visually inert when no environment is used.
rm -rf .test-renders
mkdir -p .test-renders/pkg .test-renders/ref
pdftoppm -png -r 72 test-no-band.pdf .test-renders/pkg/page >/dev/null 2>&1
pdftoppm -png -r 72 test-no-band-ref.pdf .test-renders/ref/page >/dev/null 2>&1
python3 - <<'PY'
from pathlib import Path
from PIL import Image, ImageChops
pkg=sorted(Path('.test-renders/pkg').glob('*.png'))
ref=sorted(Path('.test-renders/ref').glob('*.png'))
assert len(pkg)==len(ref), (len(pkg),len(ref))
for a,b in zip(pkg,ref):
    diff=ImageChops.difference(Image.open(a).convert('L'),Image.open(b).convert('L'))
    assert diff.getbbox() is None, f'no-band visual mismatch: {a.name}'
print(f'No-band pixel comparison passed for {len(pkg)} page(s).')
PY

"$root/scripts/check-pdf-bounds.py" \
  test-wideband.pdf test-edgecases.pdf test-hyperref.pdf test-floats.pdf

if grep -E 'Overfull \\vbox' test-wideband.log test-edgecases.log test-hyperref.log; then
  echo "ERROR: overfull vertical box found in core regression logs" >&2
  exit 1
fi

rm -rf .test-renders
echo "All regression expectations satisfied. Build artifacts: $build"
