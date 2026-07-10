#!/usr/bin/env bash
# wideband driver — build, drive, and visually verify the package.
#
# Runs against the project sources at the repo root (wideband.sty,
# wideband.lua, tests/*.tex). It copies them into a scratch directory so the
# repo itself is never polluted with .aux/.log/.pdf/.png build junk, then:
#   1. compiles every test (twice, for \ref/\eqref) and checks exit codes
#   2. greps the log to confirm each band scenario path was exercised
#   3. runs the inertness regression: a twocolumn doc that loads the package
#      but uses no band must be PIXEL-IDENTICAL to the same doc without it
#   4. renders test-wideband.pdf to PNGs so you can LOOK at the bands
#
# Requires: lualatex (TeX Live), pdftoppm (poppler-utils), python3 + PIL.
# Usage:    bash .claude/skills/run-wideband/driver.sh
# Output:   PNGs + PDFs land in $OUT (printed at the end); open them.
set -u

# --- locate repo root (dir containing wideband.sty) -----------------------
here=$(cd "$(dirname "$0")" && pwd)
root=$here
while [ "$root" != / ] && [ ! -f "$root/wideband.sty" ]; do root=$(dirname "$root"); done
if [ ! -f "$root/wideband.sty" ]; then echo "FATAL: cannot find wideband.sty above $here"; exit 2; fi

OUT=${WB_OUT:-/tmp/wb-driver}
rm -rf "$OUT"; mkdir -p "$OUT"
cp "$root"/wideband.sty "$root"/wideband.lua "$root"/tests/*.tex "$OUT"/ 2>/dev/null
cd "$OUT" || exit 2
echo "scratch: $OUT   (sources copied from $root)"
echo

fail=0
compile () {
  lualatex -interaction=nonstopmode "$1" >/dev/null 2>&1
  lualatex -interaction=nonstopmode "$1" >/dev/null 2>&1
  if [ $? -ne 0 ]; then echo "FAIL compile: $1"; fail=1; else echo "ok  compile: $1"; fi
}

echo "== compile tests =="
for t in test-wideband.tex test-baseline.tex test-edgecases.tex; do
  [ -f "$t" ] && compile "$t" || echo "skip (missing): $t"
done

echo "== scenario diagnostics (test-wideband.log) =="
if [ -f test-wideband.log ]; then
  grep -i "anchored in column 1"        test-wideband.log >/dev/null && echo "ok  state-1 anchor path exercised" || { echo "FAIL: no anchored band"; fail=1; }
  grep -i "fell into the second column" test-wideband.log >/dev/null && echo "ok  deferral path exercised"       || { echo "FAIL: deferral scenario not triggered"; fail=1; }
  grep -E "Reference .* undefined" test-wideband.log >/dev/null && { echo "FAIL: undefined references (dropped band?)"; fail=1; } || echo "ok  all references resolved"
fi

echo "== inertness regression (must be pixel-identical) =="
cat > _ri.tex <<'EOF'
\documentclass[twocolumn]{article}
\usepackage{lipsum}
\usepackage{wideband}
\begin{document}
\lipsum[1-20]
\end{document}
EOF
sed '/usepackage{wideband}/d' _ri.tex > _rr.tex
lualatex -interaction=nonstopmode _ri.tex >/dev/null 2>&1
lualatex -interaction=nonstopmode _rr.tex >/dev/null 2>&1
pdftoppm -png -r 40 _ri.pdf _ri >/dev/null 2>&1
pdftoppm -png -r 40 _rr.pdf _rr >/dev/null 2>&1
python3 - <<'EOF'
import glob, sys
from PIL import Image, ImageChops
a = sorted(glob.glob('_ri-*.png')); b = sorted(glob.glob('_rr-*.png'))
if len(a) != len(b) or not a:
    print("FAIL inertness: page count differs or no pages"); sys.exit(1)
worst = max(ImageChops.difference(Image.open(x).convert('L'),
                                  Image.open(y).convert('L')).getextrema()[1]
            for x, y in zip(a, b))
print(("ok  inertness: pixel-identical (%d pages)" % len(a)) if worst == 0
      else ("FAIL inertness: max pixel diff %d" % worst))
sys.exit(0 if worst == 0 else 1)
EOF
[ $? -ne 0 ] && fail=1
rm -f _ri* _rr*

echo "== render pages (look at these) =="
if [ -f test-wideband.pdf ]; then
  pdftoppm -png -r 60 test-wideband.pdf page >/dev/null 2>&1
  echo "ok  rendered: $OUT/page-*.png"
  ls "$OUT"/page-*.png | sed 's/^/    /'
fi

echo
[ $fail -eq 0 ] && echo "ALL GREEN — bands render in $OUT" || echo "REGRESSIONS FAILED"
exit $fail
