#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
build=${WB_CC_BUILD_DIR:-"$root/build/cc-tests"}

case "$build/" in
  "$root/build/"*|/tmp/*) ;;
  *)
    echo "ERROR: WB_CC_BUILD_DIR must be below $root/build or /tmp" >&2
    exit 2
    ;;
esac

rm -rf "$build"
mkdir -p "$build/stress" "$build/renders" "$build/texmf/tex/latex/wideband" "$build/install-check"
cp "$root/wideband-cc.sty" "$root/wideband-cc.lua" "$build/stress/"
cp "$root/tests/stress"/stress-*.tex "$build/stress/"

export max_print_line=2000

cd "$build/stress"
for source in stress-*.tex; do
  job=${source%.tex}
  echo "[CC] $source"
  lualatex -interaction=nonstopmode -halt-on-error "$source" >/dev/null
  lualatex -interaction=nonstopmode -halt-on-error "$source" >/dev/null
  if grep -E 'Overfull \\vbox|^! |Undefined control sequence|Fatal error' "$job.log"; then
    echo "ERROR: vertical overflow or TeX failure in $source" >&2
    exit 1
  fi
  "$root/scripts/check-cc-stress.py" "$source" "$job.pdf"
  case "$source" in
    stress-elsevier-adapter-safe-top.tex|\
    stress-elsevier-adapter-band-at-document-end.tex)
      grep -q 'Elsevier NeoPage adapter selected' "$job.log" || {
        echo "ERROR: Elsevier adapter was not selected for $source" >&2
        exit 1
      }
      ;;
    stress-elsevier-adapter-fullpage-safe-top.tex)
      grep -q 'fullpage band.*reduced to a' "$job.log" || {
        echo "ERROR: Elsevier fullpage safety degradation was not logged for $source" >&2
        exit 1
      }
      ;;
  esac
done


# A package-loaded document with no band must be pixel-identical to the same
# source without the package. This is the strongest guard against accidental
# output-routine changes on ordinary pages.
sed '/\\usepackage{wideband-cc}/d' \
  stress-no-bands-baseline-unchanged.tex > inertness-reference.tex
lualatex -interaction=nonstopmode -halt-on-error inertness-reference.tex >/dev/null
lualatex -interaction=nonstopmode -halt-on-error inertness-reference.tex >/dev/null
mkdir -p .inertness/package .inertness/reference
pdftoppm -png -r 72 stress-no-bands-baseline-unchanged.pdf \
  .inertness/package/page >/dev/null 2>&1
pdftoppm -png -r 72 inertness-reference.pdf \
  .inertness/reference/page >/dev/null 2>&1
python3 - <<'PY'
from pathlib import Path
from PIL import Image, ImageChops

package = sorted(Path('.inertness/package').glob('*.png'))
reference = sorted(Path('.inertness/reference').glob('*.png'))
assert package and len(package) == len(reference), (len(package), len(reference))
for actual, expected in zip(package, reference):
    diff = ImageChops.difference(
        Image.open(actual).convert('L'), Image.open(expected).convert('L')
    )
    assert diff.getbbox() is None, f'wideband-cc inertness mismatch: {actual.name}'
print(f'Continuous-Column no-band inertness passed for {len(package)} page(s).')
PY

# Installation-path regression: the document is deliberately compiled outside
# the package directory.  This fails if the style uses cwd-relative dofile().
cp "$root/wideband-cc.sty" "$root/wideband-cc.lua" "$build/texmf/tex/latex/wideband/"
cp "$root/tests/test-installed-path.tex" "$build/install-check/"
cd "$build/install-check"
TEXMFHOME="$build/texmf" \
  lualatex -interaction=nonstopmode -halt-on-error test-installed-path.tex >/dev/null
TEXMFHOME="$build/texmf" \
  lualatex -interaction=nonstopmode -halt-on-error test-installed-path.tex >/dev/null
"$root/scripts/verify-token-counts.py" test-installed-path.pdf \
  '[INSTALL-01]' '[INSTALL-02]' '[INSTALL-03]' INSTALL-PATH-BAND \
  '[INSTALL-04]' '[INSTALL-05]' '[INSTALL-06]' '[INSTALL-07]'

# Render representative pages for the mandatory human/agent visual gate.
pdftoppm -png -r 90 \
  "$build/stress/stress-band-follows-paragraph-end.pdf" \
  "$build/renders/follows" >/dev/null 2>&1
pdftoppm -png -r 90 \
  "$build/stress/stress-fullpage-band-own-page.pdf" \
  "$build/renders/fullpage" >/dev/null 2>&1
pdftoppm -png -r 90 \
  "$build/stress/stress-elsevier-adapter-safe-top.pdf" \
  "$build/renders/elsevier" >/dev/null 2>&1

echo "All Continuous-Column stress tests passed."
echo "Visual-review PNGs: $build/renders"
