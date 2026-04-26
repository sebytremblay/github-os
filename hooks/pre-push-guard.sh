#!/usr/bin/env bash
# PreToolUse guard for Bash commands.
#
# Blocks:
#   1. `git push --force` / `-f` without `--force-with-lease`.
#   2. `git push --force` (any form) targeting a protected branch.
#   3. `git commit` or `git push` with `--no-verify` / `-n`.
#
# Input:  JSON on stdin (Claude Code PreToolUse payload).
# Output: JSON on stdout with a PreToolUse permissionDecision, or nothing to allow.

set -euo pipefail

PROTECTED_BRANCH_REGEX='^(main|master|develop|release/.+|hotfix/.+)$'

payload=$(cat)
command=$(printf '%s' "$payload" | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("command",""))')

deny() {
  local reason="$1"
  /usr/bin/python3 -c '
import json, sys
reason = sys.argv[1]
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }
}))
' "$reason"
  exit 0
}

# Split on shell separators so piped/chained commands are each inspected.
# Keep it simple: split on `;`, `&&`, `||`, `|`, and newlines.
IFS=$'\n' read -r -d '' -a segments < <(
  printf '%s' "$command" \
    | sed -E 's/(\|\||&&|;|\|)/\n/g' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    && printf '\0'
) || true

check_segment() {
  local seg="$1"
  # Tokenize on whitespace.
  # shellcheck disable=SC2206
  local -a tokens=( $seg )
  local cmd="${tokens[0]-}"
  [[ "$cmd" == "git" ]] || return 0

  local subcmd="${tokens[1]-}"
  [[ "$subcmd" == "push" || "$subcmd" == "commit" ]] || return 0

  local has_force=0
  local has_force_with_lease=0
  local has_no_verify=0
  local -a positional=()

  local t
  for t in "${tokens[@]:2}"; do
    case "$t" in
      --force|-f)
        has_force=1
        ;;
      --force-with-lease|--force-with-lease=*)
        has_force_with_lease=1
        ;;
      --no-verify)
        has_no_verify=1
        ;;
      -n)
        # `-n` on `git commit` means `--no-verify`? No: on `git commit` `-n` is `--no-verify`.
        # On `git push` `-n` is `--dry-run`. Only flag for commit.
        if [[ "$subcmd" == "commit" ]]; then
          has_no_verify=1
        fi
        ;;
      -*)
        ;;
      *)
        positional+=("$t")
        ;;
    esac
  done

  if (( has_no_verify )); then
    if [[ "$subcmd" == "commit" ]]; then
      deny "Refusing git commit --no-verify: do not skip commit hooks. Fix the underlying issue instead."
    else
      deny "Refusing git push --no-verify: do not skip pre-push hooks. Fix the underlying issue instead."
    fi
  fi

  if (( has_force && ! has_force_with_lease )); then
    if [[ "$subcmd" == "push" ]]; then
      # Protected-branch check: `git push [remote] [branch]` — branch is second positional.
      local branch=""
      if (( ${#positional[@]} >= 2 )); then
        branch="${positional[1]}"
        # Strip optional `refs/heads/` prefix or `HEAD:branch` refspec.
        branch="${branch##refs/heads/}"
        branch="${branch#*:}"
      fi
      if [[ -n "$branch" ]] && [[ "$branch" =~ $PROTECTED_BRANCH_REGEX ]]; then
        deny "Refusing git push --force to protected branch '$branch'. Use --force-with-lease and target a feature branch."
      fi
      deny "Refusing git push --force without --force-with-lease. Use --force-with-lease to avoid overwriting reviewer commits."
    fi
  fi
}

for seg in "${segments[@]-}"; do
  [[ -z "$seg" ]] && continue
  check_segment "$seg"
done

# Allow by default (no output).
exit 0
