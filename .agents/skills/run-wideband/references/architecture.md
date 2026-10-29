# wideband architecture reference

Everything in this file was established empirically during the original
development session (July 2026, TeX Live 2023 kernel). Trust it before
trusting intuition; re-verify against `latex.ltx` only if the kernel
version changes.

## Contents
1. Kernel output-routine facts (load-bearing)
2. The marker protocol
3. The split/assembly algorithm
4. The deferral path
5. Rejected architectures and why
6. Prior art comparison
7. Current limitations (v0.2)

## 1. Kernel output-routine facts

These four facts carry the whole design:

- `\@outputdblcol` runs once per column. First pass (`\if@firstcolumn`
  true): saves the cut column into `\@leftcolumn`, flips the flag,
  returns without shipping. Second pass: glues `\@leftcolumn` and
  `\@outputbox` side by side, ships the page via `\@outputpage`.
- After **every** output cycle the kernel runs `\@startcolumn`, which does
  `\global\@colroom\@colht` and the output tail then does
  `\global\vsize\@colroom`. Therefore **`\@colht` is the only reliable
  knob for the height of the *next* column**. Shrinking `\@colroom` or
  `\vsize` directly is overwritten and does nothing.
- `\@outputpage` resets `\@colht` to `\textheight` (minus float space
  bookkeeping) after shipping. Any height adjustment intended for the
  page *after* the current one must be applied **after** `\@outputpage`
  runs — this is why the deferral hook (`\wb@after@page`) sits
  immediately after `\@outputpage` in the patched routine.
- `\@makecol` packages each column `\vbox to\@colht`. With the default
  `\flushbottom` of twocolumn mode, artificially shortened or split
  columns produce underfull vbox warnings (badness up to 10000). These
  are cosmetic; `\raggedbottom` silences most of them.

The patched `\@outputdblcol` in `wideband.sty` is a verbatim copy of the
2023 kernel definition with exactly three insertions: `\wb@scan@first` at
the top of the first-column branch, `\wb@scan@second` + a `\ifcase\wb@state`
dispatch replacing the stock assembly in the second-column branch, and
`\wb@after@page` immediately after `\@outputpage`. Keep it that way: any
restructuring makes diffing against future kernels harder.

## 2. The marker protocol

`\wb@place` (called at `\end{wideband}`):

1. Wraps the band box with its decoration rules (top rule flush left,
   bottom rule flush right, `\wideband@rulefrac` × `\textwidth` wide,
   `\wideband@rulesep` gaps) — **before** measuring, so the reservation is
   exact.
2. Computes `\wb@reserve = ht + dp + 2\wideband@sep` of the decorated box.
3. Fit check: if `\pagegoal − \pagetotal < \wb@reserve + \baselineskip`,
   emits `\vfil\penalty-\@M` to force a column break, so the marker always
   lands somewhere the band physically fits. (`\pagegoal = \maxdimen`
   means no page builder run yet; substitute `\vsize`.)
4. `wideband.mark(reserve)` splices into `tex.lists.page_head` tail (in
   the galley, via `node.write` from `\directlua`): a `whatsit`
   `user_defined` node with `user_id = 0x57424E44` ("WBND"), a kern of
   `reserve`, and a `\penalty10000` binding them to the preceding line.
5. `\penalty\z@` afterwards restores a legal breakpoint.

The reservation kern is what makes the page breaker leave room: TeX
breaks the column as if an object of the band's height were inline, so
the material that would have collided with the band is pushed to the next
column naturally, with paragraphs broken correctly.

## 3. The split/assembly algorithm (state 1)

`\wb@scan@first`: `wideband.find(boxnum)` walks the cut column-1 vlist,
counts markers (>1 → warning, only first honoured), and returns the
vertical position *h* of the first marker via `tex.setdimen`. Vertical
position must be accumulated manually — see pitfalls file. If found:
state ← 1, `\@colht −= \wb@reserve`.

`\wb@assemble@split` (second pass):

- state ← 0, `\@colht += \wb@reserve` (restore for subsequent pages).
- `wideband.split(leftcol, Ltop, Lbot, h, bottomheight)`: cuts the stored
  `\@leftcolumn` node list **exactly at the marker**, stripping the
  marker, the reservation kern, and any interleaved penalties/stale glue
  around them. Top part is vpacked "exactly h"; bottom part exactly
  `\@colht − h − reserve`.
