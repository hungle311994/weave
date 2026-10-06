---
name: new-component
description: Scaffold a reusable Weave design-system component (lib/core/design_system/components) from the Figma spec — token-only styling, keyboard and semantics support, barrel export, and a widget test that asserts the design values. Use when a screen needs a visual element that the design system does not have yet.
---

# New design-system component

## Step 1 — Check it doesn't exist

Read `apps/weave_desktop/lib/core/design_system/design_system.dart` and the files it exports. Prefer extending an existing component (a new variant, size or optional parameter) over adding a near-duplicate.

## Step 2 — Get the exact design values

Use `/design-spec` to find the element in the Figma export: size, padding (`layout.padding` is top, right, bottom, left), gap, radius, fills, strokes, effects, text font/size/colour, icon name and size. Map every value to a token (`WeaveColors`, `WeaveTypography`, `WeaveSpacing`, `WeaveRadii`, `WeaveLayout`, `WeaveShadows`, `WeaveGradients`, `WeaveMotion`, `WeaveTone`). If a value has no token, add one with a doc comment saying where the design uses it.

## Step 3 — Write the component

Location: `lib/core/design_system/components/<group>/weave_<name>.dart`, where `<group>` is one of `buttons`, `surfaces`, `feedback`, `inputs`, `navigation`, `layout`, `data`, `overlays`.

Conventions (see `buttons/weave_button.dart` and `surfaces/weave_card.dart`):

- `StatelessWidget` (stateful only for real local state), `const` constructor, named parameters, `super.key` last; named constructors for common variants (`WeaveButton.primary`).
- Variants as an `enum` with a `///` doc comment per value naming the design example.
- A nullable callback disables the component: wrap in `Opacity(opacity: enabled ? 1 : 0.45)`.
- Interactive: `Semantics(button: true, enabled: …)` → `DecoratedBox(decoration)` → `Material(type: MaterialType.transparency)` → `InkWell(onTap, borderRadius, splashFactory: NoSplash.splashFactory, hoverColor: onAccent 6 %, focusColor: purple 22 %)`. Not `Ink` — it adds the border width to the size.
- Icon-only controls get a `Tooltip` whose message is also the semantics label.
- Text uses `WeaveTypography` styles with `copyWith` for colour/weight only; long labels get `maxLines: 1, overflow: TextOverflow.ellipsis`.
- No `Colors.*`, `Color(0x…)`, `TextStyle(...)` literals or bare spacing numbers.

## Step 4 — Export and showcase

- Add `export 'components/<group>/weave_<name>.dart';` to `design_system.dart` (keep the list alphabetical).
- If a component gallery exists in the app, add the component with every variant and state to it.

## Step 5 — Test

Create `test/core/design_system/weave_<name>_test.dart` (or extend the group's test file) using `pumpComponent` and `decorationAround` from `test/helpers/design_system_harness.dart`. Assert, for each variant: colours/gradient/border from tokens, the size from the design (e.g. 44 px), the callback fires on tap, the disabled state ignores taps and reports `isSemantics(isButton: true, hasEnabledState: true, isEnabled: false)`, and keyboard activation (Tab then Enter) works.

## Step 6 — Verify

Run `/verify-step`.
