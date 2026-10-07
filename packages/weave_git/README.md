# weave_git

Git repository setup, read-only inspection, and approval-gated commits for Weave.

`GitRepositoryCloner` clones an HTTPS or SSH URL into a new child of a parent directory explicitly selected by the user. It rejects embedded credentials, URL query parameters, and fragments, chooses a non-conflicting directory name, and verifies the resulting working tree before returning it.

`GitRepositoryService` finds the repository root and reads the current branch,
`HEAD` commit, detached state, and staged, unstaged, untracked, and conflicted
paths from `git status --porcelain=v2 --branch -z`.

Git runs through `GitCommandRunner` with a separate executable and argument
list, never through a shell. Commands use `--no-optional-locks` and disable
repository fsmonitor hooks, so reading a snapshot does not modify the
repository. Inherited `GIT_*` environment variables are removed, and error
messages never include Git output.

`readDiff` returns staged, unstaged, and untracked patches with a size limit, using `--no-ext-diff --no-textconv` so repository-configured programs never run; untracked symlinks and special files are skipped.

Inside an existing working tree, `GitWriteService.commitAll` is the only write: it classifies the command with `weave_security`, calls an approval gate with the exact file list, and only then runs `git add --all` and `git commit -m <message>`. Clone is a repository setup operation that creates a new directory under the user's selected destination; it never mutates an existing working tree.
