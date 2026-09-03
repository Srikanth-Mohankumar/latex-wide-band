# AUDIT workstream status

Branch `worktree-agent-a8190bfc1dd45cb97`, worktree
`/data/personal-projects/latex-wide-band/.claude/worktrees/agent-a8190bfc1dd45cb97`.

## Done

All in the single commit on this branch (`WIP(audit): material ledger package`).

- `wideband-audit.sty` — attributes (`\wbaudit@attr@seq`, `@kind`, `@fn`, and a
  private `@frame`), `json`/`verbose` key options, callback registration,
  narrow kernel patches (`\@floatboxreset`, `\@marginparreset`,
  `\@footnotemark`, `\@footnotetext`, hooks `build/page/before` and
  `build/page/reset`), `\everydisplay` appended, per-page text-area geometry.
- `wideband-audit.lua` — all state in `wbaudit.state`; sequence ids in
  `post_linebreak_filter` and `\everydisplay`; `wbaudit.request(bandid)`;
  a hand-written page walk with TeX's own cumulative glue rounding, discretionary
  `replace` lists and a `node.dimensions` self-check; the six contract checks;
  `\jobname.wbaudit.json` sidecar.
- `scripts/check-audit.py` — parses the records, exits 1 on a missing summary,
  `fails>0`, a FAIL/summary mismatch, a `WBAUDIT ERROR`, or a never-reported
  check; `--json` writes the parsed report.
- `tests/test-audit-inert.tex` + `tests/test-audit-inert-ref.tex` — differ only
  in the `\usepackage` line; **verified pixel-identical over 3 pages**. Doubles
  as the plain two-column acceptance document (footnotes, column float,
  `figure*`, marginal notes, `equation`, `align`): `fails=0`.
- `tests/test-audit-broken.tex` — negative control, sabotages its own pages;
  reports `ledger-unique FAIL dup=1 lost=1` and `check-audit.py` exits 1.
- `docs/AUDIT.md` — attributes, the six checks with their blind spots, the
  kernel patches and their graceful degradation, the ruler self-check,
  inertness, how to run, limits.

## In progress

Nothing half-written. Every file above is complete and was exercised.

## Next steps, in order

1. Re-run the acceptance sweep after any change: copy `tests/*.tex` into
   `build/audit/`, insert `\usepackage{wideband-audit}` after
   `\documentclass` in the copies, compile twice, run `check-audit.py`
   (`build/audit/drive.py`, gitignored, does this and is a good starting
   point — it is deliberately not checked in, since `scripts/` is not this
   workstream's to extend beyond `check-audit.py`).
2. Exercise the band checks. They are inactive on the baseline (no
   `wb@attr@band`, no `wbaudit.request`). As soon as CORE sets the attribute
   and calls `\directlua{if wbaudit then wbaudit.request(<id>) end}`, verify
   `band-order` and `geometry-band-width` on a band document, including a
   deferred band and a band that never ships.
3. Consider a one-column and a `twoside` smoke document
   (`\@themargin` parity and the disabled column test in `footnote-place` are
   implemented but only reviewed, not yet run).
4. Feed the `WBAUDIT` records to CORPUS's `run-matrix.sh` once it exists.

## Known issues

- **Two baseline documents fail on purpose, and the failures are real.** On
  every page where the baseline `wideband` places a band mid-page
  (`test-wideband` p1, `test-edgecases` p1-p4, `test-hyperref` p1,
  `test-floats` p1):
  - `ledger-order FAIL` — the baseline fills column 1 to full height across
    the band's reserved gap, so the material immediately following the request
    lands *below* the band while later material lands *above* it in column 2.
    Verified on `test-wideband` p1: content order is
    `L-top 1..24, R-top 33..56, band(25), L-bot 26..32, R-bot 57..63`, so the
    page reads 1..24, 33..56, band, 26..32 — a reading-order violation of
    report section 1 / 2.1, which the stratum core is specified to fix.
  - `geometry-textarea FAIL edge=bottom by=8.7..13.2pt` — the assembled band
    page is that much taller than `\textheight` and the overflow is hidden by
    the trailing `\vss`. Verified against `pdftotext -bbox` (agreement 0.05pt).
  These are the contract's "fails=0 on every baseline test document"
  requirement that could not be honoured; see the final report. Every non-band
  page of those documents passes, and `test-no-band`,
  `test-right-column-deferral` and `test-audit-inert` are `fails=0`.
- `test-baseline.tex` (which loads `cuted`, not `wideband`) fails
  `geometry-textarea` on its strip page by 0.50pt: the last body baseline is
  1.0pt below the text area. Also verified against the PDF. `cuted`'s
  arithmetic, not this repository's.
- The summary is written from `enddocument/end`; `wrapup_run` cannot write to
  the transcript on LuaTeX 1.22 (it runs after the log is closed). Documented
  in `docs/AUDIT.md`.
- `ledger-unique` cannot see band content on the baseline (the band attribute
  is CORE's). A dropped band is therefore invisible until CORE sets it.

## How to run / verify

`docs/AUDIT.md`, section "How to run", has the exact commands (build in
`build/audit/`, never in the repository root). The three quick ones:

```sh
cd build/audit && ../../scripts/check-audit.py test-audit-inert.log    # exit 0
cd build/audit && ../../scripts/check-audit.py test-audit-broken.log   # exit 1
# plus the pdftoppm + PIL inertness comparison in docs/AUDIT.md
```
