# wideband-cc stress-test suite

Scenario coverage for the Continuous-Column wide-band package, focused on the
marker-driven **page assignment** (which page a band lands on) and general band
robustness. Each `stress-*.tex` is self-contained, carries a `TITLE` + `ASSERTION`
banner at the top, and has a descriptive file name.

## How to run

Each file is an ordinary LuaLaTeX document; build it twice (floats/marks settle on
the second pass) with `wideband-cc.sty` and `wideband-cc.lua` beside it:

```
lualatex <file>.tex && lualatex <file>.tex
```

Then check the file's `ASSERTION`:

- **No overflow:** `grep -c 'Overfull \vbox' <file>.log` must be `0`.
- **Content conserved:** every `[NN]` paragraph appears exactly once (`pdftotext`).
- **Band placement:** each `[\text{LABEL}]` band appears once, on the page the
  assertion names (`pdftotext -f P -l P`).

## Scenarios

| File | What it exercises |
|------|-------------------|
| `stress-band-after-page2-paragraph` | A band authored after a page-2 paragraph lands on page 2 (the core page-assignment fix). |
| `stress-two-bands-page1-and-page2` | A page-1 band and a page-2 band; the page-2 band is not dragged onto page 1 by page 1's rebuild (the reported bug). |
| `stress-band-left-column-page1` | A single band interrupting the left column. |
| `stress-band-right-column-page1` | A band authored in the right column (marker past the left column) — detach-up to the split height. |
| `stress-two-bands-same-page-equal-Y` | Two bands at equal Y stack without a zero-height segment. |
| `stress-two-bands-same-page-ascending-Y` | Two bands at ascending Y on one page. |
| `stress-two-bands-authored-descending-Y` | Two bands authored with descending Y — the sort keeps the split valid. |
| `stress-band-deferred-when-too-low` | A band authored too low to fit is deferred (overdue) to the next page. |
| `stress-bands-spread-across-three-pages` | One band per page across a 3-page document. |
| `stress-four-bands-across-document` | Four bands (the pending-pool maximum) across the document. |
| `stress-band-with-footnotes-same-page` | A band sharing its page with footnotes (re-set at the page bottom). |
| `stress-band-with-bottom-float-same-page` | A band sharing its page with a `[b]` bottom float. |
| `stress-band-with-figurestar-top-float` | A band on a page whose top carries a full-width `figure*` (reduced `\@colht`). |
| `stress-band-near-document-end` | A band authored near the end flushes on the last page. |
| `stress-band-explicit-Y-override` | An explicit `[Y]` optional argument overriding the default. |
| `stress-no-bands-baseline-unchanged` | The package loaded but unused — ordinary two-column pages. |

These sixteen build with no `Overfull \vbox`, conserve their paragraphs (checked at the
**body** level, not just the `[NN]` tags), and place each band on the asserted page. A
seventeenth file is a content-conservation regression:

| File | What it exercises |
|------|-------------------|
| `stress-final-overflow-content-conserved` | A band-rebuild's overflow that is the document's **last content** still ships (once dropped ~2 sentences; now 2 pages, all 28 present). |

## Automatic Y (Phase B)

With **no** `[Y]` and **no** `\wbccReserve`, a band's split height Y is derived
automatically from its marker's within-column position, so the band appears where it was
authored. These files exercise the automatic path (all conserve their paragraphs at the
body level; the first four build with no `Overfull \vbox`):

