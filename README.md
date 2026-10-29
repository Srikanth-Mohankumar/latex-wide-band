# wideband

This repository contains two LuaLaTeX implementations of mid-page full-width
bands in two-column documents:

- **`wideband-cc` v0.10** is the current production candidate. It preserves
  continuous column reading order, derives placement from an in-flow marker,
  supports bands originating in either column, and rebuilds only pages that
  actually contain a band.
- **`wideband` v0.5** is the earlier stratum implementation. It remains covered
  by its original regression suite and is kept for comparison and fallback.

## Production-candidate usage (`wideband-cc`)

Install both `wideband-cc.sty` and `wideband-cc.lua` in the same searchable
TEXMF directory. The Lua companion is resolved through kpathsea, so the source
document does not need to be compiled from the package directory.

```tex
\documentclass[twocolumn]{article}
\usepackage{wideband-cc}

\begin{document}
Two-column text before the band.

\begin{wideband}
  \begin{equation}
    E = mc^2
  \end{equation}
\end{wideband}

Two-column text after the band.
\end{document}
```

A bare environment uses automatic Y placement. Per-band controls are accepted
in the optional argument:

```tex
\begin{wideband}[y=180pt,skipabove=8pt,skipbelow=4pt,rules=column]
  ...
\end{wideband}
```

Supported keys are `y`, `skipabove`, `skipbelow`, `framesep`, `rulewidth`,
`rules`, and `fullpage`. Large bands automatically receive their own page;
`fullpage` forces that policy for one band.

The package option defaults to `auto` (same as `generic`): a band is placed on
the page where it is written, mid-column, on every host including Elsevier
NeoPage. This is the manual-placement mode used from mr-bean: one LuaLaTeX run,
no `.aux` state. The operator puts a band where there is room; when a band does
not end up where it is written, the package raises a LaTeX error, which mr-bean
lists in its Errors tab while still showing the PDF:

- the band does not fit on its page (it is set at the top of the next page, after
  the text that follows it), or is held back (more than four bands on a page, or
  a full-page band ahead of it);
- the band comes after the host replaced the two-column page routine (NeoPage's
  `\lastpagebalance`): it is set at the top of the next page;
- the band could not be placed at all (its page was built by another routine):
  it is set on a page of its own at the end;
- a page prints past its text area: a band page whose row holds unsplittable
  material, or, after any band, a page whose planned figures no longer fit with
  the text the bands moved forward (more than `\wbccoverflowlimit`, 30pt).

Each message names the band, the input line of its `\end{wideband}` and the
page, and says what to do. The usual fixes are mr-bean's own: an
`\enlargethispage` on the band's page, moving the band, or moving a figure or
table with the float panel. `\enlargethispage` on a band page is honoured.
To nudge a placed band up or down on its page, give it `y=<dim>` (the column
text above it; the automatic value is in the log, `placed, Y=...`).

A `y` the page cannot honour is moved up, with an error.

On NeoPage, a band set on a page of its own takes a page number NeoPage's float
plan uses; if floats are planned for it, the operator gets an error naming
them. The fix: move every float planned on or after the band page one page
later in the float panel.

`elsevier` forces the page-top placement instead, for workflows with no
operator: an active band ends the current page and uses the next page's
full-width top area, keeping source order at the cost of a short page before
each band.

```tex
\usepackage{wideband-cc}            % same-page, operator errors (default)
\usepackage[elsevier]{wideband-cc}  % page-top, no operator
```

The supported production scope and remaining exclusions are recorded in
[`docs/PRODUCTION-READINESS.md`](docs/PRODUCTION-READINESS.md).

## Legacy implementation (`wideband` v0.5 — stratum model)

`wideband` is a LuaLaTeX two-column layout package for full-width equation bands without balancing the material above the band.

## Placement policy

A page is a stack of horizontal *strata*; each stratum is a small two-column page (left piece, then right piece, in reading order) and consecutive strata are separated by full-width bands. Column material is held in raw form until the page is decided, then the page is assembled stratum by stratum, so PDF content order equals reading order.

- A request in **column 1** is placed at `y = h` (column 1 untouched); if that does not fit and the `recut` policy allows it, column 1 is cut at an earlier legal breakpoint.
- A request in **column 2** is placed on the *same* page by cutting the held column-1 piece at a legal breakpoint and letting its tail flow into column 2 above the band.
- Several bands per page are supported; adjacent requests stack.
- Post-request text fills the pieces above the band; pre-request text never falls below it.
- A band that cannot be placed on its page is deferred to the top of the next page (`col=0`); nothing is ever dropped.
- An oversized band (taller than a page column) is a `\PackageError`.

