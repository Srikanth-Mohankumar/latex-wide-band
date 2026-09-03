# CORE workstream status (wideband v0.5, stratum model)

Branch: `worktree-agent-a47f11aaee9bf0f11`
Worktree: `/data/personal-projects/latex-wide-band/.claude/worktrees/agent-a47f11aaee9bf0f11`
Baseline commit: `67756d5`

## Done

Everything is in the single WIP commit on this branch (`WIP(core): stratum-model
output routine, partial`). Two files were rewritten from scratch:

- `wideband.sty` — v0.5, stratum model.
- `wideband.lua` — v0.5, measurement / exact cut / decision records / sidecar.

Implemented and verified by compiling:

1. **`\output` wrapper.** The kernel token list is captured with
   `\edef\wb@kernel@output{\the\output}` and the surrounding braces are stripped
   (`\the\output` returns the list wrapped in an extra `{...}`; running it
   unstripped would put the whole kernel routine in a group). `\output` becomes
   `\wb@output`, which dispatches on `\outputpenalty = -10007` and otherwise runs
   the kernel tokens verbatim, then runs `\wb@epilogue` which sets `\@colroom`
   and `\vsize` explicitly on band cycles (the kernel tail forces
   `\vsize=\maxdimen` for any penalty at or below −10004).
2. **Band request protocol.** `\end{wideband}` decorates the band, measures
   `B = ht+dp+2\wideband@sep`, moves the box into an 8-slot pool, contributes a
   `user_defined` whatsit (`user_id` 0x57424E44, value = band id) and
   `\penalty-10007`. `\directlua{if wbaudit then wbaudit.request(<id>) end}` is
   called at `\begin{wideband}`, and `\wb@attr@band` (a `\newattribute`) is set
   to the band id while the box is built and decorated.
   *Eager path*: when `\pagegoal = \maxdimen` (top of a column) TeX would discard
   the penalty, so the decision is taken immediately on the main vertical list
   instead (`\wb@eager`).
3. **Raw capture** in `build/column/before` (`\wb@capture`): copies of `\box255`,
   `\footins`, `\vbox{\pagediscards}` (with `\savingvdiscards=1`) and a
   float-attached flag, for column-1 pieces only. Inert when no band is present.
4. **Placement geometry** per report §2: `P`, `S`, `R`, `y_min`, `y_max = S−R−B`,
   fit test, `minpiece` (default 2 lines of `\baselineskip`). `h` includes the
   float space already committed to the piece (`\@colht − \@colroom − botfloats`),
   which is what stopped the `test-floats` overfull box.
5. **Column-2 re-cut**: `wideband.probe` finds the first legal vertical
   breakpoint at or after `ceil(P/2)` (TeX's own legality rules; positions summed
   by hand, never `node.dimensions`), `wideband.docut` cuts exactly there and
   prunes the discardables at the break. The tail, the *original* break's
   discards (`\wb@Ldisc`) and the old column-2 material are re-fed with the
   forcing marker; the left piece is rebuilt with `\@texttop` / depth trick /
   `\@textbottom`. `\vsize` gets `\topskip+\baselineskip` of slack for the
   re-fire cycle so the page builder cannot break before the marker.
6. **Multiple bands**: `due` / `top` / `next` record lists, stacked bands
   (a request inside a piece that already has bands below it is enqueued and the
   material re-fed), recursion into the remaining stratum, deferred bands placed
   as a zero-height first stratum at the top of the next page (`col=0`).
7. **Footnotes**: `\count\footins=0` and `\skip\footins=0pt` while filling
   non-final pieces, stash into `\wb@holdA`/`\wb@holdB`, pre-charge with
   `\insert\footins{\unvbox...}` when a final piece opens. A re-cut is refused
   (D4) unless every footnote callout of the held piece is provably above the cut
   (detected with the `\wb@attr@fnmark` attribute set around `\@footnotemark`).
8. **Assembly by strata**: rows are composed into `\wb@page` as
   `\hb@xt@\textwidth{\hb@xt@\columnwidth{piece\hss}\hfil rule \hfil
   \hb@xt@\columnwidth{piece\hss}}` with interline glue switched off, band rows as
   `\vskip sep / \hb@xt@\textwidth{band} / \vskip sep`, then `\@combinedblfloats`,
   `\@outputpage`, and the kernel's `\@startdblcolumn` loop. Page height is
   checked against `\wb@pageht` and warns on mismatch.
