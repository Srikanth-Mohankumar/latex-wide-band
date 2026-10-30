---
name: run-wideband
description: Build, run, drive, and visually verify the wideband LuaLaTeX package in this repo — compile the test documents, render the pages to PNG, and screenshot/inspect the full-width bands. Use whenever asked to run, build, compile, test, or screenshot wideband / wideband.sty / wideband.lua, to confirm a change to the package actually works, or to reproduce the mid-column full-width band (wide equations/figures spanning both columns in twocolumn mode). For architecture and LuaTeX/output-routine gotchas while editing the package, see references/architecture.md and references/pitfalls.md.
compatibility: Linux + TeX Live (verified on TeX Live 2025 / LuaHBTeX 1.22). Needs lualatex, pdftoppm (poppler-utils), python3 + PIL.
---

# run-wideband

`wideband-cc.sty` + `wideband-cc.lua` are the current production candidate;
`wideband.sty` + `wideband.lua` retain the earlier stratum implementation. Both
provide a full-width band anchored **mid-column** in a twocolumn document — both columns flow above it, jump across it, and
continue below it on the same page (what revtex's `widetext` and `\onecolumn`
cannot do). "Running" this project means compiling the test documents and
**looking at the rendered pages** — compilation success proves nothing here,
because box-surgery bugs produce silently-wrong pages (overlaps, lost text,
wrong column heights).

Paths below are relative to the **repo root**. Regression inputs live in
`tests/`; the production driver lives at `.agents/skills/run-wideband/driver.sh`.

## Prerequisites

Verified already present in this container (`which lualatex pdftoppm python3`).
On a bare Ubuntu box:

```bash
apt-get install -y texlive-luatex texlive-latex-recommended poppler-utils python3-pil
```

## Run (agent path) — do this

One command builds every test, checks the regressions, and renders the bands:

```bash
bash .agents/skills/run-wideband/driver.sh
```

It works out of `/tmp/wb-driver` by default and runs both maintained gates:

- the v0.5 stratum regression, including pixel-identical no-band inertness;
- all 59 Continuous-Column stress documents and 3 expected-error documents, compiled twice and checked for
  TeX errors, vertical overflow, lost/duplicated paragraph and band tokens,
  explicit body-word conservation, unresolved references, and installed-path
  Lua discovery;
- representative Continuous-Column pages rendered for visual review.

Expected tail on success:

```
ALL GREEN — both implementations passed
Visual-review PNGs: /tmp/wb-driver/continuous-column/renders
```

**Then LOOK at the pages** — this is the actual verification step:

```
/tmp/wb-driver/continuous-column/renders/follows-6.png  table band after its source text
/tmp/wb-driver/continuous-column/renders/follows-7.png  conserved trailing material
/tmp/wb-driver/continuous-column/renders/fullpage-2.png full-page band with no body text
/tmp/wb-driver/continuous-column/renders/elsevier-2.png safe Elsevier page-top adapter
```

Open the PNGs and inspect the band boundaries, reading order, page bottom, and
the trailing text page. A blank band, overlapping text, or content outside the
text area is a real bug, not a pass.

## Manual iteration (editing the package)

To iterate on one change without the full suite, work in a scratch dir:

```bash
mkdir -p /tmp/wb && cp wideband.sty wideband.lua tests/test-wideband.tex /tmp/wb && cd /tmp/wb
lualatex -interaction=nonstopmode test-wideband.tex   # run TWICE for \eqref
lualatex -interaction=nonstopmode test-wideband.tex
grep -iE "anchored|fell|deferred|undefined" test-wideband.log
pdftoppm -png -r 60 test-wideband.pdf page            # then Read page-*.png
```

For fine geometry (rule alignment, band gaps) crop-and-upscale a page with PIL.
Before editing the `.lua` node surgery or the `\@outputdblcol` patch, read
`references/architecture.md` (kernel output-routine facts, marker protocol,
why the three rejected designs fail) and `references/pitfalls.md` (LuaTeX
gotchas — the costliest: `node.dimensions()` measures **horizontally**, so
vertical position in a vlist must be accumulated by hand).

## Gotchas

- **Compile twice.** `\label`/`\eqref` need a second pass; the driver already
  does this. A dropped band never runs its deferred `\write`s, so `(??)`
  cross-references are the tell-tale of a lost band.
- **`luaotfload: reverting to OT1`** in the log is cosmetic font-cache noise in
  this container, **not** a failure. Judge by exit code, log diagnostics, and
  the rendered pages.
- **Success ≠ correct.** Box surgery fails silently. Never call a change good
  without rendering and viewing the pages.
- **Inertness is the real gate.** If the pixel-diff regression goes non-zero,
  the patch is no longer transparent to band-free documents — stop and fix
  that before anything else.
- **Kernel version.** The `\@outputdblcol` patch mirrors the 2023 kernel;
  verified still inert on TeX Live 2025 here. Classes that redefine the output
  routine (revtex, IEEEtran, acmart) need their own variant.

## Troubleshooting

- `FAIL: no anchored band` / `deferral scenario not triggered` — a prose edit
  in `test-wideband.tex` moved a band so its scenario changed. How much text
  precedes a band decides mid-column vs. forced-break vs. deferral; re-check
  the log and restore the intended trigger.
- `FAIL inertness: max pixel diff N` — the patch is altering band-free layout.
  The change is wrong; the patch must be a no-op when no band is used.
- Missing `lualatex`/`pdftoppm`/PIL — install per Prerequisites.
