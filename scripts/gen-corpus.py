#!/usr/bin/env python3
"""Deterministic generator of self-contained wideband corpus documents.

    scripts/gen-corpus.py --seed 1 --count 30 --out build/corpus

Every document is a complete two-column article that loads only packages from
TeX Live, carries its own prose, and declares the expectations the
specification fixes without knowing where the page builder happens to break:
the request count, the tokens (each must appear exactly once in the pdftotext
output) and whether the run compiles.  Placement and deferral counts are left
to the audit and to the decision log, because y_min and y_max depend on the
line breaking of the generated prose.

Determinism: each document is generated from random.Random("<seed>:<index>"),
which is seeded from a string (hashed with sha512 by the standard library) and
therefore reproducible across runs, machines and Python versions.  No use of
hash(), set iteration or dict ordering influences any choice.

Parameters varied (contract 6.2): request column and position by paragraph
count, band heights from two lines to near-page by stacking equation rows,
one to four bands per page, adjacent requests, footnote density including
notes in the paragraphs just before and after a request, headings and
displays right before a request, single-column floats with t/b/h, figure*,
marginal notes, \\raggedbottom versus \\flushbottom, and with or without
hyperref, amsmath, xcolor and fancyhdr.
"""
from __future__ import annotations

import argparse
import random
import sys
from pathlib import Path

# --------------------------------------------------------------------- prose
# Real technical sentences about typesetting, page building and numerical
# methods.  No filler, no lipsum: the corpus has to break lines the way a real
# article does, which generated placeholder text does not.
SENTENCES = [
    "A two-column output routine does not build both columns at the same time.",
    "TeX contributes paragraphs, displays, insertions and penalties to one vertical list.",
    "When the contribution list reaches the column goal the output routine takes over.",
    "The completed left column is stored while the right column is still being collected.",
    "A request seen in the left column can still change the height of the right column.",
    "A request first seen in the right column arrives after the left column is finished.",
    "Interline glue is computed from the depth of the previous box and the height of the next.",
    "The topskip glue fixes the position of the first baseline in a column.",
    "Depth below the last line of a column is charged against maxdepth, not against the goal.",
    "Discardable items are removed at the breakpoint the page builder finally chooses.",
    "Saving the discarded items is what lets a later re-cut restore the original spacing.",
    "A kern is rigid, but at the top of an empty page it is discarded like glue.",
    "Penalties describe how much TeX dislikes breaking at a particular place.",
    "An infinite penalty forbids a break; a negative penalty invites one.",
    "Insertions carry footnotes and floats through the output routine as separate lists.",
    "The source position of an insertion does not fix the box it finally lands in.",
    "Marks let a running head report the first and the last section on a page.",
    "Splitting a box with vsplit produces both a fragment and a set of split marks.",
    "Badness measures how far a glue setting is from its natural width.",
    "An overfull vertical box means the material was larger than the box it was packed into.",
    "Packing an overfull list into an exact height does not remove the excess material.",
    "The natural height of a list is what decides whether it really fits.",
    "Node lists in LuaTeX are doubly linked and can be traversed in either direction.",
    "An attribute set on a node is inherited by every node created inside its scope.",
    "A whatsit records a side effect that must happen when the page is shipped out.",
    "Colour is a shipout-time property, so a colour stack must follow reading order.",
    "A link annotation that begins on one page and ends on another is a nesting error.",
    "Mirroring the box nesting of the kernel keeps annotations balanced on every page.",
    "Newton iteration roughly doubles the number of correct digits at every step.",
    "Bisection halves the bracket each time and never diverges, but converges slowly.",
    "Gaussian quadrature fixes both the nodes and the weights before any evaluation.",
    "Richardson extrapolation cancels the leading term of the discretisation error.",
    "A tridiagonal system can be solved in time proportional to the number of unknowns.",
    "Partial pivoting keeps Gaussian elimination stable for a well-conditioned matrix.",
    "The condition number bounds how much a relative perturbation can grow.",
    "Floating point addition is not associative, so the summation order matters.",
    "Catastrophic cancellation destroys the leading digits of a nearly zero difference.",
    "Horner's rule evaluates a polynomial of degree n with n multiplications.",
    "A residual is cheap to compute, while the error itself usually is not.",
    "Krylov subspace methods build a nested sequence of search spaces.",
    "A good preconditioner reshapes the spectrum instead of shrinking the residual.",
    "Adaptive step control estimates the local error and rejects a step that is too large.",
    "Stiff systems need implicit methods, because the explicit stability limit is tiny.",
    "The stability region of a method decides the largest usable time step.",
    "Discretisation error and rounding error move in opposite directions as h shrinks.",
    "Measuring the convergence order requires at least three refinements of the grid.",
    "A grid function samples the continuous solution at a finite set of points.",
    "The gutter between two columns is set once and never varies within a page.",
    "Hyphenation adds discretionary breaks that the line breaker may or may not use.",
    "A ledger over every line proves that nothing was lost, duplicated or reordered.",
    "Reading order must equal content order, or the reader silently loses the argument.",
    "A full-width band is an in-flow object, not a float that drifts to the next page.",
    "Text that follows the request may legitimately appear above the band.",
    "Balancing the material above wide content is a different operation from placing it.",
    "The feasible interval for a band position is closed and can be computed exactly.",
    "Choosing the earliest legal position keeps the band close to its request.",
    "A stratum piece is either exactly empty or at least two lines high.",
    "A column with less than one and a half baselines of room is treated as float-only.",
    "Deterministic geometry beats a badness search when the result must be reproducible.",
    "Every deferral should carry a code, so the deferral rate can be tracked per reason.",
]

