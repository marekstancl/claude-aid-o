Gate fixture (test-aid-ui-verify.bats). `site/` = two pages with one planted defect per
check; copying `fixed/` over it gives a clean site. `project/` = the project files the
gate reads (facts register, brand package). Planted: index.html - no_overflow, one_line_controls,
facts_match (999 Kč), axe (img without alt), image_weight (PNG); o-nas/index.html -
glyph_coverage (monospace), no_placeholders (lorem), brand_assets (drawn logo),
links_resources (/neni.html), required_files (no og:image), seo (noindex).
Fonts: Geist (SIL OFL 1.1). The red lazy image at the bottom of index.html proves the
screenshot is taken after scrolling.
