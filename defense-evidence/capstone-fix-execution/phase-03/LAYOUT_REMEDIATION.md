# Phase 3 narrow-screen/report layout remediation

Owner verifier attempt `20261029-104115-295`: analyzer passed; 230 tests passed and one failed; web build did not run. The 360 px spatial test selected constant soil pH; its unconstrained legend Row overflowed by 96 px. The legend Text now has a Flexible parent so the full label wraps inside the available card width. The test still checks for framework exceptions and now checks immediately after selecting the layer as well.

Both real report PDFs from the same run were rendered (six pages each). All seven layer labels, clipped maps, masks, stats, source details and unavailable notices were present, with no text outside page bounds. Visual inspection found layer headings orphaned from maps at page breaks. The PDF builder now groups each bounded layer heading, map, metadata and legend in one container. Regeneration and final render inspection remain pending.

Dart formatting and git whitespace checks passed. Full Flutter verification must be rerun in the owner terminal; no passing result is claimed for these changes yet. No backend/model behavior changed.
