---
name: push-stack
description: Force-with-lease push every branch in the current stack and rebase descendants so the stack stays consistent on GitHub. This skill should be used when the user says "push the stack", "push all branches", "sync the stack to GitHub", or runs `/github-os:push-stack`. Called by `address-reviews` and also usable standalone after a local rebase.
---

<objective>
Publish local stack state to GitHub safely. Every push is `--force-with-lease` to detect upstream changes. Descendant branches get rebased onto their freshly-pushed parents before pushing so the stack remains a linear chain of PRs.
</objective>

<allowed-tools>
- `Bash(git:*)`
- `Bash(gh:*)`
- `Bash(jq:*)`
- `Bash(${CLAUDE_PLUGIN_ROOT}/scripts/stack-manifest.sh:*)`
- `Read`
</allowed-tools>

<preconditions>
- `.github-os/stack.json` exists.
- Working tree is clean.
- The user's `gh` session is authenticated and has push access to each PR branch.
</preconditions>

<workflow>

### 1. Load the manifest

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/stack-manifest.sh" show > /tmp/stack.json
BRANCHES="$(jq -r '.prs | sort_by(.index) | .[].branch' /tmp/stack.json)"
```

### 2. Verify lease targets

For each branch, read the current remote tip:

```
git fetch origin --quiet
git rev-parse "origin/$BRANCH"
```

If any remote tip differs from what the manifest recorded in `head_sha` and the local branch is *not* a descendant of the remote tip, stop: someone pushed to this branch since the last manifest update. Ask the user to rebase manually — automatic overwrite risks losing reviewer-pushed commits (e.g., "Apply suggestion" from the GitHub UI).

### 3. Rebase descendants

Walk the branches in index order. For each branch after the first:

```
git checkout "$BRANCH"
git rebase --update-refs "$PARENT_BRANCH"
```

`--update-refs` keeps the whole stack's local branch refs moving in lockstep; without it, later branches would have to rebase twice.

### 4. Push

For each branch in index order:

```
git push --force-with-lease=origin/"$BRANCH":"$(git rev-parse origin/$BRANCH)" origin "$BRANCH"
```

The explicit lease value matches the remote tip we sampled in step 2. This makes the lease robust even if `git fetch` runs between checks.

### 5. Update the manifest

For each branch, record the new head SHA:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/stack-manifest.sh" set-sha "$BRANCH" "$(git rev-parse $BRANCH)"
```

### 6. Refresh PR bodies if stack indices shifted

If the count or order of slices changed since the PRs were first opened, walk each PR and update its body's Stack position and Siblings sections per the `pr-description` skill's rules. Nothing else in the body changes.

### 7. Report

```
Pushed N branches:
  - feat-x/01-extract-parser      abc123 -> def456
  - feat-x/02-add-error-spans     111222 -> 333444
  ...
All PRs remain draft. Run `gh pr ready <n>` to flip when review-ready.
```

</workflow>

<failure-modes>
- **Lease rejected.** Someone pushed since the last fetch. Stop. Do not retry with a fresh lease automatically — that defeats the safety.
- **Rebase conflict on a descendant.** Stop in the middle of the stack, report which branch conflicted, and leave the user on that branch so they can resolve.
- **Branch has no upstream.** Happens when `slice-stack` was interrupted. Run `git push -u origin <branch>` the first time; on subsequent runs the `--force-with-lease` path takes over.
</failure-modes>

<safety>
- Never run `git push --force` without `--force-with-lease`. The `pre-push-guard` hook will block it anyway, but this skill must not even try.
- Never push to a branch whose name matches `main`, `master`, `develop`, `release/*`, or `hotfix/*`. These are never stack branches; if they appear in the manifest, the manifest is corrupted.
- Never push with `--no-verify`.
</safety>
