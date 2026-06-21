# AID Orchestrator — production brand package

This is the cleaned production package. Older experiments, duplicate exports and internal working files were removed.

## Recommended files by use case

### Website / Docusaurus
- Main dark-mode logo: `brand/logo/svg/aid-logo-color-on-dark.svg`
- Light background logo: `brand/logo/svg/aid-logo-color.svg`
- Favicon: `icons/favicon/favicon.svg`
- Legacy favicon fallback: `icons/favicon/favicon.ico`

### iOS
- Primary Apple touch icon with symbol + AID wordmark: `icons/apple/apple-touch-icon.png`
- Symbol-only alternative: `icons/apple/apple-touch-icon-symbol-only.png`

### PWA / Android
- Primary 192 px logo+text icon: `icons/pwa/pwa-192.png`
- Primary 512 px logo+text icon: `icons/pwa/pwa-512.png`
- Symbol-only alternatives are included with `-symbol-only` suffix.

### Claude Code marketplace / GitHub social / app listing
Use the square lockups in `icons/marketplace/`.
Recommended:
- `aid-marketplace-512-dark.png`
- `aid-marketplace-1024-dark.png`

### CLI / monochrome contexts
Use:
- `brand/symbol/svg/aid-symbol-white.svg`
- `brand/symbol/svg/aid-symbol-black.svg`

## Structure

```text
brand/
  logo/
    svg/
    png/
  symbol/
    svg/
    png/
icons/
  favicon/
  apple/
  pwa/
  marketplace/
source/
docs/
preview/
README.md
manifest.webmanifest
asset-manifest.json
```

## Typography
Wordmark source: **Inter Display ExtraBold**. All delivered SVG wordmarks are converted to paths.

## Colors
- Purple: `#7C3AED`
- Blue: `#3B82F6`
- Cyan: `#22D3EE`
- Deep black: `#0B0F14`
- Off white: `#E5E7EB`
