# Continuous-Column POC (throwaway, branch `cc/poc`)

Proves the **Continuous-Column assembly** is feasible and content-safe for a
column-1 wide band, in a single LuaLaTeX pass — the shared foundation of both
the strict (`defer`) and relocatable (`detach-up`) modes in
`docs/design-manual-band-placement-pgc-editor.md`.

## What it does

`wideband-cc.sty` + `wideband-cc.lua` reuse the stratum machinery's *concepts*
(a WBND marker whatsit in the galley, output-routine box capture, exact node
cutting) but replace the **assembly**: instead of the stratum row-major
`hbox(Ltop|Rtop)/band/hbox(Lbot|Rbot)` (which reads
`L-top, R-top, band, L-bot, R-bot`), it fills the columns *naturally* (a
reservation kern in column 1, `\@colht -= reserve` for column 2) and assembles
so each column stays contiguous. Reading order is
`L-top → band → L-bot → R-top → R-bot` — the whole left column (band in it),
then the whole right column.

Mechanism, in the patched `\@outputdblcol`:
1. first-column pass: `markinfo` finds the marker's height `h` in column 1; if
   present, `\@colht -= reserve` so column 2 packs shorter by the band height.
2. second-column pass: `cutmarker` cuts column 1 at the marker → `Ltop`,`Lbot`
   (dropping marker + reservation); `splitat` cuts column 2 at `h` → `Rtop`,
   `Rbot`; assemble `hbox(Ltop|Rtop)/band/hbox(Lbot|Rbot)`, full-width band
   between the rows.

## Verified (see the render)

    lualatex test-cc2.tex   # twice, for the equation number

- Reading order is Continuous-Column and source-contiguous: left column
  `[01][02][03][04]`, band, `[05][06][07…]`; right column `[07-cont]…[13]`.
- Full-width equation drawn mid-column, both columns flow around it.
- Content conserved: all 20 tagged paragraphs appear exactly once, no `(??)`.

Measured alignment: `Ltop=304pt`, `Rtop=322pt`, `h=310pt` — the ~1-line (18pt)
slack above the band in the shorter column is inherent line-quantization
between independently-broken columns (same class as the stratum model's
"baseline grid drifts below the band").

## Scope / not done (deliberately, per the design's POC fence)

- Column-1 band only; a column-2 (right) request would defer — not built here.
- One band per page; `\raggedbottom`; no footnotes, no floats.
- Band-free pages take the stock kernel assembly (`\else` branch) → inert.
- Tagged-PDF content-stream order not addressed (visual order is correct).

## Rung 1 result — `\wb@capture` is NOT reusable for CC (probed)

Probed the real stratum package's raw capture non-destructively (attribute-
tagged paragraphs, a `build/column/before` hook forced to run after
`\wb@capture`). Result: `\@cclv` / `\wb@Lraw` at that hook is the
**already-balanced per-stratum piece**, not a full column. For a column-1 band
at `h=310pt`:

    col 1 capture = paragraphs [1..4] only   (marker already gone)
    col 2 capture = paragraphs [5..8]         (the tail, pushed across — balancing)

The stratum reservation forces the column to break at the band and re-cut
*before* this hook, so the marker never appears in the capture (`markers=0`)
and column 1 never holds `[5..]` below the band.

**Conclusion:** CC cannot be built on `\wb@Lraw`. It needs its **own**
reservation — an in-column gap (`\nobreak\kern`, no forced break, no balancing)
so column 1 keeps its tail below the band — plus its own capture. That is what
this POC already does. Reuse from the real package is only the low-level surgery
(marker whatsit, node cut/split, vpos accounting), **not** `\wb@capture`.
Integrating CC is therefore a *parallel assembly path with its own reservation*,
not a swap on top of the stratum capture.

Next rungs: column-2 detach-up (needs a Y source — satellite/attribute);
harden column-1 CC for footnotes/floats/marks/discards + grow the audit.

## Column-2 detach-up (POC, hardcoded Y) — proven

