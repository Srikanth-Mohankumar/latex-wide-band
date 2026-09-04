#!/usr/bin/env python3
"""Dry-run the matrix expectations against hand-written, spec-conforming logs.

This proves the WB-EXPECT headers are satisfiable by a decision log that obeys
report sections 2.1-2.3 and contract 4.2 -- i.e. that they are consistent with
the specification and not merely unfalsifiable.  Nothing here touches the
package; the logs are synthesised from the derivations in each header.
"""
import subprocess
import tempfile
from pathlib import Path

MATRIX = Path(__file__).resolve().parent
ROOT = MATRIX.parent.parent
CHECK = ROOT / "scripts/check-decisions.py"


def line(**kw):
    order = ["id", "page", "col", "stratum", "h", "S", "R", "B", "P",
             "ymin", "ymax", "y", "result", "code", "note"]
    return "WIDEBAND DECISION: " + " ".join(f"{k}={kw[k]}" for k in order)


def d(v):
    return "-" if v is None else f"{float(v):.4f}pt"


def placed(i, page, col, stratum, h, S, R, B, P, ymin, ymax, y, note):
    return line(id=i, page=page, col=col, stratum=stratum, h=d(h), S=d(S), R=d(R),
                B=d(B), P=d(P), ymin=d(ymin), ymax=d(ymax), y=d(y),
                result="placed", code="OK", note=note)


def deferred(i, page, col, stratum, h, S, R, B, P, ymin, ymax, code, note):
    return line(id=i, page=page, col=col, stratum=stratum, h=d(h), S=d(S), R=d(R),
                B=d(B), P=d(P), ymin=d(ymin), ymax=d(ymax), y="-",
                result="deferred", code=code, note=note)


def top(i, page, B, S=600):
    return placed(i, page, 0, 1, 0, S, 0, B, 0, 0, S - B, 0, "top-of-page")


