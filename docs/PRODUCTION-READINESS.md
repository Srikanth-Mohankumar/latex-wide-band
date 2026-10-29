# `wideband-cc` production readiness

Status: **v0.10 release candidate.** Intended use on Elsevier NeoPage: manual
band placement from mr-bean, one LuaLaTeX run per build, with an operator who
reads the Errors tab. In that setting no band and no text is lost by the package
on the corpus or the AA_9001 sweep below, and every band that does not end up
where it is written, and every page pushed more than 30pt past its text area,
is reported as an error (one footnote placement issue remains; see open issues). It is **not** a hands-off automatic placement on NeoPage: see the
open issues.

## Supported scope

- LuaLaTeX / LuaHBTeX with standard LaTeX two-column page construction.
- Bands authored in either column, with automatic marker-driven page and Y
  placement or an explicit per-band `y` override.
- Multiple bands per page, including equal or descending requested Y values.
- Footnotes, bottom column floats, and top `figure*` material on band pages.
- `\raggedbottom` and `\flushbottom` documents.
- Full-page bands, end-of-document deferral, and one-column fallback.
- Output-routine packages loaded before `wideband-cc`; band-free pages are
  delegated to the routine that was in force when the overlay was installed.
- Elsevier NeoPage articles with bands placed by an operator (mr-bean): the
  same-page engine, one run, operator errors (see README). `[elsevier]` keeps the
  page-top placement for a workflow with no operator.
- `\enlargethispage` on a band page (mr-bean PI tag).

## Release gate

```bash
make test
```

This runs both maintained implementations. The Continuous-Column half compiles
all 57 stress documents twice (plus 3 expected-error documents), checks vertical bounds through TeX's overfull
diagnostics, verifies paragraph and band token conservation from extracted PDF
text, checks explicit body-word counts where fixtures declare them, validates
declared page counts, requires pixel-identical output for a package-loaded
document with no bands, validates the package from an installed directory, and
renders representative pages.

Compilation is not sufficient for output-routine code. Review the PNGs under
`build/cc-tests/renders/` before release, especially the table band in
`follows-6.png`, its trailing page, and `fullpage-2.png`.

## Fail-safe behaviour

- A band that cannot fit below its source text is deferred; it is never pulled
  above that text merely to satisfy a clamp.
- Deferred markers ride with overflow when their source text moves to the next
  page.
- Pending bands are flushed at document end; a band whose marker never reached
  a page of ours is set on a page of its own there, with an operator error.
- A band after the host replaced the two-column routine is set page-top in the
  same run, with an operator error.
- A band whose row would protrude below the text area is taken off that page.
- More pending bands than the fixed pool can hold produce a package error and
  leave the excess band in the flow so its content survives.
- Placement decisions are written as `wideband-cc` Info/Warning messages in the
  log; every band not placed where written is also a LaTeX error (mr-bean shows
  `!` lines), as is any page that prints past its text area after a band
  (`\wbccoverflowlimit`, 30pt, on pages the host builds).
- The Elsevier adapter flushes all preceding material before creating the
  full-width top area, so following article content cannot overtake the band.

## Known exclusions before broad rollout

- Tagged-PDF structure on rebuilt band pages is not claimed or tested.
- Journal classes that replace the two-column output routine after
  `\begin{document}` need an explicit compatibility test; bands after such a
  switch go page-top (with an error).
- A full-page band on NeoPage (`fullpage`, or a band too tall for a row) takes
  a page number NeoPage's float plan uses: floats planned for that page can be
  lost (5 of 10 test builds). The operator now gets an error naming those
  floats (raised in exactly those 5, in none of the other 5). Fix: in the float
  panel, move every float planned on or after the band page one page later
  (verified 5/5). The package does not shift the plan itself: that needs
  NeoPage to support a page inserted into its plan. (The `[elsevier]` adapter
  degrades `fullpage` to page-top.)
- Margin notes and arbitrary insertion classes are not part of the current
  stress matrix.
- The pending pool is intentionally bounded: at most four bands are placed on a
  page and five may be pending before the explicit overflow guard fires.

