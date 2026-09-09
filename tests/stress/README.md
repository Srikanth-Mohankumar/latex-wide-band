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

These sixteen build with no `Overfull \vbox`, conserve their paragraphs, and place
each band on the asserted page. The seventeenth file is a bug reproducer:

| File | What it exercises |
|------|-------------------|
| `stress-KNOWN-ISSUE-boundary-overflow-10pt` | **Reproduces a pre-existing overflow bug — EXPECTED to overflow.** Fails-before for a follow-up budget fix. |

## Known limitation found while writing these tests

**Boundary overflow (~10pt), pre-existing — not the page-assignment concern.** When a
band page is packed to within ~10pt of `\textheight`, the assembled page overflows the
text area by ~10pt instead of deferring that last sliver to the next page. This is what
`stress-KNOWN-ISSUE-boundary-overflow-10pt.tex` captures.

Measured facts (not a theory — the cause is not yet pinned):

- The overflow is exactly `10.0pt too high`.
- The assembled page's natural height+depth is `549pt`, i.e. *below* `\textheight`
  (`550pt`) — the content fits, yet the frame still spills.
- It reproduces on the pre-page-assignment code as well, so it is not a regression.
- Setting `\boxmaxdepth\z@` on the outer assembly `\vbox` does not change it.

Because this scenario overflows at the page boundary, the two feature-demo versions
(`stress-band-right-column-page1`, `stress-band-with-figurestar-top-float`) are authored
with a little headroom so they demonstrate the scenario cleanly; the boundary-packed
form lives in the known-issue file above. A follow-up rung should find the true cause,
widen the reserve accordingly, and add an automatic `Ymax` clamp so a too-large manual
`Y` defers rather than overflows.
