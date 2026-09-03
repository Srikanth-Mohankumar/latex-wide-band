#!/usr/bin/env python3
"""Reproduce the measurements the matrix and corpus derivations rest on.

    ./tests/matrix/probes/measure.py [BUILD_DIR]        # default build/probe-measure

Everything printed here is a property of the document class, the geometry
settings, the prose helpers in tests/matrix/matrix-content.tex and the band
rows in scripts/gen-corpus.py.  None of it involves the package under test, so
the numbers are legitimate *inputs* to an expectation, not observed output.

Three measurements:

1. Geometry of the standard matrix preamble: \\textheight (which is S on a
   float-free page), \\baselineskip, \\topskip, \\textwidth, \\columnwidth and
   the paper size, plus the same for the narrow marginpar preamble.
2. The prose helpers: that \\WBMlines{n} sets exactly n one-line paragraphs,
   how many of them fill a column (the matrix derivations assume 50), and that
   \\WBMbandbox{H} produces a box of height exactly H and depth 0.
3. The band footprint B = box + 2 x 12pt for each gather* row count
   gen-corpus.py can choose, so the generator's row weights can be checked
   against the two size limits (the baseline package refuses a band above
   \\textheight - 2\\baselineskip = 576pt, the stratum core above S = 600pt).
"""
import importlib.util
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MATRIX = HERE.parent
ROOT = MATRIX.parent.parent

GEO_STD = ("\\usepackage[a4paper,textheight=600pt,textwidth=460pt,top=80pt,"
           "columnsep=18pt]{geometry}")
GEO_MARGIN = ("\\usepackage[a4paper,textheight=600pt,textwidth=388pt,left=104pt,"
              "top=80pt,columnsep=18pt,marginparsep=8pt,marginparwidth=38pt]{geometry}")


def compile_tex(build: Path, stem: str, text: str) -> str:
    (build / (stem + ".tex")).write_text(text)
    env = dict(os.environ, max_print_line="1000")
    r = subprocess.run(["lualatex", "-interaction=nonstopmode", "-halt-on-error",
                        stem + ".tex"], cwd=build, capture_output=True, text=True,
                       env=env)
    if r.returncode != 0:
        first = next((l for l in r.stdout.splitlines() if l.startswith("!")), "")
        raise SystemExit("measure: %s failed to compile: %s" % (stem, first))
    return (build / (stem + ".log")).read_text(errors="replace")


def probe(geo: str, extra: str = "") -> str:
    return "\n".join([
        r"\documentclass[twocolumn]{article}", geo, r"\usepackage{amsmath}",
        r"\begin{document}\makeatletter",
        r"\typeout{P textheight=\the\textheight\space"
        r" baselineskip=\the\baselineskip\space topskip=\the\topskip\space"
        r" textwidth=\the\textwidth\space columnwidth=\the\columnwidth\space"
        r" colht=\the\@colht\space maxdepth=\the\maxdepth\space"
        r" marginparwidth=\the\marginparwidth\space"
        r" paperwidth=\the\paperwidth\space paperheight=\the\paperheight}",
        extra, r"\makeatother x\end{document}"])