- Right column: `\vsplit\@outputbox to\wb@h` under `\vbadness\maxdimen`,
  `\splittopskip\topskip`, `\splitmaxdepth\@maxdepth`.
- Final page box, `\vbox to\@colht`: hbox(Ltop | Rtop) / `\vskip\wideband@sep`
  / band / `\vskip\wideband@sep` / hbox(Lbot | Rbot, both re-boxed through
  `\wb@vtop{...} = \vtop{\kern\z@\unvbox...}` so their **tops** align on
  the row baseline) / `\kern\z@\vss`.

## 4. The deferral path (state 2)

If `\wb@scan@second` finds the marker (i.e. the forced break pushed it
into column 2), the band cannot be anchored on this page — column 1 was
already built at full height. `wideband.strip(boxnum)` removes marker +
reservation in place, `\wb@defer@request ← 1`, warning issued. After
`\@outputpage` ships the page (and resets `\@colht`), `\wb@after@page`
converts the request: state ← 2, `\@colht −= \wb@reserve`. The next
second-pass assembly (`\wb@assemble@deferred`) puts the band across the
top of that page, sep below it, then the two columns.

**End-of-document guard (added in v0.2 after a real silent-loss bug):**
if all remaining text fits before another output cycle runs, a deferred
band would die with the document — its box never ships, its `\label`s
never write (symptom: `(??)` references). `\AtEndDocument` does
`\clearpage`, then if state = 2, warns and emits `\null\clearpage` to
force one extra page carrying the band.

## 5. Rejected architectures and why

- **Synchronized skips** (insert matching vertical space into both
  columns from the galley): while typesetting column 1 you cannot know
  where the same height falls in column 2 — page breaking may move
  material between columns, and the columns are broken in separate
  output cycles. Structurally impossible to do reliably.
- **Insertions / double floats** (`\insert`, `stfloats`, `dblfloatfix`):
  the float mechanism can place material only at the top or bottom of a
  page/column, never anchored mid-column. `stfloats`/`dblfloatfix` fix
  *which page* a `figure*` lands on, not mid-column anchoring.
- **Pure shipout rebuilding** (`pre_shipout_filter` in Lua, tear the
  finished page apart): too late. The page breaker has already cut both
  columns with no height reserved, so a band inserted at shipout either
  overflows the page or requires re-breaking paragraphs, which the
  shipout hook cannot do.
- **Chosen: output-routine box surgery with a Lua-located marker.** The
  OR is the only moment where (a) both column boxes exist as first-class
  objects and (b) the next column's height (`\@colht`) can still be
  changed. Lua's node library makes "cut exactly at the marker" exact,
  which is the step pure-TeX prior art approximates fragilely.

## 6. Prior art

- `cuted.sty` (`\begin{strip}`): same goal, pure TeX, uses trial
  `\vsplit`s inside a rewritten output routine. Known fragile with
  footnotes, marks, floats; the Lua marker replaces its guesswork with an
  exact cut.
- `widetext` (revtex) and manual `\onecolumn ... \twocolumn`: both flush
  the current page (revtex balances the columns above). Fundamentally a
  different, weaker behaviour — kept in `test-baseline.tex` for visual
  comparison.

## 7. Current limitations (v0.2)

- One band per page; a second on the same page is stripped with a
  warning and its reservation is not honoured.
- Opening a new band before a deferred one has been placed overwrites
  `\wb@band` (single box register).
- Floats on band pages untested; `\@combinedblfloats` runs after band
  assembly and interaction is undefined.
- Baseline grid drifts below the band; `\flushbottom` yields cosmetic
  underfull warnings.
- Bands taller than roughly `\textheight` minus a few lines unsupported.
- Box surgery destroys tagged-PDF structure on band pages.
- `\marks` are taken from the pre-surgery boxes; mark-based running
  heads can be off by one item on band pages.
- Kernel-version sensitive: patch mirrors the 2023 `\@outputdblcol`;
  classes that redefine it (revtex, IEEEtran, acmart) need dedicated
  variants.