`wideband-cc2.sty` (+ `tests/test-detach.tex`, reusing `wideband-cc.lua`) proves
the design's hardest claim: a band **authored in the right column** can be
placed same-page, mid-column, **without a float and without balancing** — pulled
*up* to a chosen Y, both columns flowing around it.

Mechanism: the band is captured out of column 2's flow; both finished columns are
`splitat` the hardcoded target Y in the output routine and reassembled
`hbox(Ltop|Rtop)/band/hbox(Lbot|Rbot)`.

Verified render (`\wbccReserve{48pt}{220pt}`): left column `[01][02][03]` / band /
`[04][05][06][07]`; right column `[08][09][10]` / `[11][12][13][14]`. Reading each
column fully gives `[01]..[14]` in source order (Continuous-Column); the band —
authored after `[09]` — renders at Y≈220pt (between `[03]` and `[04]`), i.e. pulled
earlier than authored (the detach-up displacement). All 16 paragraphs conserved.

**Simplifications (deliberate — this isolates the *assembly*, not the discovery):**
- **Y is hardcoded** (`220pt`) — the "where does Y come from" (operator draw /
  satellite / attribute) is deferred, and ties to reviewer Q1.
- **Foreknowledge + hardcoded budget**: because a column-2 band is discovered only
  after column 1 is built, this POC reserves the band height on the page from the
  start (`\AtBeginDocument`, `\@colht -= budget`). The real path must discover the
  band late and reserve dynamically via an **in-run rebuild** (design §3) — done in
  `wideband-cc3.sty`, below.
- Single band, one page, `\raggedbottom`, no floats/footnotes; ~1-line alignment
  slack as in the column-1 case.

## In-run rebuild (POC) — foreknowledge cheat removed

`wideband-cc3.sty` (+ `tests/test-rebuild.tex`) removes the pre-reservation. The
band is discovered late (both columns already built at full `\textheight`), and
room is made **dynamically, in one pass, on the normal output routine** — no custom
`\output` penalty, unlike the stratum re-fire machinery.

In `\@outputdblcol`, band pending:

1. recombine both finished columns: `\vbox{\unvbox\@leftcolumn\unvbox\@outputbox}`;
2. re-split that galley with `\vsplit` at the reduced budget `\textheight-B`:
   `Ltop`(Y), `Lbot`(H-B-Y), `Rtop`(Y), `Rbot`(H-B-Y), leaving the overflow (~2B);
3. assemble page 1 with the band between the rows, `\@outputpage` it;
4. **`\unvbox` the overflow** back onto the main list so it becomes page 2, which
   the page builder finishes normally (plus any input still pending).

`\vsplit` on already-line-broken material does not re-break (the vsplit probe):
the lines are cut exactly, never reflowed. That guarantee is about *line-
breaking* only — it does **not** by itself make the seams glue-clean (see the
rejoin-gap artifact below).

**Verified** (`tests/test-rebuild.tex`, 20 paragraphs, band after [09]):
- page 1: left `[01][02][03]` / band / `[03-cont][04..07]`; right `[07-cont][08][09][10]` / `[11][12][13]`;
- page 2 continues `[14][15]…[20]`;
- reading each column of each page gives `[01]..[20]` in source order (Continuous-Column across the page boundary);
- **all 20 paragraphs conserved, no loss/dup at the rebuilt boundary** — the risk that mattered.

### Pressure test (advisor review) — conservation holds; one cosmetic seam found (now fixed)

Re-ran with the band budget widened to `150pt` (so the overflow spans **four**
paragraphs, not one) and with two `\section*` headings placed near cut points, to
stop the earlier pass from looking clean only because every cut fell on inter-
paragraph `\medskip` glue. Instrumented the output routine to dump the overflow
box (line count + per-line paragraph attribute) right before `\unvbox`.

- **The `\unvbox` re-inject is genuinely exercised**: the overflow measured
  `276.94pt / 22 lines / paras [11..14]` — real body text carried across the
  boundary, not a near-empty tail. Page 2 = that overflow flowing seamlessly into
  the still-pending `[15..20]`.