| File | What it exercises |
|------|-------------------|
| `stress-auto-Y-left-column` | A bare band in the **left** column lands where authored (between [03] and [04]). |
| `stress-auto-Y-explicit-and-auto-mix` | An explicit `[Y]` band and a bare (auto) band on the same page — precedence: the explicit one is untouched. |
| `stress-two-auto-bands-same-page` | Two bare bands on one page — the N>1 clamp; both land at their authored positions in order. |
| `stress-auto-Y-overdue-to-top` | A bare band authored past page 1 defers (overdue) and, having no marker on page 2, lands at Ymin (top of page 2). |
| `stress-flushbottom-band-page` | In a `\flushbottom` document the band page ends flush: its lowest baseline equals a plain page's (675.64pt here; it was 7.9pt short — the budget's unused reserve sat in a `\vfil`). |
| `stress-fullpage-band-running-head` | `\pagestyle{headings}` with a section change on page 1 and a full-page band on page 2: the band page's head reads `2 BETA` (the section current when it begins), the next page `3 BETA`. A stock `figure*` float page shows the stale `1 ALPHA` here. |
| `stress-band-keyval-options` | `\begin{wideband}[y=…, skipabove=…, skipbelow=…, framesep=…, rulewidth=…, fullpage]` per band; a bare `[140pt]` still means `y=140pt`; `[fullpage]` forces a small band onto its own page. |
| `stress-band-spacing-controls` | **User request.** `\wbccskipabove`/`\wbccskipbelow`/`\wbccframesep`/`\wbccrulewidth`, recorded per band: one default band and one with 18pt above, 2pt below, no padding, no rules — budget and clamp follow the per-band values. |
| `stress-fullpage-band-own-page` | **User request.** A 0.9`\textheight` band gets a page of its own (no rows, no rules) after the page carrying its text, instead of a few stray lines flowed around it. |
| `stress-fullpage-band-exact-textheight` | A band exactly `\textheight` tall fits its own page with no overflow (unframed; it used to be 41pt too high from the frame and gaps). |
| `stress-fullpage-band-then-small-band` | A full-page band followed by an ordinary band in the same page's text: the small band waits until after the full-page band's page — bands never change order. |
| `stress-band-after-overflowed-paragraph` | **User-reported.** A band deferred from a page whose other bands push its paragraph to the next page: its marker now *rides* in the overflow and the band lands after `[20]` there (it used to be stripped and force-placed one line from the top, *above* its own paragraph); an overdue band whose text ended on the previous page sits at the very top, Y=0, with no orphaned line. Mirrors `to-check/wideband-cc/example.tex` (incl. `stfloats`). |
| `stress-band-deferred-at-document-end` | A band deferred on the document's **last** page (nothing follows it) gets a final page instead of being silently dropped (it was: 1 page, band absent, no warning). |
| `stress-onecolumn-band-inline` | In one-column mode (no `\@outputdblcol`) the band is typeset in the flow as a full-width display where written (it was captured and never placed). |
| `stress-five-bands-overdue-cap` | Five bands deferred together from one page: four are placed on the next page (the per-page cap), the fifth waits for the page after — no errors (it used to run off the end of the segment pool). |
| `stress-band-fit-decision-with-footnotes` | A page with six footnotes and a band whose marker fits only if the notes are ignored: the fit decision now budgets the notes, so the band defers with its text instead of landing a page **before** it (found by sweeping band position × footnote count). |
| `stress-explicit-Y-too-low-clamped` | An explicit `[492pt]` that leaves no room for a line under the band is clamped to Ymax with a `wideband-cc` warning (unclamped it forced a one-line overfull last row). |
| `stress-shrunk-split-row-no-overflow` | A bare **right**-column band (detach-up, Y=P−bud) whose split lands where `\vsplit` had to **shrink glue** — the regression for the row re-expansion bug below (once overflowed 4.56pt). |

### A row re-expansion bug this suite found and fixed

`stress-shrunk-split-row-no-overflow` used to overflow its band page by **4.56pt** (it was
first committed as `stress-KNOWN-ISSUE-auto-Y-budget-resonance`). It was never an auto-Y
defect and never data loss; the diagnosis went through one wrong turn worth recording:

- **Pre-existing:** the identical overflow occurs on the old code with a fixed
  `\begin{wideband}[351.44pt]`; auto-Y merely picks that Y (`P − bud`). Sweeping the
  explicit Y over 200..420pt, *only* 351.44pt overflowed — a "resonance".
- **Wrong first explanation (retracted):** a toy probe suggested each height-0
  `\wbcc@vtop` row carried an unbudgeted "first-line excess". The toy lacked
  `\makeatletter`, so `\kern\z@` had typeset a stray `@` paragraph — the excess was the
  probe's own artefact. Lesson re-learned: `\showbox` the real box, don't infer.
