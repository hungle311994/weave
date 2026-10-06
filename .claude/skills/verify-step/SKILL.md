---
name: verify-step
description: Verify a Weave change before reporting it done — format only the changed files, run the analyzer for the whole workspace, run the tests of every touched package plus the packages that depend on it, and report the results honestly. Use at the end of every numbered step or any code change.
---

# Verify step

## Why this matters

The user reviews each step before the next one starts. A report that says "done" while a package three levels up no longer compiles, or that skips a failing test, costs a full review round. This skill makes the check complete and the report trustworthy.

## Step 1 — Collect the changed files

```sh
git status --porcelain
```

The repository may have no commits yet, so everything can show as untracked; in that case use the files you edited in this step (you know them) rather than the whole tree. Split them into Dart files, Markdown/JSON/YAML files, and assets.

## Step 2 — Format only those files

```sh
fvm dart format <changed .dart files>
npx --yes prettier@3 --write <changed .md/.json/.yaml files>
```

Never format whole packages. If formatting changed a file, mention it (the user may have it open).

## Step 3 — Analyze the workspace

From the repository root:

```sh
fvm dart analyze
```

The bar is `No issues found!` — infos included. Fix every issue; don't add `// ignore:` unless the user agrees.

## Step 4 — Run the affected tests

Map each changed file to its package and add every package that depends on it (internal dependency direction: `weave_core`/`weave_security` → `weave_agents`/`weave_git`/`weave_storage` → `weave_workflow` → `apps/weave_cli`, `apps/weave_desktop`):

| Changed package  | Also test                                    |
| ---------------- | -------------------------------------------- |
| `weave_core`     | agents, storage, workflow, cli, desktop      |
| `weave_security` | agents, git, storage, workflow, cli, desktop |
| `weave_agents`   | workflow, cli, desktop                       |
| `weave_git`      | workflow, cli, desktop                       |
| `weave_storage`  | workflow, cli, desktop                       |
| `weave_workflow` | cli, desktop                                 |
| `apps/*`         | — (only itself)                              |

Run from each package folder: `fvm dart test` for pure Dart packages and the CLI, `fvm flutter test --no-pub` for `apps/weave_desktop`. For desktop icon or asset changes, also run `fvm dart run tool/generate_icons.dart --check` there.

## Step 5 — Report

Report in the user's language (Vietnamese for this user) with:

- the goal of the step and what changed, as clickable file links;
- the exact verification results: analyzer output line, `N/N tests passed` per package (or the failing test names and messages);
- anything not verified (e.g. not run in the real app) — say so plainly;
- then stop and wait for the user's "đã xong" before starting the next step. Never commit.