9. **Deferral codes** D1 (`no-room`), D2 (`oversized`, still a `\PackageError`),
   D3 (`unbreakable-range`), D4 (`enlargethispage`,
   `marginpar-in-moved-material`, `float-in-moved-material`,
   `footnotes-in-moved-material`, `nested`, `recut-disabled`, `no-raw-column`,
   `cycle-limit`), D5 (`kernel-mismatch`, `pkg-conflict-<name>`).
10. **Logs and sidecar**: one `WIDEBAND DECISION:` line per request in the exact
    contract format, `WIDEBAND PAGE:` per band page, `WIDEBAND GATE:` once at
    `\begin{document}`, and `\jobname.wideband.json` written from `wrapup_run`.
    Dimensions are formatted with TeX's own `print_scaled`, so they are
    byte-identical to `\the<dimen>`.
11. **Compatibility gate** at `\begin{document}`: `\meaning` of `\@makecol`,
    `\@opcol`, `\@specialoutput`, the saved kernel `\@outputdblcol` and
    `\the\output` compared against load-time captures, plus the conflicting
    package list (cuted, midfloat, stfloats, dblfloatfix, nidanfloat, flushend,
    balance, ftnright, fnpos, ltxgrid, lineno, multicol).
12. **Options** `recut`, `policy`, `minpiece`, `audit`, `verbose` via
    `\DeclareKeys` / `\ProcessKeyOptions`. `policy=bottom` parses and warns once.
13. **End of document**: `\AtEndDocument` forces up to 4 extra pages while a band
    is still pending, so nothing is ever dropped.

Measured results (single `lualatex` pass each, in `build/dev2/`):

| document | rc | TeX errors | `Overfull \vbox` | decisions | band pages |
|---|---|---|---|---|---|
| test-wideband | 0 | 0 | 0 | 4 | 3 |
| test-edgecases | 0 | 0 | 0 | 4 | 4 |
| test-hyperref | 0 | 0 | 0 | 1 | 1 |
| test-floats | 0 | 0 | 0 | 1 | 1 |
| test-right-column-deferral | 0 | 0 | 0 | 1 | 1 |
| test-pending-error | 0 | 0 | 0 | 2 | 1 |
| test-no-band | 0 | 0 | 0 | 0 | 0 |
| test-oversized-error | 1 (expected) | 1 | 0 | 1 (D2) | 0 |

- **Inertness verified**: `test-no-band.pdf` is pixel-identical to
  `test-no-band-ref.pdf` (PIL diff bbox `None` on both pages, 72 dpi).
- **Column-2 same-page placement works**: `test-right-column-deferral.tex`,
  which used to defer, now logs
  `id=1 page=1 col=2 stratum=1 h=130.0pt S=742.61694pt R=0.0pt B=93.53897pt
  P=872.61694pt ymin=445.993pt ymax=649.07797pt y=445.993pt result=placed
  code=OK note=col2-recut` and `PAGE: page=1 strata=2 bands=1
  heights=445.993pt,93.53897pt,203.08498pt` (sums to the full column height).
- **Stacked bands work**: `test-pending-error.tex` (two bands close together)
  logs `col1-at-h` then `stacked` and one page with
  `heights=238.0pt,62.4pt,0.0pt,62.4pt,187.20001pt`.
- **D1 deferral + top-of-page placement works**: `test-wideband.tex` band 3
  defers with `code=D1 note=no-room` and is then placed with
  `col=0 note=top-of-page` on the next page.

## In progress

Nothing is half-written; `wideband.sty` and `wideband.lua` are complete and
compile. What is *missing* is the surrounding work of contract §8, listed next.

## Next steps (ordered)

1. **Visual verification** — not yet done for the new code. Use the
   `run-wideband` skill: `pdftoppm -png -r 60` on `build/dev2/*.pdf` and look at
   the pages, especially `test-right-column-deferral.pdf` page 1 (the re-cut) and
   `test-pending-error.pdf` page 1 (stacked bands). Compile twice and confirm
   `(??)` never appears in `pdftotext` output.
2. **`scripts/run-tests.sh`** — must be updated:
   - move `test-pending-error.tex` from `expected_fail_tests` to `pass_tests`
     (several pending bands are now allowed by specification);
   - replace the `grep -q "Wideband request encountered in column 2"` check on
     `test-right-column-deferral.log` with a check for
     `note=col2-recut` (that document is now a same-page placement);
   - `export max_print_line=2000` before the `lualatex` calls — **required**:
     TeX wraps log lines at 80 columns, which splits the
     `WIDEBAND DECISION:` line. The environment variable is the only way to
     change it (`--max-print-line` and runtime Lua do **not** work; verified).
     Tell CORPUS about this, or their `check-decisions.py` will see broken lines.
   - keep the `Overfull \vbox` grep and the pixel inertness test as they are.
