# github-os

Use GitHub as an agent control plane. After you finish a feature locally, this plugin slices the change into a stack of single-purpose draft PRs, replies to every review comment with `git commit --fixup` + `git rebase --autosquash`, and mines repeat offenses into `CLAUDE.md` rules and new skills.

## What you get

| Entry point | Kind | Purpose |
|---|---|---|
| `/github-os:slice-stack` | skill | Decompose the current branch into a stack of draft PRs. |
| `/github-os:stack-self-review` | skill | Pre-flight audit of the proposed stack. |
| `/github-os:pull-reviews` | skill | Pull every review comment into a local worklist. |
| `/github-os:address-reviews` | skill | Apply every comment with fixup + autosquash, propagate patterns, resolve threads. |
| `/github-os:push-stack` | skill | Force-with-lease push every branch and rebase descendants. |
| `/github-os:extract-patterns` | skill | Mine addressed comments for repeat offenses and propose CLAUDE.md or skill additions. |

Passive rule skills (`conventional-commits`, `pr-description`, `contribute-claude-md`) trigger automatically when the plugin drafts commit messages, PR bodies, or new project rules.

Two agents (`stack-reviewer`, `fixup-router`) do the heavy reasoning about stack shape and fixup targeting.

One safety hook (`pre-push-guard`) blocks bare `git push --force` and blocks pushes that skip hooks.

## Prerequisites

- `gh` authenticated against your GitHub account (`gh auth status` must succeed).
- `git` version 2.38 or newer (required for `--update-refs` during rebase).
- A clean working tree on the branch you want to stack from.

## Install

From the GitHub marketplace definition (after the repo is public):

```
/plugin marketplace add sebytremblay/github-os
/plugin install github-os@github-os
```

Or point at a local clone:

```
/plugin marketplace add /path/to/github-os
/plugin install github-os@github-os
```

## Workflow

```
feature branch
     │
     ▼
/github-os:slice-stack ──► /github-os:stack-self-review
     │                             │
     ▼                             ▼
draft PRs on GitHub         punch list of violations
     │
     ▼
reviewer leaves comments on GitHub
     │
     ▼
/github-os:pull-reviews ──► /github-os:address-reviews ──► /github-os:push-stack
     │
     ▼
thread resolved, change-log comment posted, CLAUDE.md proposals surfaced
     │
     ▼
/github-os:extract-patterns (across merged PRs in a date range)
```

## State

The plugin writes `<your-repo>/.github-os/stack.json` in the target repo. Add `.github-os/` to your repo's `.gitignore` if you do not want it versioned.

## Safety

- Every push uses `--force-with-lease`, never bare `--force`.
- The `pre-push-guard` hook blocks unsafe pushes and `--no-verify` commits.
- `address-reviews` never rewrites a commit that is not yet in the stack manifest.

## License

MIT
