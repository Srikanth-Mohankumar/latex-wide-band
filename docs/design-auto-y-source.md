# Automatic Y (and page) source for wideband-cc — approach

*Status: Phase A (marker-driven **page assignment**) and Phase B (**automatic Y** from the
marker's within-column height, clamped) are both implemented on branch `cc/poc`. This doc
keeps the full plan; "Which page a band lands on" and "Phase B — as implemented" below mark
what now ships.*

## Phase B — as implemented

`\wbcc@detachY` is now the sentinel `\maxdimen` ("auto"); the env's optional-argument
default is still `[\wbcc@detachY]`, so a bare `\begin{wideband}` requests auto. In the band
branch of `\@outputdblcol` the order is **`\wbcc@computebud` → `\wbcc@autoY` → sort**:

- `\wbcc@autoY` resolves every placed band whose `\wbcc@Yd@i` is still `\maxdimen`. A **new**
  band (pool position `i > \wbcc@overdue`) reads its marker's galley position
  `P = \wbcc@mh@(i-\wbcc@overdue)` and sets `Y = (P ≤ bud) ? P : P − bud` — the second case
  is a genuine right-column band detaching up. `bud` (not the original left-column height)
  is the L/R boundary, because `\wbcc@splitcol`'s L segments sum to exactly `bud`. An
  **overdue** band has no marker on the page it lands on (its text ended on the previous
  page), so it takes `Y = 0` — the very top.
- Clamp to `[0, \wbcc@ymax]`: `\wbcc@ymax = bud − (tallest placed band) − 2·sep −
  \baselineskip`. Clamping is monotone, so it cannot reorder bands;
  near-equal clamped Y's are de-collided by the existing sort + `\wbcc@splitcol` stack.
- It **must** run before the sort (the marker index `i − overdue` keys the *unsorted* pool
  order). A leftover `\maxdimen` reaching `\wbcc@sortbands` raises a `\PackageError`.
- Precedence: an explicit `[<Y>]` or a `\wbccReserve{<Y>}` sets a concrete
  `\wbcc@Yd@i ≠ \maxdimen`, which `\wbcc@autoY` keeps — but clamps into the same
  `[Ymin, Ymax]`, with a `\PackageWarning` naming the requested and clamped values, since
  a Y that leaves no room for the band plus one line below it can only be honoured by a
  one-line overfull last row (`stress-explicit-Y-too-low-clamped`). Explicit Y's that do
  fit are untouched (verified byte-identical across the suites when Phase B landed).

**Known simplification (N>1).** The clamp uses a single page-wide `\wbcc@ymax` from the
tallest placed band rather than a per-band `Ymax_i`. This is correct (monotone clamp cannot
reorder; the deepest band is the binding one) and simpler; `stress-two-auto-bands-same-page`
exercises it. A per-band refinement is possible but not needed today.

**A bug auto-Y exposed, now fixed — rows re-expanding past their split height.** With
some contents auto Y lands on a split point where `\vsplit … to X` reaches X only by
*shrinking* glue (`\medskip` has `minus 2pt`). `\vsplit` packages the segment exactly to X,
but the row then `\unvbox`ed it, dropping the glue-set, so the segment re-expanded to its
natural height — measured L1 351.44+2.06 → 360.06 (+6.56pt) — and the band page overflowed
by 4.56pt. It was pre-existing (a fixed `[351.44pt]` on the old code did the same) and
content was never lost; an earlier "first-line excess" explanation came from a probe that
lacked `\makeatletter` and is retracted. Fix: `\wbcc@fitseg` finishes each segment the way
`\@makecol` finishes a column — the set box is kept when `\vsplit` shrank, the row is filled
to X under `\flushbottom`, and reboxed to its natural height under `\raggedbottom` (so the
band follows the taller column, as before). A row is therefore never taller than X plus a
`\maxdepth`-clamped depth, the rows sum to at most `bud + (N+1)·\maxdepth`, and the budget
reserve bounds the page for **any** Y. `\vfuzz` is back to TeX's 0.1pt. Regression:
`tests/stress/stress-shrunk-split-row-no-overflow.tex`.

**Reading-order cue rules (house style, RevTeX geometry, replaces the frame).**
`\wbcc@autoY` records each placed band's reading column (`\wbcc@sd@i`: L if its marker's
galley position is within the left column's budget, R beyond it, T for a top-of-page band);
`\wbcc@capture` records the band's rule style (`\wbcc@rs@i`, from `\wbccrulestyle` or
`[rules=…]`); `\wbcc@rulesides` resolves both into the half each rule occupies, and
`\wbcc@assemble` sets `\wbcc@cueabove`/`\wbcc@cuebelow`: plain half-width
(`\wbccrulefraction`, 0.5) rules (RevTeX's inner-end tick available via `\wbccruletick`,
default 0pt). Arrangements: `revtex` above-left / below-right, `mirror` the opposite. The
default style `column` picks `\wbccrulesleft` (default `mirror`) for a band read in the
left column and `\wbccrulesright` (default `revtex`) for one read in the right column, so
the two come out opposite; `revtex|mirror|none` force one arrangement. Every piece in the
stack is separated by `\nointerlineskip`, so the budget no longer reserves `N·\lineskip`;
it adds `2·\wbccrulewidth + 2·\wbccruletick` per band instead.

