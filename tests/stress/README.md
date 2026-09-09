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
**body** level, not just the `[NN]` tags), and place each band on the asserted page. The
seventeenth file is a bug reproducer:

| File | What it exercises |
|------|-------------------|
| `stress-KNOWN-ISSUE-final-overflow-content-loss` | **Reproduces a pre-existing content-loss bug — EXPECTED to drop text.** Fails-before for a follow-up `\output`-flush fix. |

## Known limitation found while writing these tests

**Final-overflow content loss, pre-existing — not the page-assignment concern.** When a
band-rebuild's overflow is the *document's last content* (nothing authored after the
band's page), that overflow is dropped instead of shipping as a final page. This is what
`stress-KNOWN-ISSUE-final-overflow-content-loss.tex` captures: the tail of the last
paragraph (~2 sentences) never renders.

Measured facts and the named mechanism:

- The assembled band page is a correct `\vbox to\@colht` (`550/0`); its natural
  height+depth is `549pt` < `\textheight` (`550pt`) — it fits. So it is **not** a
  budget/reserve problem, and not a `joincols` problem.
- The overflow galley (~55pt) is `\unvbox`'d back for the next page. With more content
  after the band it re-fills and ships normally (add paragraphs after the last one →
  2 pages, every sentence present). Only when the overflow is the *last* content is it
  lost.
- In that case **no output routine fires for the trailing partial page** at
  `\end{document}`: a clean probe shows exactly two OR firings, both on the band page,
  and none for the overflow. `\clearpage` does not ship it, and forcing a page ships an
  *empty* one — the content is gone from the list by document end.
- It reproduces on the pre-page-assignment code as well, so it is not a regression. The
  stray `Overfull \vbox (10.0pt)` is a side effect of the same event, not the defect.

**Detection note:** a `[NN]`-tag count does *not* catch this — the paragraph tag survives
even when its body is dropped. Verify conservation at the body-word level (e.g. count
`minim`: it must equal `2 ×` the paragraph count). The runner and `test-bandpage` use the
body-word check for this reason.

A follow-up rung should add the missing final-page flush to the `\@outputdblcol` override
(stock LaTeX ships a trailing first-column-only page; this override does not), then this
file becomes a passing content-conservation regression. A separate rung adds an automatic
`Ymax` clamp so a too-large manual `Y` defers rather than being placed too low.