- **Content conservation still holds** under this harder input: every `[01]..[20]`
  appears exactly once, none duplicated or dropped — including a paragraph that
  the *natural* page break splits across the boundary.
- **Artifact found — a mid-paragraph spacing gap at the overflow↔pending seam.**
  When the output routine's own page break falls mid-paragraph (the common case),
  the galley holds only that paragraph's first lines; the overflow carries them,
  and the paragraph's remaining lines arrive later from pending input and rejoin
  on the next page. The rejoin shows a visibly wrong inter-line gap. Root cause:
  the overflow box carries trailing `\vsplit` glue (a `-2.06pt` userskip seen in
  the dump) and `\prevdepth` is stale when the pending line lands, so the page
  builder computes the wrong baselineskip at the junction. It is **cosmetic, not
  content loss** (text and order are correct). **Fixed — see below.**

### Seam gap FIXED — strip `\@makecol`'s column-bottom glue

    \unvbox\wbcc@galley       % overflow becomes the next page
    \unskip\unpenalty\unskip  % drop \@makecol's column-bottom glue

One line does it — and the *reason* matters, because the first commit
(87cedf9→4a49f8e) shipped a wrong mechanism story that a second advisor pass
caught. What the fix actually is (verified with a node dump, not assumed):

- The residue on the overflow's tail is **not `\vsplit` residue**. It is column
  2's `\@makecol` **column-bottom glue**: a `\vskip` of `-2.06pt` = exactly
  `-\dp` (depth compensation) followed by `\@textbottom`, an **infinite-stretch
  fill** (`order=2` in the node dump; it is `\vskip\z@\@plus…` under
  `\raggedbottom`). `\unvbox\@outputbox` carried that tail into the galley and it
  rides the overflow's bottom.
- Left in place, that infinite-stretch glue lands **mid-column on the next page**
  and shares the new column's bottom slack, so the split paragraph rejoins with a
  **stretched (loose) gap** — which is why the defect was loose and variable
  (~3pt), the opposite of what a stale-`\prevdepth` story predicts.
  `\unskip\unpenalty\unskip` drops it off the list `\unvbox` just laid down (pure
  TeX, no Lua). The held material keeps its own break glue on the contribution
  list, so nothing needs restoring.
- **No `\pagediscards`.** The first commit added it and claimed it was
  load-bearing; it is **inert here** — `\savingvdiscards` is `0` in this POC
  (measured `SVD=0`), so `\pagediscards` is empty, and strip-alone heals
  identically. Worse, it is a latent hazard: the stratum package sets
  `\savingvdiscards\@ne` (wideband.sty:202), and once integration turns it on,
  `\pagediscards` in the column-2 output routine holds column 2's *top-of-column*
  discards — the wrong glue at this seam. So it was removed, not kept.

**Verified (measured, not eyeballed)** with `pdftotext -bbox` geometry, on the
committed files, fails-before/passes-after:

| case | break falls | before fix | after fix |
|------|-------------|-----------|-----------|
| paragraph boundary (`tests/test-seam.tex`) | between paragraphs | one paragraph gap `20.81pt` vs the normal `17.87pt` | all paragraph gaps `17.87–17.88pt` (spread `0.01`) |
| mid-paragraph (`test-seam.tex` + a heading) | inside a paragraph | the split paragraph's internal line stretches | line delta `11.96pt` = baselineskip, uniform |

All 20 paragraphs still conserved; the budget-48 rung-3 test and a band-free
document are unaffected (the re-inject lives in the band-pending branch); logs are
error-clean (`\unskip` in the OR is legal internal-vmode). `tests/test-seam.tex`
is the reproducer.

### Page-1 col1|col2 junction FIXED — `joincols`