Every request produces exactly one placement record (see [Decision log](#decision-log)), with a deferral code `D1`–`D5` when it could not be placed on its own page.

## Options

`\usepackage[<key=value>]{wideband}`:

| Key | Values | Default | Meaning |
|---|---|---|---|
| `recut` | `never`, `when-needed`, `always-earliest` | `when-needed` | Column-1 re-cut policy. `never` places at `y=h` or defers; `when-needed` re-cuts only if `y=h` does not fit; `always-earliest` always re-cuts to the earliest legal position. Column-2 requests always require a re-cut; with `recut=never` they defer (`D4 recut-disabled`). |
| `policy` | `earliest`, `bottom` | `earliest` | Choice within the feasible interval. `bottom` parses but warns once and behaves as `earliest`. |
| `minpiece` | integer | `2` | Minimum height of a non-empty stratum piece, in lines of `\baselineskip`. |
| `audit` | boolean | `false` | Load `wideband-audit` if present. |
| `verbose` | boolean | `false` | Extra `WIDEBAND INFO:` log lines. |

## Decision log

Every placement attempt writes one `WIDEBAND DECISION:` line to the `.log`. **Export `max_print_line=2000` before running LuaLaTeX** or TeX wraps the line at 80 columns and the tooling misreads it. Fields that do not apply to a given decision are logged as `-` (for example `S=- R=- ymin=- ymax=-` on a deferral taken before any geometry was computed).

The `note` field is a single spaceless token from the vocabulary below. Placement notes:

- `col1-at-h` — column-1 request placed at `y = h`.
- `col1-recut` — column-1 request placed after re-cutting column 1.
- `col2-recut` — column-2 request placed after re-cutting the held column 1.
- `stacked` — a band placed directly under the previous band (zero-height stratum between).
- `top-of-page` — a deferred band placed across the top of the next page (`col=0`).

Deferral notes, by code:

- `D1` `no-room` — the earliest legal position plus the band does not fit above the reserved bottom.
- `D2` `oversized` — the band is taller than a fresh page column (also a `\PackageError`).
- `D3` `unbreakable-range` — column 1 has no legal breakpoint in the feasible range.
- `D4` (unsafe page state) `footnotes-in-moved-material`, `marginpar-in-moved-material`, `holdover-footnote`, `float-in-moved-material`, `enlargethispage`, `nested`, `recut-disabled`, `no-raw-column`, `cycle-limit`.
- `D5` (environment refusal, whole document) `kernel-mismatch`, `pkg-conflict-<name>`.

`float-in-moved-material`, `no-raw-column` and `cycle-limit` are phase-1 extensions of the contract §4.2 vocabulary: `float-in-moved-material` and `no-raw-column` are re-cut refusals (a float in the material that would move; the raw column-1 copy is unavailable), and `cycle-limit` is the output-cycle guard on a single page.

## Usage

```tex
\usepackage{wideband}

\setwidebandrule{0.4pt}{0.75} % thickness, fraction of \textwidth
\setwidebandrulesep{6pt}
\setwidebandsep{14pt plus 4pt minus 2pt}

\begin{wideband}
  \begin{equation}
    E = mc^2
  \end{equation}
\end{wideband}
```

The upper rule begins at the left edge. The lower rule ends at the right edge.

```tex
\widebandrulesoff
\widebandruleson
```

## Safety guarantees within the supported scope

The regression suite checks that:

- a right-column band takes the deferral branch;
- unique pre-band, band, post-band, and reference tokens appear exactly once in extracted PDF text;
- no-band documents remain pixel-identical to the standard two-column output;
- core test PDFs have no text objects outside the configured page bounds;
- pending and oversized requests fail explicitly rather than silently corrupting output.

## Current limitations

This release does not claim general compatibility with single-column floats, double-column floats, custom journal output routines, column-balancing packages, or tagged PDF. It emits warnings when common conflicting packages or pending float queues are detected.

A right-column request can produce a visibly ragged preceding page. That is the documented production-safe fallback, not a layout-measurement error.

## Tests

All sample prose is editable technical content; no `lipsum` filler is used.

```bash
make test          # stratum + Continuous-Column gates
make test-stratum  # legacy wideband only
make test-cc       # 55 wideband-cc stress + 3 expected-error documents, install-path check
```

The test runner builds in `build/tests`, keeping generated LaTeX files out of
the source tree. It requires LuaLaTeX, Poppler (`pdftotext` and `pdftoppm`),
Python 3, and Pillow.

Important files:

- `wideband-cc.sty` and `wideband-cc.lua` — production-candidate sources
- `wideband.sty` and `wideband.lua` — legacy stratum package sources
- `tests/` — regression documents and shared test content
- `scripts/` — the test runner and PDF validation utilities
- `docs/TEST-RESULTS.md` — verification scope and current expectations
- `tests/reference/` — versioned sample PDFs retained for visual comparison

## Repository layout

```text
.
├── wideband-cc.sty       # Continuous-Column release candidate
├── wideband-cc.lua       # Continuous-Column node-list support
├── wideband.sty          # legacy stratum package
├── wideband.lua          # legacy stratum node-list support
├── tests/                # regression inputs
│   └── reference/        # checked-in sample output
├── scripts/              # build and verification tools
├── docs/                 # project documentation
└── build/                # generated locally; ignored by Git
```
