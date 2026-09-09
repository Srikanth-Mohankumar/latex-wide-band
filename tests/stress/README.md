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
| `stress-KNOWN-ISSUE-auto-Y-budget-resonance` | A bare **right**-column band (detach-up, Y=P−bud, correct) that also trips a **pre-existing** budget resonance — see below. |

### A pre-existing budget resonance that auto-Y exposes

`stress-KNOWN-ISSUE-auto-Y-budget-resonance` overflows the band page by **4.56pt**. It is
**not** an auto-Y defect and **not** data loss (content is fully conserved — 16 paras, 32
`minim`; the page is merely drawn 4.56pt too tall):

- **Pre-existing:** the identical 4.56pt overflow occurs on the old code with a fixed
  `\begin{wideband}[351.44pt]` on the same document. Auto-Y just picks that Y (`P − bud`).
- **Y-specific resonance (measured):** sweeping the explicit Y over 200..420pt, *only*
  Y=351.44pt overflows; every other value is clean. At that Y both columns `\vsplit` land
  on line boundaries summing to **exactly** `bud` (L1=351.44=Y, L2=147.06=bud−Y), leaving
  zero snapping slack, so the unbudgeted per-row depth excess of the height-0 `\wbcc@vtop`
  rows (~7pt/row, measured) pushes the box past `\@colht`. Off-resonance Y leaves slack
  that absorbs it.
- **Why auto-Y surfaces it:** auto Y = the marker's true position, itself a natural line
  boundary, so exact-fill resonance is over-represented compared with hand-picked Y.

**Fix (a separate rung):** `\wbcc@computebud`'s reserve under-accounts for the height-0
`\wbcc@vtop` rows' first-line excess; it needs to cover that without wasting space
off-resonance. Because changing the reserve moves `bud` on *every* band page (breaking the
byte-identical guarantee), it is deliberately kept out of the auto-Y change.

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

Still open (a separate rung): the `\wbcc@vtop` budget resonance documented above
(`stress-KNOWN-ISSUE-auto-Y-budget-resonance`) — the per-column reserve under-accounts for
the height-0 rows' first-line excess, so an exact-fill split point overflows by a few
points.
