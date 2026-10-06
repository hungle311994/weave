# Weave for macOS

Flutter desktop app for Weave.

- **New workflow**: pick a repository, describe the change, assign an agent to each role, list verification commands, choose MCP servers, and optionally save them as the repository's defaults. Links in the request (e.g. Figma designs) trigger an offer to enable a matching MCP server.
- **Workflow view**: phase progress, live agent activity, approval prompts, plan / implementation / verification / review artifacts, the current diff, cancel, and an approval-gated commit for completed workflows.
- **Agents** and **MCP servers** screens show availability and manage custom MCP servers.

```sh
fvm flutter run -d macos
fvm flutter build macos --release
```

The app runs without App Sandbox (see `macos/Runner/*.entitlements`) because it starts Git, agent CLIs, and checks in arbitrary repositories; sign it with a Developer ID and notarize it for distribution.