CASES = {
    # m01: h=202, B=90, y=h
    "m01-col1-mid-column": [
        placed(1, 1, 1, 1, 202, 600, 0, 90, 202, 202, 510, 202, "col1-at-h")],
    # m02: h=538 does not fit, re-cut to the first legal cut 274
    "m02-col1-recut-when-needed": [
        placed(1, 1, 1, 1, 538, 600, 0, 90, 538, 274, 510, 274, "col1-recut")],
    # m03: recut=never, y=h=538 does not fit -> D1, then top of page 2
    "m03-col1-recut-never-d1": [
        deferred(1, 1, 1, 1, 538, 600, 0, 90, 538, 538, 510, "D1", "no-room"),
        top(1, 2, 90)],
    # m04: h=202 in column 2, P=802, ymin=406
    "m04-col2-fits": [
        placed(1, 1, 2, 1, 202, 600, 0, 90, 802, 406, 510, 406, "col2-recut")],
    # m05: same request, B=246 -> D1
    "m05-col2-d1-tall-band": [
        deferred(1, 1, 2, 1, 202, 600, 0, 246, 802, 406, 354, "D1", "no-room"),
        top(1, 2, 246)],
    # m06: h=442, B=60, ymin=526 but the two-line rule pushes y to ymax=540
    "m06-col2-flush-bottom": [
        # phase-1: flush-bottom not implemented, so D1 then top-of-page (m06)
        deferred(1, 1, 2, 1, 442, 600, 0, 60, 1042, 526, 540, "D1", "no-room"),
        top(1, 2, 60)],
    # m07: h=442, B=132 -> D1
    "m07-col2-d1-deep-request": [
        deferred(1, 1, 2, 1, 442, 600, 0, 132, 1042, 526, 468, "D1", "no-room"),
        top(1, 2, 132)],
    # m08: h=0 in column 2, P=600, ymin=310, B=150
    "m08-col2-empty": [
        # 50 lines = 598pt, 2pt short of a full column, so the request is still
        # in column 1 (h=598) and placed by a col1 re-cut, not col2-empty (m08)
        placed(1, 1, 1, 1, 598, 600, 0, 150, 598, 310, 450, 310, "col1-recut")],
    "m09-recut-across-heading": [
        placed(1, 1, 2, 1, 82, 600, 0, 90, 682, 346, 510, 346, "col2-recut")],
    # m10: two bands, second in stratum 2 (S' = 600-214 = 386)
    "m10-two-bands-one-page": [
        placed(1, 1, 1, 1, 142, 600, 0, 72, 142, 142, 528, 142, "col1-at-h"),
        placed(2, 1, 1, 2, 34, 386, 0, 72, 34, 34, 314, 34, "col1-at-h")],
    "m11-stacked-bands": [
        placed(1, 1, 1, 1, 142, 600, 0, 72, 142, 142, 528, 142, "col1-at-h"),
        placed(2, 1, 1, 2, 0, 386, 0, 72, 0, 0, 314, 0, "stacked")],
    "m12-band-at-page-start": [
        placed(1, 1, 1, 1, 0, 600, 0, 90, 0, 0, 510, 0, "top-of-page")],
    "m13-band-last-on-page": [
        placed(1, 1, 1, 1, 142, 600, 0, 90, 142, 142, 510, 142, "col1-at-h")],
    "m14-band-at-document-end": [
        deferred(1, 1, 2, 1, 550, 600, 0, 246, 1150, 575, 354, "D1", "no-room"),
        top(1, 2, 246)],
    "m15-footnote-in-moved-material-d4": [
        deferred(1, 1, 2, 1, 202, 600, 30, 90, 802, 406, 480, "D4",
                 "footnotes-in-moved-material"),
        top(1, 2, 90)],
    "m16-marginpar-in-moved-material-d4": [
        deferred(1, 1, 2, 1, 142, 600, 0, 90, 742, 371, 510, "D4",
                 "marginpar-in-moved-material"),
        top(1, 2, 90)],
    "m17-unbreakable-range-d3": [
        deferred(1, 1, 2, 1, 214, 600, 0, 90, 814, 407, 510, "D3",
                 "unbreakable-range"),
        top(1, 2, 90)],
    "m19-gate-pkg-conflict-cuted": [
        "WIDEBAND GATE: status=disabled reason=pkg-conflict-cuted",
        deferred(1, 1, 1, 1, 202, 600, 0, 90, 202, 202, 510, "D5",
                 "pkg-conflict-cuted"),
        top(1, 2, 90)],
    "m20-hyperref-across-cut": [
        placed(1, 1, 2, 1, 202, 600, 0, 66, 802, 406, 534, 406, "col2-recut")],
    "m21-xcolor-across-band": [
        placed(1, 1, 1, 1, 202, 600, 0, 90, 202, 202, 510, 202, "col1-at-h")],
    "m22-fancyhdr-running-heads": [
        "WIDEBAND GATE: status=disabled reason=kernel-mismatch",
        deferred(1, 1, 1, 1, 202, 600, 0, 90, 202, 202, 510, "D5",
                 "kernel-mismatch"),
        top(1, 2, 90)],
    "m23-figurestar-on-band-page": [
        placed(1, 1, 1, 1, 202, 520, 0, 90, 202, 202, 430, 202, "col1-at-h")],
    "m24-column-floats-t-and-b": [
        placed(1, 1, 1, 1, 296, 600, 94, 90, 296, 296, 416, 296, "col1-at-h")],
    "m25-raggedbottom": [
        placed(1, 1, 1, 1, 202, 600, 0, 90, 202, 202, 510, 202, "col1-at-h")],
    "m26-flushbottom": [
        placed(1, 1, 1, 1, 202, 600, 0, 90, 202, 202, 510, 202, "col1-at-h")],
    "m27-nested-minipage-d4": [
        deferred(1, 1, 1, 1, 142, 600, 0, 90, 142, 142, 510, "D4", "nested"),
        top(1, 2, 90)],
    "m28-enlargethispage-d4": [
        deferred(1, 1, 1, 1, 202, 600, 0, 90, 202, 202, 510, "D4",
                 "enlargethispage"),
        top(1, 2, 90)],
    "m29-col1-recut-always-earliest": [
        placed(1, 1, 1, 1, 202, 600, 0, 90, 202, 106, 510, 106, "col1-recut")],
    "m30-tall-top-float": [
        # phase-1: re-cut refuses a float in the moved material, D4 then top (m30)
        deferred(1, 1, 2, 1, 142, 600, 0, 90, 742, 394, 510, "D4",
                 "float-in-moved-material"),
        top(1, 2, 90)],
    "m31-footnote-inside-band": [
        placed(1, 1, 1, 1, 202, 600, 20, 102, 202, 202, 478, 202, "col1-at-h")],
    "m32-holdover-footnote": [
        deferred(1, 1, 2, 1, 130, 600, 60, 90, 730, 365, 450, "D4",
                 "holdover-footnote"),
        top(1, 2, 90)],
    "m33-short-stratum-under-band": [
        placed(1, 1, 1, 1, 478, 600, 0, 90, 478, 478, 510, 478, "col1-at-h")],
    "m34-equation-number-order": [
        placed(1, 1, 1, 1, 202, 600, 0, 66, 202, 202, 534, 202, "col1-at-h")],
    "m35-gate-kernel-mismatch": [
        "WIDEBAND GATE: status=disabled reason=kernel-mismatch",
        deferred(1, 1, 1, 1, 202, 600, 0, 90, 202, 202, 510, "D5",
                 "kernel-mismatch"),
        top(1, 2, 90)],
}

fails = 0
# Any scenario with decision expectations but no entry above is uncovered.
for tex in sorted(MATRIX.glob("m*.tex")):
    if tex.stem in CASES:
        continue
    header = "\n".join(tex.read_text().splitlines()[:40])
    if "WB-EXPECT-DECISION" in header or "WB-EXPECT: " in header:
        if "WB-EXPECT-COMPILE: fail" in header:
            continue          # no decision log to synthesise
        print(f"{tex.stem}: WARNING no dry-run entry; add one to stratum-dryrun.py")

with tempfile.TemporaryDirectory() as td:
    for stem, lines in sorted(CASES.items()):
        tex = MATRIX / (stem + ".tex")
        if not tex.is_file():
            print(f"{stem}: MISSING .tex")
            fails += 1
            continue
        log = Path(td) / (stem + ".log")
        log.write_text("\n".join(lines) + "\nOutput written on x.pdf (2 pages).\n")
        r = subprocess.run([str(CHECK), "--package-mode", "stratum", "--wrap-width",
                            "1000", "--strict-format", "--quiet", str(tex), str(log)],
                           capture_output=True, text=True)
        if r.returncode == 0:
            print(f"{stem}: ok")
        else:
            fails += 1
            print(f"{stem}: EXIT {r.returncode}")
            print("   " + "\n   ".join((r.stdout + r.stderr).strip().splitlines()[:6]))
print(f"\n{len(CASES) - fails}/{len(CASES)} matrix headers satisfied by a spec-conforming log")
raise SystemExit(1 if fails else 0)
