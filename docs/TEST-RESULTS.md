# Test results — v0.5 stratum model

Run `make test` (or `./scripts/run-tests.sh`) to reproduce the core checks
(export `max_print_line=2000` first). The scenario matrix is
`./scripts/run-matrix.sh --keep-going` and the synthetic corpus is
`./scripts/run-corpus.sh --seed 1 --count 30`.

## `make test` (core regression)

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