## Single-pass evidence, manual mode (2026-10-28)

**Corpus.** The 54 compilable `regression-check/elsevier` articles, three bands
each inserted automatically before section headings (deliberately harsh
positions, not where an operator would put them), one LuaLaTeX run from the
process folder's own `.aux`, against a baseline built the same way. One run per
variant, one machine. Scripts: `run-article-single.sh`, `analyse-single.py`.

| Check | Result |
|---|---|
| Builds | 54/54 produce a PDF |
| Bands lost or duplicated | 0 of 157 |
| Placed where written | 77 |
| Deferred to the next page top (operator error) | 52 |
| Set on an end page: page built by NeoPage's last-page routine (operator error) | 8 |
| Set inline inside a host box | 11 (9 more unlogged, most likely one-column regions) |
| Articles with a new overflow over 5pt | 7: 6 reported (all 5 over 30pt, and a 21pt band page); 1 at 8.6pt not reported |
| Footnote and float inventories, sidecar `.FN` | all present; 1 article (JCLP_146437) had a footnote note one page before its callout: fixed (see below) |
| Total pages (baseline 780) | 821 |

Both articles missing more than 40 words (DAACH_360 501, EJMFLU_204268 48) are
among the reported ones: NeoPage plans figures page by page, and text a band pushes
forward runs into a page planned with little room for text.

**Operator scenarios, AA_9001.** 54 positions × 2 band sizes (≈50pt formula,
≈190pt box), one run each; for a band not placed where written, the operator's
single moves were tried in order: `\enlargethispage{20pt}`, `{40pt}`, band one
paragraph earlier, `\newpage` before the lead-in paragraph.

| | small band | tall band |
|---|---|---|
| Placed where written | 30 | 14 |
| Placed after one move | 14 | 19 |
| Not by one move | 8 | 19 |
| Inside a NeoPage text box: set inline where written | 2 | 2 |

The ones left need a combination of moves or a float move: a band on page 1
under the title block; bands on pages 5–7 that collide with NeoPage's plan for
Figs 1–2 on page 7 (a float move; see the float-panel evidence below); tall bands on pages 7–8 and
11–12. 338 builds; no silent text loss from the package. Six silent losses all
came from `\enlargethispage` on a NeoPage float page, which loses the float (the
Nomenclature, a table) with no wideband package loaded too; and one
`\enlargethispage{40pt}` stops NeoPage with a fatal "endlink ... nesting level"
error, also without the package. Files:
`/data/neopage/.temporary/wideband-manual-test/AA_9001/sweep/`.

## Float panel and band adjustments, five articles (2026-10-29)

AA_9001, ACTHIS_152193, YJEMA_126557, KNOSYS_112150, YENRS_122475
(`regression-check/elsevier`, all `placementEngine: new`). One LuaLaTeX run per
build from a copy of the process folder; one machine. Content checked against
the article's own no-band build: words (line-end hyphenation joined), every
figure/table caption, image count. Scripts and results:
`/data/neopage/.temporary/wideband-float-adjust-20261029/`.

**The float panel works in a single compile.** NeoPage reads `satellite.json`
beside the `.tex` on every run: changing a float's `page` in
`floatReorder.floatPlacementOrder` moves it (AA_9001 Fig. 1, page 7 → 9).

**Scan.** About 15 band positions per article, 78 builds: every text deficit is
on a page the package reports; YJEMA_126557 exposed the crash fixed in this
release (the attempt loop running out of tries).

**Rescue by one float move.** For the 23 bands not placed where written
(page 1 excluded), each float planned on the band's page or the next two was
moved one page earlier or later, one move per build, and each move also built
without the band. 15 of 23 bands are then placed where written, with no error,
no overflow and nothing lost. The other 8 need more than one move. Of 64 moves
without a band, 7 lose text silently in NeoPage alone (345–723pt overflow, no
error: ACTHIS fig3/fig4/fig5, YENRS fig1/tbl1); the one band build that lost
text without a package error was one of them, the loss on a page before the
band.

