# wideband pitfalls — hard-won gotchas

Each of these cost real debugging time in the original session. Check this
list first when something behaves inexplicably.

## LuaTeX node library

- **`node.dimensions()` measures HORIZONTALLY.** It returns width-axis
  dimensions of a node span. Using it to find a marker's vertical position
  in a vlist returned 8.9pt where the true answer was ~120pt. Vertical
  position must be accumulated manually while walking the vlist:
  - `hlist`/`vlist`/`rule`: add `height + depth`
  - `kern`: add `kern` amount
  - `glue`: add `width`, then apply the *parent box's* `glue_set`,
    `glue_sign`, `glue_order` to stretch/shrink components
  See `vpos()` in `wideband.lua` for the working implementation.
- **`node.vpack(nil)` crashes** LuaTeX. To vpack "nothing", pack a
  zero-width kern node as the content instead.
- When cutting at the marker, **strip penalties AND glue interleaved
  around the marker/reservation kern**, not just the two target nodes.
  The galley contains `penalty 10000 / kern(reserve) / penalty 0` plus
  possible baselineskip glue; leaving strays produces mysterious extra
  vertical space at the cut point (symptom seen: ~16pt excess gap below a
  deferred band).
- Pass register numbers to Lua at load time via
  `\newcount\foo \edef\foo@num{\the\allocationnumber}`, and return
  results with `tex.setcount("global", n, v)` / `tex.setdimen`. Do not
  hardcode register numbers.
- Boxes are shared structures: `node.copy_list` before destructive edits
  of anything that TeX might still reference; `tex.box[n]` assignment
  frees the old list.

## LaTeX output routine

- **Only `\@colht` controls the next column's height.** `\@startcolumn`
  copies `\@colht → \@colroom`, then the output tail copies
  `\@colroom → \vsize`, after *every* cycle. Writes to `\@colroom` or
  `\vsize` are silently overwritten.
- `\@outputpage` resets `\@colht` to `\textheight`. Adjustments for the
  *next* page must happen after it (hence `\wb@after@page`).
- All state that crosses an output-routine boundary must be `\global`
  (the OR runs inside a group).
- `\newpage` inside twocolumn mode breaks the **column**, not the page;
  use `\clearpage` in test files to actually start a fresh page.
- `\pagegoal = \maxdimen` when the page builder has not run yet on the
  current column; fall back to `\vsize` in fit checks.
- `\vsplit` needs `\vbadness\maxdimen \vfuzz\maxdimen` locally to stay
  quiet, and `\splittopskip\topskip` so the split-off top gets correct
  first-line spacing.
- Top-aligning an unvboxed column fragment in an hbox row: rebox through
  `\vtop{\kern\z@ \unvbox...}` — the leading kern makes the vtop's height
  zero so its top sits on the row baseline.

## Environment / testing

- The container's `luaotfload` prints "Error in luaotfload: reverting to
  OT1" — cosmetic font-cache noise, NOT a compile failure. Judge success
  by exit code, log content, and rendered pages.
- Compile **twice** when the document uses `\label`/`\eqref`.
- A band whose box never ships also never executes its deferred
  `\write`s: `(??)` cross references are the tell-tale of a lost/dropped
  band (this is how the end-of-document silent-drop bug was found).
- Visual checks: `pdftoppm -png -r 60 file.pdf page`, then view PNGs.
  For fine geometry (rule alignment, gaps) crop and upscale with PIL.
- The inertness regression (package loaded, no band used, pixel-diff of 0
  against unpatched document) is the strongest safety net — run it after
  every change via `scripts/run-tests.sh`.
- Grep the log for the package's own diagnostics:
  `band anchored in column 1 at <h>` (state 1 path),
  `Band fell into the second column` (deferral path),
  `Deferred band pending at end of document` (v0.2 guard).

## Band placement tuning in test documents

The scenario a band exercises depends on how much text precedes it:
- mid-column: marker lands with room to spare in column 1;
- forced-break-then-anchor: fit check fails near the bottom of column 1,
  marker lands at top of the *next column 1* — still state 1;
- deferral: fit check fails and the forced break lands the marker in
  column 2 → state 2, band moves to next page top.
When editing test prose, re-check the log to confirm each scenario still
triggers its intended path; text edits silently flip scenarios.
