---
name: stack-self-review
description: Audit a proposed or existing PR stack against single-purpose, standalone, 600 LOC, and cross-PR leakage criteria. This skill should be used right after `slice-stack` produces a dry-run plan, before flipping drafts to ready-for-review, or when the user asks to "review the stack", "check the stack", or "lint my PR stack". Delegates the heavy analysis to the `stack-reviewer` agent and returns a structured punch list.
---

<objective>
Catch mis-sliced stacks before the reviewer sees them. The audit has four checks, each with a clear verdict:

1. **Single purpose.** Every PR has one sentence of intent; no PR says "and".
2. **Standalone.** Every PR except possibly the last can merge on its own.
3. **Soft cap 600 LOC.** Flag any PR over the cap with a rationale request.
4. **No cross-PR leakage.** No file is edited inconsistently across PRs; no PR's tests cover code it does not own.
</objective>

<allowed-tools>
- `Bash(git:*)`
- `Bash(gh:*)`
- `Bash(jq:*)`
- `Bash(${CLAUDE_PLUGIN_ROOT}/scripts/stack-manifest.sh:*)`
- `Read`
- `Grep`
- `Glob`
- `Agent(stack-reviewer)`
</allowed-tools>

<workflow>

### 1. Resolve inputs

Two modes:

- **Plan mode.** Caller passes the dry-run plan JSON from `slice-stack`. Use it directly.
- **Existing-stack mode.** No input passed. Read `.github-os/stack.json` via `scripts/stack-manifest.sh show`. Reconstruct each slice's diff with `git diff <base-branch>..<slice-branch>`.

If neither is available, stop and ask the user which stack to audit.

### 2. Delegate to the reviewer agent

Invoke `stack-reviewer` with:

- The stack description (plan JSON or manifest).
- Each slice's full diff.
- The four criteria above.

The agent returns a JSON punch list:

```json
{
  "violations": [
    {
      "slice_index": 2,
      "check": "single_purpose",
      "severity": "block",
      "message": "Slice 2 extracts the parser AND adds error spans. Split the error-span work into a new slice after slice 1.",
      "evidence": ["src/parser/tokens.ts:40-78", "src/parser/errors.ts:1-120"]
    }
  ],
  "summary": "3 of 4 slices clean; slice 2 is dual-purpose."
}
```

### 3. Present the punch list

Format:

```
## Stack self-review — <N> slices

<summary line>

### Violations

- [BLOCK] slice 2 — single_purpose: <message>
  evidence: src/parser/tokens.ts:40-78, src/parser/errors.ts:1-120
- [WARN]  slice 3 — loc: 720 LOC, over the 600 soft cap
  evidence: tests account for 310 LOC; consider splitting fixtures into slice 3a.

### Recommendation

<one sentence: block on BLOCKs, flag WARNs for user decision, or "green — ready for review">
```

### 4. Advance or halt

- If all violations are severity `block`, halt. Tell the user the stack needs re-slicing and name which slices to re-examine.
- If only `warn`-severity issues remain, summarize and let the user decide. `slice-stack` will not proceed without acknowledgement.
- If the list is empty, print "green — ready for review" and exit cleanly.

</workflow>

<severity-rules>
- `block`: violates single-purpose or standalone. Never let the stack ship.
- `warn`: LOC over cap, or cross-PR file touched with non-disjoint line ranges when `overlaps_with` was empty.
- `info`: stylistic notes (scope naming inconsistency, missing test plan section). Never block on these.
</severity-rules>

<examples>
**Planted cross-PR leak (block):** Slice 1 extracts `parser.ts`. Slice 2 renames a function inside `parser.ts` that was already moved in slice 1. The agent flags `cross_pr_leak` with evidence pointing to the conflicting diff regions.

**Soft-cap violation (warn):** Slice 3 adds a 700-LOC test fixture. The agent flags `loc` as warn, notes that fixtures are often acceptable over cap, and asks the user to confirm.

**Dual purpose (block):** Slice 2's commits include both `feat(parser): extract tokens` and `feat(parser): add error spans`. The agent flags `single_purpose` as block and proposes a new slice boundary between the two commit ranges.
</examples>