HEADINGS = [
    "Column geometry and the fit test",
    "Restoring discarded glue at a cut",
    "Insertions across a re-cut",
    "Reading order and the stratum model",
    "Quantisation on a baseline grid",
    "Error estimates for the coarse grid",
    "Stability of the implicit scheme",
    "Conditioning of the assembled system",
]

# gather* rows used to stack a band to a chosen height
BAND_ROWS = [
    r"\mathcal{T}[u] = \int_{\Omega} \bigl( \tfrac12 |\nabla u|^2 - f u \bigr) \, dx",
    r"\delta\mathcal{T}[u;v] = \int_{\Omega} \bigl( \nabla u \cdot \nabla v - f v \bigr) \, dx",
    r"A_{ij} = \int_{\Omega} \nabla \varphi_i \cdot \nabla \varphi_j \, dx",
    r"b_i = \int_{\Omega} f \varphi_i \, dx",
    r"\kappa(A) = \|A\| \, \|A^{-1}\|",
    r"\|u - u_h\|_{1} \le C h^{p} \, \|u\|_{p+1}",
    r"\sum_{k=0}^{n} c_k \, T_k(x) = f(x) + \mathcal{O}(h^{p+1})",
    r"y_{n+1} = y_n + h \sum_{s=1}^{m} b_s \, k_s",
    r"k_s = f\bigl( t_n + c_s h, \; y_n + h \textstyle\sum_j a_{sj} k_j \bigr)",
    r"\oint_{\partial\Omega} u \, \nabla v \cdot n \, ds = \int_{\Omega} \nabla \cdot (u \nabla v) \, dx",
    r"\mathcal{L}[u] = -\nabla \cdot (a \nabla u) + c \, u",
    r"\rho(I - M^{-1} A) < 1 \quad \text{for a convergent iteration}",
]

DISPLAY = (r"\begin{align*}"
           "\n  P &= S_1 + h, & y_{\\min} &= \\left\\lceil P/2 \\right\\rceil \\\\"
           "\n  y_{\\max} &= S - R - B, & B &= b + s_a + s_b"
           "\n\\end{align*}")

GEO_STD = ("\\usepackage[a4paper,textheight=600pt,textwidth=460pt,top=80pt,"
           "columnsep=18pt]{geometry}")
# Narrower type block so that marginal notes stay inside the envelope
# scripts/check-pdf-bounds.py enforces (55pt from each paper edge).
GEO_MARGIN = ("\\usepackage[a4paper,textheight=600pt,textwidth=388pt,left=104pt,"
              "top=80pt,columnsep=18pt,marginparsep=8pt,marginparwidth=38pt]{geometry}")

OVERSIZED_ROWS = 32
MAX_TOKEN_LINES = 24
TOKENS_PER_LINE = 10


def weighted(rnd: random.Random, choices: list, weights: list[float]):
    return rnd.choices(choices, weights=weights, k=1)[0]