**Band adjustments.** Two placed bands per article (a high and a low one), 130
builds: `y` = auto ±12 and ±24pt, `0pt`, `2000pt`; `skipabove`/`skipbelow`
0 and 20pt; `fullpage`; the band one paragraph earlier or later.
- `y` moves the band up or down on its page; text, floats and footnotes kept.
  `y=0pt` puts it at the top. A `y` past the room left is clamped to the
  lowest position; this is now an operator error (it was a warning, which
  mr-bean does not show).
  One `y` (AA_9001, 12pt up) hit an unbreakable spot and the band moved to the
  next page with the usual error; 24pt up placed it.
- Larger skips can push a low band off its page (error); 0pt skips never did.
- Moving the band a paragraph places it at the new paragraph, or defers it
  with the error.
- `fullpage`: floats lost in 5 of 10, now reported (see Known exclusions).
- There is no horizontal position: a band spans both columns.

## Footnotes, ACS and tagged PDF (2026-10-29)

One LuaLaTeX run per build (tagged: two, as mr-bean compiles a tagged PDF), from a
copy of each process folder, one machine; NeoPage (`/app/lamput`) and Simba
(`/app/simba`) unchanged since 2026-10-21 / 2026-10-16. The same three bands per
article as the single-pass corpus (before the 2nd, middle and second-to-last
section). Scripts and results: `/data/neopage/.temporary/wideband-footnote-20261029/`.

**Footnote follows its callout.** Each footnote is now tagged with its callout
when it reaches the page builder; on a rebuilt page, a note whose callout went
to the next page leaves the page's footnote block and its insert goes after the
callout. JCLP_146437 fn1 (note p5, callout p6) is fixed, tagged and untagged.

| | Elsevier (54 articles) | ACS (39: `smoke` + `footnotes` suites) |
|---|---|---|
| Package loaded, no band: pixels and NeoPage sidecars (`.FN`, `-apg.xml`, `.fwh`, `.apg`) | identical, 54/54 | identical, 39/39 |
| Bands; each printed exactly once | 157; all | 73; all |
| Operator errors | 52 deferred, 9 end page, 2 band-page overflow, 6 host-page overflow | 39 deferred, 6 page overflow |
| Footnote note on another page than its callout | 2 articles, both also in the no-band build (NeoPage) | 0 |
| Text lost (more than 10 letters, hyphenation joined) | 2: DAACH_360 (reported), AA_9004 (a continued table splitting once fewer: a repeated header row and "continued on next page" label) | 1: EM_5c00771 (reported, 291pt) |
| New overflow not reported | 8.6pt (YJEMA_126336) | 12.3pt (NP_5c01252); every ACS page already overflows 1.25pt in Simba, so an extra band page adds one more |
| Pages (no-band build) | 821 (780) | 500 (484) |

**Tagged PDF** (`\tagpdfsetuptrue`, two runs): 5 Elsevier (AA_9001, DAACH_360,
JCLP_146437, KNOSYS_112150, YJEMA_126557) and 5 ACS articles, each with and
without bands. Every PDF has its structure tree; no tagpdf errors with bands;
tagpdf warnings within ±5 of the same article without bands (Elsevier has 17–308
of its own); no new LaTeX errors (ACS's `__tag/mc/TAG` errors are Simba's, in
both); bands printed once; no footnote mismatch. Not checked: whether a band's
content gets its own structure element (it is set outside the flow), or a PDF/UA
validator.

## Elsevier corpus evidence, two-run harness (2026-10-28)

Earlier evidence: page-top adapter and the then-unfixed same-page engine.

All 55 articles of `/data/neopage/watcher/regression-check/elsevier` were
copied into `/data/neopage/.temporary/wideband-prod-20261028/` and compiled with
two LuaLaTeX passes, as simba's harness does. Each article was built three ways:
an unmodified baseline, the package loaded with no band, and three bands
inserted automatically before section headings (the second, middle and
second-to-last `\section`). These positions are deliberately harsh: some fall
in back matter, in NeoPage boxed floats or in `furtherreading`. One run per
variant, on one machine. AA_9003 fails in its own baseline and is excluded.

