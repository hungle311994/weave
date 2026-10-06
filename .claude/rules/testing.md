---
paths:
  - "**/test/**/*.dart"
---

# Testing

Principles: `AGENTS.md` → Testing. This file adds the operational details.

## Rules

- **Run via FVM** from the package folder: `fvm dart test` (packages, CLI) or `fvm flutter test --no-pub` (desktop). Run one file with its path. Run the relevant tests before a change (baseline) and after it; use `/verify-step` to run the full set for a change.
- **Mirror the source layout**: `lib/src/x/y.dart` → `test/x/y_test.dart`; desktop `lib/core/design_system/...` → `test/core/design_system/...`, `lib/features/<f>/...` → `test/features/<f>/...`.
- **No real agents, network or user data.** Use `ScriptedAgentAdapter` from `package:weave_agents/testing.dart` for agent behaviour, a temporary directory for `WEAVE_HOME`/`WeaveStoragePaths`, and a temporary Git repository created in `setUp` (deleted in `tearDown`). Never call a real `codex`/`claude` binary or the Figma API.
- **Desktop widget tests with real I/O** (Git, files, processes) must let that I/O finish outside FakeAsync: use `pumpUntil` and `tapReal` from `test/widget_test.dart` (move them into `test/helpers/` when a second file needs them) rather than `pumpAndSettle`, which can hang.
- **Component tests** use `test/helpers/design_system_harness.dart` (`pumpComponent`, `decorationAround`) and assert design values — colour, gradient, border, size, semantics, keyboard activation — not just that the widget is found.
- **Test names describe behaviour** (`'a disabled button is dimmed and ignores taps'`), grouped with `group(...)` when one unit has several cases.
- **Never weaken an assertion to make a test pass.** If a test fails after your change, decide whether the code or the test is wrong and say which; a mismatch with the design (e.g. 46 px instead of 44 px) is a code bug.
