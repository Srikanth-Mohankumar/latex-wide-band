# CORPUS: scenario matrix, synthetic generator and runners

This is the CORPUS workstream of `docs/implementation-contract.md` (section 6). It provides:

| File | Purpose |
|---|---|
| `scripts/check-decisions.py` | parses the `WB-EXPECT*` header of a document and checks it against the `WIDEBAND DECISION:` lines in the `.log`; also checks the spec invariants of report 2.1 to 2.3 on every decision line |
| `scripts/run-matrix.sh` | compiles and checks a directory of scenario documents (default `tests/matrix`) |
| `scripts/gen-corpus.py` | deterministic generator of self-contained corpus documents |
| `scripts/run-corpus.sh` | generates a corpus and runs the same checks over it |
| `tests/matrix/*.tex` | the hand-written scenario matrix, one document per expressible case |
| `tests/matrix/matrix-content.tex` | shared prose and layout helpers for the matrix (CORPUS' own copy; `tests/test-content.tex` is shared and read-only) |
| `tests/matrix/stratum-dryrun.py` | synthesises a spec-conforming decision log for every scenario and checks the headers against it; needs no LaTeX |

## How to run

```bash
./scripts/run-matrix.sh                        # the whole matrix into build/matrix
./scripts/run-matrix.sh --only 'm0[1-8]*'      # just the report 2.8 geometry rows
./scripts/run-matrix.sh --keep-going           # do not stop at the first failure
./scripts/run-matrix.sh --strict               # ignore %% WB-BASELINE-DIFFERS
./scripts/run-matrix.sh /tmp/wb                # explicit build directory
WB_BUILD_DIR=/tmp/wb ./scripts/run-matrix.sh   # same, through the environment

./scripts/run-corpus.sh --seed 1 --count 30    # generate + check, into build/corpus
./scripts/run-corpus.sh --seed 1 --count 200 --keep-going
./scripts/gen-corpus.py --seed 1 --count 30 --out /tmp/src   # generate only

./scripts/check-decisions.py --selftest        # 28 checker self-tests, no LaTeX needed
./scripts/check-decisions.py doc.tex doc.log   # one document
./scripts/check-decisions.py --print-meta doc.tex
./tests/matrix/stratum-dryrun.py               # headers vs a spec-conforming log
```

`run-matrix.sh` runs both `check-decisions.py --selftest` and
`tests/matrix/stratum-dryrun.py` before it compiles anything, and stops if either fails.

Exit codes of the runners: `0` all good, `1` at least one document failed, `2` usage error.

Requirements: LuaLaTeX (TeX Live 2025), Poppler (`pdftotext`), Python 3. The runners export
`max_print_line=1000` so that long `WIDEBAND DECISION:` lines are not wrapped by TeX at 79
characters; `check-decisions.py` also un-wraps defensively for logs produced elsewhere.

## Baseline mode versus stratum mode

`run-matrix.sh` detects which package it is running against by looking for the string
`WIDEBAND DECISION` in `wideband.sty` and `wideband.lua`:

- **stratum mode** (the new CORE): everything is checked.
- **baseline mode** (the package at commit `67756d5`, which writes no decision log): the
  decision-derived checks are skipped and reported as `skip-base` — the `WB-EXPECT` counts, the
  `WB-EXPECT-DECISION` lines, and any `WB-EXPECT-LOG`/`WB-EXPECT-NOLOG` pattern that mentions
  `WIDEBAND`, `code=`, `stratum=`, `ymin=` or `ymax=`. Compile status, tokens, PDF bounds,
  overfull vertical boxes and the remaining log patterns are still checked.

`--package-mode baseline|stratum` overrides the detection; `--strict` forces stratum behaviour
and ignores `WB-BASELINE-DIFFERS`.

### `%% WB-BASELINE-DIFFERS`

A document carries this marker when the *baseline* package's behaviour differs from the
specification, so a failure against the baseline is expected and must not be read as a defect in
the tooling. Such a document is reported as:

- `XFAIL` — it failed, as expected for the baseline (does not affect the exit code);
- `XPASS` — it passed, which only means the checks that still run in baseline mode could not see
  the difference (usually because the difference is *which page* the band landed on, and the token
  count is per document, not per page).

In stratum mode and under `--strict` the marker is ignored and every failure counts.

## Expectation comments (contract 6.1)

They must appear in the **first 40 lines** of the document.

```
%% WB-EXPECT: requests=<n> placed=<n> deferred=<n> [errors=<n>]
%% WB-EXPECT-DECISION: id=<n> result=<placed|deferred|error> [col=<c>] [code=<Dx>] [page=<p>] [note=<t>]
%% WB-EXPECT-LOG: <Python regex that must match at least one log line>
%% WB-EXPECT-NOLOG: <Python regex that must match no log line>
%% WB-EXPECT-TOKENS: TOKEN-A TOKEN-B ...        (each exactly once in pdftotext output)
%% WB-EXPECT-COMPILE: pass|fail
%% WB-ALLOW-OVERFULL
%% WB-BASELINE-DIFFERS
```

Notes on the semantics `check-decisions.py` implements:

- every field of `WB-EXPECT` is optional and only the ones present are compared; `requests` counts
  distinct band ids, `placed`/`deferred`/`errors` count decision lines by `result`;
- `WB-EXPECT-DECISION` is satisfied when **at least one** decision line for that id matches every
  field given, because a band legitimately produces two lines (`deferred` on page p, then
  `placed col=0` on page p+1);
- `WB-EXPECT-TOKENS` and `WB-EXPECT-DECISION` may be repeated; token lists are cumulative;
- a token must never be a substring of another token in the same list, because
  `verify-token-counts.py` counts substrings — the checker rejects such a list;
- `errors=<n>` is a CORPUS extension of contract 6.1, for the D2 error class;
- exit code `3` means "the document declares decision expectations but the log has no decision
  lines at all", reported as `no decision lines: baseline package?`.

### Spec invariants checked on every decision line

These come from the report, not from the document, so they apply to every run (tolerance 0.05pt,
which absorbs the grid rounding of report 2.6):

| Invariant | Source |
|---|---|
| `ymax = S - R - B` | report 2.3 |
| `ymin >= P/2` for `col=1` and `col=2` | report 2.1, 2.2 (reading-order rule) |
| `ymin <= y <= ymax` for a same-page placement | report 2.3 |
| `P = h` when `col=1` | report 1 |
| `y = -` unless `result=placed`, and numeric when it is | contract 4.2 |
| `y = 0` when `col=0` | contract 4.2 |
| at most one `result=placed` line per band id | report 6 ("band shipped twice or never") |
| `result`, `code`, and the key set and their value shapes | contract 4.2 |

Key *order* inside a decision line and a `note` outside the contract 4.2 vocabulary are warnings,
not failures, unless `--strict-format` (implied by `--strict`) is given.

## Geometry of the matrix documents, and how the expectations were derived

Every matrix document declares

```tex
\usepackage[a4paper,textheight=600pt,textwidth=460pt,top=80pt,columnsep=18pt]{geometry}
```

which measures (TeX Live 2025, `build/probe/probe-geo.log`) as

| quantity | value |
|---|---|
| `\textheight`, so `S = \@colht` on a float-free page | 600pt |
| `\baselineskip` | 12pt |
| `\topskip` | 10pt |
| `\textwidth` / `\columnwidth` | 460pt / 221pt |
| paper | 597.5pt x 845.0pt, side margins 68.75pt, type block ends 165pt above the paper bottom |

`S = 600pt`, `R = 0` and a 12pt baseline are exactly the numbers report section 2.8 works with, so
its eight rows transfer to these documents unchanged. The margins keep every word inside the
envelope `scripts/check-pdf-bounds.py` enforces (55pt from each paper edge, 95pt from the bottom).
The two `marginpar` scenarios need room for the notes and therefore use a narrower type block
(`textwidth=388pt, left=104pt, marginparsep=8pt, marginparwidth=38pt`); `\textheight` is still
600pt there, so `S` is unchanged.

Heights come from three measured facts, all taken from a **band-free** compile (that is, from the
prose and the class, not from the package under test):

1. `\WBMlines{n}{tag}` sets exactly `n` one-line paragraphs (verified by counting `hlist` nodes),
   so the material above a request is `h(n) = \topskip + (n-1)\baselineskip = 12n - 2` pt, plus at
   most 2.2pt of last-line depth.
2. Exactly **50** such lines fill a 600pt column, so `\WBMlines{50}` fills column 1 and the next
   line starts column 2. A column-2 request preceded by `k` further lines therefore has
   `h = 12k - 2` and `P = S + h`.
3. `\WBMbandbox{H}{token}{content}` builds a band box of height exactly `H` and depth 0 (a
   zero-width `\vrule` strut sets the height; the visible content is placed with
   `\raisebox{...}[0pt][0pt]`, so it does not contribute). With `\widebandrulesoff` and
   `\setwidebandsep{12pt}` the band footprint of report section 1 is therefore
   `B = H + 2 x 12pt = H + 24pt`, with no dependency on font metrics.

Documents that rely on 1 and 2 declare `\raggedbottom`, which removes `\flushbottom`'s interline
stretching so the positions are exact; `m26-flushbottom` is the paired `\flushbottom` control.

From these, `y_min`, `y_max` and the fit test of report 2.1 to 2.3 are arithmetic, and each
document's header shows the calculation. Two deliberate deviations from the report's illustrative
numbers:

- `m05` and `m07` replicate report 2.8 rows 5 and 7 but with the *margin* of the failing fit test
  widened from 10pt and 15pt to 52pt and 58pt, so that the expectation survives one line of prose
  drift. The row's structure (a column-2 request that cannot be placed, D1) is unchanged.
- `m06` replicates row 6, the one row where the two-line minimum piece rule forces `y` to `y_max`.
  It is inherently a boundary case: a stricter reading of report 2.3 ("else `y_max` **when that is
  a legal cut**") would defer with D1 instead of placing flush at the bottom. The expectation
  follows the report, which records "placed"; a D1 from CORE here is a specification question, not
  necessarily a bug.

### Two checks that the derivations are right

1. `tests/matrix/stratum-dryrun.py` writes, for each scenario, the decision log a
   specification-conforming CORE would produce (from the arithmetic in that scenario's header) and
   runs `check-decisions.py --package-mode stratum --strict-format` against it. All 34 scenarios
   with a decision log pass, so the headers are consistent with the specification rather than
   merely unfalsifiable, and the checker will not reject a conforming CORE. `run-matrix.sh` runs
   this before it compiles anything.
2. The baseline package reports the marker position it measured
   (`Package wideband info: marker found at Xpt from column top`). Compared against the `h` each
   header predicts, 19 of the 20 documents where the baseline reaches the marker agree to within
   2.1pt, which is exactly the last line's depth. The twentieth,
   `m24-column-floats-t-and-b`, showed that a single-column `[t]` float counts towards `h` (it sits
   inside the column) rather than reducing `S`; the header was corrected accordingly, and the
   conclusion (`placed`) is unchanged. `build/probe/verify-h.py` reproduces the comparison after a
   matrix run.

Nothing in any expectation was copied from observed output. Where the geometry could not be pinned
down (a heading's `3.5ex` space, a float's `\textfloatsep`, a split footnote's reservation), the
document asserts only what the specification fixes — usually `result` and `code` — and its header
says so.

## The scenario matrix

`m01` to `m08` are the eight rows of report 2.8; the rest are the rows of report section 6 that
can be expressed today, plus the cases contract section 8 asks for.

| Document | Case | Expected outcome |
|---|---|---|
| `m01-col1-mid-column` | col-1 request, h=202, B=90 | placed col=1 at y=h |
| `m02-col1-recut-when-needed` | col-1 at h=538, default re-cut | placed col=1, `col1-recut` |
| `m03-col1-recut-never-d1` | same with `recut=never` | deferred D1, then placed col=0 |
| `m04-col2-fits` | col-2 at h=202, B=90 | placed col=2, `col2-recut` |
| `m05-col2-d1-tall-band` | col-2 at h=202, B=246 | deferred D1, then placed col=0 |
| `m06-col2-flush-bottom` | col-2 at h=442, B=60 | placed col=2 at y=y_max |
| `m07-col2-d1-deep-request` | col-2 at h=442, B=132 | deferred D1, then placed col=0 |
| `m08-col2-empty` | col-2 with h=0, B=150 | placed col=2, column 1 halved |
| `m09-recut-across-heading` | heading inside the moved material | placed col=2, heading space survives |
| `m10-two-bands-one-page` | two requests, one page | both placed |
| `m11-stacked-bands` | adjacent requests | both placed, `note=stacked` |
| `m12-band-at-page-start` | h=0 in col 1 | placed col=1, `top-of-page` |
| `m13-band-last-on-page` | nothing follows the request | placed col=1, empty bottom strata |
| `m14-band-at-document-end` | pending band at `\end{document}` | deferred D1, forces page 2 |
| `m15-footnote-in-moved-material-d4` | footnote below the cut | deferred D4 `footnotes-in-moved-material` |
| `m16-marginpar-in-moved-material-d4` | marginal note below the cut | deferred D4 `marginpar-in-moved-material` |
| `m17-unbreakable-range-d3` | 160pt unbreakable block over `[y_min,y_max]` | deferred D3 `unbreakable-range` |
| `m18-oversized-d2-error` | B=664 > S | D2, run must fail |
| `m19-gate-pkg-conflict-cuted` | `cuted` loaded | gate disabled, D5, band at next page top |
| `m20-hyperref-across-cut` | link spanning the cut | placed col=2, no nesting-level error |
| `m21-xcolor-across-band` | colour spanning the band | placed col=1 |
| `m22-fancyhdr-running-heads` | running head and foot | placed col=1 |
| `m23-figurestar-on-band-page` | `figure*[t]` on the band page | placed col=1 |
| `m24-column-floats-t-and-b` | column floats `[t]` and `[b]` | placed col=1 |
| `m25-raggedbottom` | `\raggedbottom` | placed col=1 |
| `m26-flushbottom` | `\flushbottom`, same content as m25 | placed col=1 |
| `m27-nested-minipage-d4` | request inside a `minipage` | deferred D4 `nested` |
| `m28-enlargethispage-d4` | `\enlargethispage` active | deferred D4 `enlargethispage` |
| `m29-col1-recut-always-earliest` | `recut=always-earliest` | placed col=1, `col1-recut` |
| `m30-tall-top-float` | 340pt top float covering `y_min` | placed col=2 after the float |
| `m31-footnote-inside-band` | `\footnote` inside the band | placed col=1, note at a column foot |
| `m32-holdover-footnote` | split footnote held over | deferred (D4 or D1), then placed col=0 |
| `m33-short-stratum-under-band` | bottom stratum of 32pt | placed col=1 |
| `m34-equation-number-order` | numbered display above the band | placed col=1, both numbers resolve |
| `m35-gate-kernel-mismatch` | `\@makecol` re-wrapped after load | gate disabled, D5 |

Rows of report section 6 deliberately **not** expressed: "float page appears between strata"
(cannot be provoked reliably without controlling `\@fpmin` from inside the document), "tagged PDF"
(warn-only until validated, phase 2), "baseline grid drifts below the band" and "stacked-band
decoration" (phase 2 policies with no phase-1 observable), and "kernel update changes `\@makecol`"
in the sense of a *newer kernel* (that needs latex-dev in the environment matrix, not a document).

## How to add a scenario

1. Write `tests/matrix/mNN-short-name.tex`. Use `matrix-content.tex` for prose and bands, and the
   standard geometry, unless the case needs something else — then say why in the header.
2. Put the derivation in the header comment: `h`, `S`, `R`, `B`, `y_min`, `y_max`, the fit test,
   the minimum-piece check, and the conclusion. Cite the report section.
3. Add the expectation lines, within the first 40 lines. Assert only what the specification fixes.
   `y` is deliberately not part of `WB-EXPECT-DECISION`, so no expectation has to predict it.
4. Give every paragraph, band, footnote, float and marginal note a unique token and list the ones
   that matter in `WB-EXPECT-TOKENS`. Fixed-width tokens only (`MXA07`, never `MXA7`).
5. If the baseline package behaves differently, add `%% WB-BASELINE-DIFFERS` and one comment line
   saying what the baseline does instead.
6. Run `./scripts/run-matrix.sh --only 'mNN*' --keep-going`.

## The synthetic generator

`gen-corpus.py --seed N --count M --out DIR` writes `corpus-<seed>-<index>.tex`. Documents are
self-contained: they carry their own prose (a bank of 60 real technical sentences about
typesetting, page building and numerical methods — no filler) and load only TeX Live packages.

Determinism: each document comes from `random.Random("<seed>:<index>")`. Python seeds a `Random`
from a string through sha512, so the corpus is reproducible across runs, machines and Python
versions; `hash()`, set iteration and dict ordering are never used for a choice. Verified by
generating the same seed twice, including under a different `PYTHONHASHSEED`.

Parameters varied per document:

| Parameter | Values |
|---|---|
| bands per document | 1 (40%), 2 (30%), 3 (20%), 4 (10%) |
| band height | 1 to 20 stacked `gather*` rows; one document in twelve gets a 32-row band instead, which must fail with D2 |
| request position | 2 to 24 paragraphs before the first request; 0 to 16 between later requests (0 = adjacent requests, which must stack) |
| trailing paragraphs | 10, 16, 22 or 30 |
| footnote density | none (35%), low (45%), high (20%); at high density the paragraphs immediately before and after every request carry a note |
| bottom policy | `\raggedbottom` / `\flushbottom` |
| single-column floats | 0 to 2, placement `t`, `b` or `h` |
| `figure*` | 15% |
| marginal notes | 20% of documents (these switch to the narrow geometry) |
| headings before a request | 35% per band |
| displays before a request | 30% per band |
| packages | `amsmath` always; `hyperref` 30%, `xcolor` 30%, `fancyhdr` 20% |

Band footprints `B` (band box plus 2 x 12pt separation) were measured once on TeX Live 2025
(`build/probe/probe-rows.log`) so the row counts span "a couple of lines" to "most of a column"
without straying into the size limits by accident:

| rows | 1 | 2 | 3 | 5 | 8 | 12 | 16 | 18 | 20 | 32 |
|---|---|---|---|---|---|---|---|---|---|---|
| `B` (pt) | 52 | 78 | 105 | 149 | 230 | 306 | 412 | 444 | 510 | 749 |

The baseline package refuses a band above `\textheight - 2\baselineskip` = 576pt and the stratum
core above `S` = 600pt, so 1 to 20 rows is safe for both and 32 rows fails for both. Row counts in
between (24 rows is 587pt) would be refused by one package and accepted by the other, and are
deliberately not generated.

Generated expectations: `requests=<n>`, `WB-EXPECT-COMPILE`, and `WB-EXPECT-TOKENS` for every
token (10 per line, at most 24 lines, so the header stays inside the 40-line window). Placed and deferred counts are **not** emitted, because `y_min` and `y_max` depend on where
the page builder breaks the generated prose; the audit ledger and the decision log cover those.
Any document with more than one band is marked `WB-BASELINE-DIFFERS`, because the baseline package
rejects a second pending band.

The 40% single-band share is deliberate: it keeps a useful number of documents fully strict when
the corpus is run against the baseline package.

### `--load-style`

The contract's 6.2 wording has generated documents load `\usepackage[audit]{wideband}`. The
baseline package declares no options at all, so that form aborts every run with

```
! LaTeX Error: Unknown option `audit' for package `wideband'.
```

which would make the acceptance criterion "runs end to end against the baseline package"
impossible. The default `--load-style explicit` therefore emits the other form contract 6.2
allows:

```tex
\usepackage{wideband}
\IfFileExists{wideband-audit.sty}{\usepackage{wideband-audit}}{}
```

This works with both packages and still loads the audit package whenever AUDIT has been merged.
Once the new CORE with `\DeclareKeys` is in place, `--load-style option` regenerates the same
corpus with `\usepackage[audit]{wideband}` instead. The matrix documents use the same guarded
form, except `m03` and `m29`, which pass a `recut` option on purpose and are marked
`WB-BASELINE-DIFFERS`.

## Dependency on the other workstreams

- **CORE** must emit `WIDEBAND DECISION:`, `WIDEBAND PAGE:` and `WIDEBAND GATE:` in exactly the
  contract 4.2 formats, on one line each. If CORE writes them with `\wlog` or `texio.write_nl`
  under a default `max_print_line` of 79 they will be wrapped in the `.log`; the runners set
  `max_print_line=1000` and the checker un-wraps as a fallback, but the cleanest fix is for CORE to
  raise `max_print_line` itself or to keep the lines short.
- **AUDIT** must provide `wideband-audit.sty` and `scripts/check-audit.py`. Until both exist the
  runners print `audit = SKIPPED (...)` and report `skip` in the AUDIT column.