- **Real mechanism (measured in the package with `\showbox`):** `\vsplit … to X`
  packages a segment **exactly** to X, and TeX may reach X by *shrinking* glue
  (`\medskip` has `minus 2pt`). The row then did `\unvbox`, which **drops the glue-set**
  and lets the segment re-expand to its natural height — past X and past the budget.
  Measured: L1 set 351.44+2.06 → unboxed 360.06 (+6.56); R1 +3.50; L2 +3.88. The
  "resonance" is simply a split point where the best break needed shrink; elsewhere an
  underfull break wins and its slack hides the error. Smaller instances (0.9–2pt) were
  present in several other tests, silently absorbed by the old 2pt `\vfuzz`.

**Fix (`\wbcc@fitseg` in `wideband-cc.sty`):** each segment is finished the way
`\@makecol` finishes a column. If `\vsplit` shrank it, the set box is kept (as
`\flushbottom` would). Otherwise, under `\flushbottom` the row is filled exactly to its
split height, and under `\raggedbottom` it is reboxed to its natural height so the band
follows the taller column's last line. In every branch a row is at most its split height
plus a `\maxdepth`-clamped depth, so the rows sum to at most `bud + (N+1)·\maxdepth` and
the budget reserve bounds the page **for any Y** — no split height can overflow. With
that, `\vfuzz` is back at TeX's default 0.1pt: any overfull band page is a genuine defect.
Verified across the whole suite: 0 overfull, every paragraph conserved, every band and
paragraph on the same page as before; 23 of 38 files render byte-identically, the rest
move by ≤ 2pt (the previously masked shrink, now honoured; one by 6.5pt — this file).

## A content-loss bug this suite found and fixed

Writing these tests exposed a pre-existing bug (present before the page-assignment work
too): when a band-rebuild's overflow was the *document's last content*, it was **dropped**
instead of shipping as a final page — the tail of the last paragraph (~2 sentences) never
rendered.

Mechanism (measured): the assembled band page is a correct `\vbox to\@colht`, and the
~55pt overflow is `\unvbox`'d back for the next page. With content after the band it
re-fills and ships normally; only as the *last* content was it lost, because at
`\end{document}` the band rebuild fires from `\clearpage`'s forcing penalty and **consumes
it**, so nothing fires for the trailing overflow (a clean probe showed two output-routine
firings, both on the band page, none for the overflow). The fix (in `wideband-cc.sty`) is
the plain-TeX idiom `\penalty\outputpenalty` right after the re-inject: it re-asserts the
break that fired the output, so a `\clearpage`-forced flush re-forces a page for the
trailing galley, while a natural page break leaves it inert. Verified content-safe across
the whole suite (every other test's output is byte-identical; only this file changes,
1 → 2 pages with the recovered text).

**Detection note:** a `[NN]`-tag count does *not* catch body-text loss — the paragraph tag
survives even when its body is dropped. Verify conservation at the body-word level (e.g.
count `minim`: it must equal `2 ×` the paragraph count).

**Baseline alignment.** Segments produced by `\vsplit` start with `\splittopskip` glue, which
the package sets to `\topskip` (it was `0pt`). Before, the right column's first baseline sat
3.1pt above the left's on every band page (the left column's top row keeps the page's
`\topskip`, a split-off segment did not), and rows after a band could misalign by their
first lines' height difference; now both columns' first baselines coincide with a stock
page's (137.70pt from the top in these tests) and post-band rows align. Each split segment
holds ~3pt less text, so a paragraph opening can spill to the next page (it did in three
files, e.g. `stress-bands-spread-across-three-pages`); bands stay on their pages.

**`\flushbottom` band pages.** Rows are filled exactly to their split heights, but the
page budget keeps a reserve (`(N+1)·\maxdepth + N·\lineskip`) the rows rarely use in
full, and the band page ended in `\vfil` — ragged by a few points in a flush document.
Now the bottom block (bottom floats, footnotes) and the rows above the last row are boxed
first, the leftover is measured, and under `\flushbottom` the last row's two segments are
refilled to absorb it, so both columns end at the page bottom. Under `\raggedbottom`
nothing changes (the `\vfil` stays; all those tests are byte-identical).

