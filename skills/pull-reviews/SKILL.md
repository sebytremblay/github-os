---
name: pull-reviews
description: Pull every review comment and thread for the PRs in the current stack into a local worklist file. This skill should be used when the user asks to "pull reviews", "fetch comments", "sync review threads", "get the latest review", or runs `/github-os:pull-reviews`. The worklist is consumed next by `address-reviews`.
---

<objective>
Materialize all open, unresolved review threads across the stack into `.github-os/reviews.json` so `address-reviews` can walk them deterministically, cluster them, and attribute each one to the right commit.
</objective>

<allowed-tools>
- `Bash(git:*)`
- `Bash(gh:*)`
- `Bash(jq:*)`
- `Bash(${CLAUDE_PLUGIN_ROOT}/scripts/stack-manifest.sh:*)`
- `Bash(${CLAUDE_PLUGIN_ROOT}/scripts/gh-comments.sh:*)`
- `Read`
- `Write`
</allowed-tools>

<workflow>

### 1. Load the manifest

```
MANIFEST_PATH="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/stack-manifest.sh" path)"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/stack-manifest.sh" show > /tmp/stack.json
```

If the manifest is missing, stop: the stack was not created with `slice-stack`. Ask the user whether to bootstrap a manifest from open PRs, or abort.

### 2. Fetch comments per PR

For each PR in the manifest:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gh-comments.sh" list "$PR_NUMBER"
```

Filter out `resolved:true` threads and outdated comments (`line == null` after a force-push). Merge the filtered arrays from every PR into a single worklist, tagged with `pr_number` and `slice_index`.

### 3. Cluster by intent

The worklist drives `address-reviews`, which batches related comments. Add a `cluster_key` to each comment using a simple hash:

- Comments touching the same file → candidate cluster.
- Comments whose bodies share the same normalized verb-object ("rename X", "extract Y", "reject empty input") → stronger candidate.
- Single-sentence comments that share a noun phrase → candidate.

Do not over-merge. When in doubt, leave `cluster_key: null` and let `address-reviews` handle them individually.

### 4. Write the worklist

```json
{
  "fetched_at": "<UTC iso>",
  "stack_head": "<head-branch>",
  "comments": [
    {
      "id": 987654,
      "thread_id": "PRT_kwD...",
      "pr_number": 412,
      "slice_index": 1,
      "path": "src/parser/tokens.ts",
      "line": 42,
      "body": "rename `tok` to `token` for consistency with the rest of the module",
      "author": "alex",
      "commit_id": "abc123",
      "html_url": "https://github.com/.../pull/412#discussion_r...",
      "cluster_key": "rename-tok-to-token",
      "state": "open"
    },
    ...
  ]
}
```

Write to `.github-os/reviews.json` (in the target repo). Overwrite any prior worklist — stale comments are a footgun.

### 5. Report

Print a compact summary:

```
Fetched N comments across M PRs (K unresolved threads).
Clusters:
  - rename-tok-to-token (3 comments in 2 PRs)
  - null (4 comments, no cluster)
Worklist written to .github-os/reviews.json
```

If the worklist is empty, say so plainly and exit — `address-reviews` has nothing to do.

</workflow>

<safety>
- Do not fetch with credentials other than the user's `gh` auth. No PATs in skill context.
- Do not mutate GitHub state here. Reads only.
- If `gh-comments.sh list` returns HTTP 404 for a PR, the manifest is stale. Stop and suggest `scripts/stack-manifest.sh reset`.
</safety>
