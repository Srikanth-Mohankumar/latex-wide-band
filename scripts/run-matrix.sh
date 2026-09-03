#!/usr/bin/env bash
# Compile and check a directory of wideband scenario documents.
#
#   scripts/run-matrix.sh [options] [BUILD_DIR]
#
# Options
#   --only GLOB        only documents whose basename matches GLOB
#   --keep-going       do not stop at the first failing document
#   --strict           ignore %% WB-BASELINE-DIFFERS and decision-format leniency
#   --source-dir DIR   where the .tex documents live (default: tests/matrix)
#   --package-mode M   force baseline|stratum instead of detecting it
#   -h | --help
#
# The build directory defaults to $WB_BUILD_DIR or build/matrix.  Every
# document is compiled twice with lualatex (once when it declares
# %% WB-EXPECT-COMPILE: fail) and then checked with check-decisions.py,
# check-audit.py, verify-token-counts.py and check-pdf-bounds.py, plus a grep
# for "Overfull \vbox" unless the document carries %% WB-ALLOW-OVERFULL.
set -uo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_dir="$root/tests/matrix"
build=""
only='*'
keep_going=0
strict=0
forced_mode=""

die() { echo "run-matrix: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --only) only=${2:?--only needs a glob}; shift 2 ;;
    --only=*) only=${1#*=}; shift ;;
    --keep-going) keep_going=1; shift ;;
    --strict) strict=1; shift ;;
    --source-dir) source_dir=${2:?--source-dir needs a path}; shift 2 ;;
    --source-dir=*) source_dir=${1#*=}; shift ;;
    --package-mode) forced_mode=${2:?--package-mode needs baseline|stratum}; shift 2 ;;
    --package-mode=*) forced_mode=${1#*=}; shift ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown option $1" ;;
    *) [ -n "$build" ] && die "unexpected argument $1"; build=$1; shift ;;
  esac
done

[ -n "$build" ] || build=${WB_BUILD_DIR:-"$root/build/matrix"}
source_dir=$(cd "$source_dir" 2>/dev/null && pwd) || die "no such source directory: $source_dir"
mkdir -p "$build" || die "cannot create $build"
build=$(cd "$build" && pwd)

# The repository root must never be used as a build directory (contract 3.6).
[ "$build" = "$root" ] && die "refusing to build in the repository root"

in_place=0
[ "$source_dir" = "$build" ] && in_place=1

# ------------------------------------------------------------------ collection
shopt -s nullglob
all_docs=()
for f in "$source_dir"/*.tex; do
  base=$(basename "$f")
  case "$base" in
    *-content.tex|*-preamble.tex) continue ;;   # shared prose, not a scenario
  esac
  all_docs+=("$base")
done
shopt -u nullglob
[ ${#all_docs[@]} -gt 0 ] || die "no scenario documents in $source_dir"

docs=()
for base in "${all_docs[@]}"; do
  # shellcheck disable=SC2053
  if [[ ${base%.tex} == $only || $base == $only ]]; then docs+=("$base"); fi
done
[ ${#docs[@]} -gt 0 ] || die "--only $only matched none of ${#all_docs[@]} documents"

# ---------------------------------------------------------------- build set-up
if [ "$in_place" -eq 0 ]; then
  rm -rf "$build"
  mkdir -p "$build"
  for base in "${docs[@]}"; do cp "$source_dir/$base" "$build/"; done
  for extra in "$source_dir"/*-content.tex "$source_dir"/*-preamble.tex; do
    [ -e "$extra" ] && cp "$extra" "$build/"
  done
  [ -e "$root/tests/test-content.tex" ] && cp "$root/tests/test-content.tex" "$build/"
fi
for pkg in wideband.sty wideband.lua wideband-audit.sty wideband-audit.lua; do
  [ -e "$root/$pkg" ] && cp "$root/$pkg" "$build/"
done
[ -e "$build/wideband.sty" ] || die "wideband.sty not found in $root"

# No filler prose anywhere in the checked-in corpus (contract 3.7).
if grep -RniE '\\usepackage\{[^}]*lipsum|\\lipsum|blindtext' -- "$source_dir"/*.tex >/dev/null 2>&1; then
  grep -RniE '\\usepackage\{[^}]*lipsum|\\lipsum|blindtext' -- "$source_dir"/*.tex >&2
  die "filler text found in the scenario sources"
fi

# ------------------------------------------------------------- package probing
mode="$forced_mode"
if [ -z "$mode" ]; then
  if grep -q 'WIDEBAND DECISION' "$build/wideband.sty" "$build/wideband.lua" 2>/dev/null; then
    mode=stratum
  else
    mode=baseline
  fi
fi
[ "$mode" = baseline ] || [ "$mode" = stratum ] || die "--package-mode must be baseline or stratum"
[ "$strict" -eq 1 ] && mode_effective=stratum || mode_effective=$mode

audit_available=0
if [ -e "$build/wideband-audit.sty" ] && [ -x "$root/scripts/check-audit.py" ]; then
  audit_available=1
fi

pkg_version=$(sed -n 's/.*\\ProvidesPackage{wideband}\[\([^]]*\)\].*/\1/p' "$build/wideband.sty" | head -1)

