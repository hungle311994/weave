---
name: add-icon
description: Add or change a Weave desktop icon or brand mark — edit tool/icons/icon_sources.dart, regenerate the SVG assets with the Dart generator, add the WeaveIcons/BrandMark enum value, and keep the staleness test green. Use instead of dropping SVG files into assets by hand.
---

# Add an icon

All commands run from `apps/weave_desktop`.

## UI icon

1. In `tool/icons/icon_sources.dart`, add an entry to `uiIcons` with a snake_case file name. Use `_stroke('…')` for outline icons (24 × 24 viewBox, the shared 1.8 stroke) or `_fill('…')` for solid ones. Draw with paths/shapes only — no colours, gradients, `<style>`, or `<use>`; the asset is tinted at runtime with `BlendMode.srcIn`.
2. Run `fvm dart run tool/generate_icons.dart`.
3. Add the enum value to `WeaveIcons` in `lib/core/design_system/icons/weave_icons.dart` (alphabetical, camelCase name, file name in the constructor).
4. Use it as `WeaveIcon(WeaveIcons.<name>, size: …, color: …)`.

## Brand mark

1. Get a single-path SVG for the brand (Simple Icons, CC0, or the brand's official asset) and place it in the brand source folder (currently `~/Documents/weave-brand-icons`).
2. Add an entry to `brandSources` (crop `viewBox` if the mark isn't optically centred).
3. Run `fvm dart run tool/generate_icons.dart --brands ~/Documents/weave-brand-icons`.
4. Add the `BrandMark` value with its file name, display name and design colour (token or `Color` documented in the enum). Agents and integrations pick marks by name from data through `BrandMark.byName`, so never map an agent ID to a brand in code.

## Verify

`fvm dart run tool/generate_icons.dart --check`, then `/verify-step` (`test/core/design_system/weave_icons_test.dart` and `test/tool/icon_sources_test.dart` must pass).
