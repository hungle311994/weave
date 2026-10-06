---
paths:
  - "**/*.md"
  - "**/*.yaml"
  - "**/*.json"
---

# Docs and config

## Rules

- **Prettier, width 390**: format the files you changed with `npx --yes prettier@3 --write <files>` (root `.prettierrc`, `.prettierignore` skips `.fvm`, `build`, `pubspec.lock`). The project hook formats files Claude edits. Never add Node as a project dependency.
- **pubspec.yaml**: keep dependencies alphabetical; workspace packages use `resolution: workspace`; new assets or fonts are declared under `flutter:` in the desktop app. Adding a third-party package needs the user's agreement.
- **README.md** describes the product, setup and security model for people; **AGENTS.md** files hold the rules for coding agents (Claude reads them through `CLAUDE.md`). Update the right one when behaviour or conventions change, and keep them truthful — no features that don't exist yet.
- **analysis_options.yaml**: every package keeps `formatter: page_width: 390`, `trailing_commas: preserve` and `always_specify_types: true`.
