# Changelog

## Unreleased — production hardening (2026-10-28)

Each fix has a regression test that fails before it and passes after.

- `y=top` and `y=bottom` place a band first on its page and as the last thing
  on it (the row below is left empty and the text goes on to the next page),
  with no clamp error; `y=bottom` is re-resolved per placement attempt like an
  automatic Y. Explicit cue-rule arrangements `same`, `same-left`, `above`,
  `above-left`, `below`, `below-left` are drawn as asked, on a page-top band too
  (the automatic arrangements still draw nothing there). Stress test
  `stress-band-top-bottom-rules`.

- The Lua companion is also found beside the `.sty` when the package is loaded
  by path (`\usepackage{/dir/wideband-cc}`, NeoPage's `\Templatepath` convention,
  with no `TEXINPUTS`): `kpse.find_file` cannot see such a directory, and the
  package stopped with "wideband-cc.lua not found". kpathsea is still tried
  first. Test: the install-path gate now also compiles a path-loaded copy.

- A `\footnote` inside a band is no longer lost (generic, Elsevier and
  one-column paths): the band's inserts move to where the band is placed.
- Hyperlinks broken across lines no longer abort a run with a band page
  ("'endlink' ended up in different nesting level"). Band-page lines sit at
  kernel-column depth, and links are balanced per row segment.
- A band authored inside a box (float, minipage, host boxed float) is set
  inline instead of being lost (generic) or breaking the page (Elsevier).
- Elsevier adapter: NeoPage's float reservations are re-synced after the
  band's `\twocolumn[...]` (AA_9001 overflowed 454pt without it), and the
  forced page end is announced with `\SpaceReserveMarkColumnSwitchPage`.
  Corpus: overflowing articles 15 → 10; articles missing over 40 words 6 → 0.
- Elsevier adapter: pending floats are no longer flushed before a band. The
  page ends with `\newpage` and the band joins the next page's full-width top
  area (kernel `\@addtodblcol` accounting), falling back to the flush only when
  it cannot fit beside queued floats. Consecutive bands now share one top area.
  NeoPage's reservation re-sync runs on both paths: without it on the queued
  path, 23 of 55 corpus articles lost text.
- Manual placement (mr-bean) is the default: `auto` now runs the same-page
  engine on every host, NeoPage included (one compile, no `.aux` state);
  `[elsevier]` keeps the page-top placement. A band that does not end up where
  it is written raises a LaTeX error naming the band, its input line and the
  page, with what to do, so an editor that lists only `!` lines shows it:
  deferred, held back, after the host replaced the two-column routine (now set
  page-top in the same run instead of being lost), never placed (now set on a
  page of its own at the end instead of being lost), or a page printing past
  its text area (a band page, or after a band any page over
  `\wbccoverflowlimit`, 30pt, where NeoPage's planned figures collided with
  text the bands moved).
- `\enlargethispage` on a band page works: the band was never placed (the
  kernel wraps that column one box level deeper); the rebuilt page now has the
  operator's extra height.
- A band whose row would protrude below the text area (unsplittable material
  taller than the row) is taken off that page in the same run. Trial splits no
  longer log Overfull messages for pages that never ship.
- Single-pass corpus (54 Elsevier articles, 157 bands at deliberately harsh
  positions, one compile each): no band lost; 77 placed where written, 52
  deferred and 8 set at the end, each with an operator error; every page more
  than 30pt past its text area reported (5 articles), including both articles
  that lost text (DAACH_360, EJMFLU_204268).
- Fix (generic engine): a footnote whose callout a band page pushed to the next
  page stayed on the band page, a page before its callout (JCLP_146437). Notes
  are tagged with their callouts as they reach the page builder, and such a note
  now goes with its callout. Elsevier (54 articles) and ACS (39) corpora: no
  note away from its callout because of a band; package-loaded documents with no
  band unchanged (pixels and NeoPage sidecars); tagged PDF builds unaffected.
