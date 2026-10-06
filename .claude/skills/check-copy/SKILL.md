---
name: check-copy
description: Audit user-facing text in the Weave desktop app and CLI for claims that contradict how Weave works (isolated worktree, separate branch, macOS Keychain, push, hard-coded agent lists, a Pause action without the feature). Read-only — reports each hit with a suggested replacement.
---

# Check copy

## Why this matters

The Figma design was drawn before some product decisions and promises things Weave does not do. Shipping that copy misleads users about safety (where edits happen, where secrets live, whether code leaves the machine). The truth is in `apps/weave_desktop/AGENTS.md` → Copy rules.

## Step 1 — Search

From the repository root:

```sh
grep -rniE "worktree|separate branch|keychain|push|gemini|pause" apps/weave_desktop/lib apps/weave_cli/lib --include=*.dart
```

## Step 2 — Judge each hit

Only string literals shown to people matter; identifiers and comments are fine unless a comment documents behaviour wrongly.

| Found                                           | Verdict                                          | Suggested copy                                                             |
| ----------------------------------------------- | ------------------------------------------------ | -------------------------------------------------------------------------- |
| "isolated worktree", "separate branch"          | Wrong — Weave edits the working tree directly    | "Uncommitted edits only · HEAD and branch guarded"                         |
| "Keychain", "stored securely"                   | Wrong — Weave stores no credentials              | "Uses the agent's own sign-in" / "Tokens are read from `${VAR}` at launch" |
| "push", "ready to push"                         | Wrong unless it says Weave never pushes          | "Done" / "Weave never pushes"                                              |
| A fixed list of agents (e.g. "Gemini CLI" card) | Wrong — agents come from presets + `agents.json` | Render from data                                                           |
| "Pause"                                         | Wrong until the pause feature exists             | Hide the action                                                            |
| Shell/network "Ask" toggles                     | Wrong — the permission policy is fixed           | Read-only policy view                                                      |

## Step 3 — Report

List each problem as `file:line — "current text" → suggestion`. Do not edit unless the user asks. If nothing is found, say which patterns were checked.