**Overlay on the host output routine (from the first production article).** The
`acs-fla` template loads `flushend` and `stfloats`, which install their own
`\@outputdblcol`; replacing it wholesale discarded them on every page. `wideband-cc` now
saves the routine in force at load time (`\wbcc@orig@outputdblcol`), calls it for the
first-column invocation and for every page without a band (entered in the second-column
state it expects), and rebuilds only band pages; `\AtBeginDocument` re-overlays a routine
installed after ours. The double-float page loop after a band page is ours (stock tail);
the delegated branch leaves it to the host.

**`\flushbottom` band pages.** The assembly is now: bottom block (`\wbcc@bot`: floats,
footnotes) boxed; rows 1..N with their bands boxed at natural size (`\wbcc@top`); under
`\flushbottom` the leftover `\@colht − top − lastrow − bot` is measured and the last row's
two segments are refilled (`\wbcc@refill`) to that total, so the band page ends where a
plain flush page does. `\raggedbottom` keeps the `\vfil` and is byte-identical.

**Per-band options.** `\begin{wideband}[y=…, skipabove=…, skipbelow=…, framesep=…,
rulewidth=…, fullpage]` via `keyval`; `\wbcc@setopts` keeps a bare dimension meaning `y`.
Values are set locally in the environment group, so `\wbcc@capture` records them per band
and `[fullpage]` forces `\wbcc@fptest` true for that band only.

**Spacing controls (user request).** `\wbccskipabove`, `\wbccskipbelow`, `\wbccframesep`,
`\wbccrulewidth` replace the hard-wired 6pt/6pt/3pt/1pt. The frame is baked at capture;
the two skips are stored per pool slot (`\wbcc@ab@i`, `\wbcc@bl@i`), swapped by the sort
and shifted with the pool, and used by `\wbcc@computebud`, the `Ymax` clamp, the
full-page test and `\wbcc@assemble`, so per-band values keep the budget exact.

**Placement trace.** `\wbcc@logpage` (called once per page in both output branches) and
`\wbcc@emitfullpages` log every decision as `band #n (page p): …` — Info for placed /
moves-with-its-text / full-page, Warning for deferred-to-top and held-back — so an
operator can audit a document's bands from the log alone.

**Full-page bands (user request).** Flowing a few stray lines around a band that takes
most of the page is worse than giving it the page. `\wbcc@fptest` marks a band *full-page*
at capture when its height plus gaps reaches `\wbccfullpagefraction × \textheight` (default
.75) or would leave under two lines of text; such a band is stored **unframed** (a
`\textheight` image then fits exactly) and never placed in-flow: `\wbcc@duecount` caps the
page's placements before the first full-page band among the candidates, so bands after it
cannot overtake it. Once its text has shipped (it is overdue and at the pool front),
`\wbcc@emitfullpages` — run after `\@outputpage` in both output branches and at the end of
the document — ships it centred on a page of its own and pops it from the pool; remaining
overdue bands land at the top of the following page. Before shipping it runs the kernel's
`\@expl@@@mark@update@singlecol@structures@@` on the (mark-free) band box, so the running
head shows the section current when the page begins rather than the preceding page's
first mark (which is what a stock `figure*` float page shows). Tests:
`stress-fullpage-band-*`.