| Check | Package loaded, no band | Page-top adapter (now `[elsevier]`) | Same-page engine (before this review's fixes) |
|---|---|---|---|
| Compiles where the baseline compiles | 54/54 | 54/54 | 51/54 |
| Pixel- and sidecar-identical to the baseline | 54/54 | n/a | n/a |
| A band lost (captured, never placed) | n/a | 0 | 8 |
| A band set after the text that follows it (deferred) | n/a | 0 | 33 |
| New `Overfull \vbox` (text past the text area) | 0 | 12 (15 before the break announcement) | 13 |
| Floats now before their callout | n/a | 38 | 26 |
| Total pages (baseline: 780) | 780 | 858 | n/a |

The page-top adapter is content-safe on this corpus: no lost bands, no failed
builds, and source order kept. Its layout cost is large, though. `\clearpage`
flushes every pending float ahead of the band, which can leave a page with one
line of text and float-only pages (FLUID_114571, pages 3–4). Small overflows of
5–15pt follow some of those flushes.

The same-page engine's failures in that run are fixed: the pool-bookkeeping
crash (AA_10515, EJMFLU_204268, YJASC_106330), protruding rows, and bands lost
after `\lastpagebalance` or in back matter.

## Fixed in this review (each with a test that fails before the fix)

- A `\footnote` inside a band was silently lost under every adapter. Its
  inserts are now moved to the page the band lands on.
- A hyperlink broken across lines on a band page stopped the run with a
  fatal PDF-backend error, under any class using hyperref. Band-page lines now
  sit at kernel-column depth, and links are balanced per segment.
- A band inside a box (float, minipage, NeoPage boxed float) was lost
  (generic) or broke the page (Elsevier). It is now set inline.
- The Elsevier adapter skipped NeoPage's reservation re-sync after its
  `\twocolumn[...]`. AA_9001 overflowed by 454pt; the sync is now called.
- The Elsevier adapter now announces its forced page end with
  `\SpaceReserveMarkColumnSwitchPage`, as NeoPage's own column switches do.
  Otherwise the wide-float gate replays the short page's tail elsewhere. On
  the corpus, overflowing articles went from 15 to 10, and articles missing
  more than 40 words from 6 to 0.
- Detection also accepts NeoPage's public space-reservation interface.
- The Elsevier adapter no longer flushes pending floats before a band. It ends
  the page with `\newpage` and adds the band to the next page's full-width top
  area, after any wide float the kernel has placed there, by the kernel's own
  accounting rule. It falls back to flushing only when the band cannot fit
  beside what is queued. Every page-top placement in the corpus (137) took the
  queued path; 11 band executions inside host boxes were set inline. The other
  9 of the 157 bands logged neither, which is consistent with one-column regions
  (inline, unlogged) but was not confirmed. On FLUID_114571, page 3 went
  from one line of text to a full page. Consecutive bands now share one top
  area instead of the first getting a page alone.
- The re-sync is also required on the queued path: without it, 23 corpus
  articles lost text.
- Errors instead of silent misbehaviour: an unknown option, a band taller
  than the text area, and a missing `wideband-cc.lua` (now a clean stop).

## Open issues

- **NeoPage's float plan does not know about bands.** It is page-keyed; text a
  band moves forward can collide with a page planned for figures and run off it.
  The package reports it (page and amount); the operator moves the figure. A
  plan computed with the bands present (lego) would remove most of these.
- **A deferred band prints after the text written below it** until the operator
  makes room; the PDF in between is a working state, flagged by the error.
- **NeoPage and `\enlargethispage`** (no wideband needed): on a page with a
  planned float it can drop the float or text (AA_9001: the Nomenclature, a
  table), and once it stopped the run with a fatal hyperlink-nesting error.
  Operators should prefer moving the band or a float there.
- Overflows under `\wbccoverflowlimit` (30pt) after a band are not reported
  (one corpus article, 8.6pt).

Before enabling a new journal class, add a fixture using that class, run the
full gate, and visually compare both a band page and a package-loaded page with
no band.
