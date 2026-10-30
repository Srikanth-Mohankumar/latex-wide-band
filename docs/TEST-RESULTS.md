# Test results

## Continuous-Column v0.10 release candidate

Run `make test-cc` (or `./scripts/run-cc-tests.sh`). The gate builds in
`build/cc-tests` and currently covers all 59 `tests/stress/stress-*.tex`
documents.

Each document is compiled twice. The gate fails on a LuaLaTeX error, an
`Overfull \vbox`, an unresolved `(??)` reference, a missing/duplicated
`\Par{...}` token, a missing/duplicated uppercase stress label, or a mismatch
with an explicit body-word count declared by the fixture. This last check is
important because a paragraph tag can survive even when the end of its body is
dropped at an output-routine boundary. An explicit `N pages` promise in an
assertion banner is also enforced through `pdfinfo`.

The package-loaded no-band fixture is raster-compared against the same source
with `wideband-cc` removed; every pixel must match.

The gate also performs an installed-layout regression: `wideband-cc.sty` and
`wideband-cc.lua` are placed in a separate TEXMF-like directory while the test
document is compiled elsewhere. This proves that the Lua companion is found via
kpathsea rather than the process working directory.

Representative pages are rendered under `build/cc-tests/renders/` for visual
inspection. The current review set covers the seven-band user-reported document
and a full-page band.

Elsevier page-top adapter fixtures (`[elsevier]`), on NeoPage host stand-ins:

- `stress-elsevier-adapter-safe-top` / `-fullpage-safe-top`: ordinary and
  `fullpage` bands start a new page in the full-width top area (red before
  v0.10: the ordinary band stayed on page 1, `fullpage` made its own page).
- `stress-elsevier-adapter-band-at-document-end`: a final band still ships its
  own page (red before v0.10).

Manual-mode (default) fixtures. A stress document may declare
`%% EXPECT-ERROR: <text>` lines: the gate then requires each operator error and
fails on any other `!` line. The eight fixtures that defer or hold back a band
on purpose now declare their operator errors.

- `stress-neopage-host-same-page`: on a NeoPage stand-in host `auto` installs the
  engine and places the band on its page (replaces the two detection fixtures,
  `-public-interface` and `-load-before-host`, whose contract — `auto` picks
  page-top on NeoPage — was withdrawn).
- `stress-band-after-host-routine-swap`: a band after the host put back its own
  `\@outputdblcol` (as `\lastpagebalance` does) is set page-top with an error
  (red: the band was lost).
- `stress-band-protruding-row-is-shed`: unsplittable material taller than the
  row under a band: the band is taken off that page and reported (red: 117pt
  Overfull \vbox).
- `stress-band-page-enlarged`: `\enlargethispage` on the band's page; the band is
  placed there and the page is 20pt taller (red: band never placed, an extra
  page at the end).

### Live article `AA_9001` (2026-10-28)

Article `AA_9001` was copied from
`/data/neopage/.temporary/els-live-sample/AA_9001/process_folder` to
`/data/neopage/.temporary/wideband-aa9001-review-20261028/runs/<variant>`
and compiled with two LuaLaTeX passes against the current `/app/lamput`
(`development`). The baseline was rebuilt the same way, not taken from the
stored PDF. One run per variant on one machine.

- Package loaded with no band (`auto` after the template, `auto` before the
  template, explicit `[elsevier]`): adapter selected in all three; 16 pages;
  identical error/overfull/underfull/warning counts; all 16 pages
  pixel-identical at 100 dpi; `.FN`, `.fwh`, `.apg`, `-apg.xml` byte-identical.
- One band after section 5 (`auto`, `[elsevier]`, package before template,
  `fullpage`): 16 pages, no errors, overfull counts unchanged, underfull vbox
  34 → 33. All alphanumeric text conserved after subtracting the band. All 75
  heading lines in identical reading order (coordinate-based check); the band
  tops page 5 between "5. Footnotes" and "6. Display quotes". Footnotes 3–6
  present once, callout and note on the same page. `\columnwidth` unchanged
  (253.19998pt) across the band. Page 4's right column is left empty.
- Three bands (before sections 3 and 6 and before "Ethical Approval"): same
  results; each band tops the page after its preceding text. A table that the
  baseline split across pages 2–3 no longer splits, so its continuation header
  disappears (the only text difference).