**Robustness guards.** (1) One-column mode: `\@outputdblcol` never runs, so the
environment typesets the framed band in the flow when `\if@twocolumn` is false (it used to
be captured and never placed). (2) A band deferred on the document's last page has no next
page: `\AtEndDocument` forces one when `\wbcc@overdue > 0` (it used to be dropped
silently — a content loss). (3) Bands still pending at the end (marker never at a column's
top level, e.g. inside a box) raise a warning naming the count. (4) The pending pool holds
`MAX+1` bands and the fit descent caps placements at `MAX` per page; a further band raises a
`PackageError` and is typeset in the flow so nothing is lost. Tests:
`stress-onecolumn-band-inline`, `stress-band-deferred-at-document-end`.

**Baseline alignment.** `\splittopskip` is `\topskip` (was `0pt`): a split-off segment now
starts its first baseline where a stock column does, so the right column's top row no
longer sits 3.1pt above the left's and rows after a band align across columns.
Budget-neutral (the glue is inside the segment); each segment holds ~3pt less text.

> This doc covers two coupled placement questions — **which page** a band lands on and
> **how far down** (Y) — because the same marker answers both. The page part is written
> up in "Which page a band lands on" near the end.

## The problem

`wideband-cc` places each full-width band at a height **Y** — the amount of column
text that sits above the band on its page. Everything else in the package is proven,
but Y is still supplied **by hand**:

- `\wbccReserve{...}{<Y>}` — a document-wide default, or
- `\begin{wideband}[<Y>]` — per band.

An author has to guess a point value and nudge it. The goal of this rung is to make Y
**automatic** in the common case, so a bare `\begin{wideband}…\end{wideband}` lands the
band in the right place without a magic number, while keeping the manual knob for
override.

## Key idea — Y = the band's own authored position

The band is captured *out* of the flow, but we can leave a lightweight **marker** in
the flow at the point where it was authored. That marker travels with the surrounding
text into the finished columns; at output-routine time it sits in the recombined galley
at a known vertical position **P** (its `\pagetotal` there). P *is* the placement we
want: the band should appear where the author put it.

Concretely, the rebuild recombines the two finished columns into one galley
`G = [column 1 | column 2]` and re-splits it at height Y per column:

```
  left column  = G[0 .. bud]         split at Y  -> L-above=G[0..Y], L-below=G[Y..bud]
  right column = G[bud .. 2*bud]     split at Y  -> R-above, R-below
```

`bud` is the per-column text budget (already computed from `\@colht` minus band/notes/
float heights). So the galley's left/right boundary is at height `bud`, and a marker at
galley position **P** maps to a page height as:

- **P ≤ bud** (marker in the left column): `Y = P`. The band interrupts the left column
  exactly at the authored point; the right column is cut at the same page height.
- **P > bud** (marker in the right column — a genuine right-column band): `Y = P − bud`.
  The band sits at the authored point in the right column; the left column is cut at the
  same height. This is the detach-up placement (the impossibility theorem says a
  right-column band cannot keep its source position *and* an intact left column — CC
  accepts cutting the left column, which reading order tolerates).

In both cases **Y = the marker's height within its own column**, and reading order stays
correct because the assembled page reads `L-above → L-below → R-above → R-below`, i.e.
the galley in order, with the band between the above- and below-segments.

