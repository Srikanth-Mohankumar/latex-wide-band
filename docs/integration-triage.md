# Integration triage: stratum-v0.5, iteration 1

Branch `integration/stratum-v0.5` merges the three workstream branches (core a131973, audit 2847a61,
corpus 60b7da7..69921d2) cleanly. Results of the full run (with `max_print_line=2000` exported):

- `make test`: fails on one point only, `test-pending-error` now compiles (multiple bands are allowed
  by spec) but `scripts/run-tests.sh` still lists it fail-expected. Runner not yet updated.
- `scripts/run-matrix.sh`: 11 pass / 24 fail of 35. The core same-page mechanism works for the
  central cases: m01 col1 mid-column, m04 col2 fits, m09 re-cut across a heading, m10 two bands,
  m12 band at page start, m20 hyperref across the cut, m21 xcolor across the band, m23 figure* on a
  band page, m25 raggedbottom, m26 flushbottom, m34 equation-number order. Failures are specific and
  localized, below.
- `scripts/run-corpus.sh --seed 1 --count 30`: first document fails only on the ymax sentinel
  invariant (item F), not on layout.

## Real defects (content or geometry), all in `wideband.sty`/`wideband.lua`

**A. Deferred band at top of next page overflows the type area by the band height B.** 12 documents
(m03, m05, m06, m07, m14, m15, m17, m19, m22, m27, m30, m35). The audit reports
`geometry-textarea FAIL edge=bottom by=(B−0.5)pt` on the `col=0 note=top-of-page` page; the rendered
m03 page 2 shows the columns hanging below the text area. Root cause: the `\@colht -= B` applied in
`\wb@after@page` (via the `build/page/after` hook) does not persist to the next page's first cycle,
so `\wb@ensurepage` sets `\wb@S = \@colht = \textheight` (not `\textheight − B`) and `\wb@pageht =
\textheight + B`; the columns under the band are then built B too tall. The architecture doc
(section 4, kernel fact 3) warned the adjustment must take effect after `\@outputpage` resets
`\@colht`. Fix so the deferred page's columns are built at `\textheight − ΣB`; verify by rendering
m03 page 2 and by the audit `geometry-textarea` check passing.

**B. Column-1 and column-2 re-cut drops the top piece (`\wb@cuttop`).** m02, m08, m29 (col1 re-cut)
and the col2 re-cut family. The left piece above the band, built into `\wb@Lpiece` from `\wb@cuttop`
in `\wb@docut`, is not emitted into the assembled page: rendered m02 page 1 starts at token MXA24,
so MXA01–MXA23 are gone; the audit reports `ledger-unique lost=23` and the token check reports the
missing tokens count 0. This is content loss and the most serious failure. Fix so the top piece is
emitted as the left piece of the re-cut stratum; verify by ledger-unique clean and every unique
token present exactly once.

**C. Short stratum under a band ships zero pages (total content loss).** m33 (band at h=478, B=90,
32 pt stratum below). The decision line is written (`placed col1-at-h`) but no page is ever shipped:
the log ends `WBAUDIT SUMMARY: pages=0 lines=0` and `no pages of output`, so the whole document is
lost and no PDF is produced. The short-stratum path fails to trigger a ship and the end-of-document
flush does not recover it. Fix so a band whose lower stratum is short still ships, and the
end-of-document guard forces a page if one is pending; verify m33 produces a PDF with every token.

**D. Stacked bands violate reading order and double-emit.** m11: band 1 requested at h=142 is placed
at y=82 (above its own request, so pre-request text would fall below it), band 2 emits two
`result=placed` lines, and an `Overfull \vbox (16.84pt)` occurs. Fix the multi-band-in-one-column
path so each band places at y ≥ its request position and emits exactly one placement.

**E. Column floats on a band page overflow.** m24: `Overfull \vbox (100.05pt too high)`. R is
computed in the decision (R=106.11) but the reserved float space is not subtracted from the built
piece heights during assembly. Fix so the assembled column height accounts for R.

## Logging / expectation mismatches (not content bugs)

