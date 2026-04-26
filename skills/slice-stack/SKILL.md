---
name: slice-stack
description: Decompose the current branch vs. its base into a stack of single-purpose draft PRs. This skill should be used when the user has finished a large feature locally and asks to "slice this into PRs", "stack this change", "split this branch", "open draft PRs", or runs `/github-os:slice-stack`. Produces a dry-run plan, invokes `stack-self-review`, then creates per-slice branches and opens draft PRs via `gh`.
---

<objective>
Transform a finished feature branch into a stack of small, single-purpose, standalone draft PRs. Each slice targets a single responsibility, respects a 600 LOC soft cap, and ships with a PR body that names its stack position, siblings, and overlap notes.
</objective>

<inputs>
- Current branch (HEAD), assumed to be the feature branch.
- Base branch, resolved in this order: `$1` (user argument), the branch the feature was created from per `git merge-base --fork-point`, then `main` or `master`.
- Clean working tree. If `git status --porcelain` is non-empty, stop and ask the user to commit or stash.
</inputs>

<allowed-tools>
- `Bash(git:*)`
- `Bash(gh:*)`
- `Bash(jq:*)`
- `Bash(${CLAUDE_PLUGIN_ROOT}/scripts/stack-manifest.sh:*)`
- `Read`
- `Write`
- `Edit`
- `Grep`
- `Glob`
- `Agent(stack-reviewer)`
</allowed-tools>

<workflow>

### 1. Gather the diff

```
git fetch origin --quiet
BASE="$(git merge-base HEAD origin/<base-branch>)"
git log --reverse --oneline "$BASE"..HEAD
git diff --stat "$BASE"..HEAD
```

Read each changed file. Do not skim. The slicing decision depends on what the change actually is, not on the commit messages.

### 2. Propose slices

Draft slices by semantic cluster, not by commit. Targets:

- **Single purpose.** One slice, one sentence of intent.
- **Standalone.** The litmus test: "Could this PR merge on Monday and the rest land on Friday without breaking main?" If the answer is no, the slice is wrong.
- **Soft cap 600 LOC** of added-plus-removed. Exceed only when splitting would hurt review comprehension more than a large diff would.

Write the dry-run plan as a JSON array:

```json
[
  {
    "index": 1,
    "branch": "<feature>/01-<slug>",
    "base_branch": "<base>",
    "purpose": "<one sentence>",
    "files": ["path/a.ts", "path/b.ts"],
    "loc_estimate": 180,
    "overlaps_with": []
  },
  ...
]
```

### 3. Self-review the plan

Invoke the `stack-reviewer` agent with the dry-run plan and the diff. The agent returns a punch list of violations (multi-purpose slice, cross-slice leakage, LOC over cap, broken standalone property). **Do not create branches until the punch list is empty or the user accepts each remaining violation.**

### 4. Create the stack

For each slice in order:

```
git checkout -b <slice-branch> <base-ref>
git cherry-pick <range>   # or apply the subset of hunks that belong to this slice
git push -u origin <slice-branch>
gh pr create --draft \
  --base <base-ref> \
  --head <slice-branch> \
  --title "[<index>/<total>] <conventional-commits subject>" \
  --body "<pr-description per pr-description skill>"
```

The first slice's `<base-ref>` is the resolved base branch (e.g. `main`). Each subsequent slice uses the previous slice's branch as its base — that is what makes it a stack.

When a slice needs hunks from multiple existing commits (not a whole commit range), use `git checkout -p <base-ref> -- <file>` to import only the relevant hunks, then commit with a Conventional Commits message via the `conventional-commits` skill.

### 5. Record the manifest

After each PR opens, record it:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/stack-manifest.sh" init <base> <head>   # first slice only
bash "${CLAUDE_PLUGIN_ROOT}/scripts/stack-manifest.sh" add-pr \
  --index <n> --branch <slice-branch> --base-branch <base> \
  --pr-number <pr> --head-sha "$(git rev-parse <slice-branch>)" \
  --loc <loc> --purpose "<purpose>"
```

### 6. Report

Print a summary table:

```
# | branch                    | PR  | base              | LOC | purpose
1 | feat-x/01-extract-parser  | #412| main              | 180 | Extract parser into its own module
2 | feat-x/02-add-error-spans | #413| feat-x/01-…       | 210 | Surface error spans on tokens
...
```

</workflow>

<failure-modes>
- **Base ambiguous.** If `git merge-base --fork-point` fails and no arg was given, ask the user.
- **Working tree dirty.** Stop. Never stash silently — the user may not want their WIP included.
- **Slice exceeds 600 LOC.** Do not split automatically. Escalate to the user with a proposal for sub-slicing, because the correct split needs domain judgement.
- **PR creation fails mid-stack.** Record the partial manifest, delete no branches, and tell the user which slice failed and what `gh` error was returned. The workflow is resumable.
</failure-modes>

<safety>
- Never force-push in this skill. All pushes are the initial `-u origin <branch>`.
- Never close or modify existing PRs on the current branch. If `gh pr list --head <branch>` returns results, stop and ask.
- Always open as draft. The author runs `stack-self-review` and flips to ready-for-review manually.
</safety>
