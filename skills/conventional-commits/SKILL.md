---
name: conventional-commits
description: Write git commit messages that follow the Conventional Commits specification (https://www.conventionalcommits.org/en/v1.0.0-beta.2/). This skill should be used whenever running `git commit`, drafting a commit message for a fixup, or composing any commit text inside the github-os workflow.
---

<objective>
Every commit message produced by the github-os plugin conforms to Conventional Commits v1.0.0-beta.2 so that automated tooling (changelogs, semantic versioning, CI gates) can parse and act on it reliably. This applies to regular commits, `--fixup` commits, and squash targets. Always apply this skill when drafting any commit text — never write freeform commit messages.
</objective>

<format>
```
<type>[optional scope]: <description>

[optional body]

[optional footer]
```

The description line is the subject. Keep it under 72 characters. Use the imperative mood ("add", "fix", "remove" — not "added", "fixes", "removed").
</format>

<types>
Choose the type that most precisely describes the change:

| Type | When to use |
|------|-------------|
| `feat` | A new feature visible to users or consumers of the API (triggers MINOR version bump) |
| `fix` | A bug fix (triggers PATCH version bump) |
| `docs` | Documentation only — no code change |
| `style` | Formatting, whitespace, missing semicolons — no logic change |
| `refactor` | Code restructuring with no behavior change and no bug fix |
| `perf` | A change that improves performance |
| `test` | Adding or correcting tests |
| `chore` | Build process, dependency updates, tooling — nothing a user sees |
| `ci` | CI configuration and scripts |
| `revert` | Reverts a previous commit |

When in doubt between `feat` and `refactor`: if a user or API consumer would notice the change, use `feat`.
</types>

<scope>
The scope is a noun describing the section of the codebase affected. It goes in parentheses after the type:

```
feat(auth): add OAuth2 login flow
fix(parser): handle empty input gracefully
chore(deps): upgrade typescript to 5.4
```

Use the scope when it makes the commit meaningfully easier to scan in a log. Omit it when the change is truly global or the type already captures all necessary context. Keep scopes consistent within a project — look at recent commit history before choosing one.
</scope>

<breaking-changes>
Mark a breaking change two ways:

1. Add `!` after the type/scope on the subject line.
2. Add a `BREAKING CHANGE:` footer explaining what broke and how to migrate.

```
feat(api)!: rename userId to accountId in all responses

BREAKING CHANGE: The `userId` field has been replaced by `accountId` across
all API responses. Update any code that reads `response.userId` to use
`response.accountId` instead.
```
</breaking-changes>

<body-and-footer>
The body explains *why* the change was made, not what it does. Separate it from the subject with a blank line. The footer is for metadata: issue references, co-authors, and breaking change notices.

Omit body and footer for self-explanatory changes. Add them when the commit would otherwise be confusing to a future reader.
</body-and-footer>

<fixup-commits>
When addressing review comments, use `git commit --fixup=<sha>` to attach changes to the original commit. The resulting message (`fixup! <subject>`) is automatically conformant; do not rewrite it. A later `git rebase -i --autosquash` will collapse the fixup into the target commit, and the original commit's Conventional message wins.

If the change addresses a review comment that requires a new commit (not a fixup to an existing commit), write a full Conventional Commits message that describes the follow-up, not the review interaction. Do not write commits like `fix: address review comment`. Write `fix(parser): reject whitespace-only input` instead.
</fixup-commits>

<workflow>
1. Read the staged diff (`git diff --cached`) to understand what changed.
2. Identify the most specific type that matches the change.
3. Choose a scope if it adds clarity; mirror scopes already used in recent `git log`.
4. Write the subject line: imperative mood, under 72 chars, no trailing period.
5. Add a body if the *why* is non-obvious.
6. Add a footer for issue links, breaking changes, or co-authors.
7. Run the commit with the composed message.
</workflow>