- Floats stayed on their baseline pages (Figs 1–2 p7, Table 1 p8, Box 1 p12),
  but their callout section moved from p6 to p8, so Figs 1–2 now precede
  their first citation. The reused `satellite.json` schedule was computed
  without the bands; a full-workflow run with bands present is still required.

### Elsevier corpus (2026-10-28)

All 55 `regression-check/elsevier` articles were built as a baseline, with the
package loaded and no band, and with three automatically inserted bands under
each adapter. Package-loaded output with no band was pixel- and
sidecar-identical on all 54 articles whose baseline compiles. Band results
(single-pass manual mode, and the earlier two-run page-top runs) and the
remaining issues are in `docs/PRODUCTION-READINESS.md`. Single-pass runs:
`run-article-single.sh`, `analyse-single.py`. The slot-0 crash fix was checked on
EJMFLU_204268: "Missing number" errors with the package before the fix, none
after; no small kernel-class document reproduced the overshoot, so it has no
stress fixture (all 54 stress outputs were pixel-identical before and after). Working files:
`/data/neopage/.temporary/wideband-prod-20261028/` (`make-variant.py`,
`run-article-final.sh`, `analyse.py`, `summarise.py`).

## v0.5 stratum model

Run `make test-stratum` (or `./scripts/run-tests.sh`) to reproduce the core checks
(export `max_print_line=2000` first). The scenario matrix is
`./scripts/run-matrix.sh --keep-going` and the synthetic corpus is
`./scripts/run-corpus.sh --seed 1 --count 30`.

## `make test-stratum` (core regression)

`make test` passes. It verifies:

1. Column-1 same-page insertion and the column-2 **same-page re-cut**
   (`note=col2-recut` on `test-right-column-deferral.log`) — column 2 is no
   longer deferred to the next page.
2. Several pending bands are allowed: `test-pending-error.tex` now compiles and
   stacks the two bands (it was fail-expected under Option A).
3. An oversized band is still an explicit `\PackageError`
   (`test-oversized-error.tex`, fail-expected).
4. Exactly-once PDF-text occurrence of the unique tokens around the band.
5. Hyperref / equation-reference compilation.
6. Pixel-identical output when the package is loaded but unused (inertness).
7. PDF page-bound checks and no overfull vertical boxes in the core logs.
8. No synthetic `lipsum` content in the regression sources.

## Scenario matrix (`run-matrix.sh`)

34 of 35 scenarios pass. The one remaining failure is a documented limitation:

- **m28 (`\enlargethispage`)**: the band correctly defers with `D4
  enlargethispage`, but the audit's `geometry-textarea` check uses a fixed text
  area and cannot see the page enlarged by `\enlargethispage`, so it flags the
  enlarged page. This is a general audit limitation (a plain `\enlargethispage`
  document would also trip it), not specific to wideband.

Four scenarios are marked `%% WB-BASELINE-DIFFERS` and record the honest phase-1
outcome rather than the phase-2 ideal (see `docs/integration-triage.md`):

- **m06** flush-bottom placement is not implemented (defers `D1`, then top of
  page 2).
- **m08** the col2-empty (`h=0`) case is not reproducible on the 12 pt grid, so
  the request is a column-1 re-cut.
- **m22** fancyhdr's benign `\@makecol` wrap trips the conservative gate, so the
  band defers with `D5 kernel-mismatch` (wideband is functionally compatible
  with fancyhdr; the `\meaning`-based gate is conservative).
- **m30** the re-cut refuses a float in the moved material (`D4
  float-in-moved-material`) because phase 1 takes no raw copies of float boxes.

## Synthetic corpus (`run-corpus.sh`)

The ledger is clean (no lost, duplicated, misordered, or footnote-misplaced
content) across the generated documents. One geometry limitation remains: a
band deferred to a page that also carries a double-column top float
(`figure*[t]`) under `\flushbottom` overflows the type area by the float height,
because the top-band reservation does not yet account for the double float.
Content is not lost.

Unsupported combinations such as tagged PDF and column-balancing packages remain
warnings (or a `D5` gate refusal) rather than compatibility claims.