The sibling of the seam: `\@leftcolumn` carries the same `\@makecol` column-bottom
tail, and in a plain `\vbox{\unvbox\@leftcolumn\unvbox\@outputbox}` it lands at the
col1|col2 join *inside* `Rtop`, where column 2's own leading `\topskip` also sits —
so the join read `0.11 − 0.11 + 0(fill) + 2.50(topskip) + 7.50 = 10.0pt` instead of
a `12pt` baselineskip: a ~2pt-**tight** line (invisible to the eye, not to the bbox
script). Pure TeX can't fix it — `\unskip` reaches column 1's tail but not column
2's *leading* `\topskip`, and the correct interline glue needs the depth/height. So
a small Lua `M.joincols` (in `wideband-cc.lua`) replaces the concat: it takes both
finished columns, drops column 1's `\@makecol` tail and column 2's `\topskip`, and
splices the glue TeX itself would insert (`baselineskip − prevdepth − height`, else
lineskip). The galley the rest of the routine `\vsplit`s is now seamless.

Two bugs found building it, both the kind that pass a single eyeball:
- **ownership** — only nulling `box.list` (not also `tex.box[n]=nil`, as
  `cutmarker`/`splitat` do) risks a double-free; mirror the existing idiom.
- **`node.vpack` returns two values** (the vlist *and* a badness), so
  `tex.setbox("global", n, node.vpack(l))` splices the badness as a 4th argument
  and `tex.setbox` throws — swallowed under `nonstopmode`, so the galley silently
  never gets set and the whole band page is lost. Capture into a local first.
  (The bug was deterministic yet masked twice by stale-PDF reads; every check now
  deletes the PDF first.)

**Verified** (committed files, fails-before/passes-after, `tests/test-seam.tex`):
the page-1 right-column tight line `9.9pt` → gone (only the band region's ~6.8pt
remains); all 20 conserved; page-2 seam still `0.01`; no Lua errors; deterministic
over five fresh double-pass runs; budget-48 `test-rebuild` and a band-free document
unaffected. Rigid `baselineskip` is assumed (exact for standard classes; a stretchy
one would want the full glue spec via `tex.getglue`).

