# Automatic Y source for wideband-cc — approach

*Status: design/approach only (not implemented). Branch `cc/poc`.*

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

- `Ymin` — leave a little above the band (e.g. one `\baselineskip`, or the first
  paragraph), so a band authored at the very top isn't flush to the header.
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

## Not doing yet

Nothing here is built. The next step, when picked up, is tier 1: emit the marker, revive
the scan, wire `Y = within-column height` with clamping behind the "auto" default, and
add a test that a bare `\begin{wideband}` lands where authored (a marker-position bbox
check) for both a left-column and a right-column band.