> This is the same signal the pruned rung-1 machinery computed (a marker whatsit +
> `markinfo`/`vscan` returning the marker's vertical position). It lives in git history;
> the automatic-Y work revives a lightweight version of it.

## Clamping

A raw P can be unusable (band too high to read, or so low the band + a line below don't
fit). Clamp:

- `Ymin` — **0**, not a line. A marker sits between paragraphs, so if any text precedes
  it on the page `P` is already ≥ one line; a band at `Y = 0` (nothing before it on the
  page, or an overdue band whose text ended on the previous page) belongs at the very top.
  A positive `Ymin` (an earlier draft used one `\baselineskip`) only orphans a line of the
  *next* paragraph above the band. `\wbcc@splitcol` voids a row shorter than a line, so
  `Y = 0` simply means "band first".
- `Ymax = bud − (band height + gaps) − \baselineskip` — guarantee the band plus at least
  one line below it fit on the page; a marker below this detaches up to `Ymax` (or, as a
  policy choice, defers to the next page).
- Multiple bands whose clamped Y's collide are already handled by the equal-Y guard
  (sort + stack).

## Layered plan

1. **Automatic default (in-engine — this doc).** Marker → `Y = within-column height`,
   clamped. A bare `\begin{wideband}` now "just works": the band appears where written.
   No external input, no magic number.
2. **Explicit override (already works).** `\begin{wideband}[<Y>]` forces Y for
   fine-tuning; the env records that Y was explicit and skips the auto computation.
   `\wbccReserve{...}{<Y>}` remains the document default fallback.
3. **External production source (deferred — integration).** In the NeoPage/simba
   pipeline, an operator (via the pgc-editor PDF pane) or a `satellite.json` record can
   supply or nudge Y per band, feeding the *same* `\wbcc@Yd@<i>` knob. This is the
   manual-placement layer already designed in
   `docs/design-manual-band-placement-pgc-editor.md`; it sits on top of the automatic
   default, not instead of it.

## Implementation sketch (tier 1)

- **Emit a marker.** In the `wideband` environment's end code (back in the main vertical
  list, *outside* the captured band box), write a marker node carrying the band index —
  a user-defined whatsit, or a zero-size node tagged with a LuaTeX attribute. It stays at
  the authored position in the flow.
- **Default Y = "auto".** Change the env's optional-argument default from `\wbcc@detachY`
  to a sentinel meaning "compute me"; a real `[<Y>]` overrides.
- **Scan at OR time.** In the band branch, *after* `joincols` and after `bud` is known
  (and after `takefootnotes`/`takebotfloats` so the scan walks only body material), call
  a Lua function (revived `vscan`) that walks `\wbcc@galley`, finds each marker, returns
  its galley position P, then deletes the marker so it doesn't affect layout.
- **Compute Y.** For each auto band: `Y = (P ≤ bud) ? P : P − bud`, then clamp; write it
  into `\wbcc@Yd@<i>`. Explicit-Y bands keep their value.
- **Proceed unchanged.** The existing `\wbcc@sortbands` + `\wbcc@splitcol` +
  `\wbcc@assemble` consume `\wbcc@Yd@<i>` exactly as today.

## Open questions / risks

- **Marker survival.** The marker must survive `\@makecol` and `joincols`. Rung-1 proved
  marks survive `joincols` (top-level nodes preserved); confirm it survives the footnote/
  float extraction, or run the scan before those.
- **Scan cost/position accounting.** `vscan` must reproduce TeX's `\pagetotal` accounting
  (height + depth + glue + kern, honoring `\maxdepth`) to get P right; this is what the
  pruned code did — reuse it, don't re-derive.
- **Below-`Ymax` policy.** Detach-up to `Ymax` (same page, higher) vs defer to the next
  page's top — the converged design's two honest outcomes. Default detach-up (matches the
  current POC); make it a switch.
- **`bud` vs Y ordering.** `bud` is independent of Y (it comes from band/notes/float
  heights), so compute `bud` first, then Y from the marker — no circular dependency.
- **Multiple markers in different columns.** Each gets its own P and column test; the sort
  + equal-Y guard order and de-collide them.

## Which page a band lands on

A band can land on the **wrong page** today, independently of Y. Observed (to-check
example, 2026-09-09): a band authored after paragraph [08] rendered on page 1 even
though [08] falls on page 2.

**Cause — the same one as manual Y.** The band is tied to a page by a *global* flag
(`\wbcc@pending`), set the instant `\begin{wideband}` is read. But the band is captured
*out* of the flow, so it has zero height on the page; TeX's page builder reads ahead past
the following paragraphs and the band declarations while still filling the current page.
By the time page 1's output routine fires, the flag is already set, so page 1 grabs the
band — even though its authored position belongs to page 2. The band is anchored to a
flag, not to its position in the text.

