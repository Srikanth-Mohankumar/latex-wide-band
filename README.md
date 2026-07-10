# wideband — non-balancing full-width equation bands for twocolumn LuaLaTeX

Proof of concept. Places a `\textwidth`-wide band (typically a display equation)
across both columns of a `twocolumn` page **without** flushing the page or
balancing the columns. Text flows normally in both columns above the band,
jumps across it, and continues in both columns below it.

```latex
\usepackage{wideband}   % requires LuaLaTeX

...column text...
\begin{wideband}
  \begin{equation} \mathcal{Z}[J] = \int \mathcal{D}\phi\, e^{iS[\phi]+iJ\phi} \end{equation}
\end{wideband}
...column text continues...
```

Configuration:

```latex
\setwidebandsep{14pt}          % gap between columns and the band block
\setwidebandrule{0.4pt}{0.75}  % rule {thickness}{fraction of \textwidth}
\setwidebandrulesep{6pt}       % gap between each rule and the content
\widebandrulesoff              % \widebandruleson to re-enable (default on)
```

The band is decorated with two rules: the top rule is flush *left*, the
bottom rule is flush *right*, each spanning the given fraction of
`\textwidth` (default 75%). The rules are wrapped around the content
before the height reservation is measured, so spacing stays exact.

## How it works

1. **Capture.** The environment body is typeset into a `\textwidth`-wide vbox
   stored in `\wb@band`.
2. **Mark + reserve.** A Lua function splices into the main vertical list, at
   the current point: a marker whatsit (`user_id 0x57424E44`), a kern equal to
   `ht+dp` of the band plus two separations (the *reservation*), and a
   `\penalty10000`. If the reservation cannot fit in what remains of the
   current column, `\vfil\penalty-\@M` forces a column break first, so the
   marker always lands in a position where the band physically fits.
3. **First column pass.** `\@outputdblcol` is patched. When the left column is
   cut, Lua scans `\@outputbox` for the marker. If found, it records the exact
   vertical position *h* of the marker and the patch does
   `\global\advance\@colht by -reservation`. This is the load-bearing trick:
   after every output cycle the kernel runs `\@startcolumn`, which copies
   `\@colht → \@colroom → \vsize`, so shrinking `\@colht` makes the *second*
   column get cut short by exactly the band's height.
4. **Assembly.** When the second column arrives, Lua performs box surgery:
   the stored left column is cut exactly at the marker (marker, reservation
   kern, and adjacent penalties/glue stripped); the right column is `\vsplit`
   to *h*. The page is rebuilt as: top row (two column tops, side by side) /
   sep / band / sep / bottom row (column bottoms, top-aligned via a
   `\vbox`+kern trick) / `\vss`, packed to the original `\@colht`.
5. **Deferral fallback.** If the marker ends up in the *second* column (a
   forced break landed it there), the band cannot interrupt the current page;
   it is stripped in place, a warning is issued, and the band is placed across
   the top of the next page (by reducing `\@colht` after `\@outputpage`
   resets it to `\textheight`).

Everything is a no-op when no band is pending — output is pixel-identical to
an unpatched document (verified).

## Why this architecture

Four approaches were evaluated:

- **Synchronized skips** (insert matching vertical space in both columns from
  the galley): impossible to do reliably, because when column 1 is being
  typeset you cannot know where the same height falls in column 2, and page
  breaking may move material between columns.
- **Insertions/floats** (`\insert`, `stfloats`-style double floats): float
  placement can only put material at the top or bottom of a page, never
  anchored mid-column; `dblfloatfix`/`stfloats` fix *which page*, not
  mid-column anchoring.
- **Pure shipout rebuilding** (intercept `pre_shipout_filter`, tear the page
  apart in Lua): too late — the page breaker has already cut both columns
  with no height reserved for the band, so rebuilding would overflow or
  require re-breaking paragraphs.
- **Output-routine box surgery with a Lua-located marker** (chosen): the OR is
  the one place where both column boxes exist as first-class objects *and*
  the height of the next column (`\@colht`) can still be changed. Lua's node
  library makes the "cut exactly at the marker" step exact and robust, which
  is the part pure-TeX prior art (`cuted.sty`) does with fragile
  `\vsplit`-and-hope macro code.

## Verified behavior (test files)

- `test-wideband.tex` — band mid-column (p.1), band near page top (p.2),
  band that doesn't fit the current column → deferred to next page top with
  warning (p.3→4).
- `test-baseline.tex` — the two existing workarounds for comparison:
  `cuted`'s `\begin{strip}` and the `\onecolumn`/`\twocolumn` switch (which
  flushes the page, à la `widetext`).
- `test-edgecases.tex` — footnotes above and below the band (stay at column
  bottoms), two bands on one page (warning + degraded but non-crashing
  output), an 8-row `align` band, band as first thing on a page.

## Known limitations

- One band per page. A second band on the same page is stripped with a
  warning (its reservation is not honored).
- If a new band is opened before a deferred band has been placed, the stored
  box is overwritten.
- A band deferred on the very last page is no longer dropped: an
  `\AtEndDocument` guard forces one extra page for it (with a warning).
- Floats on band pages are untested and likely to misplace.
- Baseline grids drift below the band; with `\flushbottom` (the twocolumn
  default) the split boxes generate underfull-vbox warnings — cosmetic, and
  `\raggedbottom` silences most of them.
- Bands taller than `\textheight` minus a few lines are unsupported.
- Box surgery destroys the structure the PDF tagging project relies on;
  tagged-PDF output will be wrong on band pages.
- `\marks` on band pages are taken from the pre-surgery boxes; running heads
  based on marks split mid-column may be off by one item.
- Kernel-version sensitive: `\@outputdblcol` is copied from the 2023 LaTeX
  kernel; class files that redefine it (revtex, IEEEtran) need their own
  patch variant.