Still hardcoded: Y (the target position) and the band budget — both orthogonal to
the rebuild (Y is the separate "Y source" rung; the budget would come from the
captured band's measured height). Still out of scope:
- **marks/floats.** Note the `\unvbox\wbcc@galley` deliberately sits
  *after* `\@outputpage` and *before* the `\@startdblcolumn` float loop; with a
  double float pending, the overflow would already be on the list when the float
  routine ships — an untested interaction (architecture §7). It sits there so the
  overflow becomes the next page's body; do not move it without handling floats;
- multiple bands, the column-1 in-flow + late-band interaction.

## Hazards rung — footnotes on band pages FIXED (commit follows)

`\@makecol` bakes each finished column's footnotes at its bottom
(`[\skip\footins glue][colour push][kern -3][\footnoterule][kern 2.6][footnote
boxes][colour pop]`). cc3's rebuild **splits those finished columns**, so the
footnotes scatter: in `tests/test-footnote.tex` (before), footnote 1 (from `[02]`,
left column) landed mid-page in the *right* column with its own rule, and footnote 2
(from `[11]`) was pushed to page 2 — neither at the page bottom.

Fix (`wideband-cc.lua::M.takefootnotes` + the band branch of `wideband-cc3.sty`):
in the output routine, before `joincols`, pull each column's footnote apparatus out
(anchor on the `\footnoterule` — the last rule narrower than the column), keep only
the footnote *content* boxes (+ their interline glue; drop the rule, kerns,
`\skip\footins` glue and the balanced colour-stack whatsits) into a hold box
`\wbcc@fn`; recombine the now footnote-free text; shrink the per-column budget by the
footnote block's height so columns + band + notes fit; and set **one** clean block —
`\vskip\skip\footins \footnoterule \unvbox\wbcc@fn` — at the true page bottom.

**Verified** (fails-before/passes-after, `tests/test-footnote.tex`): both footnotes
at the page-1 bottom under one rule, in order; all 20 paragraphs conserved;
deterministic over three fresh runs; a band-*without*-footnotes page
(`test-rightband`) and a band-*free* page with footnotes are both unaffected (the
handling lives only in the band branch, gated on `\ifvoid\wbcc@fn`).

**Honest limits (POC):** (1) all held footnotes are placed on the band page — a
footnote whose referencing paragraph *overflows* to the next page would wrongly stay
behind (not yet tied to its mark's page); (2) both columns' notes are combined at the
page bottom, left-aligned under one rule, rather than per-column as stock twocolumn
does; (3) the `\footnoterule` anchor assumes the standard rule (a full-width
redefinition would defeat the width test). Still ahead in the rung: **floats** and
**marks / running heads**.

## Hazards rung — multiple bands per page FIXED (commit follows)

The single-band POC held the band in one box `\wbcc@band` and a flag `\wbcc@pending`.
A second `\begin{wideband}` on the same page overwrote that box, so
(`tests/test-twoband.tex`, before) only the *second* band rendered — the first was
silently dropped.

Fix (`wideband-cc3.sty`): bands accumulate onto a per-page list — a pool of band
boxes `\wbcc@b@i` and split heights `\wbcc@Yd@i` (default `\wbcc@detachY`, or a
per-band optional argument `\begin{wideband}[<Y>]`), counted by `\wbcc@nb`. In the
output routine the per-column budget becomes `\textheight − Σ(band heights) −
notes`, and each recombined column is `\vsplit` into **N+1 segments** at the sorted
`Y_i`; the page is then assembled by interleaving `row₁, band₁, row₂, …, band_N,
row_{N+1}` (each row a two-column `hbox`), notes at the bottom, overflow to the next
page. Up to `\wbcc@MAX = 4` bands per page.

**Verified** (`tests/test-twoband.tex`, two bands `E=mc²` at Y=150pt and Ampère's
law at Y=330pt): both bands set full width at their heights, three two-column
segments flowing around them, reading order `[01]–[06]` / `[07]–[12]`; all
paragraphs conserved, no dups; deterministic over three fresh runs. The single-band
tests (`test-rightband`, `test-footnote`, `test-seam`, `test-rebuild`) all still pass
(20 conserved, no dups, seam and junction still clean) through the N=1 path.

**Behaviour change:** the per-column budget is now the *measured* band height, not
`\wbccReserve`'s first argument (which becomes vestigial — its second, `\wbcc@detachY`,
is still the default Y). This is more accurate (no over-reserved whitespace) but
re-flows the single-band pages relative to the earlier budget-reserved layout.

**Bug fixed while building it:** `\newenvironment`'s optional `#1` is visible only in
the *begin* code, not the *end* code (`Illegal parameter number in \endwideband`);
the Y is captured into `\wbcc@curY` in the begin code and used at `\end`. Still ahead
in the rung: **floats** and **marks / running heads**.

## Hazards rung — floats: content-safe, placement limited (investigated)

Floats on a band page were tested across the cases (`tests/test-float.tex`, and the
`figure*`/`[b]` variants). Headline: **they are content-safe** — no float is lost,
duplicated, or scattered mid-page, and content conservation holds even with a float
+ footnote + band on the same page (distinct=20, dups=0, figure once, note once).
The rebuild does **not** break floats.

Placement:
- **single-column `[t]` top floats place correctly** on the band page — `\@makecol`
  puts them at the column head, and `joincols` only strips the column *tail*, so the
  float rides into the top segment. `tests/test-float.tex`.
- **single-column `[b]` bottom floats now place on the band page too** — see the
  extract-and-replace below (`tests/test-floatb.tex`).
- **double-column `figure*` still defers** to a later page (this extraction handles
  only single-column floats; `figure*` lives in the `\@dbltoplist`/`\@combinedblfloats`
  machinery). Safe — the figure appears once, just on the next page.

### Bottom floats FIXED — extract-and-replace (commit follows)

`\@makecol` placed a `[b]` float as a VLIST at the column bottom (confirmed by node
dump: a `VLIST h=63.5 w=\columnwidth` just above the `\@makecol` tail). The rebuild's
reduced budget carried that region into the overflow, so the float deferred. Fix
(`wideband-cc.lua::M.takebotfloats` + the band branch): after `takefootnotes`, find
each finished column's last text line and pull the trailing float VLIST(s) out into a
per-side hold (`\wbcc@bfL`/`\wbcc@bfR`); shrink the per-column budget by the taller
side + `\textfloatsep`; and set the floats at the band page's bottom as
`\hb@xt@\textwidth{col bfL | col bfR}` before the footnote block.

**Verified** (`tests/test-floatb.tex`, fails-before/passes-after): the `[b]` float
`9.9`→ now on page 1 at the column bottom; a left-column `[b]` float likewise; a `[b]`
float **and** a footnote coexist on the page bottom without overlap; all paragraphs
conserved, no dups; deterministic over three runs; every earlier test (`test-float`
top float, `test-footnote`, `test-seam`, `test-rebuild`, `test-twoband`, `test-floatstar`
figure*) unaffected — the handling is gated on `\ifdim\wbcc@bfh>\z@`.

**Two bugs found building it:** (1) `\unvbox` of the float box inside `\hb@xt@\columnwidth`
is illegal (that's horizontal mode) — a float VLIST must go through `\wbcc@vtop`
(a `\vtop{\unvbox…}`) like the column segments; leaving it as `\unvbox` gives
"Missing } inserted / Unbalanced output routine". (2) the first `takebotfloats` walked
the tail with a fragile skip-list; rewritten to find the last text line and treat
everything after it as trailing float material.

**Known detail:** when a bottom float and a footnote share the page bottom, the
footnote currently renders *above* the float (measured y: note 594pt, float 632pt) —
the reverse of the ideal (footnote at the very bottom). Both are present, readable,
and non-overlapping; the order is a refinement. `figure*` on a band page and the
`\unvbox\wbcc@galley`-before-`\@startdblcolumn` ordering (architecture §7) remain the
open float items.

## Hazards rung — marks / running heads: diagnosed, not fixed

Running heads on a band page are **wrong**: a mark on content the rebuild overflows
to the next page is still counted on the band page. In `tests/test-marks.tex` (a mark
`M##` per paragraph, head printing `\leftmark`/`\rightmark`), page 1's `\leftmark`
came out `M15` though `[15]` is on page 2, and page 2's `\rightmark` was off too. It
is **not** a regression in the non-band path (stock twocolumn and the band-free page
behave identically).

**Two attempts, both on the wrong mechanism — the real reason recorded here.** I
first tried to capture the page's marks from `\splitfirstmark`/`\splitbotmark` during
the `\vsplit`s and override `\leftmark`/`\rightmark` (defined classically as
`\@firstoftwo\botmark`). Every read came back **empty** even though the galley
provably still holds the mark nodes (counted `col1=21, col2=18, galley=39` — joincols
preserves them all). The cause: **modern LaTeX no longer uses classic `\mark`.**
`\meaning\leftmark` is `\mark_use_last:nn {page}{2e-left}` — the LaTeX3 (`expl3`) mark
system, with mark *classes* `2e-left`/`2e-right` in region `page`. Classic
`\firstmark`/`\botmark`/`\splitfirstmark` are class 0 and are simply empty here, so
both attempts were targeting a mechanism the running heads don't use.

A correct fix must integrate with the `expl3` mark system: capture the `2e-left`/
`2e-right` marks for the material that actually stays on the band page (the region-
aware `\mark_use_*` / split-mark interfaces), and feed the page head from those rather
than from whatever the pre-rebuild column left in the `page` region. That is a real
piece of `expl3` output-routine work, version-sensitive; deferred. The classic-mark
attempts are reverted; the known-good code stands. `tests/test-marks.tex` still
demonstrates the visible symptom.
