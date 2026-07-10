# wideband v0.4 — production-safe Option A

`wideband` is a LuaLaTeX two-column layout experiment for full-width equation bands without balancing the material above the band.

## Placement policy

The package uses a deliberately conservative policy:

- A request discovered in **column 1** may be inserted on the current page by reserving matching vertical space in both columns.
- A request discovered in **column 2** is moved intact to the top of the next page.
- Post-band text is never pulled ahead of the band.
- A second pending band is rejected instead of overwriting the saved band.
- An oversized band is rejected instead of being clipped.

The column-2 fallback can leave unused space at the bottom of the current page. This is intentional. Rebuilding an already finalized left column from finished boxes could detach insertions, floats, marks, writes, anchors, or tagging state. Option A prioritizes preservation of source content over filling that space.

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