**F. ymax sentinel for non-geometric deferrals.** For D2 (oversized), D5 (gate disabled), and D4
`nested`, the decision line logs `S=0 R=0 B=… ymax=0`, and the checker's invariant `ymax = S − R − B`
then fails (0 vs −B). Contract 4.2 says inapplicable fields use `-`, which the checker already
skips. Fix in core: emit `S=- R=- ymin=- ymax=-` (keep `B`) when no feasible interval was computed
(stratum=0 gate/oversized/nested and any deferral before geometry). Clears m18, m19, m35 and the
corpus doc-1 failure.

**G. Note vocabulary.** `float-in-moved-material` (m30) is outside the contract 4.2 vocabulary; add
it to the vocabulary list in `README.md` (it is a legitimate phase-1 D4 sub-reason).

**H. Audit excludes running heads.** m22 (fancyhdr): the bounds check flags the running-head words
`Stratum`/`model` as outside the type area. The audit `geometry-textarea` check must exclude kind-4
(running head/foot) material, and `check-pdf-bounds.py` is a shared checker so the matrix should not
run it on a document whose head sits in the margin by design; exclude head/foot in the audit and
mark m22 accordingly.

## Genuine feature gaps (mark xfail, do not fake a pass)

- **m06 flush-bottom placement**: a col2 request whose only fit is at `y_max` (empty stratum below)
  must place flush at the bottom; core currently defers D1. This is report section 2.3 `policy`
  behaviour, not yet implemented. Mark the scenario `%% WB-BASELINE-DIFFERS` / xfail and list it as
  remaining phase-2 work.
- **m28 enlargethispage on a col1-at-h placement**: the D4 `enlargethispage` guard currently only
  covers the re-cut path; extend it to any same-page placement, or mark xfail and document.
- **m30 tall-top-float**: phase 1 refuses floats in moved material (D4 `float-in-moved-material`);
  the scenario expected a placement. Adjust the expectation to the phase-1 D4 outcome.
- **m08 col2-empty**: the scenario triggers a col1 re-cut, not a col2 placement; re-examine whether
  the request position matches the intended "column 2 still empty" case.

## Robustness

- **m18 oversized**: the `\PackageError` fires (correct) but one LuaTeX pass segfaulted. Expected-fail
  overall, but a clean error is preferable to a crash; investigate if cheap.

## Assignment

All of A–G and the m18 crash are `wideband.sty`/`wideband.lua` (plus `README.md`, `run-tests.sh`),
owned by CORE. H is split: audit exclusion in `wideband-audit.lua` (AUDIT), matrix wiring in
`run-matrix.sh` (CORPUS). The feature-gap xfays are `tests/matrix/*` (CORPUS). This pass is driven as
one core fix agent on the integration branch, with the small audit/corpus adjustments folded in by
the integrator afterwards.

## Iteration 1 outcome and remaining work

The matrix went from 11/35 to 34/35 and `make test` passes. Fixes landed:

- **A** deferred-page column reservation (survives `\@doclearpage`); also fixed
  m13 (empty bottom stratum) and the trailing-stratum height via the same
  `\wb@capture` re-assertion used by **C**.
- **B** column-1 re-cut keeps its top piece (force second-column mode on re-fire).
- **C** short/empty trailing strata ship; end-of-document flush of an open page.
- **D** stacked bands via `\wb@eagerstack`, one placement line each, `y=0`.
- **E** column bottom floats migrate to the last piece; exact top-float height.
- **F** `S/R/ymin/ymax = -` for pre-geometry deferrals (D2/D5/D4-nested).
- **G** decision-log note vocabulary in `README.md` (+ the phase-1 extensions in
  `check-decisions.py`).
