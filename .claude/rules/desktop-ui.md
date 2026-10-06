---
paths:
  - "apps/weave_desktop/lib/**/*.dart"
---

# Desktop UI

Principles: `apps/weave_desktop/AGENTS.md` (design source, folder structure, UI rules, copy rules). This file adds the operational details.

## Rules

- **Where code goes**: shared visuals → `lib/core/design_system/components/<group>/`; a screen, its controller and its dialogs → `lib/features/<feature>/presentation/`; what the screen needs from Weave → `domain/` (entities, use cases, repository interfaces, no Flutter imports) implemented in `data/` on top of the `weave_*` packages. Never add files to `lib/src/` (legacy, being migrated). Use `/new-feature` and `/new-component` to scaffold.
- **Only design-system building blocks in features**: compose `WeaveCard`, `WeaveButton`, `WeaveStatusPill`, `WeaveBadge`, `WeaveChip`, `WeaveTextField`, `WeaveIcon`, `BrandIcon` … and import them through `package:weave/core/design_system/design_system.dart`. A raw `Container`/`DecoratedBox` with its own colours, a `TextStyle(...)` literal, `Colors.*`, `Color(0x…)` or a bare number for padding/radius in feature code is a review failure — add or extend a component or token instead.
- **Tokens**: colours `WeaveColors`, tints `WeaveColors.tint()/tintBorder()`, text `WeaveTypography`, spacing `WeaveSpacing.s*`, radii `WeaveRadii`, layout sizes `WeaveLayout`, shadows/gradients/motion `WeaveShadows`/`WeaveGradients`/`WeaveMotion`. Take values from the Figma spec (`/design-spec`); when a value isn't a token yet, add it to the token file with a doc comment naming where the design uses it.
- **Components**: `StatelessWidget` with `const` constructors and named parameters; a nullable callback (`onPressed`, `onTap`) means disabled (45 % opacity). Interactive surfaces put the decoration in a `DecoratedBox` with a transparent `Material` + `InkWell` inside (not `Ink` — it adds the border width to the size). Give icon-only buttons a tooltip; expose `Semantics(button: true, enabled: …)`; keep keyboard activation working.
- **Controllers**: one `ChangeNotifier` per screen in `presentation/`, receiving repositories/use cases through its constructor; widgets read it with `ListenableBuilder`. Dispose controllers, `TextEditingController`s, `FocusNode`s and subscriptions you create. After an `await` in a `State`, check `mounted` before touching `context`.
- **Copy**: user-facing text must match what Weave does — run `/check-copy` before finishing a screen (no "isolated worktree", no Keychain, no push, no hard-coded agent list, Pause only when it exists).
- **Agents and integrations**: render from data (agent ID, display name, `BrandMark.byName(...)`), never from a hard-coded list of providers.
- **Responsive**: lay out with `Expanded`/`Flexible`/constraints, not fixed screen widths, and check the minimum window (`WeaveLayout.minimumWindow`, 1100 × 720) with the sidebar collapsed and expanded.
