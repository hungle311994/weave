---
name: design-spec
description: Look up exact values (size, padding, gap, radius, colours, effects, typography, copy) of a Weave screen, dialog or element in the Figma design — from the JSON export when the Figma MCP is unavailable, or from Figma itself when it is. Use before building or changing any desktop UI.
---

# Design spec lookup

## Sources

- **Figma file** `qLUeyOZj96lIorCcMIyeVA` — pages "10 · Product screens" (1600 × 1000 screens) and "20 · Dialogs & flows". If the Figma MCP works, prefer it (load the `figma:figma-use` / `figma:figma-design-to-code` skill first). On the user's Starter plan the MCP is often rate-limited; then use the export.
- **Export** `weave-design-spec.json` (default `~/Downloads/weave-design-spec.json`; ask the user for the path if it isn't there) plus one PNG per frame named `<page>__<frame>.png` next to it. They are produced by the local "Weave Design Export" Figma plugin (`~/Documents/weave-figma-fixer-9/`). If the design changed since the export, ask the user to re-run it.

## Export format

`pages[].frames[]` are trees of nodes: `type`, `name`, `id`, `x`, `y`, `w`, `h`, `fills` (hex, `#RRGGBB@opacity`, or `{gradient, stops, transform}`), `strokes`, `strokeWeight`, `radius` (number or `[tl, tr, br, bl]`), `effects`, `layout` (`direction`, `gap`, `padding` = top/right/bottom/left, `main`, `cross`), `sizing` (child of auto-layout), `text`, `font` ("Poppins SemiBold"), `size`, `color`, `lineHeight`, `icon` (icon frame name, e.g. "Icon / chevronDown") and `iconColor`. `tokens` aggregates colours, text styles, radii, gaps and effects with usage counts.

## Queries (jq)

```sh
SPEC=~/Downloads/weave-design-spec.json
# list frames
jq -r '.pages[] | .name as $p | .frames[] | "\($p) › \(.name)  \(.w)x\(.h)"' "$SPEC"
# one element by exact name, without children
jq '[.. | objects | select(.name? == "Status / Ready")] | .[0] | del(.children)' "$SPEC"
# direct children of a frame, one line each
jq -r '.pages[].frames[] | select(.name == "01 · New Task") | .children[] | "\(.type) \(.name) \(.w)x\(.h) \(.fills // "" | tostring)"' "$SPEC"
# every text node containing a string
jq -r '.. | objects | select(.text? and (.text | test("Advanced settings"))) | "\(.name): \(.font) \(.size) \(.color)"' "$SPEC"
# most used colours
jq '.tokens.colors' "$SPEC" | head -40
```

Look at the matching PNG with the Read tool to see the element in context.

## Mapping rules

- Translate every value to an existing token; add a token only if the value repeats or is clearly a design decision.
- Ignore known export artefacts: glyph names in layer names (e.g. "Button / ▶ Start workflow" — the glyph was replaced by an icon), extra empty space added by earlier automated fixes in frames 21–25, and the broken breakpoint bar in "Sidebar · Expanded & collapsed".
- Copy in the design that contradicts `apps/weave_desktop/AGENTS.md` → Copy rules (worktree, Keychain, push, a fixed Gemini card) must be changed, not reproduced.
