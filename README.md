# wideband v0.5 — stratum model

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
make test
# or: ./scripts/run-tests.sh
```

The test runner builds in `build/tests`, keeping generated LaTeX files out of
the source tree. It requires LuaLaTeX, Poppler (`pdftotext` and `pdftoppm`),
Python 3, and Pillow.

Important files:

- `wideband.sty` and `wideband.lua` — distributable package sources
- `tests/` — regression documents and shared test content
- `scripts/` — the test runner and PDF validation utilities
- `docs/TEST-RESULTS.md` — verification scope and current expectations
- `tests/reference/` — versioned sample PDFs retained for visual comparison

## Repository layout

```text
.
├── wideband.sty          # LaTeX package
├── wideband.lua          # LuaTeX node-list support
├── tests/                # regression inputs
│   └── reference/        # checked-in sample output
├── scripts/              # build and verification tools
├── docs/                 # project documentation
└── build/                # generated locally; ignored by Git
```
