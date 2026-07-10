---
name: run-wideband
description: Build, run, drive, and visually verify the wideband LuaLaTeX package in this repo — compile the test documents, render the pages to PNG, and screenshot/inspect the full-width bands. Use whenever asked to run, build, compile, test, or screenshot wideband / wideband.sty / wideband.lua, to confirm a change to the package actually works, or to reproduce the mid-column full-width band (wide equations/figures spanning both columns in twocolumn mode). For architecture and LuaTeX/output-routine gotchas while editing the package, see references/architecture.md and references/pitfalls.md.
compatibility: Linux + TeX Live (verified on TeX Live 2025 / LuaHBTeX 1.22). Needs lualatex, pdftoppm (poppler-utils), python3 + PIL.
---

# run-wideband

`wideband.sty` + `wideband.lua` provide a full-width band anchored **mid-column**
in a twocolumn document — both columns flow above it, jump across it, and
continue below it on the same page (what revtex's `widetext` and `\onecolumn`
cannot do). "Running" this project means compiling the test documents and
**looking at the rendered pages** — compilation success proves nothing here,
because box-surgery bugs produce silently-wrong pages (overlaps, lost text,
wrong column heights).

Paths below are relative to the **repo root** (the directory holding
`wideband.sty`). The driver lives at
`.claude/skills/run-wideband/driver.sh`.

## Prerequisites

Verified already present in this container (`which lualatex pdftoppm python3`).
On a bare Ubuntu box:

```bash
apt-get install -y texlive-luatex texlive-latex-recommended poppler-utils python3-pil
```

## Run (agent path) — do this

One command builds every test, checks the regressions, and renders the bands:

```bash
bash .claude/skills/run-wideband/driver.sh
```

It works out of a scratch dir (`/tmp/wb-driver`), so the repo stays clean. It:
- compiles `test-wideband.tex`, `test-baseline.tex`, `test-edgecases.tex`
  (twice each, for `\ref`/`\eqref`);
- greps the log to confirm both band scenario paths fired (`band anchored in
  column 1`, `Band fell into the second column`) and no references dropped;
- runs the **inertness regression** — a twocolumn doc that loads the package
  but uses no band must be **pixel-identical** to the same doc without it
  (PIL pixel-diff must be 0). This is the non-negotiable safety net: if it
  fails, the patch stopped being inert and the change is wrong regardless of
  what else it fixes;
- renders `test-wideband.pdf` to `/tmp/wb-driver/page-*.png`.

Expected tail on success:

```
== inertness regression (must be pixel-identical) ==
ok  inertness: pixel-identical (3 pages)
...
ALL GREEN — bands render in /tmp/wb-driver
```

**Then LOOK at the pages** — this is the actual verification step:

```
/tmp/wb-driver/page-1.png   mid-column band: full-width boxed equation (1),
                            two-column text above AND below it, same page
/tmp/wb-driver/page-4.png   deferral scenario section
```

Open the PNGs (Read tool on the file). Page 1 must show the boxed full-width
equation with two independent text columns above it and below it. A blank
band, overlapping text, or a flushed/half-empty page = a real bug, not a pass.

## Manual iteration (editing the package)

To iterate on one change without the full suite, work in a scratch dir:

```bash
mkdir -p /tmp/wb && cp wideband.sty wideband.lua test-wideband.tex /tmp/wb && cd /tmp/wb
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