echo "run-matrix: $source_dir -> $build"
echo "run-matrix: wideband.sty  = ${pkg_version:-unknown}"
echo "run-matrix: package mode  = $mode (decision log $([ "$mode" = stratum ] && echo present || echo absent))"
if [ "$audit_available" -eq 1 ]; then
  echo "run-matrix: audit         = wideband-audit.sty + scripts/check-audit.py"
else
  reason="wideband-audit.sty absent"
  [ -e "$build/wideband-audit.sty" ] && reason="scripts/check-audit.py absent"
  echo "run-matrix: audit         = SKIPPED ($reason; AUDIT workstream not merged)"
fi
echo "run-matrix: documents     = ${#docs[@]}"
if ! selftest=$("$root/scripts/check-decisions.py" --selftest 2>&1); then
  echo "$selftest" >&2
  die "check-decisions.py --selftest failed; fix the checker before trusting a run"
fi
echo "run-matrix: $selftest"
if [ -x "$source_dir/stratum-dryrun.py" ]; then
  if dry=$("$source_dir/stratum-dryrun.py" 2>&1); then
    echo "run-matrix: $(tail -1 <<<"$dry")"
  else
    echo "$dry" >&2
    die "the scenario headers are not satisfiable by a spec-conforming decision log"
  fi
fi
echo

export max_print_line=1000 error_line=254 half_error_line=238

# ----------------------------------------------------------------- the checker
summary=()
n_pass=0; n_fail=0; n_xfail=0; n_xpass=0; n_underfull=0
underfull_docs=()
failed_docs=()
xfail_docs=()
xpass_docs=()
soft_notes=()