- Fix (generic engine): when the correction for an overshooting band page
  cut the text above a band just placed, the band printed ahead of its own
  text and was bookkept twice; the next page read pool slot 0 ("Missing
  number", NeoPage EJMFLU_204268, AA_10515, YJASC_106330). Such a band is
  now shed and moves to the next page with its text.
- Fix (generic engine): when the attempt loop ran out of tries with the page
  still over (each cut moved the left column's tail into a right segment that
  cannot split), the band stayed placed and the next page read pool slot 0
  ("Missing number", NeoPage YJEMA_126557). The last new band is now shed and
  set on the next page with the usual operator error.
- Fix (generic engine): a band shed from a page kept the automatic Y it was
  given there, so on the next page it was placed as if that Y were explicit:
  below the band after it, with a clamp warning, despite "placed at the top of
  the next page". A shed band's Y is automatic again.
- Fix (generic engine): on a band page where the host had set a full-width
  float at the top of the columns (NeoPage/Simba spacereserve: the figure in
  column 1's `\@texttop`, a reserve of the same height in column 2's), the
  rebuild poured that area into the text, so text printed over the figure (14
  of 54 Elsevier and 10 of 39 ACS articles; none without bands). The top
  areas are now taken off both columns and set as one row above the band
  rows, at column depth so links across pages still balance.
- Fix (generic engine): a band page's bottom floats were aligned at their
  tops, so a host's wide float last in column 1 printed over a taller float
  in column 2 beside the room reserved for it (ACS JE_5c00208, NP_5c01252).
  They are aligned at the bottom, as the columns set them.
- An explicit `y` the page cannot honour (the band is moved up) is an operator
  error instead of a warning, so an editor that lists only errors shows it.
- NeoPage: a band set on a page of its own takes a page number NeoPage's float
  plan uses, and the floats planned for it could be lost with no error (5 of
  10 test builds). The operator now gets an error naming them and the fix:
  move the floats planned on or after that page one page later.
- Clear errors: an unknown package option, a band taller than the text area,
  and a missing `wideband-cc.lua`, which now stops loading cleanly instead of
  failing later in Lua.
- New `tests/cc-errors/` expected-failure gate: each document must fail with
  its declared message and never for a malformed-macro reason.
- Elsevier corpus run (55 articles): see `docs/PRODUCTION-READINESS.md`. Not
  production-ready on NeoPage yet.

## v0.10 — Elsevier NeoPage adapter (2026-10-21)

- Added `auto`, `generic`, and `elsevier` package adapters. `auto` detects the
  Elsevier NeoPage spacereserve host without relying on a jobname or customer
  string: either its public `\AddSpaceReservation`/`\LoadSpaceReservations`
  interface or the wide-float gate's transaction register. The register alone
  (added to NeoPage 2026-08-17) missed older hosts.
- Active Elsevier bands now preserve source order by ending the current page
  and using the next page's supported full-width `\twocolumn[...]` top area.
  This intentionally degrades same-page mid-column placement to safe page-top
  placement instead of rebuilding NeoPage's custom output boxes.
- Elsevier `fullpage` requests use the same safe page-top policy with an
  explicit warning; an otherwise-empty band page is not compatible with
  NeoPage's page/float state.
- The generic `\@outputdblcol` overlay is no longer installed on the Elsevier
  host. Package-loaded documents with no bands remain pixel-identical.
- Added red-before/green-after Elsevier adapter regressions for ordinary and
  `fullpage` bands, public-interface detection, loading before the host (with
  an untouched-`\@outputdblcol` assertion), and a band at document end. The
  Continuous-Column gate now covers 43 stress documents.
- Verified against Elsevier article `AA_9001` (details in
  `docs/TEST-RESULTS.md`): load-only output pixel- and sidecar-identical;
  one- and three-band runs conserve text, footnotes and heading order.
  Known cost: the page before each band ends early, and NeoPage floats can
  precede their callout unless the float schedule is computed with the bands.

## v0.9 — Continuous-Column release candidate (2026-10-21)

- Promoted `wideband-cc` from a throwaway POC label to a versioned release
  candidate while keeping the stratum package available as a fallback.
- Load `wideband-cc.lua` through kpathsea. Installed packages now work when the
  document is compiled outside the directory containing the package files.
- Added a full Continuous-Column regression gate: all 38 stress documents are
  compiled twice, checked for TeX failures and vertical overflow, and checked
  for paragraph/band token conservation. Representative PDFs are rendered for
  visual review.
- Added an explicit installation-layout regression that failed with the old
  cwd-relative `dofile("wideband-cc.lua")` loader.
- Corrected the seven-band production fixture's stale contract from paragraphs
  01–42 / 84 body sentinels to its actual 01–60 / 120.
- `make test` now runs both the legacy stratum gate and the Continuous-Column
  gate; `make test-stratum` and `make test-cc` remain individually runnable.

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
