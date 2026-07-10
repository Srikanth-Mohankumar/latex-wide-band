# Changelog

## v0.4 — production-safe Option A

- Defined the placement policy explicitly: column-1 requests may be placed on the current page; column-2 requests defer intact to the next page.
- Expanded the column-2 warning to explain the intentional unused page area and source-order guarantee.
- Added a dedicated right-column deferral regression document using real technical prose.
- Added PDF-text token accounting for pre-band, band, post-band, and reference content.
- Kept strict rejection of a second pending band and an oversized band.
- Retained asymmetric rule controls and page-boundary checks from v0.3.
