# Implementation status and how to resume

Written 2026-09-03 while the first implementation session was being stopped so it can be restarted
with a permissive permission mode. Three Opus subagents were working in parallel on isolated git
worktrees under `.claude/worktrees/`; each was asked to commit its work in progress on its own
branch and to leave a `STATUS.md` in its worktree root.

| Workstream | Worktree | Branch |
|---|---|---|
| CORE (stratum output routine: `wideband.sty`, `wideband.lua`) | `.claude/worktrees/agent-a47f11aaee9bf0f11` | `worktree-agent-a47f11aaee9bf0f11` |
| AUDIT (`wideband-audit.sty/.lua`, `scripts/check-audit.py`) | `.claude/worktrees/agent-a8190bfc1dd45cb97` | `worktree-agent-a8190bfc1dd45cb97` |
| CORPUS (`scripts/gen-corpus.py`, `scripts/run-matrix.sh`, `tests/matrix/`) | `.claude/worktrees/agent-a6f87344366c50f36` | `worktree-agent-a6f87344366c50f36` |

Binding documents (untracked in the main working tree, keep them):

- `docs/research-multiband-architecture.md`: the design (geometry, deferral codes, phases).
- `docs/implementation-contract.md`: file ownership, package options, log formats, audit
  interface, test expectation syntax, definition of done.

## Workstream reports received before the stop

**CORPUS: complete and committed** (3 commits on its branch, clean tree). `scripts/check-decisions.py`
(with `--selftest`), `scripts/run-matrix.sh`, `scripts/gen-corpus.py`, `scripts/run-corpus.sh`,
35 scenarios in `tests/matrix/` (m01–m35) with spec-derived expectations, `docs/CORPUS.md`.
Against the baseline package: `run-matrix.sh --keep-going` exits 0 with 14 pass, 10 expected
failures, 11 unexpected passes; `run-corpus.sh --seed 1 --count 30` exits 0. Baseline defects the
corpus surfaced (to be fixed by CORE): reservation kern discarded when the marker lands at a column
top (m02, m08); deferred band dropped when no page follows (m14); band dropped under
`\enlargethispage` (m28) and inside a `minipage` (m27); footnote inside a band trapped in the box
(m31); `--seed 2 --count 60` document 52 gives an overfull vbox with `figure*[t]` plus column floats
and a 510 pt band under `\flushbottom`. Contract deviations: documents load
`\usepackage{wideband}` plus a guarded `\usepackage{wideband-audit}` because the baseline package
rejects options (`gen-corpus.py --load-style option` switches to the option form once CORE parses
keys); the audit column is skipped until AUDIT is merged; m06 is a boundary case where a strict
two-line minimum gives D1 instead of "placed at y_max".

**CORE: Phase 1 implemented, committed (a131973), not yet finished.** `wideband.sty` and
`wideband.lua` rewritten (v0.5): `\output` wrapper with band penalty −10007, raw piece capture in
`build/column/before`, geometry per report §2, column-2 same-page placement by exact Lua re-cut with
discards restoration and forcing-marker re-feed, stacked bands, D1 deferral with top-of-next-page
placement, D1–D5 codes, decision/page/gate lines, sidecar JSON, footnote `\count`/`\skip` switching
with re-insertion, compatibility gate, options, end-of-document flush, `wbaudit.request` call,
`\wb@attr@band`. All test documents compile with zero errors and zero overfull vboxes; inertness
pixel test passes. Lead's visual check of `build/dev2/test-right-column-deferral.pdf` page 1 (column-2
re-cut at y = 445.99 pt) and `build/dev2/test-pending-error.pdf` page 1 (two stacked bands): both
pages are typographically sound, pieces above the bands end at the same height, reading order runs
left-top, right-top, bands, left-bottom, right-bottom, paragraphs continue correctly across the band.
Open items (see the worktree's `STATUS.md`): `scripts/run-tests.sh` not updated (`test-pending-error`
must become pass-expected, the column-2 grep must become `note=col2-recut`, and `max_print_line=2000`
must be exported because TeX wraps the decision lines at 80 columns); no `tests/test-core-*.tex`
yet; README, CHANGELOG, TEST-RESULTS not updated; flush-bottom placement at y_max not implemented
(defers with D1 instead); re-cuts refuse pieces with attached floats because raw float-box copies are
not taken; any marginal note on the page blocks a re-cut; bottom floats and float pages suppressed on
band pages. The corpus-found baseline defects (m02, m08, m14, m27, m28, m31, seed-2 document 52) have
not been re-checked against the new core.

**AUDIT: complete and committed (2847a61).** `wideband-audit.sty`, `wideband-audit.lua`,
`scripts/check-audit.py`, `tests/test-audit-inert*.tex`, `tests/test-audit-broken.tex`, `docs/AUDIT.md`.
Checks implemented as in the contract: `ledger-unique`, `ledger-order`, `band-order`,
`footnote-place`, `geometry-textarea` (ink may extend `\@maxdepth` below the text area, like TeX's own
page-depth limit), `geometry-band-width`. The horizontal walk is self-verified against
`node.dimensions`, the vertical walk was calibrated against `pdftotext -bbox` (0.05 pt agreement).
Inertness proven (3 pages pixel-identical); the negative control fails as intended. Baseline results:
`fails=0` on `test-no-band`, `test-right-column-deferral` and a plain document with footnotes, column
float, `figure*`, marginal notes and displays. Two true positives against the *baseline* package:
`ledger-order` fails on baseline band pages because v0.4 fills column 1 to full height across the
reserved gap, so text after the request lands below the band while later text lands above it in
column 2 (reading-order inversion, exactly what the stratum core fixes); `geometry-textarea` fails by
8.7–13.2 pt on baseline band pages whose assembled height exceeds `\textheight` behind a trailing
`\vss`. Deviation: the summary line is written from the `enddocument/end` hook because LuaTeX 1.22
closes the transcript before `wrapup_run`; `check-audit.py` accepts the summary anywhere in the log.
Band checks are untested against a real band until CORE is merged (the "requested but never shipped"
path is implemented but unexercised).

## Resuming in a new session

1. Read `docs/implementation-contract.md`, then each worktree's `STATUS.md` and `git log`.
2. Continue each workstream from its own worktree and branch (enter the existing worktree; do not
   create new ones). Reuse the definitions of done in the contract, section 8.
3. Integration: merge the three branches into an integration branch, run `make test`,
   `scripts/run-matrix.sh` and `scripts/run-corpus.sh --seed 1 --count 200`, send failures back to
   the owning workstream, repeat until green.

Baseline facts: `master` at 67756d5 passes `make test` in about 8 s; LuaHBTeX 1.22.0 and
LaTeX2e 2025-06-01 are installed; `origin/master` equals the local `master`.
