#!/usr/bin/env python3
"""Cross-check each matrix document's predicted h against the position the
package actually measured for the marker (its own log line).

    ./tests/matrix/probes/verify-h.py [BUILD_DIR]     # default build/matrix

This validates the *document construction* (how much material precedes the
request), not the expectation: the baseline computes the marker position with
its own Lua code, independently of anything CORPUS asserts.
"""
import glob
import os
import sys
from pathlib import Path
import re

# The build directory a previous run-matrix.sh run left behind.
HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent
build = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build/matrix"
if not build.is_dir():
    raise SystemExit("verify-h: %s does not exist; run scripts/run-matrix.sh first"
                     % build)
os.chdir(build)

PREDICTED = {
    "m01": 202, "m04": 202, "m05": 202, "m06": 442, "m07": 442, "m08": 0,
    "m09": 82, "m12": 0, "m13": 142, "m14": 550, "m17": 214, "m21": 202,
    "m22": 202, "m23": 202, "m24": 296, "m25": 202, "m26": 202, "m30": 142,
    "m33": 478, "m34": 202,
}

print("%-36s %11s %9s %8s" % ("document", "predicted h", "measured", "delta"))
worst = 0.0
for f in sorted(glob.glob("m*.log")):
    key = f[:3]
    if key not in PREDICTED:
        continue
    text = open(f, errors="replace").read()
    hits = re.findall(r"marker found at ([\d.]+)pt from column top", text)
    if not hits:
        print("%-36s %11d %9s" % (f[:-4], PREDICTED[key], "no marker"))
        continue
    got = float(hits[0])
    delta = got - PREDICTED[key]
    flag = "" if abs(delta) <= 14 else "   <-- more than one line off"
    worst = max(worst, abs(delta))
    print("%-36s %11d %9.2f %+8.2f%s" % (f[:-4], PREDICTED[key], got, delta, flag))
print("worst absolute deviation: %.2fpt (one line is 12pt)" % worst)
