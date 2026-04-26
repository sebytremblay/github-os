---
name: extract-patterns
description: Mine addressed review comments across merged PRs in a date range and propose new CLAUDE.md entries or skill stubs for recurring patterns. This skill should be used when the user asks to "extract patterns", "mine review comments", "find repeat offenses", "audit review history", or runs `/github-os:extract-patterns --since <range>`. This is the self-improving loop of the github-os workflow.
---

<objective>
Convert historical review activity into durable project knowledge. Walk recent merged PRs, cluster their review comments by intent, identify clusters with ≥ 2 occurrences, and hand each cluster to `contribute-claude-md` for placement (append to CLAUDE.md or graduate to a skill).
</objective>

<allowed-tools>
- `Bash(git:*)`
- `Bash(gh:*)`
- `Bash(jq:*)`
- `Bash(${CLAUDE_PLUGIN_ROOT}/scripts/gh-comments.sh:*)`
- `Read`
- `Write`
- `Grep`
- `Glob`
- `Skill(contribute-claude-md)`
</allowed-tools>

<arguments>
- `--since <range>` — lookback window. Accepts git-style (`7d`, `30d`, `3m`) or ISO dates. Default: `30d`.
- `--author <user>` — restrict to PRs authored by `<user>`. Default: the current `gh` user.
- `--module <path>` — restrict to comments on files matching this glob. Optional.
- `--auto-apply` — skip the per-proposal confirmation in `contribute-claude-md`. Off by default.
- `--re-propose` — surface clusters that were marked "skipped" in prior `patterns-*.md` reports. Off by default; use when a past decision deserves reconsideration.
</arguments>

<workflow>

### 1. Enumerate merged PRs in range

```
SINCE="$(date -u -v-30d +%Y-%m-%dT%H:%M:%SZ)"   # or parse --since
gh pr list --state merged --author "$AUTHOR" \
  --search "merged:>$SINCE" \
  --json number,title,mergedAt,files \
  --limit 200 > /tmp/pr-list.json
```

Filter by `--module` if given, intersecting each PR's `files[].path` with the glob.

### 2. Pull addressed comments

For each PR, fetch every comment (including resolved ones — resolution is the signal that the pattern mattered):

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gh-comments.sh" list "$PR_NUMBER"
```

Keep comments whose thread is `resolved: true` and whose author is someone other than the PR author (self-resolutions are not patterns).

### 3. Normalize and cluster

For each comment body:

1. Strip quoted lines (`> ...`).
2. Lowercase, strip punctuation.
3. Extract the leading imperative clause: first verb + object. Examples:
   - "please rename `tok` to `token` for consistency" → `rename tok to token`
   - "reject empty input at the boundary, not later" → `reject empty input at boundary`
4. Also capture the touched file's module (the directory containing its nearest `CLAUDE.md`, or the top-level directory if none).

Cluster comments whose normalized form matches (exact), whose normalized form has ≥ 0.8 similarity (simple token-overlap ratio), or which share the same module *and* touch the same verb. Keep clusters small; do not over-merge.

Threshold: a cluster is a candidate if it has ≥ 2 comments across ≥ 1 PR. Three comments from a single PR count only if they hit different files — otherwise it is the same request, not a pattern.

### 4. Rank candidates

Sort clusters by:

1. Number of distinct PRs (more PRs → stronger signal).
2. Recency of the latest occurrence.
3. Cluster size.

Cap the session at the top 10 candidates. More than that and the signal-to-noise collapses.

### 5. Propose via contribute-claude-md

For each candidate cluster, invoke `contribute-claude-md` with:

- The normalized intent sentence.
- URLs of all source comments.
- The likely target module path.
- Whether the cluster looks skill-worthy (≥ 3 occurrences + multi-step logic → propose skill stub; otherwise CLAUDE.md append).

`contribute-claude-md` prints each proposal for confirmation unless `--auto-apply` was passed.

### 6. Write a summary report

```
.github-os/patterns-<UTC-date>.md
```

Contains:

- Lookback window, author, module filter.
- Total merged PRs scanned, total comments scanned, clusters proposed.
- Per cluster: normalized intent, occurrence count, source URLs, the proposal produced (applied / skipped / skill stub), the path of the file updated or created.

This report is the audit trail for the self-improving loop. Do not delete it — future `extract-patterns` runs reference it to avoid re-proposing patterns that were already rejected.

</workflow>

<failure-modes>
- **GitHub rate limit.** `gh api` will show a 403. Honor the `X-RateLimit-Reset` header and pause; never retry in a tight loop.
- **No PRs in window.** Report "no merged PRs found in <range>" and exit 0. Empty mining is not an error.
- **Clustering collapses everything.** If more than 30% of comments land in a single cluster, the normalization is too aggressive. Loosen the similarity threshold and re-cluster. Tell the user this happened.
- **Prior rejection.** Before proposing, check recent `.github-os/patterns-*.md` reports. If an identical cluster was "skipped" within the last 30 days, silently drop it from this run's output unless `--re-propose` is set.
</failure-modes>

<safety>
- Read-only against GitHub. This skill never posts, replies, or resolves. Propagation goes through `contribute-claude-md`, and file writes wait on user confirmation.
- Never scan PRs the user does not own unless `--author` was explicitly set to someone else.
</safety>