class Document:
    def __init__(self, seed: int, index: int, count: int, load_style: str) -> None:
        self.seed = seed
        self.index = index
        self.count = count
        self.load_style = load_style
        self.rnd = random.Random("%d:%d" % (seed, index))
        self.tokens: list[str] = []
        self.plan()

    # ---------------------------------------------------------------- naming
    @property
    def name(self) -> str:
        return "corpus-%04d-%04d" % (self.seed, self.index)

    def ptok(self, n: int) -> str:
        return "CORPUS-%04d-P%03d" % (self.index, n)

    def btok(self, n: int) -> str:
        return "CORPUS-%04d-B%02d" % (self.index, n)

    def ntok(self, n: int) -> str:
        return "CORPUS-%04d-N%02d" % (self.index, n)

    def ftok(self, n: int) -> str:
        return "CORPUS-%04d-F%02d" % (self.index, n)

    def mtok(self, n: int) -> str:
        # short, because it has to fit a 38pt margin at \tiny
        return "MG%04d%02d" % (self.index, n)

    # ------------------------------------------------------------- the plan
    def plan(self) -> None:
        rnd = self.rnd
        # 40 per cent single-band documents, so a run against the baseline
        # package (which rejects a second pending band) still exercises the
        # full check chain on a useful number of documents.
        self.nbands = weighted(rnd, [1, 2, 3, 4], [0.40, 0.30, 0.20, 0.10])
        self.oversized = rnd.random() < 1 / 12.0
        self.bottom = weighted(rnd, ["raggedbottom", "flushbottom"], [0.5, 0.5])
        self.use_hyperref = rnd.random() < 0.30
        self.use_xcolor = rnd.random() < 0.30
        self.use_fancyhdr = rnd.random() < 0.20
        self.use_marginpar = rnd.random() < 0.20
        self.footnotes = weighted(rnd, ["none", "low", "high"], [0.35, 0.45, 0.20])
        self.floats = [weighted(rnd, ["t", "b", "h"], [0.5, 0.3, 0.2])
                       for _ in range(weighted(rnd, [0, 1, 2], [0.5, 0.35, 0.15]))]
        self.widefloat = "t" if rnd.random() < 0.15 else None

        # Band heights come from stacked gather* rows.  Measured band footprints
        # B (box + 2 x 12pt separation) on TeX Live 2025, from
        # build/probe/probe-rows.log:
        #   1 row  52pt   2 rows  78pt   3 rows 105pt   5 rows 149pt
        #   8 rows 230pt  12 rows 306pt  16 rows 412pt  18 rows 444pt
        #  20 rows 510pt  32 rows 749pt
        # so 1 to 20 rows spans "a couple of lines" to "most of a column" while
        # staying below both size limits (the baseline package refuses a band
        # above \textheight - 2\baselineskip = 576pt, the stratum core above
        # S = 600pt).  One document in twelve gets a 32-row band instead, which
        # is above both limits and must fail with D2.
        self.band_rows: list[int] = []
        for _ in range(self.nbands):
            self.band_rows.append(weighted(
                rnd, [1, 2, 3, 5, 8, 12, 16, 18, 20],
                [0.16, 0.18, 0.16, 0.15, 0.13, 0.10, 0.06, 0.04, 0.02]))
        if self.oversized:
            self.band_rows[rnd.randrange(self.nbands)] = OVERSIZED_ROWS

        # Paragraphs before each request.  A zero gap after the first band is
        # the "adjacent requests" case that must stack.
        self.gaps: list[int] = [weighted(rnd, [2, 4, 6, 9, 13, 18, 24],
                                         [0.10, 0.18, 0.20, 0.20, 0.16, 0.10, 0.06])]
        for _ in range(self.nbands - 1):
            self.gaps.append(weighted(rnd, [0, 1, 3, 6, 10, 16],
                                      [0.22, 0.15, 0.20, 0.20, 0.14, 0.09]))
        self.tail = weighted(rnd, [10, 16, 22, 30], [0.25, 0.35, 0.25, 0.15])
        self.heading_before = [rnd.random() < 0.35 for _ in range(self.nbands)]
        self.display_before = [rnd.random() < 0.30 for _ in range(self.nbands)]
        self.sentence_cursor = rnd.randrange(len(SENTENCES))

    # ------------------------------------------------------------- rendering
    def paragraph(self, n: int, footnote: int | None = None) -> str:
        rnd = self.rnd
        token = self.ptok(n)
        self.tokens.append(token)
        parts = ["\\mbox{%s}" % token]
        for _ in range(rnd.randint(3, 7)):
            parts.append(SENTENCES[self.sentence_cursor % len(SENTENCES)])
            self.sentence_cursor += 1
        text = " ".join(parts)
        if footnote is not None:
            ftoken = self.ntok(footnote)
            self.tokens.append(ftoken)
            note = SENTENCES[self.sentence_cursor % len(SENTENCES)]
            self.sentence_cursor += 1
            text += "\\footnote{\\mbox{%s} %s}" % (ftoken, note)
        return text + "\n"

    def band(self, n: int, rows: int) -> str:
        token = self.btok(n)
        if not self.oversized or rows != OVERSIZED_ROWS:
            self.tokens.append(token)
        body = [r"\begin{gather*}"]
        for i in range(rows):
            sep = r" \\" if i < rows - 1 else ""
            body.append("  " + BAND_ROWS[i % len(BAND_ROWS)] + sep)
        body.append(r"\end{gather*}")
        body.append(r"\noindent\hbox to\textwidth{\hfil\mbox{%s}\hfil}" % token)
        return ("\\begin{wideband}\n" + "\n".join(body) + "\n\\end{wideband}\n")

    def float_block(self, n: int, placement: str) -> str:
        token = self.ftok(n)
        self.tokens.append(token)
        return ("\\begin{figure}[%s]\n  \\centering\n"
                "  \\rule{.7\\columnwidth}{40pt}\n"
                "  \\caption{\\mbox{%s} A single-column diagnostic float.}\n"
                "\\end{figure}\n" % (placement, token))

    def widefloat_block(self, placement: str) -> str:
        token = self.ftok(90)
        self.tokens.append(token)
        return ("\\begin{figure*}[%s]\n  \\centering\n"
                "  \\rule{.6\\textwidth}{40pt}\n"
                "  \\caption{\\mbox{%s} A double-column diagnostic float.}\n"
                "\\end{figure*}\n" % (placement, token))

    def marginpar(self, n: int) -> str:
        token = self.mtok(n)
        self.tokens.append(token)
        return "\\marginpar{\\tiny\\raggedright\\mbox{%s}}\n" % token

    def body(self) -> str:
        rnd = self.rnd
        out: list[str] = []
        para = 0
        nfloat = 0
        nnote = 0
        nmargin = 0
        fnprob = {"none": 0.0, "low": 0.12, "high": 0.35}[self.footnotes]

        if self.widefloat:
            out.append(self.widefloat_block(self.widefloat))
        for placement in self.floats:
            nfloat += 1
            out.append(self.float_block(nfloat, placement))

        for band_index in range(self.nbands):
            gap = self.gaps[band_index]
            for i in range(gap):
                para += 1
                note = None
                last = i == gap - 1
                # a footnote in the paragraph immediately before the request is
                # the phase-1 D4 case, so force one at high density
                if self.footnotes == "high" and last:
                    nnote += 1
                    note = nnote
                elif rnd.random() < fnprob:
                    nnote += 1
                    note = nnote
                out.append(self.paragraph(para, note))
                if self.use_marginpar and rnd.random() < 0.25:
                    nmargin += 1
                    out.append(self.marginpar(nmargin))
            if self.heading_before[band_index]:
                out.append("\\section{%s}\n"
                           % HEADINGS[(self.index + band_index) % len(HEADINGS)])
            if self.display_before[band_index]:
                out.append(DISPLAY + "\n")
            out.append(self.band(band_index + 1, self.band_rows[band_index]))
            # a footnote in the paragraph immediately after the request
            if self.footnotes != "none":
                para += 1
                nnote += 1
                out.append(self.paragraph(para, nnote))

        for _ in range(self.tail):
            para += 1
            note = None
            if rnd.random() < fnprob:
                nnote += 1
                note = nnote
            out.append(self.paragraph(para, note))
            if self.use_marginpar and rnd.random() < 0.15:
                nmargin += 1
                out.append(self.marginpar(nmargin))
        return "\n".join(out)

    # ------------------------------------------------------------ the header
    def header(self, differs: bool) -> str:
        packages = ["amsmath"]
        if self.use_hyperref:
            packages.append("hyperref")
        if self.use_xcolor:
            packages.append("xcolor")
        if self.use_fancyhdr:
            packages.append("fancyhdr")
        rows = ",".join(str(r) for r in self.band_rows)
        gaps = ",".join(str(g) for g in self.gaps)
        heads = "".join("1" if h else "0" for h in self.heading_before)
        disps = "".join("1" if d else "0" for d in self.display_before)
        lines = [
            f"%% Generated by scripts/gen-corpus.py --seed {self.seed} "
            f"--count {self.count} (document {self.index} of {self.count}).",
            "%% Deterministic: the same seed and index reproduce this file byte for byte.",
            f"%% bands={self.nbands} rows={rows} gaps={gaps} tail={self.tail} "
            f"bottom={self.bottom} footnotes={self.footnotes}",
            f"%% packages={','.join(packages)} "
            f"floats={','.join(self.floats) or 'none'} "
            f"figure*={self.widefloat or 'none'} "
            f"marginpar={'yes' if self.use_marginpar else 'no'} "
            f"headings={heads} displays={disps}",
            "%% Only the expectations the specification fixes without knowing where the",
            "%% page builder breaks are declared here: the request count, the tokens and",
            "%% the compile outcome.  Placement and deferral counts depend on y_min and",
            "%% y_max, which depend on the line breaking of this document's prose, so they",
            "%% are left to the audit and to the decision log.",
        ]
        if self.oversized:
            lines += [
                f"%% One band is stacked to {OVERSIZED_ROWS} rows, taller than a fresh"
                " column, so the run",
                "%% must fail with the D2 error of report section 5.",
                "%% WB-EXPECT-COMPILE: fail",
                "%% WB-EXPECT-LOG: ^! Package wideband Error:",
            ]
        else:
            lines += [
                f"%% WB-EXPECT: requests={self.nbands}",
                "%% WB-EXPECT-COMPILE: pass",
            ]
        if differs:
            reasons = []
            if self.nbands > 1:
                reasons.append("the baseline package rejects a second pending band")
            if self.load_style == "option":
                reasons.append("the baseline package declares no options")
            lines.append("%% Baseline: " + "; ".join(reasons) + ".")
            lines.append("%% WB-BASELINE-DIFFERS")
        if not self.oversized:
            for i in range(0, len(self.tokens), TOKENS_PER_LINE):
                if i // TOKENS_PER_LINE >= MAX_TOKEN_LINES:
                    break
                chunk = self.tokens[i:i + TOKENS_PER_LINE]
                lines.append("%% WB-EXPECT-TOKENS: " + " ".join(chunk))
        return "\n".join(lines)

    # -------------------------------------------------------------- assembly
    def render(self) -> str:
        body = self.body()          # fills self.tokens
        differs = self.nbands > 1 or self.load_style == "option"

        if self.load_style == "option":
            load = "\\usepackage[audit]{wideband}"
        else:
            load = ("\\usepackage{wideband}\n"
                    "\\IfFileExists{wideband-audit.sty}{\\usepackage{wideband-audit}}{}")

        pre = [GEO_MARGIN if self.use_marginpar else GEO_STD, "\\usepackage{amsmath}"]
        if self.use_xcolor:
            pre.append("\\usepackage{xcolor}")
        if self.use_fancyhdr:
            pre.append("\\usepackage{fancyhdr}")
        if self.use_hyperref:
            pre.append("\\usepackage{hyperref}")
        setup = ["\\" + self.bottom, "\\setwidebandsep{12pt}"]
        if self.use_fancyhdr:
            setup += ["\\setlength{\\headheight}{14pt}", "\\pagestyle{fancy}",
                      "\\fancyhf{}", "\\fancyhead[L]{Wideband synthetic corpus}",
                      "\\fancyhead[R]{\\thepage}", "\\fancyfoot[C]{Generated document}"]
        if self.use_xcolor:
            setup.append("\\color{black}")

        return "\n".join([
            self.header(differs),
            "\\documentclass[twocolumn]{article}",
            "\n".join(pre),
            load,
            "\n".join(setup),
            "\\begin{document}",
            body,
            "\\end{document}",
        ]) + "\n"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--count", type=int, required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--load-style", choices=("explicit", "option"), default="explicit",
                    help="explicit (default): \\usepackage{wideband} plus a guarded "
                         "\\usepackage{wideband-audit}; option: \\usepackage[audit]{wideband}, "
                         "which the baseline package rejects with 'Unknown option'")
    ap.add_argument("--list", action="store_true", help="print names only, write nothing")
    args = ap.parse_args(argv)
    if args.count < 1:
        ap.error("--count must be positive")

    out = Path(args.out)
    if not args.list:
        out.mkdir(parents=True, exist_ok=True)
    written = []
    for index in range(1, args.count + 1):
        doc = Document(args.seed, index, args.count, args.load_style)
        text = doc.render()
        if args.list:
            print(doc.name)
        else:
            (out / (doc.name + ".tex")).write_text(text)
        written.append(doc.name)
    if not args.list:
        print("gen-corpus: wrote %d documents to %s (seed %d, load-style %s)"
              % (len(written), out, args.seed, args.load_style))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
