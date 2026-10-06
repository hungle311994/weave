---
paths:
  - "**/*.dart"
---

# Dart style

Principles: `AGENTS.md` → Code style. This file adds the operational details.

## Rules

- **Format only the files you changed**: `fvm dart format path/to/a.dart path/to/b.dart`. The page width (390) and `trailing_commas: preserve` come from each package's `analysis_options.yaml`, so never pass `-l`. Never format a whole package just to touch one file — it reflows unrelated code and bloats the diff. (The project hook in `.claude/settings.json` already formats each Dart file Claude edits.)
- **A trailing comma is a deliberate line break.** With `preserve`, a comma after the last argument keeps one argument per line. Add one to split a long call; remove it to join. Don't strip existing ones.
- **Explicit types everywhere** (`always_specify_types`): `final List<String> names = <String>[...]`, `for (final MapEntry<String, String>(:String key, :String value) in map.entries)`, `(String value) => ...` in closures, `WidgetStateProperty.resolveWith<Color>(...)`. `jsonDecode` returns `Object?` — narrow it with pattern matching, never cast to `dynamic`. If you run `dart fix --apply` for this lint, review it: it inserts `<dynamic>` into literals that need real types.
- **Imports**: inside a package's own `lib/` use relative imports (`import 'agent_role.dart';`); from tests, tools and other packages use `package:` imports of the public library (`package:weave_agents/weave_agents.dart`), never another package's `src/`.
- **Public API**: every public class, constructor parameter group and non-obvious member gets a `///` doc comment that says what it is for, not how it works. Keep inline `//` comments for reasons the code can't show.
- **Immutability**: prefer `final class` value types with `final` fields and `List<T>.unmodifiable(...)` copies in constructors, as in `AgentDefinition` and `WorkflowTask`. Validate constructor input and throw `ArgumentError`/`FormatException` with the field name.
- **No `print`/`debugPrint`** in packages or the desktop app. Packages report through return values, `WorkflowEvent`s and the event log; only the CLI writes to its output sink.
- **Async**: always `await` or explicitly handle a `Future`; close every `StreamController`, `Process` stream subscription and `ChangeNotifier` you create.
