# Changelog

## v0.5 — stratum model

Behavioural changes by specification (stratum model replacing Option A):

- **Column-2 requests are placed on the same page** by re-cutting column 1 at a
  legal breakpoint and letting its tail flow into column 2 above the band
  (`note=col2-recut`); they no longer defer to the next page.
  `tests/test-right-column-deferral.tex` is now a same-page placement.
- **Several pending bands are allowed** and adjacent bands stack, so
  `tests/test-pending-error.tex` now compiles (it was fail-expected).
- The band request penalty is `-10007`.
- Every request writes one `WIDEBAND DECISION:` log line and a
  `\jobname.wideband.json` sidecar; deferrals carry a code D1–D5.  Export
  `max_print_line=2000` so the decision line is not wrapped.
- An oversized band is still a `\PackageError` (`test-oversized-error.tex`
  stays fail-expected).

Fixes in this iteration:

- A band deferred to the top of the next page now reserves its space so the
  columns build at `\textheight − ΣB` (previously overflowed by the band
  height, including when the page is flushed by `\clearpage`).
- A column-1 re-cut keeps the piece above the band (previously the top of the
  moved column was dropped).
- A column-2 request that is then deferred keeps the column-2 material on its
  page (previously the whole of column 2 above the request was dropped).
- Short/empty trailing strata below a band ship, and a pending page is flushed
  at end of document.
- Stacked bands place each at or below its request with one placement line and
  no overfull.
- Column bottom floats already committed to column 1 are kept within the type
  area; a footnote typed inside a band is extracted and placed.
- The oversized-band error no longer crashes LuaTeX during shutdown.

## v0.4 — production-safe Option A

- Defined the placement policy explicitly: column-1 requests may be placed on the current page; column-2 requests defer intact to the next page.
- Expanded the column-2 warning to explain the intentional unused page area and source-order guarantee.
- Added a dedicated right-column deferral regression document using real technical prose.
- Added PDF-text token accounting for pre-band, band, post-band, and reference content.
- Kept strict rejection of a second pending band and an oversized band.
- Retained asymmetric rule controls and page-boundary checks from v0.3.

## Known issues (v0.5, 2026-09-04)

- Three or more bands deferring across pages: the middle band can be dropped (corpus-0001-0023) or
  misordered (corpus-0001-0024). Fewer than three deferred bands are unaffected. Tracked in
  docs/integration-triage.md for iteration 3.