def main(argv: list[str]) -> int:
    build = Path(argv[0]) if argv else ROOT / "build/probe-measure"
    build.mkdir(parents=True, exist_ok=True)
    shutil.copy(MATRIX / "matrix-content.tex", build)

    print("== 1. geometry of the matrix preambles " + "=" * 38)
    for name, geo in (("standard", GEO_STD), ("marginpar (narrow)", GEO_MARGIN)):
        log = compile_tex(build, "geo-" + name.split()[0], probe(geo))
        for line in log.splitlines():
            if line.startswith("P textheight="):
                print("%-20s %s" % (name, line[2:]))
    print("check-pdf-bounds.py accepts words at least 55pt from each paper edge and")
    print("95pt from the paper bottom; both preambles keep the type block inside that.")

    print()
    print("== 2. the prose helpers " + "=" * 54)
    extra = "\n".join([
        r"\input{matrix-content.tex}",
        r"\setbox0=\vbox{\hsize\columnwidth \WBMlines{48}{ZZA}}",
        r"\directlua{local n=0 "
        r"for h in node.traverse_id(node.id('hlist'), tex.box[0].head) do n=n+1 end "
        r"texio.write_nl('P WBMlines48 hlists='..n)}",
        r"\typeout{P WBMlines48 ht=\the\ht0\space dp=\the\dp0}",
        r"\setbox0=\vbox{\hsize\textwidth \WBMbandbox{66pt}{ZZB}{$E=mc^2$}}",
        r"\typeout{P WBMbandbox66 ht=\the\ht0\space dp=\the\dp0}",
        r"\setbox0=\vbox{\hsize\textwidth \WBMbandbox{222pt}{ZZC}{$E=mc^2$}}",
        r"\typeout{P WBMbandbox222 ht=\the\ht0\space dp=\the\dp0}",
    ])
    log = compile_tex(build, "helpers", probe(GEO_STD, extra))
    for line in log.splitlines():
        if line.startswith("P WBM"):
            print("  " + line[2:])
    print("  expected: 48 hlists (one line per paragraph), ht = 7.1 + 12*47 = 571.2pt,")
    print("            WBMbandbox{H} exactly H tall with depth 0, so B = H + 24pt")

    # lines per column: set 200 lines and read the token positions from the PDF
    pages = "\n".join([r"\documentclass[twocolumn]{article}", GEO_STD,
                       r"\usepackage{amsmath}", r"\input{matrix-content.tex}",
                       r"\pagestyle{empty}", r"\raggedbottom",
                       r"\begin{document}\WBMlines{200}{ZZB}\end{document}"])
    compile_tex(build, "lines", pages)
    html = subprocess.check_output(["pdftotext", "-bbox-layout",
                                    str(build / "lines.pdf"), "-"], text=True)
    for i, (w, _h, body) in enumerate(
            re.findall(r'<page width="([\d.]+)" height="([\d.]+)">(.*?)</page>',
                       html, re.S), 1):
        mid = float(w) / 2
        cols = {1: [], 2: []}
        for m in re.finditer(r'<word xMin="([\d.]+)"[^>]*>(ZZB\d+)</word>', body):
            cols[1 if float(m.group(1)) < mid else 2].append(m.group(2))
        print("  page %d: %d lines in column 1, %d in column 2 "
              "(the matrix derivations assume 50)" % (i, len(cols[1]), len(cols[2])))

    print()
    print("== 3. generated band footprints " + "=" * 46)
    spec = importlib.util.spec_from_file_location(
        "gencorpus", ROOT / "scripts/gen-corpus.py")
    gen = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gen)
    counts = [1, 2, 3, 5, 8, 12, 16, 18, 20, 24, gen.OVERSIZED_ROWS]
    body = []
    for n in counts:
        rows = " \\\\\n".join("  " + gen.BAND_ROWS[i % len(gen.BAND_ROWS)]
                              for i in range(n))
        body.append(
            r"\setbox0=\vbox{\hsize\textwidth \columnwidth\textwidth"
            r" \linewidth\textwidth \abovedisplayskip\z@skip"
            r" \belowdisplayskip\z@skip \abovedisplayshortskip\z@skip"
            r" \belowdisplayshortskip\z@skip \noindent\ignorespaces"
            "\n\\begin{gather*}\n" + rows +
            "\n\\end{gather*}\n\\noindent\\hbox to\\textwidth{\\hfil X\\hfil}}")
        body.append(r"\typeout{P rows=%d ht=\the\ht0\space dp=\the\dp0}" % n)
    log = compile_tex(build, "bandrows", probe(GEO_STD, "\n".join(body)))
    print("  %5s %10s %10s  %s" % ("rows", "box", "B=box+24", "verdict"))
    for line in log.splitlines():
        m = re.match(r"P rows=(\d+) ht=([\d.]+)pt ?dp=([\d.]+)pt", line)
        if not m:
            continue
        n, box = int(m.group(1)), float(m.group(2)) + float(m.group(3))
        B = box + 24
        if B > 600:
            verdict = "refused by both packages (D2)"
        elif B > 576:
            verdict = "refused by the baseline only - do not generate"
        else:
            verdict = "accepted by both"
        print("  %5d %9.1fpt %9.1fpt  %s" % (n, box, B, verdict))
    print()
    print("build artifacts: %s" % build)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
