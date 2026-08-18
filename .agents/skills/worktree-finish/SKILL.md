---
name: worktree-finish
description: Safely finish a Worktrunk feature worktree by rebasing it onto the local main branch, fast-forward merging it into main, validating the result, and removing the merged worktree. Use when the user explicitly asks to finish, integrate, merge, or clean up a completed feature worktree with this rebase-plus-ff-only flow.
---

# Worktree Finish

Complete a finished feature worktree with this fixed sequence:

1. Confirm current feature worktree and branch.
2. Require clean feature worktree; stop if uncommitted or untracked files exist.
3. Require local `main` branch and its worktree.
4. Rebase feature branch onto local `main`.
5. Run the smallest relevant validation, plus `git diff --check`.
6. Require clean `main` worktree.
7. Run `git merge --ff-only <feature-branch>` from the `main` worktree.
8. Verify `main` contains the feature commit and remains clean.
9. Run `wt remove --foreground <feature-branch>` from the `main` worktree.
10. Verify feature worktree and branch were removed.

Use `rtk` before every shell command in this repository. Use absolute paths as
`workdir` values rather than relying on `cd` state.

## Safety rules

- Perform this flow only after an explicit user request.
- Never use `git reset --hard`, `git checkout --`, `wt remove -f`, or `wt remove -D`.
- Do not stash or overwrite dirty changes. Stop and report the exact dirty worktree.
- Stop on rebase conflicts, validation failures, a dirty `main`, or a failed
  fast-forward merge. Preserve the worktree for recovery.
- Use local `main` as the rebase and merge target. Do not silently substitute
  `origin/main`.
- Keep the feature worktree if removal fails. Never delete an unmerged branch.

## Commands

From the feature worktree, inspect:

```sh
rtk git status --short --branch
rtk git branch --show-current
rtk git rev-parse --show-toplevel
rtk git show-ref --verify refs/heads/main
rtk git worktree list --porcelain
```

Record the feature branch and the worktree path whose branch is
`refs/heads/main`. Require both worktrees to be clean before changing history.

Rebase and validate in the feature worktree:

```sh
rtk git rebase main
rtk git diff main...HEAD --check
```

Run the repository's relevant checks. For Swift source or test changes, use
the repository's preferred `just` task and run `just check` when required by
`AGENTS.md`. Do not merge a failed validation.

Merge from the `main` worktree:

```sh
rtk git merge --ff-only <feature-branch>
rtk git status --short --branch
rtk wt remove --foreground <feature-branch>
```

Use the branch name, not a guessed path, for `wt remove`. Omit force flags so
Worktrunk deletes the branch only after it is merged and the worktree is clean.

Finish with:

```sh
rtk git status --short --branch
rtk git worktree list --porcelain
rtk git show-ref --verify refs/heads/<feature-branch>
```

The final branch lookup should fail because `wt remove` deleted the merged
feature branch. Report the resulting `main` commit, validation status, and any
failure without hiding it.
