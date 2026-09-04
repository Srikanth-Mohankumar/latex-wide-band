# wideband-audit: the material ledger

`wideband-audit` is a LuaLaTeX package that proves a document lost, duplicated,
misordered or misplaced nothing. It gives every line box, every display and
every footnote an identity, walks each shipped page in content order, and
writes one record per check to the transcript. It works on a plain two-column
article, alongside the `wideband` package (baseline or new core), and it may
not change layout.

It implements section 5 of `docs/implementation-contract.md` and the validation
strategy of `docs/research-multiband-architecture.md` section 7. Deviations from
the contract are listed under [Limits](#limits).

## Loading

```latex
\usepackage{wideband-audit}                      % JSON sidecar on
\usepackage[json=false]{wideband-audit}          % no sidecar
\usepackage[verbose]{wideband-audit}             % extra WBAUDIT INFO: lines
```

LuaLaTeX only. Nothing else is required; the package uses only the format's own
`ltluatex` layer (`\newattribute`, `luatexbase.registernumber`,
`luatexbase.add_to_callback`).

## Output

One record per check, per page or per document:

```
WBAUDIT: <check> ok|FAIL|skipped <details>
```

and, after the last page:

```
WBAUDIT SUMMARY: pages=<n> lines=<n> bands=<n> footnotes=<n> fails=<n>
```

`lines` counts distinct sequence ids that reached a page, `bands` the band ids
seen, `footnotes` the footnotes whose text was shipped, `fails` the number of
`FAIL` records. Records are kept under 78 characters because TeX wraps log
lines at `max_print_line`.

With `json` (the default) the run also writes `\jobname.wbaudit.json`: the
summary, the patch status, the `FAIL` lines, and per page the text-area
rectangle and the `[seq, kind, x, y]` of every ledger entry in content order.
That file is the fastest way to see *why* an order check failed.

## Attributes

Registered with `\newattribute`; the names are part of the contract.

| Attribute | Set where | Meaning |
|---|---|---|
| `\wbaudit@attr@seq` | `post_linebreak_filter` (every line box) and `\everydisplay` (every display box) | sequence id, in creation order |
| `\wbaudit@attr@kind` | `\@floatboxreset` (1), `\@footnotetext` (2), `\@marginparreset` (3), the `build/page/reset` hook (4) | 0 body, 1 float, 2 footnote, 3 marginal note, 4 running head or foot |
| `\wbaudit@attr@fn` | `\@footnotemark` and `\@footnotetext` | footnote id, shared by the mark and the text |
| `\wbaudit@attr@frame` | `build/page/before` hook, on `\@outputbox` | private: marks the body box so the walk can measure the text area |
| `\wb@attr@band` | the `wideband` core (not by this package) | band id; looked up with `luatexbase.registernumber("wb@attr@band")`, and a missing attribute means "this document has no bands" |

LuaTeX gives a node the attributes that were in force when it was created, so
tagging the kernel's reset macros tags whole floats, footnotes and marginal
notes, including their captions and their line boxes. The walk therefore reads
each node's *own* kind and never inherits one from an enclosing box: the page
box built inside `\@outputpage` carries kind 4 as well, and inheriting from it
would mark the whole page as running head.

Lua global `wbaudit`, called by the core: `wbaudit.request(<bandid>)` records
the current highest sequence id as that band's request position.

### Main-list ids

Each id also records whether it was created on the *main vertical list*
(`tex.nest[...].mode == 1`). Only such material is required to reach a page:
anything built inside a box may legitimately be discarded — the kernel
typesets both variants of a two-sided `\marginpar`, `amsmath` measures
alignments, `\sbox` throws material away. Ids created inside a box (float,
footnote, marginal note, `minipage`, `\parbox`, a `wideband` band body) are
therefore excluded from the order checks but still watched for duplication.

## Checks

| Check | What it proves | Blind spots |
|---|---|---|
| `ledger-unique` (per document) | Every id created on the main vertical list, in a float or in a footnote reached a page, and no id was shipped twice. Catches lost, dropped and duplicated material. | A display id that appears on several sibling boxes of one page (alignment rows) counts once; such an id is only a duplicate when it reaches two pages. Ids created inside a box are not required to ship, so a *float* whose box is silently dropped is caught (kind 1) but a `minipage` that vanishes is not. Band content is only tracked through `wb@attr@band`, so on the baseline package a dropped band is invisible here — `band-order` is the check for that, and it needs the core's attribute. |
| `ledger-order` (per page) | Body ids increase along the page's content order (the node order of the shipped box, which for a two-column page is left column then right column, and for a band page is stratum, band, stratum), and the last body id of page *p* is smaller than the first of page *p+1*. | Only main-list ids take part. A page with no body ids carries the previous page's boundary forward. The check reports the first inversion and the number of inversions, not every pair. |
| `band-order` (per document) | Every body line created before a band's request position ships before the band (earlier page, or earlier in content order on the same page); a requested band ships exactly once. | Needs `wb@attr@band` and `wbaudit.request`; inactive (and reported `bands=0`) when the core does not provide them, which is the case for the baseline `wideband.sty`. Two occurrences of one band on the *same* page are not distinguished from one. |
| `footnote-place` (per page) | Each footnote text is on the same page and in the same column as its mark. The column is decided geometrically, from the horizontal position against the middle of the text area. | The column test only runs in two-column mode. A footnote split over two pages is judged by its first fragment. `\footnotetext` without a preceding `\footnotemark` gets an id of its own and is skipped (with a `verbose` note) rather than paired with the wrong mark. Marks inside a running head or a float are not paired. |
| `geometry-textarea` (per page) | Every glyph and rule of body, float and footnote material lies inside the text area: 0.5 pt tolerance on the left, right and top edges; a baseline at most 0.5 pt below the bottom edge; ink at most `\@maxdepth` + 0.5 pt below it. | The depth allowance is not slack: the kernel packs a full column so that its last baseline sits exactly on the text-area bottom and TeX limits the page box's depth to `\maxdepth`, so descenders legitimately reach that far and no further. Marginal notes (kind 3) and the running head and foot (kind 4) are excluded — marginal notes are outside the text area by construction, and the contract excludes head and foot. Only the ink bounding box is reported, with the sequence id of the extreme node. Leader boxes are measured as glue, so ink drawn by `\leaders` is not checked. |
| `geometry-band-width` (per document) | Band content is at most `\textwidth` + 0.5 pt wide. | Needs `wb@attr@band`. Uses the last page's `\textwidth`. |

### The ruler is verified

The walk accumulates positions by hand — `node.dimensions` measures
horizontally only, and vertical stacking has to add height *and* depth, apply
the enclosing box's `glue_set`/`glue_sign`/`glue_order`, and account for the
`replace` list of an unbroken discretionary. It reproduces TeX's own
cumulative glue rounding (`cur_glue`/`cur_g` of `hlist_out`), so the positions
it computes are the ones the PDF shows.

To keep that honest, every horizontal list is measured a second time with
LuaTeX's own `node.dimensions` and the two results are compared. A
disagreement above 64 sp makes `geometry-textarea` **fail** for that page with
`edge=ruler`, because a page whose measurement cannot be reproduced cannot be
certified. This self-check found a real 0.28 pt error during development (the
discretionary `replace` lists) and is silent on the whole test corpus.

The vertical walk was calibrated independently against `pdftotext -bbox`: on a
band page of `tests/test-wideband.tex` the ledger and the PDF agree on the
deepest baseline to 0.05 pt.

## Kernel patches

| Patch | How | If it does not apply |
|---|---|---|
| `floatboxreset`, `marginparreset` | `\g@addto@macro`, guarded by a check that the macro takes no parameters (`\meaning` is inspected in Lua because a percent sign cannot appear in a `\directlua` argument) | `WBAUDIT: patch-<name> skipped not-applied`; `geometry-textarea` is skipped for every page, because marginal notes could no longer be told apart from body text |
| `headfoot` | `\AddToHook{build/page/reset}` sets kind 4; the hook runs inside `\@outputpage`'s group, before the shipout box is built, so the assignment tags exactly the head and the foot and is undone with the group | as above |
| `footnotemark`, `footnotetext` | wrappers around the kernel macros, installed in `begindocument/end` so that packages which redefine them in their own `\AtBeginDocument` (hyperref) are wrapped rather than overwritten | `footnote-place` is skipped |

`\everydisplay` is *appended* to, never assigned, for the same reason
(`amsmath` puts its own setup there).

## Inertness

The package assigns attributes, reads the shipped page and writes to the log.
It never modifies a node of a shipped page. `tests/test-audit-inert.tex` and
`tests/test-audit-inert-ref.tex` differ only in the `\usepackage` line and are
required to render pixel-identically; the pair carries footnotes, a column
float, a `figure*`, marginal notes, an `equation` and an `align` so that every
tagging path is exercised.

## How to run

Everything below runs from the repository root. Do not build in the root
itself (contract non-negotiable 6).

```sh
mkdir -p build/audit
cp wideband-audit.sty wideband-audit.lua tests/test-content.tex build/audit/
cp tests/test-audit-*.tex build/audit/
cd build/audit
lualatex -interaction=nonstopmode -halt-on-error test-audit-inert.tex   # twice
lualatex -interaction=nonstopmode -halt-on-error test-audit-inert.tex
../../scripts/check-audit.py test-audit-inert.log                       # exits 0
```

Inertness (the same comparison `scripts/run-tests.sh` makes for
`test-no-band`):

```sh
cd build/audit
lualatex -interaction=nonstopmode -halt-on-error test-audit-inert-ref.tex
lualatex -interaction=nonstopmode -halt-on-error test-audit-inert-ref.tex
mkdir -p .r/pkg .r/ref
pdftoppm -png -r 72 test-audit-inert.pdf     .r/pkg/page
pdftoppm -png -r 72 test-audit-inert-ref.pdf .r/ref/page
python3 - <<'PY'
from pathlib import Path
from PIL import Image, ImageChops
pkg = sorted(Path('.r/pkg').glob('*.png')); ref = sorted(Path('.r/ref').glob('*.png'))
assert len(pkg) == len(ref) and pkg
for a, b in zip(pkg, ref):
    d = ImageChops.difference(Image.open(a).convert('L'), Image.open(b).convert('L'))
    assert d.getbbox() is None, f'mismatch on {a.name}'
print(f'inertness ok for {len(pkg)} page(s)')
PY
```

The negative control must fail:

```sh
cd build/audit
lualatex -interaction=nonstopmode test-audit-broken.tex
../../scripts/check-audit.py test-audit-broken.log   # exits 1, dup=1 lost=1
```

Auditing an existing document: add `\usepackage{wideband-audit}` after
`\documentclass` (or load `wideband` with its `audit` option once the core
provides it), compile in a build directory, and run `check-audit.py` on the
log. To audit the baseline test documents without editing them, copy them and
insert the `\usepackage` line in the copy.

## Limits

Beyond the per-check blind spots above:

- **The summary is written from `enddocument/end`, not from `wrapup_run`.**
  The contract asks for `wrapup_run`, but LuaTeX 1.22 closes the transcript
  before that callback runs, so `texio.write_nl("log", ...)` is lost there
  (verified: only `term` output survives). The package therefore writes the
  document-level checks and the summary from the last kernel hook of the run,
  and keeps a `wrapup_run` callback as a safety net that refreshes the sidecar
  if a page was shipped after `\end{document}`. `check-audit.py` accepts the
  summary anywhere in the log and uses the last one.
- **`geometry-textarea` excludes kind 3 as well as kind 4.** The contract only
  excludes the running head and foot, but a marginal note is outside the text
  area by definition. Scenario `m22-fancyhdr-running-heads` exercises this: a
  fancyhdr head and foot sit in the top and bottom margins, and the check must
  not flag them as outside the text area (`record_ink` returns early for
  `KIND_HEADFOOT` and `KIND_MARGIN`).
- **`geometry-textarea` uses a fixed text-area rectangle and does not model
  `\enlargethispage`.** The rectangle is computed once from the page geometry
  (`\textheight`, margins), so a page enlarged by `\enlargethispage` legitimately
  has ink below that rectangle and the check reports `FAIL edge=bottom`. This is
  not wideband-specific — a plain two-column document with `\enlargethispage` and
  no band trips it too. Scenario `m28-enlargethispage-d4` therefore carries a
  `%% WB-KNOWN-XFAIL` marker (the band itself correctly defers `D4
  enlargethispage` and ships with a clean ledger); modelling the per-page
  enlargement is phase-2 AUDIT work.
- A document that never reaches `\end{document}` writes no summary, and
  `check-audit.py` then exits 1 by design.
- The checks are per page and per document, never per column: a two-column
  page is judged by its content order, not by a column model.