- **H** m22: the audit already excludes kind-4; the real blocker was the gate,
  now recorded as a `D5 kernel-mismatch` deferral (fancyhdr's `\@makecol` wrap).
- A shared column-2 deferral content-loss bug (`\wb@dodefer` fed back the wrong
  box) fixed m05, m07, m14, m15, m16, m17, m32.
- m31 band-footnote extraction; m18 oversized error no longer crashes LuaTeX.

### Remaining

- **m28** (`\enlargethispage`): the band correctly defers `D4 enlargethispage`
  (clean ledger), but `geometry-textarea` uses a fixed text area and flags the
  enlarged page 1 — a general audit limitation (a plain `\enlargethispage`
  document trips it too). Recorded as a matrix **XFAIL** via a `%% WB-KNOWN-XFAIL`
  marker (see `run-matrix.sh`; `--strict` still treats it as a hard failure).
  Modelling `\enlargethispage` in the audit is phase-2 AUDIT work.
- **m06** flush-bottom placement (report 2.3) — phase-2 policy; currently `D1`.
- **m08** the col2-empty (`h=0`) case is not reproducible on the 12 pt baseline
  grid (a full column is never an exact line multiple); exercises col1-recut.
- **m22** wideband is functionally compatible with fancyhdr, but the
  `\meaning`-based gate cannot distinguish a benign `\@makecol` wrap from a
  harmful one and conservatively refuses (`D5`). Distinguishing them is phase-2.
- **m30** re-cut across a float in the moved material (report 4.8, raw float
  copies) — phase-2; currently `D4 float-in-moved-material`.
- **Corpus**: a band deferred to a page that also carries a `figure*[t]` double
  float under `\flushbottom` overflows by the float height (the top-band
  reservation does not yet account for the double float). No content is lost.

## Integrator independent verification (2026-09-04, after the 16-commit fix pass)

Re-ran all three suites from a clean tree on `integration/stratum-v0.5`:

- `make test`: PASS (inertness pixel test and token accounting included).
- Matrix: 34/35 pass. Only `m28` fails.
- Corpus (`--seed 1 --count 30`, 30 documents): 29 clean, 1 fails (`corpus-0001-0008`).

Every content-integrity check passes across the entire suite: `ledger-unique` clean
(no lost, no duplicated), `ledger-order` clean, and token accounting exact on all
make-test, matrix and corpus documents. The two residual failures are geometry-only,
both with `lost=0`:

- **m28** — NOT a wideband defect. The band correctly defers `D4 enlargethispage` and
  is placed at the top of page 2; `ledger-unique ok created=68 shipped=68`. The audit's
  `geometry-textarea` check uses a fixed text-area rectangle and flags the deliberately
  enlarged page-1 content (14.34pt); a plain `\enlargethispage` document with no band
  trips it too. AUDIT phase-2 limitation. Recommended: mark m28 xfail with this reason.
- **corpus-0001-0008** — a real but narrow geometry defect. Two tall bands (B=330.7pt and
  B=103.1pt) are both deferred and both placed at the top of page 2; each top-of-page
  reservation is computed against the full column height independently, so the combined
  bands plus columns overflow the text area by ~80pt. No content lost
  (`ledger-unique ok created=156 shipped=156`). Fix: the top-of-page reservation must sum
  ALL bands queued to the same page (build columns at textheight − Σ top-band B).

## Known content-integrity bugs remaining after iteration 2 (found 2026-09-04)

Independent verification with `run-corpus.sh --seed 1 --count 30 --keep-going` is 28/30 (an
earlier report of "29/30 content-clean" was wrong: it was run WITHOUT `--keep-going`, so it
stopped at the first failure and never reached these). Both remaining failures are in the
3-band-deferral path and are genuine violations of the core guarantee, NOT geometry:

- **corpus-0001-0023: a band is dropped (content loss).** Three bands are requested; ids 1 and 3
  defer and are placed top-of-page, but **band id=2 gets no `WIDEBAND DECISION` line and never
  ships** (`band-order FAIL band=2 never-shipped`). Its equation and `\label` are lost, which will
  also produce `(??)` references. The line ledger is clean (`lost=0`); it is the band box that is
  dropped.
- **corpus-0001-0024: a band is misordered.** All three bands ship, but band id=2 lands out of
  reading order (`band-order FAIL band=2 seq=83`), i.e. content it should follow appears after it.

`--seed 2 --count 60` is 48/60, a similar cluster of pre-existing multi-band/footnote defects.
These are the top items for iteration 3: the multi-band-deferral queue drops or misorders the
middle band when three or more bands defer across pages. `make test` (green) and the 34/35 matrix
do not exercise three deferred bands, which is why the scenario matrix did not catch this; add a
matrix scenario for it.
