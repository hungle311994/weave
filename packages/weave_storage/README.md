# weave_storage

External, local-first persistence for Weave workflow state.

On macOS, state defaults to `~/Library/Application Support/Weave`. The
`WEAVE_HOME` environment variable can select another absolute location. Task
IDs are encoded before becoming directory names, and task JSON is written
through a temporary file before replacement.

`FileWorkflowArtifactStore` keeps each workflow's artifacts (plan, implementation, self-review, verification, review per round) and an append-only `events.jsonl` log next to the task. Every stored text is redacted, log lines are size-capped, and a partially written final log line from a crash is ignored.