check_doc() {
  local base=$1 stem=${base%.tex}
  local meta compile_expect allow_overfull differs tokens has_dec
  meta=$("$root/scripts/check-decisions.py" --print-meta "$build/$base") || {
    echo "  $stem: expectation header is malformed" >&2; return 1; }
  compile_expect=$(sed -n 's/^compile=//p' <<<"$meta")
  allow_overfull=$(sed -n 's/^allow_overfull=//p' <<<"$meta")
  differs=$(sed -n 's/^baseline_differs=//p' <<<"$meta")
  tokens=$(sed -n 's/^tokens=//p' <<<"$meta")
  has_dec=$(sed -n 's/^has_decision_expectations=//p' <<<"$meta")

  local r_compile=- r_dec=- r_audit=- r_tok=- r_bnd=- r_ovf=-
  local bad=0 detail=()

  # ---- compile -------------------------------------------------------------
  local runs=2 rc=0 i
  [ "$compile_expect" = fail ] && runs=1
  for ((i = 1; i <= runs; i++)); do
    ( cd "$build" && lualatex -interaction=nonstopmode -halt-on-error "$base" ) \
      >"$build/$stem.run$i.out" 2>&1
    rc=$?
    [ $rc -ne 0 ] && break
  done
  if [ "$compile_expect" = fail ]; then
    if [ $rc -eq 0 ]; then
      r_compile=FAIL; bad=1
      detail+=("compile: expected WB-EXPECT-COMPILE: fail but lualatex succeeded")
    else
      r_compile=ok-fail
    fi
  else
    if [ $rc -ne 0 ]; then
      r_compile=FAIL; bad=1
      detail+=("compile: lualatex exited $rc on run $i; $(grep -m2 -n '^!' "$build/$stem.run$i.out" | tr '\n' ' ')")
    else
      r_compile=ok
    fi
  fi

  # ---- decision log --------------------------------------------------------
  if [ -f "$build/$stem.log" ]; then
    local dec_out dec_rc
    dec_out=$("$root/scripts/check-decisions.py" \
      --package-mode "$mode_effective" --wrap-width 1000 \
      $([ "$strict" -eq 1 ] && echo --strict-format) \
      --compile-status "$([ "$r_compile" = ok ] && echo pass || echo fail)" \
      "$build/$base" "$build/$stem.log" 2>&1)
    dec_rc=$?
    case $dec_rc in
      0) if [ "$mode_effective" = baseline ] && [ "$has_dec" = 1 ]; then
           r_dec=skip-base
         elif [ "$compile_expect" = fail ] && [ "$has_dec" = 1 ]; then
           r_dec=skip-xfail
         else
           r_dec=ok
         fi ;;
      3) r_dec=skip-nodec; soft_notes+=("$stem: $(tail -1 <<<"$dec_out")") ;;
      *) r_dec=FAIL; bad=1; detail+=("decisions: $dec_out") ;;
    esac
  else
    r_dec=nolog
    [ "$compile_expect" = pass ] && { bad=1; detail+=("decisions: no $stem.log produced"); r_dec=FAIL; }
  fi

  # ---- audit ---------------------------------------------------------------
  if [ "$audit_available" -eq 1 ] && [ -f "$build/$stem.log" ]; then
    local aud_out
    if aud_out=$("$root/scripts/check-audit.py" "$build/$stem.log" 2>&1); then
      r_audit=ok
    else
      r_audit=FAIL; bad=1; detail+=("audit: $aud_out")
    fi
  else
    r_audit=skip
  fi

  # ---- tokens and PDF geometry --------------------------------------------
  if [ "$compile_expect" = fail ]; then
    r_tok=skip; r_bnd=skip
  elif [ ! -f "$build/$stem.pdf" ]; then
    r_tok=FAIL; r_bnd=FAIL; bad=1; detail+=("tokens/bounds: no $stem.pdf produced")
  else
    if [ -n "$tokens" ]; then
      local tok_out
      if tok_out=$("$root/scripts/verify-token-counts.py" "$build/$stem.pdf" $tokens 2>&1); then
        r_tok=ok
      else
        r_tok=FAIL; bad=1
        detail+=("tokens: $(grep -vE ': 1$' <<<"$tok_out" | tr '\n' ' ')")
      fi
    else
      r_tok=none
    fi
    local bnd_out
    if bnd_out=$("$root/scripts/check-pdf-bounds.py" "$build/$stem.pdf" 2>&1); then
      r_bnd=ok
    else
      r_bnd=FAIL; bad=1; detail+=("bounds: $(head -3 <<<"$bnd_out" | tr '\n' ' ')")
    fi
  fi

  # ---- overfull vertical boxes --------------------------------------------
  if [ -f "$build/$stem.log" ]; then
    local ovf
    ovf=$(grep -c 'Overfull \\vbox' "$build/$stem.log")
    if [ "$ovf" -eq 0 ]; then
      r_ovf=ok
    elif [ "$allow_overfull" = 1 ]; then
      r_ovf="allow($ovf)"
    else
      r_ovf="FAIL($ovf)"; bad=1
      detail+=("overfull: $(grep -m2 'Overfull \\vbox' "$build/$stem.log" | tr '\n' ' ')")
    fi
    if grep -q 'Label(s) may have changed' "$build/$stem.log"; then
      soft_notes+=("$stem: labels still moving after the second run (aux not converged)")
    fi
    local unf
    unf=$(grep -c 'Underfull \\vbox' "$build/$stem.log")
    if [ "$unf" -gt 0 ]; then
      n_underfull=$((n_underfull + unf))
      underfull_docs+=("$stem($unf)")
    fi
  fi

  # ---- verdict -------------------------------------------------------------
  local status
  if [ "$bad" -eq 0 ]; then
    if [ "$differs" = 1 ] && [ "$mode" = baseline ] && [ "$strict" -eq 0 ]; then
      status=XPASS; n_xpass=$((n_xpass + 1)); xpass_docs+=("$stem")
    else
      status=PASS; n_pass=$((n_pass + 1))
    fi
  elif [ "$differs" = 1 ] && [ "$mode" = baseline ] && [ "$strict" -eq 0 ]; then
    status=XFAIL; n_xfail=$((n_xfail + 1)); xfail_docs+=("$stem")
  else
    status=FAIL; n_fail=$((n_fail + 1)); failed_docs+=("$stem")
  fi

  summary+=("$(printf '%-34s %-8s %-11s %-5s %-5s %-5s %-9s %s' \
    "$stem" "$r_compile" "$r_dec" "$r_audit" "$r_tok" "$r_bnd" "$r_ovf" "$status")")

  if [ ${#detail[@]} -gt 0 ]; then
    local label="FAIL"
    [ "$status" = XFAIL ] && label="XFAIL (WB-BASELINE-DIFFERS, baseline package)"
    echo "  $stem: $label"
    local d
    for d in "${detail[@]}"; do echo "      $d" | head -6; done
  else
    echo "  $stem: $status"
  fi
  [ "$status" = FAIL ] && return 1
  return 0
}

for base in "${docs[@]}"; do
  check_doc "$base"
  rc=$?
  if [ $rc -ne 0 ] && [ "$keep_going" -eq 0 ]; then
    echo
    echo "run-matrix: stopping after the first failing document (use --keep-going)" >&2
    break
  fi
done

# --------------------------------------------------------------------- summary
echo
printf '%-34s %-8s %-11s %-5s %-5s %-5s %-9s %s\n' \
  DOCUMENT COMPILE DECISIONS AUDIT TOKEN BOUND OVERFULL STATUS
printf '%.0s-' {1..106}; echo
for line in "${summary[@]}"; do echo "$line"; done
printf '%.0s-' {1..106}; echo
echo "pass=$n_pass fail=$n_fail xfail=$n_xfail xpass=$n_xpass  (mode=$mode)"

if [ ${#soft_notes[@]} -gt 0 ]; then
  echo
  echo "Notes:"
  printf '  %s\n' "${soft_notes[@]}" | sort -u
fi
if [ ${#xfail_docs[@]} -gt 0 ]; then
  echo
  echo "Expected baseline divergences (%% WB-BASELINE-DIFFERS, spec expectation kept):"
  printf '  %s\n' "${xfail_docs[@]}"
fi
if [ ${#xpass_docs[@]} -gt 0 ]; then
  echo
  echo "Marked WB-BASELINE-DIFFERS, but the checks that still run in baseline mode saw"
  echo "no difference (the divergence is in the decision log, which the baseline package"
  echo "does not write, or in the page the band landed on):"
  printf '  %s\n' "${xpass_docs[@]}"
fi
if [ "$n_underfull" -gt 0 ]; then
  echo
  echo "Underfull \\vbox warnings (not gated; report section 7 treats a high count as a"
  echo "sign of a wrong reservation): $n_underfull in ${#underfull_docs[@]} document(s)"
  printf '  %s\n' "${underfull_docs[@]}" | head -12
fi
if [ ${#failed_docs[@]} -gt 0 ]; then
  echo
  echo "Failures:"
  printf '  %s\n' "${failed_docs[@]}"
  echo
  echo "Build artifacts: $build"
  exit 1
fi
echo
echo "Build artifacts: $build"
exit 0
