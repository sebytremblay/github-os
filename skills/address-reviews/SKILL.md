---
name: address-reviews
description: Walk the review worklist produced by `pull-reviews` and apply each comment as a `git commit --fixup` onto the correct stack commit, propagate pattern-matched changes across the PR, resolve threads, and post a change-log comment per PR. This skill should be used when the user says "address reviews", "reply to comments", "apply review fixups", or runs `/github-os:address-reviews`.
---

<objective>
Convert every unresolved review comment into either a fixup commit on the correct slice, a reply that dismisses with reason, or a new standalone commit when the change cannot be squashed. Propagate pattern-applicable changes across the rest of the PR. Emit a change-log comment per PR at the end.
</objective>

<allowed-tools>
- `Bash(git:*)`
- `Bash(gh:*)`
- `Bash(jq:*)`
- `Bash(${CLAUDE_PLUGIN_ROOT}/scripts/stack-manifest.sh:*)`
- `Bash(${CLAUDE_PLUGIN_ROOT}/scripts/gh-comments.sh:*)`
- `Read`
- `Edit`
- `Write`
- `Grep`
- `Glob`
- `Agent(fixup-router)`
- `Agent(stack-reviewer)`
- `Skill(conventional-commits)`
- `Skill(pr-description)`
- `Skill(contribute-claude-md)`
- `Skill(push-stack)`
</allowed-tools>

<preconditions>
- Clean working tree.
- `.github-os/stack.json` exists.
- `.github-os/reviews.json` exists — if not, run `pull-reviews` first.
- The user is on a known branch in the stack or on the stack head; never run from a detached HEAD.
</preconditions>

<workflow>

### 1. Load worklist and group by PR

```
WORKLIST=".github-os/reviews.json"
jq -c '.comments | group_by(.pr_number)[]' "$WORKLIST"
```

Process PRs from the *bottom* of the stack upward. Earlier slices get rewritten first, so later slices rebase onto stable ancestors.

### 2. For each comment in each PR

**a. Decide verdict.** Three options:

- `apply` — the comment asks for a code change; make it.
- `dismiss` — the comment is wrong, outdated, or out of scope for this PR; reply with a one-line reason.
- `defer` — the comment asks for follow-up work that is explicitly out of this PR's purpose; reply pointing to a tracking issue, and open the issue with `gh issue create` if one does not exist.

Default to `apply` unless a clear reason dismisses.

**b. If `apply`, route to a target commit.**

Invoke the `fixup-router` agent with: the comment, the slice's commit graph (`git log --oneline <base>..<branch>`), and the touched file. The agent returns a commit SHA and a one-line justification. If it cannot confidently pick, it returns `new_commit: true` and you create a fresh commit instead of a fixup.

**c. Make the change.** Check out the slice's branch, edit the files, and:

- For fixup: `git commit --fixup=<sha>` using the `conventional-commits` skill for the body, if any.
- For new commit: `git commit -m "<conventional message>"`.

Stage only files relevant to the comment. Never stage unrelated drift.

**d. Propagate.** Read the comment intent and scan the rest of the PR for the same pattern. Example: "rename `tok` to `token`" — grep the PR's touched files for `tok\b` and apply the same rename, then commit with `git commit --fixup=<same-sha>`. Record each propagation in the change-log comment's "Propagated changes" section.

**e. Record for later.** Append to an in-memory list:

```
{ comment_id, thread_id, pr_number, verdict, fixup_sha_or_new_sha, propagated_to: [] }
```

### 3. Rebase per slice

After all comments in a slice are addressed:

```
git rebase -i --autosquash <base-branch> --update-refs
```

`--update-refs` is what keeps descendant branches in the stack consistent with the rewritten ancestor.

### 4. Self-audit

After every slice in the stack has been rebased, invoke `stack-reviewer` once on the whole stack. Any new violation from the fixups (e.g. a propagation pulled in an unrelated file) blocks the push. Fix or ask the user.

### 5. Push the stack

Delegate to the `push-stack` skill. Do not call `git push` directly from this skill.

### 6. Post change-log comments

For each PR, compose a change-log comment using the `pr-description` skill's template. Post with:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gh-comments.sh" post-changelog "$PR" "$BODY"
```

### 7. Resolve threads

For every `apply` verdict, post a one-line reply ("addressed — see change log") and resolve the thread:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gh-comments.sh" reply "$COMMENT_ID" "$PR" "addressed — see change log"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gh-comments.sh" resolve-thread "$THREAD_ID"
```

For every `dismiss` verdict, reply with the reason and resolve:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gh-comments.sh" reply "$COMMENT_ID" "$PR" "dismissed — <one-line reason>"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gh-comments.sh" resolve-thread "$THREAD_ID"
```

For `defer`, reply with the tracking issue URL and leave the thread open unless the reviewer's comment clearly asked "for this PR or follow-up", in which case resolve.

### 8. Mine for repeat offenses

Count intents across the session. If any intent appears ≥ 2 times (same PR, different lines; or sibling PRs; or a merged PR from the last 30 days), trigger the `contribute-claude-md` skill with the matching comments as evidence. The skill proposes a CLAUDE.md append or a skill stub; apply only after user confirmation.

### 9. Refresh worklist

Delete `.github-os/reviews.json`. The next round starts from a fresh `pull-reviews`.

</workflow>

<failure-modes>
- **Rebase conflict.** Pause and show the conflict. Never pass `-X theirs` or `-X ours` automatically — the conflict means two review comments disagree and the user must arbitrate.
- **Fixup router uncertain.** Create a new commit instead of forcing a fixup. Better to add a commit than to squash into the wrong ancestor.
- **Propagation explodes.** If a grep returns more than 20 hits, stop and show the hits; ask the user to confirm before applying all.
- **Thread resolution fails.** The thread is likely already resolved by the author; log and continue.
</failure-modes>

<safety>
- Never use `git push --force` — always go through `push-stack`, which uses `--force-with-lease`.
- Never `--no-verify`. If a pre-commit hook fails, fix the underlying issue.
- Never amend a commit that has been merged to the base branch. `fixup-router` must not return a SHA older than `merge-base`.
</safety>
