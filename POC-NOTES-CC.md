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