**Per-band options.** The optional argument takes key=value pairs (`keyval`):
`y=<dimen>` (explicit split height; a bare `[<dimen>]` still works), `skipabove=`,
`skipbelow=`, `framesep=`, `rulewidth=` (this band's spacing), and `fullpage` (a page of
its own regardless of size). They are set locally inside the environment, which is the
scope the band's capture reads.

**Spacing controls.** Four lengths, set with `\setlength`: `\wbccskipabove` (6pt, text →
band frame), `\wbccskipbelow` (6pt, frame → text), `\wbccframesep` (3pt, padding inside
the rules), `\wbccrulewidth` (1pt; 0pt removes the rules). Each band records the values in
force at its `\end{wideband}` — the frame is built then, and the two skips travel with the
band through the pool, sort and page budget — so a `\setlength` before one
`\begin{wideband}` changes that band only (values set *inside* the environment are local to
the band's box and have no effect). Defaults reproduce the previous output exactly.

**Placement trace in the log.** Every band decision is logged as `band #n (page p): …`,
where `#n` is the band's serial number in document order. Placed bands, bands that move to
the next page together with their text, and full-page bands are `Package wideband-cc Info`
lines; a band that cannot go where it was written — deferred to the top of the next page
because a band page holds less text than a plain one, or held back by the per-page limit
or a full-page band ahead of it — is a `Package wideband-cc Warning`. Grep the log for
`wideband-cc` to audit a document.

**Full-page bands.** A band whose height (with its gaps) reaches `\wbccfullpagefraction`
of `\textheight` (default `.75`; `\renewcommand\wbccfullpagefraction{.6}` to change), or
that would leave less than two lines for text, is a *full-page* band: stored unframed and
never placed in-flow. The page carrying its text ships as usual, then the band is emitted
centred on a page of its own (like a float page), and later bands are held back until it
is out so source order is kept. A full-page band whose marker rides in the overflow waits
for its text. In one-column mode it is set inline unframed. At the end of the document any
remaining full-page band is emitted before the pending-band check. Running heads: the
kernel's `page` mark structure is recomputed in `\@opcol` before `\@outputdblcol`, so a
page shipped from inside the same call would inherit the text page's marks (`\rightmark`
= that page's *first* mark, stale if a section began on it — stock `figure*` float pages
show exactly that). The band page runs the kernel's single-column mark update on its own
(mark-free) box first, so its head shows the section current when it begins.

**Deferred markers ride; Ymin is 0.** When a band page is rebuilt, only the *placed*
bands' markers are stripped. A deferred band's marker that lies in the overflow rides to
the next page and is found there at its true position, so the band follows the paragraph
the rebuild pushed over with it (`wbcc.countmarks` counts the riders; bookkeeping
`overdue' = overdue − nb + found − ride`). Only markers that actually ship (a stock page, or
a marker inside a rebuilt page's rows) make their band overdue — and an overdue band's text
ended on the previous page, so it sits at the very top, `Y = 0`. The earlier `Ymin` of one
`\baselineskip` orphaned a line of the next paragraph above every top-placed band.

**Never lose a band silently.** Three guards, each with its failure mode named: a band
deferred on the document's last page gets a final page (`\AtEndDocument`, only when a
deferred band exists — no blank page otherwise); a band whose marker never reaches a
column's top level (authored inside a box or list) raises a `wideband-cc` warning at the
end saying how many were never placed; a sixth pending band (the pool holds five; at most
four are placed per page) raises a `PackageError` and is typeset in the flow so the content
survives the error (probed manually with six back-to-back bands: all six present).

Known limit (shared with stock two-column LaTeX): an unbreakable item taller than the
room left at a split point — a large display or an in-column figure sitting exactly where
a row ends — is taken by `\vsplit` regardless and protrudes; nothing here can split it.
