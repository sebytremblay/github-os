---
name: pr-description
description: Author pull request bodies and change-log comments for stacked PRs produced by the github-os workflow. This skill should be used whenever drafting a PR body, updating an existing PR body after a rebase, or posting a change-log comment summarizing fixup activity. Apply it automatically from `slice-stack`, `address-reviews`, and `push-stack`.
---

<objective>
Every PR body and change-log comment produced by the github-os plugin follows the same shape so that a reviewer can answer three questions at a glance: where does this PR sit in the stack, could this PR ship on its own, and what changed since the last review pass.
</objective>

<pr-body-template>
```markdown
## Purpose

<one sentence — what this PR does, not how>

## Stack position

- Index: **N of M**
- Base: `<base-branch>`
- Next: `<next-branch-or-"terminal">`
- Siblings:
  - #<pr-number> — <sibling purpose>
  - ...

## Standalone?

<one of:>
- **Yes.** This PR compiles, passes tests, and is shippable without any PR after it.
- **No.** This PR depends on #<pr> because <reason>. Merge order: #<first>, #<second>, ...

## Overlap notes

<files or modules touched by more than one PR in the stack, with a one-line note on why the split is safe. Omit this section if there is no overlap.>

## Summary of changes

- <bullet 1>
- <bullet 2>
- ...

## Test plan

- [ ] <what you ran or will run to verify>
```
</pr-body-template>

<rules>
- **Title.** Use the Conventional Commits subject of the PR's single squash-target commit. Keep it under 72 characters. Prefix with the stack index inside brackets: `[2/4] feat(parser): extract tokenizer`.
- **Draft first.** Every PR opens as a draft. The author flips it to ready-for-review after `stack-self-review` passes.
- **Sibling links.** List *every* other PR in the stack, not just adjacent ones. Link by `#<number>` once the PRs exist; otherwise use branch name and update after creation.
- **Standalone verdict.** Never leave this section blank. If the answer is "no", the stack is mis-sliced and you must escalate to `stack-self-review` before opening PRs.
- **Overlap notes.** Only include when two or more PRs touch the same file. State the rationale: "`parser.ts` is edited in #412 (extract tokens) and #413 (add error spans); the splits are disjoint line ranges and #413 rebases cleanly after #412."
- **Test plan.** Concrete commands or scenarios, not aspirations. If CI covers it, say "CI" and name the job.
</rules>

<changelog-comment-template>
Post this comment on each PR at the end of every `address-reviews` pass:

```markdown
## Change log — <UTC-timestamp>

**Commits added (fixup targets in parentheses):**
- `<short-sha>` fixup! <original subject>  — addresses thread #<thread-id>
- ...

**Files touched this pass:**
- `path/to/file.ts`
- ...

**Review threads:**
- Resolved (addressed): #<id>, #<id>
- Resolved (dismissed + reason): #<id> — <one-line reason>

**Propagated changes:** <none | list of sibling PRs that received the same pattern>
```
</changelog-comment-template>

<changelog-rules>
- Post exactly one change-log comment per `address-reviews` pass, per PR. Do not edit prior change-log comments; always append a new one.
- List thread IDs, not comment IDs. Reviewers follow threads; comment IDs are noisy.
- "Propagated changes" is the teaching surface — it is how the reviewer learns which comments the agent generalized. Never omit it.
</changelog-rules>

<update-after-rebase>
When the stack is rebased and branches move, re-open each PR body and update:

1. Stack position if indices shifted.
2. Sibling list if PRs were added, merged, or closed.
3. Standalone verdict if dependencies changed.

Do not rewrite the summary or test plan during a rebase update. Those are historical for the review.
</update-after-rebase>
