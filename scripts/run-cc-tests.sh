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
  # A fixture may declare the operator errors it must raise (`%% EXPECT-ERROR: text`,
  # one per line). It is then compiled without -halt-on-error, every declared text
  # must be in the log, and every `!' line must be one of them; anything else fails.
  expected_errors=$(sed -n 's/^%% EXPECT-ERROR: //p' "$source")
  if [ -n "$expected_errors" ]; then
    lualatex -interaction=nonstopmode "$source" >/dev/null || true
    lualatex -interaction=nonstopmode "$source" >/dev/null || true
    while IFS= read -r text; do
      grep -qF "$text" "$job.log" || {
        echo "ERROR: $source did not raise the expected error: $text" >&2
        exit 1
      }
    done <<< "$expected_errors"
    unexpected=$(grep '^! ' "$job.log" | grep -vF -f <(printf '%s\n' "$expected_errors") || true)
    if [ -n "$unexpected" ]; then
      echo "$unexpected"
      echo "ERROR: unexpected TeX error in $source" >&2
      exit 1
    fi
    if grep -E 'Overfull \\vbox|Undefined control sequence|Fatal error' "$job.log"; then
      echo "ERROR: vertical overflow or TeX failure in $source" >&2
      exit 1
    fi
  else
    lualatex -interaction=nonstopmode -halt-on-error "$source" >/dev/null
    lualatex -interaction=nonstopmode -halt-on-error "$source" >/dev/null
    if grep -E 'Overfull \\vbox|^! |Undefined control sequence|Fatal error' "$job.log"; then
      echo "ERROR: vertical overflow or TeX failure in $source" >&2
      exit 1
    fi
  fi
  "$root/scripts/check-cc-stress.py" "$source" "$job.pdf"
  case "$source" in
    stress-elsevier-adapter-safe-top.tex|\
    stress-elsevier-adapter-band-at-document-end.tex|\
    stress-elsevier-adapter-footnote-inside-band.tex)
      grep -q 'Elsevier NeoPage adapter selected' "$job.log" || {
        echo "ERROR: Elsevier adapter was not selected for $source" >&2
        exit 1
      }
      ;;
    stress-band-page-enlarged.tex)
      grep -q 'band #1 (page 1): placed' "$job.log" || {
        echo "ERROR: the band on an enlarged page was not placed on it in $source" >&2
        exit 1
      }
      ;;
    stress-band-protruding-row-is-shed.tex)
      # the shed band is overdue on page 2: at the top, above band B, not at the
      # automatic Y it was given on page 1
      grep -q 'band #1 (page 2): placed, Y=0.0pt' "$job.log" || {
        echo "ERROR: the shed band kept page 1's position on page 2 in $source" >&2
        exit 1
      }
      ;;
    stress-neopage-host-same-page.tex)
      grep -q 'band #1 (page 1): placed' "$job.log" || {
        echo "ERROR: the band was not placed on its own page on the NeoPage host in $source" >&2
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

# Expected failures: each tests/cc-errors document must stop the run AND log the
# message in its EXPECT-ERROR banner (and never a FORBID text).  The Lua-missing
# case is compiled with the .sty alone.
mkdir -p "$build/errors"
for source in "$root/tests/cc-errors"/*.tex; do
  job=$(basename "$source" .tex)
  dir="$build/errors/$job"
  mkdir -p "$dir"
  cp "$source" "$root/wideband-cc.sty" "$dir/"
  [ "$job" = error-lua-missing ] || cp "$root/wideband-cc.lua" "$dir/"
  echo "[CC expected error] $job"
  # No -halt-on-error: production compiles keep going after an error, so a
  # follow-on failure (FORBID) must be visible too.
  if (cd "$dir" && lualatex -interaction=nonstopmode "$job.tex" >/dev/null 2>&1); then
    echo "ERROR: $job unexpectedly succeeded" >&2
    exit 1
  fi
  expected=$(sed -n 's/^%% EXPECT-ERROR: //p' "$source")
  grep -qF "$expected" "$dir/$job.log" || {
    echo "ERROR: $job failed without the expected message: $expected" >&2
    exit 1
  }
  if grep -qE 'Illegal parameter number|Undefined control sequence' "$dir/$job.log"; then
    echo "ERROR: $job failed for the wrong reason (malformed message or macro)" >&2
    exit 1
  fi
  forbidden=$(sed -n 's/^%% FORBID: //p' "$source")
  if [ -n "$forbidden" ] && grep -qF "$forbidden" "$dir/$job.log"; then
    echo "ERROR: $job log contains forbidden text: $forbidden" >&2
    exit 1
  fi
done
cd "$build/stress"

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

# Path-loaded package: \usepackage{/abs/dir/wideband-cc} from a directory that holds
# neither file, with no TEXMFHOME or TEXINPUTS pointing at it (how NeoPage loads its
# templates through \Templatepath). kpathsea cannot see the .lua; the style must find
# it beside itself.
mkdir -p "$build/install-check-abspath"
sed "s|\\\\usepackage{wideband-cc}|\\\\usepackage{$build/texmf/tex/latex/wideband/wideband-cc}|" \
  "$root/tests/test-installed-path.tex" > "$build/install-check-abspath/test-installed-abspath.tex"
cd "$build/install-check-abspath"
lualatex -interaction=nonstopmode -halt-on-error test-installed-abspath.tex >/dev/null
"$root/scripts/verify-token-counts.py" test-installed-abspath.pdf \
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
