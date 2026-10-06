# Weave desktop — guide for coding agents

Flutter macOS app (`package:weave`). The repository-wide rules in `../../AGENTS.md` apply; this file adds the UI rules. `CLAUDE.md` imports it.

## Design source

- The design lives in Figma (file `qLUeyOZj96lIorCcMIyeVA`, pages "10 · Product screens" and "20 · Dialogs & flows"). Its values are already captured in `lib/core/design_system/tokens/`; **the tokens are the source of truth in code** — if a value is missing, add a token instead of hard-coding it.
- The app is **dark-only** (`WeaveTheme.dark()`, `ThemeMode.dark`). Do not add a light theme.
- Fonts: Poppins 400/500/600/700, bundled in `assets/fonts/poppins/` with its OFL licence (registered in `main.dart`). Never load fonts from the network.

## Folder structure (clean architecture)

```
lib/
  app/                     composition root: bootstrap, dependency wiring, navigation, window
  core/
    design_system/         tokens/, theme/, icons/, components/ — exported by design_system.dart
    utils/                 formatting helpers shared by features
  features/<feature>/
    domain/                entities, use cases, repository interfaces — pure Dart, no Flutter imports
    data/                  repository implementations wrapping the weave_* packages
    presentation/          ChangeNotifier controllers, pages, widgets, dialogs
```

- `lib/src/` holds the pre-redesign code and is being migrated into `app/` and `features/`; do not add new code there.
- Business logic stays in the `weave_*` packages. A feature's `data` layer adapts them; its `domain` layer defines what the UI needs; `presentation` depends on `domain` only (receive repositories/use cases through the constructor or the app scope, never construct services in widgets).
- State: `ChangeNotifier` + `ListenableBuilder`. Do not add a state-management package without the user's agreement.

## UI rules

- Build screens only from `core/design_system` components (`WeaveButton`, `WeaveIconButton`, `WeaveCard`, `WeaveStatusPill`, `WeaveBadge`, `WeaveChip`, `WeaveTextField`, …). If a screen needs something new, add a reusable component with tests first — no one-off styled `Container`s in feature code.
- Use tokens for every colour (`WeaveColors`), text style (`WeaveTypography`), spacing and radius (`WeaveSpacing`, `WeaveRadii`), shadow, gradient and motion (`WeaveShadows`, `WeaveGradients`, `WeaveMotion`). No raw `Color(0x…)`, font sizes or magic numbers in features.
- Status colours go through `WeaveTone`; agent and integration logos through `BrandIcon`/`BrandMark.byName` (from data, never by hard-coding an agent ID).
- Icons are `WeaveIcon(WeaveIcons.x)`. To add one, edit `tool/icons/icon_sources.dart` and run `fvm dart run tool/generate_icons.dart` (`--brands <folder>` rebuilds the brand marks); add the enum value in `lib/core/design_system/icons/weave_icons.dart`. Icons must stay single-colour black SVGs — they are tinted at runtime.
- Interactive components must work with the keyboard (focus + Enter/Space), expose semantics (button role, labels for icon-only buttons via the tooltip), and show a 45 % opacity disabled state.
- Layout: minimum window 1100 × 720, default 1600 × 1000; sidebar 288 px expanded / 72 px collapsed, expanded by default from 1360 px wide (`WeaveLayout`). Content must reflow without overlapping at the minimum size.

## Copy rules (product truth)

The UI must describe what Weave really does:

- Weave edits the repository's working tree directly, guarded (uncommitted edits only; HEAD and branch must not move). Never say "isolated worktree" or "separate branch".
- Weave stores no credentials. Agents keep their own sign-in; MCP tokens are `${VAR}` environment references. Never mention the macOS Keychain.
- Weave never pushes. A finished workflow is "Done", never "ready to push".
- Agent permissions are a fixed policy (read-only planner/reviewer, implementer limited to edits, Weave runs verification, commits need approval). Show it read-only; only real settings (checkpoints, review limit, token budget, verification commands) get controls.
- Show the Pause action only once the pause feature exists. The agent list comes from presets plus `agents.json` — never a hard-coded list.

## Testing

- `fvm flutter test --no-pub` from this folder. Component tests use `test/helpers/design_system_harness.dart` (`pumpComponent`, `decorationAround`) and assert the design values (colours, sizes, semantics), not only that a widget exists.
- `test/tool/icon_sources_test.dart` fails while an icon asset is stale.
- Run the app with `fvm flutter run -d macos`; set `WEAVE_HOME` to an empty folder to try it without touching real data.
