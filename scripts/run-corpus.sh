#!/usr/bin/env bash
# Generate a synthetic wideband corpus and run the matrix checks over it.
#
#   scripts/run-corpus.sh --seed N --count M [options] [BUILD_DIR]
#
# Options
#   --seed N           generator seed (required)
#   --count M          number of documents (required)
#   --only GLOB        only documents whose basename matches GLOB
#   --keep-going       do not stop at the first failing document
#   --strict           ignore %% WB-BASELINE-DIFFERS
#   --load-style S     explicit (default) or option; see gen-corpus.py --help
#   --package-mode M   force baseline|stratum instead of detecting it
#   -h | --help
#
# The build directory defaults to $WB_BUILD_DIR or build/corpus.  Documents are
# generated into it and then compiled and checked in place by run-matrix.sh, so
# generated sources never land in tests/ (contract 3.7).
set -uo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
seed=""
count=""
build=""
load_style=explicit
pass_through=()

die() { echo "run-corpus: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --seed) seed=${2:?--seed needs a number}; shift 2 ;;
    --seed=*) seed=${1#*=}; shift ;;
    --count) count=${2:?--count needs a number}; shift 2 ;;
    --count=*) count=${1#*=}; shift ;;
    --load-style) load_style=${2:?--load-style needs explicit|option}; shift 2 ;;
    --load-style=*) load_style=${1#*=}; shift ;;
    --only|--package-mode) pass_through+=("$1" "${2:?$1 needs a value}"); shift 2 ;;
    --only=*|--package-mode=*) pass_through+=("$1"); shift ;;
    --keep-going|--strict) pass_through+=("$1"); shift ;;
    -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown option $1" ;;
    *) [ -n "$build" ] && die "unexpected argument $1"; build=$1; shift ;;
  esac
done

[ -n "$seed" ] || die "--seed is required"
[ -n "$count" ] || die "--count is required"
[ -n "$build" ] || build=${WB_BUILD_DIR:-"$root/build/corpus"}

rm -rf "$build"
mkdir -p "$build" || die "cannot create $build"
build=$(cd "$build" && pwd)
[ "$build" = "$root" ] && die "refusing to build in the repository root"

"$root/scripts/gen-corpus.py" --seed "$seed" --count "$count" \
  --load-style "$load_style" --out "$build" || die "generator failed"

exec "$root/scripts/run-matrix.sh" --source-dir "$build" \
  ${pass_through+"${pass_through[@]}"} "$build"
