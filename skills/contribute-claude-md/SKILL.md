---
name: contribute-claude-md
description: Append a repeat-offense rule to the nearest CLAUDE.md file or promote a recurring pattern into a new skill. This skill should be used whenever a review comment is the second or later occurrence of the same request within a stack, a merged PR window, or a single module, or when the user asks to "add this to CLAUDE.md", "promote this to a skill", "contribute a rule", or "capture this pattern". Triggered inline by `address-reviews` and by `extract-patterns`.
---

<objective>
The github-os workflow converts repeat reviewer feedback into durable guidance. This skill decides two things per repeat offense: where the rule lives (which CLAUDE.md), and whether the rule has enough surface area to graduate into its own skill.
</objective>

<when-it-fires>
A "repeat offense" is a review comment whose intent matches one of:

- Another comment on a **different line** of the same PR.
- A comment on a **sibling PR in the current stack**.
- A comment on a **merged PR from the last 30 days** inside the same module.

If any of those match, trigger this skill. A single isolated comment never triggers it.
</when-it-fires>

<decision-tree>
```
Repeat offense detected
 ├── Same rule could be expressed in ≤ 3 lines?
 │    ├── Yes → append to CLAUDE.md (see "Placement")
 │    └── No  → draft a skill stub (see "Promote to skill")
 └── Rule is already in a CLAUDE.md?
      └── Update the existing entry instead of adding a new one. Never duplicate.
```
</decision-tree>

<placement>
Walk from the changed file upward to find the nearest `CLAUDE.md`. Add the rule to *that* file, not to the repo root.

- Change in `src/parser/tokenizer.ts` → check `src/parser/CLAUDE.md`, then `src/CLAUDE.md`, then `CLAUDE.md`. Write to the deepest existing one. If none exists at or above the changed file, create `<module>/CLAUDE.md` at the tightest scope that still makes the rule correct.
- Rule entries go under an `## Instructions` or `## Conventions` heading. Create the heading if missing.
- Each entry is one imperative sentence followed by a `Why:` line when the reason is not obvious from the rule.

Example entry:

```markdown
- Reject whitespace-only input at the tokenizer boundary, not downstream. Why: three separate reviewers asked for this in parser PRs during March and April 2026.
```
</placement>

<promote-to-skill>
Graduate to a skill when the rule needs: multiple steps, a template, a script, or a decision tree. Draft the skill stub under the *target repo's* `.claude/skills/<name>/SKILL.md`, not inside github-os.

Stub shape:

```markdown
---
name: <kebab-case>
description: <third-person trigger description naming the exact phrases or situations that activate this skill>
---

<one-paragraph objective>

<steps or rules>

<examples, drawn from the review comments that motivated the promotion>
```

Leave a TODO comment at the top of the stub listing the source comment URLs so a human can refine it before it hardens.
</promote-to-skill>

<proposal-format>
Do not append to CLAUDE.md or write the skill stub silently. Print a proposal to the user first:

```
Proposed CLAUDE.md addition at <path>:
---
<one-line diff of the new entry>
---
Rationale: <one sentence naming the two or more comments that motivated it, with URLs>
Apply? [y/N]
```

Only write the file after confirmation, unless the invoking skill has `--auto-apply` set.
</proposal-format>

<anti-patterns>
- Do not add a rule the first time a reviewer asks for something. One comment is a request; two or more is a pattern.
- Do not add a rule that restates what the code would already enforce (types, lint, tests). CLAUDE.md is for guidance the tools miss.
- Do not write rules in the negative if a positive form exists. "Return early on empty input" beats "do not run the main loop on empty input".
- Do not add rules to the repo root when a module-level CLAUDE.md would be more correct. Scope matters; rules at the wrong level get ignored.
</anti-patterns>
