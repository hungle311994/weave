# weave_git

Read-only Git inspection and approval-gated commits for Weave.

`GitRepositoryService` finds the repository root and reads the current branch,
`HEAD` commit, detached state, and staged, unstaged, untracked, and conflicted
paths from `git status --porcelain=v2 --branch -z`.

Git runs through `GitCommandRunner` with a separate executable and argument
list, never through a shell. Commands use `--no-optional-locks` and disable
repository fsmonitor hooks, so reading a snapshot does not modify the
repository. Inherited `GIT_*` environment variables are removed, and error
messages never include Git output.

`readDiff` returns staged, unstaged, and untracked patches with a size limit, using `--no-ext-diff --no-textconv` so repository-configured programs never run; untracked symlinks and special files are skipped.

`GitWriteService.commitAll` is the only write: it classifies the command with `weave_security`, calls an approval gate with the exact file list, and only then runs `git add --all` and `git commit -m <message>`.
