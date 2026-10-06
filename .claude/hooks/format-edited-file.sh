#!/bin/sh
# PostToolUse hook: formats the file Claude just wrote or edited, the same way the
# project rules require — Dart with `fvm dart format` (page width from the package's
# analysis_options.yaml), Markdown/JSON/YAML with Prettier (root .prettierrc).
# Never blocks the edit: any failure is ignored.

file=$(jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$file" ] && [ -f "$file" ] || exit 0

case "$file" in
  "$CLAUDE_PROJECT_DIR"/*) ;;
  *) exit 0 ;;
esac

case "$file" in
  */.fvm/* | */build/* | */.dart_tool/* | */macos/Pods/* | */pubspec.lock) exit 0 ;;
  *.dart) cd "$CLAUDE_PROJECT_DIR" && fvm dart format "$file" >/dev/null 2>&1 ;;
  *.md | *.json | *.yaml | *.yml) cd "$CLAUDE_PROJECT_DIR" && npx --yes prettier@3 --write "$file" >/dev/null 2>&1 ;;
esac
exit 0