3. **New tests `tests/test-core-*.tex`** (contract §8): column-2 same-page
   placement, two bands on one page, stacked bands, D1 and D3 deferrals,
   footnote-in-moved-material D4, pending band at document end, gate refusing
   `cuted`. `test-right-column-deferral.tex` and `test-pending-error.tex`
   already cover the first and third cases in substance.
4. **Docs**: `README.md` (options, note vocabulary incl. the added
   `float-in-moved-material`, `no-raw-column`, `cycle-limit`,
   `top-of-stratum`→`top-of-page`/`stacked`, the `max_print_line` caveat, the
   D-code table, and the documented limitations below), `CHANGELOG.md` (the
   behavioural changes: `test-pending-error` now passes; column-2 requests are
   placed on the same page; band penalty is −10007), `docs/TEST-RESULTS.md`.
5. **Then** run `make test` and iterate.

## Known issues / deliberate gaps

- **Flush-bottom placement is not implemented.** Report §2.3 allows moving `y` to
  `y_max` when the bottom stratum would be shorter than `minpiece`. This
  implementation requires `S − y − B >= minpiece` and otherwise defers with
  `D1 no-room`. Reason: with a zero-height bottom stratum the pieces *above* the
  band become the final pieces of their columns, which changes footnote finality
  mid-decision. Worked example 6 of report §2.8 therefore reports D1 here.
- **Marks / running heads** are fed by letting `\@opcol` run per piece, so
  `first-column` / `last-column` / `page` marks come from the first and last
  *piece* in reading order rather than from a proper per-stratum feed
  (report §4.9 puts this in phase 2). Not validated.
- **Bottom floats are suppressed on band pages** (`\@botnum=0`) and float
  columns/pages are suppressed while a band is pending (`\@fpmin=\maxdimen`).
  Top floats are allowed only in the first piece-bearing stratum.
- **Re-cuts refuse any float** attached to the material involved
  (`float-in-moved-material`), because raw copies of the float boxes are not
  taken; report §4.8 wants those copies.
- **Marginal notes** are counted per page (`\marginpar` wrapper); *any*
  marginal note on the page blocks a re-cut, which is more conservative than
  "in the moved material".
- **`\wb@guard`** aborts with `D4 cycle-limit` after 40 output cycles on one
  page. If a legitimate page ever needs more, raise it.
- **The `\@floatplacement` and `\@dblfloatplacement` wrappers** append to the
  kernel macros; the gate does not check *their* meaning (it checks
  `\@makecol`, `\@opcol`, `\@specialoutput`, `\@outputdblcol`, `\output`).
- Band pool is 8 slots; a 9th simultaneously pending band is a `\PackageError`.
- `policy=bottom` parses and warns, behaves as `earliest` (as the contract
  permits).

## How to run / verify

```bash
cd /data/personal-projects/latex-wide-band/.claude/worktrees/agent-a47f11aaee9bf0f11

# compile every test document once and summarise (dev driver, gitignored)
bash build/runall.sh test-wideband test-edgecases test-hyperref test-floats \
     test-right-column-deferral test-pending-error test-no-band

# the decision lines, unwrapped, need max_print_line:
cd build/dev2 && max_print_line=2000 lualatex -interaction=nonstopmode test-wideband.tex
grep 'WIDEBAND' test-wideband.log
cat test-wideband.wideband.json

# inertness (must be a zero pixel diff)
pdftoppm -png -r 72 test-no-band.pdf a/p ; pdftoppm -png -r 72 test-no-band-ref.pdf b/p
# then PIL ImageChops.difference(...).getbbox() must be None for every page

# full suite (will fail until run-tests.sh is updated, see Next steps 2)
make test
```

Useful traps hit while writing this (all cost real time):

- **Digits cannot appear in control-sequence names.** `\newbox\wb@col2` silently
  declared `\wb@col` and typeset a stray `2` in the preamble, which started the
  document early. All identifiers here are letters-only for that reason.
- **`\the\output` includes an extra pair of braces**; strip them with a `\long`
  macro (the kernel token list contains `\par`).
- `\wb@placed{\wb@d@note}` made `\wb@d@note` self-referential and hung the run;
  use `\wb@placedkeep` when the note is already stored.
- Register numbers must be captured with `\the\allocationnumber` right after
  `\newcount` / `\newdimen` / `\newattribute` — `\number\wb@foo` gives the
  *value*. (`\newattribute` does set `\allocationnumber`.)
- Adding a debug `\message` right after `{%` puts it inside the comment.