**The marker fixes page assignment for free.** The auto-Y marker sits at the authored
position, so it flows onto whichever page that position lands on. Change the output
routine to place a band only when **its marker is in the current page's galley**
(otherwise hold it and re-check on the next page). Then:

- band after [06], [06] on page 1 → placed on page 1;
- band after [08], [08] on page 2 → held on page 1, placed on page 2.

So one marker gives both the correct **page** (which galley contains it) and the correct
**Y** (its height within that galley's column). No page number to supply. This also means
a band whose marker never appears (authored past the end) simply flushes on the last page
rather than being stranded.

**Implemented (Phase A).** The output routine now scans both finished columns for markers
(`wbcc.markpos`, non-destructive) and reports each marker's position in *galley*
coordinates — a column-1 marker at height `h` keeps `P = h`; a column-2 marker gets
`P = A_end + h`, where `A_end` is column 1's height, because `joincols` lays column 2
directly below column 1. A marker lands on this page iff **`P ≤ 2·bud`** (a column-1
marker below `bud` simply becomes the top of the rebuilt right column — still on the
page). Galley order is document order, so the deepest fitting marker is the last one, and
a one-pass descent shrinks the fitting count until it holds. The pool is split into a
persistent pending total (`\wbcc@np`) and a per-page place count (`\wbcc@nb =` overdue +
fitting-new). What happens to a deferred band's marker depends on where it ends up:

- **Page rebuilt (`nb > 0`).** Only the placed bands' markers (the first `m` found) are
  stripped. A deferred-new marker past the band-page budget lies in the **overflow** and
  *rides* to the next page, where `markpos` finds it again at its true position — so the
  band lands after its paragraph, which the rebuild pushed there too. After the split
  `wbcc.countmarks` counts the riders in the overflow galley; a deferred-new marker that
  instead lies inside this page's rows ships with them (a zero-size whatsit) and its band
  becomes overdue. Pool bookkeeping: `overdue' = overdue − nb + found − ride`; galley order
  is source order, so shipped-marker bands precede riders and the overdue prefix stays
  contiguous. (Before this, *every* found marker was stripped and a deferred band was
  force-placed near the top of the next page — *above* the tail of its own paragraph when
  that tail had overflowed with it; reported from production, regression
  `stress-band-after-overflowed-paragraph`.)
- **Page shipped stock (`nb = 0`).** All found markers ship with the page; they are
  stripped and their bands become overdue, force-placed first on the next page at the very
  top (`Y = 0`, since their text ended on the shipped page). The fit descent budgets the page's footnotes
and bottom floats exactly: before deciding, `wbcc.measurebottom` runs the real footnote/
float extraction on *copies* of the finished columns (only when a band is pending) so the
descent sees the same budget the split will use; a band whose text would be pushed off a
page carrying notes or floats is deferred with its text, never placed a page ahead of it
(`stress-band-fit-decision-with-footnotes`). Regression: `tests/test-bandpage.tex` (a band after [08], which falls on
page 2, must not render on page 1). Phase A keeps **manual Y** — a deferred (overdue) band
has no marker position, so Phase B will give it `Y = Ymin`; today it lands at its manual Y
on the next page.

The overflow galley `\unvbox`'d back for the next page is followed by `\penalty
\outputpenalty` (the plain-TeX re-inject idiom): it re-asserts the break that fired the
output, so a band whose overflow is the *document's last content* still ships (a
`\clearpage`-forced flush re-forces a final page; a natural break stays inert). Only the
rebuild branch adds it — the stock branch would double-force and emit a blank page.
Regression: `tests/stress/stress-final-overflow-content-conserved.tex`.

**Manual page control — as an override, forward only.** When the automatic page is not
what an author wants, expose a *relative* nudge, e.g. `\begin{wideband}[<Y>][+1]` =
"one page later." Design constraints, honestly:

- **Forward (defer) is safe.** Holding a band an extra page is just deferring its
  placement — cheap and robust. (This is the direction the observed case needs: the band
  is landing too *early*.)
- **Backward (pull to an earlier page) is not reliable.** The earlier page is often
  already shipped, and may have no room; do not promise it.
- **Absolute page numbers are fragile.** A hardcoded `[page=2]` silently goes wrong when
  content shifts the pagination; prefer a relative offset over an absolute page.

So the plan: marker-driven automatic page assignment (fixes the bug), with an optional
**forward** page-offset override for fine control — not an absolute page, not a backward
pull.

## Real-article validation (ACS, `acs-fla` template, 2026-09-10)

Setup (scratch, `/data/neopage/.temporary/wideband-realtest/`, `run.sh`/`compare.sh`):
copy an article's `process_folder` from `regression-check/acs`, compile unmodified as the
baseline (lualatex ×2, as simba's harness does), then compile again with `wideband-cc`
loaded after `autotemplate` and this hook, which turns every display wider than the column
into a band — the production integration point is exactly this policy inside
`neopage-math.sty`:

```latex
\usepackage{wideband-cc}          % after autotemplate (flushend/stfloats are loaded there)
\makeatletter
\let\np@DisplayFormula\DisplayFormula
\long\gdef\DisplayFormula#1#2#3{%
  \ifAppendixSection\np@DisplayFormula{#1}{#2}{#3}\else
    \begin{TNQalign*}#3\end{TNQalign*}%          the template's own trial set -> \eqlen
    \ifdim\eqlen>\columnwidth
      \begin{wideband}\np@DisplayFormula{#1}{#2}{#3}\end{wideband}%  (\columnwidth=\textwidth inside)
    \else\np@DisplayFormula{#1}{#2}{#3}\fi\fi}
\let\np@DisplayFormulaImage\DisplayFormulaImage  % \mathImage scales images to \columnwidth
\newsavebox\wbcc@eqimg
\long\gdef\DisplayFormulaImage#1#2#3{%
  \ifAppendixSection\np@DisplayFormulaImage{#1}{#2}{#3}\else
    \sbox\wbcc@eqimg{\includegraphics{#2}}%       natural size (image file named by the id)
    \ifdim\wd\wbcc@eqimg>\columnwidth
      \begin{wideband}%
        \ifdim\wd\wbcc@eqimg<\textwidth \columnwidth\wd\wbcc@eqimg \fi   % natural, not inflated
        \np@DisplayFormulaImage{#1}{#2}{#3}%
      \end{wideband}%
    \else\np@DisplayFormulaImage{#1}{#2}{#3}\fi\fi}
\makeatother
```

Results: `CI_6c00357` (38 pages, 25 displays; eq 23/24 are images 336/358pt wide in a 245pt
column) → 38 pages, two bands on page 11 (one deferred from page 10, at the top; one at
Y=317pt), word count identical (25 595). `EM_7c00997` (16 pages; eq 7 image 276pt) → 17
pages, band on page 5, body text identical (+18 words = the extra page's running
head/foot). No TeX errors. The one structural finding — the template's `flushend`/
`stfloats` output routine being discarded — is fixed by the overlay above. Template noise
to know about: the production page box is **1.25pt overfull on every page** in the baseline
too (15/16 pages EM, 37/37 CI), so a per-page 1.25pt "while \output is active" is not ours;
CI's single 1.6pt overfull in the band build sits between pages 30 and 33, produced by the
host routine on re-flowed pages (the baseline had 1.83pt/0.23pt ones elsewhere). Cosmetic:
`\DisplayFormulaImage` sets the image flush left with the number on the next line; in a
band it should be centred — that is the template's layout, not the band's.

## Built vs. still to do

Built (tiers 1–2): the marker emits at the authored position; the scan drives **both**
page assignment (Phase A) and `Y = within-column height` with clamping (Phase B, see "Phase
B — as implemented" above). Covered by `tests/test-cc` (bare, left column) and the
`tests/stress/stress-auto-Y-*` / `stress-shrunk-split-row-no-overflow` files (left
column, right column, explicit+auto mix, two auto bands, overdue→top).

Still to do:

- **Tier 3, external production source** — feed `\wbcc@Yd@<i>` from the pgc-editor /
  `satellite.json` layer, on top of the automatic default.
- **The optional forward page-offset override** (`[<Y>][+1]`) for manual page control.
