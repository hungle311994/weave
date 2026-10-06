---
name: new-feature
description: Scaffold a clean-architecture feature in the Weave desktop app (lib/features/<name>/{domain,data,presentation}) — pure-Dart domain, data layer adapting the weave_* packages, ChangeNotifier controller and page built from design-system components, wired through the app composition root, with tests per layer. Use when adding or migrating a screen.
---

# New desktop feature

## Step 1 — Define the feature

Name it after the user-facing area in snake_case: `new_task`, `workflow_run`, `plan_review`, `code_review`, `commit`, `agents`, `integrations`, `settings`, `workspace`, `chat`, `shell`. Find its screens and dialogs in the Figma export (`/design-spec`) and list what data the screen shows and which actions it triggers.

## Step 2 — Domain (`lib/features/<name>/domain/`) — pure Dart

- `entities/`: immutable `final class` values the screen needs, shaped for the UI (e.g. `AgentCardData`), not raw package types when those carry more than the screen needs.
- `repositories/<name>_repository.dart`: an `abstract interface class` with the operations the feature needs (`Future<List<…>> load…()`, `Future<void> start…()`).
- `use_cases/`: only when logic combines several repository calls or holds a rule worth testing on its own (e.g. building split-diff rows). One public `call(...)` method.
- No `package:flutter` imports here.

## Step 3 — Data (`lib/features/<name>/data/`)

- `<name>_repository_impl.dart` implements the interface on top of `WeaveServices` and the `weave_*` packages; map package types to domain entities here.
- No business rules duplicated from the packages — call them.

## Step 4 — Presentation (`lib/features/<name>/presentation/`)

- `<name>_controller.dart`: `ChangeNotifier` taking the repository (or use cases) in its constructor; exposes immutable state getters and intent methods; catches failures into a user-facing error state; `dispose()` cleans up.
- `<name>_page.dart` and `widgets/`, `dialogs/`: built only from `core/design_system` components and tokens; read the controller with `ListenableBuilder`. Check `mounted` after `await` before using `context`.
- Copy follows `apps/weave_desktop/AGENTS.md` → Copy rules; run `/check-copy`.

## Step 5 — Wire it

Register the repository and controller in the composition root under `lib/app/` (create the scope/wiring there if it doesn't exist yet) and add the route/navigation entry. Widgets never construct services themselves.

## Step 6 — Tests (mirror the folders under `test/features/<name>/`)

- domain/use cases: plain `test(...)` with fake repositories.
- data: against real packages with a temporary `WEAVE_HOME`, a temporary Git repository and `ScriptedAgentAdapter` — no real agents.
- presentation: controller unit tests with a fake repository; widget tests for the page (loading, data, error, main actions) using the real theme.

## Step 7 — Verify

Run `/verify-step`, then check the screen at the minimum window size (1100 × 720) with the sidebar collapsed and expanded.
