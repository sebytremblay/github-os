#!/usr/bin/env bash
#
# stack-manifest.sh — read and write .github-os/stack.json in a target repo.
#
# The stack manifest tracks the branch → PR mapping, base SHAs, and review-thread
# IDs that the github-os workflow skills share across invocations. Every skill
# that mutates the stack goes through this script so the manifest stays the
# single source of truth.
#
# Usage:
#   stack-manifest.sh init <base-branch> <head-branch>
#   stack-manifest.sh path
#   stack-manifest.sh show
#   stack-manifest.sh add-pr --index N --branch B --base-branch BB --pr-number P \
#                            --head-sha S --loc L --purpose "text"
#   stack-manifest.sh set-sha <branch> <sha>
#   stack-manifest.sh list-branches
#   stack-manifest.sh reset
#   stack-manifest.sh --help
#   stack-manifest.sh --self-test
#
# Exit codes:
#   0  success
#   1  usage error
#   2  manifest missing when a read was requested
#   3  manifest already exists when init was requested
#
# Requires: jq, git.

set -euo pipefail

MANIFEST_DIR=".github-os"
MANIFEST_FILE="stack.json"

die() { printf 'stack-manifest: %s\n' "$*" >&2; exit 1; }

require() {
  command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"
}

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || die "not inside a git repo"
}

manifest_path() {
  printf '%s/%s/%s\n' "$(repo_root)" "$MANIFEST_DIR" "$MANIFEST_FILE"
}

cmd_path() {
  manifest_path
}

cmd_init() {
  local base="${1:-}"; local head="${2:-}"
  [ -n "$base" ] && [ -n "$head" ] || die "init requires <base-branch> <head-branch>"
  local path; path="$(manifest_path)"
  [ -e "$path" ] && exit 3
  mkdir -p "$(dirname "$path")"
  jq -n \
    --arg base "$base" \
    --arg head "$head" \
    --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{base:$base, head:$head, created_at:$created, prs:[]}' > "$path"
  printf '%s\n' "$path"
}

cmd_show() {
  local path; path="$(manifest_path)"
  [ -f "$path" ] || exit 2
  cat "$path"
}

cmd_reset() {
  local path; path="$(manifest_path)"
  [ -f "$path" ] && rm -f "$path"
  rmdir "$(dirname "$path")" 2>/dev/null || true
}

cmd_list_branches() {
  local path; path="$(manifest_path)"
  [ -f "$path" ] || exit 2
  jq -r '.prs[].branch' "$path"
}

cmd_add_pr() {
  local path; path="$(manifest_path)"
  [ -f "$path" ] || die "manifest not initialized; run: stack-manifest.sh init"
  local index="" branch="" base_branch="" pr_number="" head_sha="" loc="" purpose=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --index) index="$2"; shift 2;;
      --branch) branch="$2"; shift 2;;
      --base-branch) base_branch="$2"; shift 2;;
      --pr-number) pr_number="$2"; shift 2;;
      --head-sha) head_sha="$2"; shift 2;;
      --loc) loc="$2"; shift 2;;
      --purpose) purpose="$2"; shift 2;;
      *) die "add-pr: unknown flag $1";;
    esac
  done
  for v in index branch base_branch pr_number head_sha loc purpose; do
    eval "[ -n \"\${$v}\" ]" || die "add-pr: missing --${v//_/-}"
  done
  local tmp; tmp="$(mktemp)"
  jq \
    --argjson index "$index" \
    --arg branch "$branch" \
    --arg base_branch "$base_branch" \
    --argjson pr_number "$pr_number" \
    --arg head_sha "$head_sha" \
    --argjson loc "$loc" \
    --arg purpose "$purpose" \
    '.prs += [{index:$index, branch:$branch, base_branch:$base_branch, pr_number:$pr_number, head_sha:$head_sha, loc:$loc, purpose:$purpose, overlaps_with:[]}]' \
    "$path" > "$tmp"
  mv "$tmp" "$path"
}

cmd_set_sha() {
  local branch="${1:-}"; local sha="${2:-}"
  [ -n "$branch" ] && [ -n "$sha" ] || die "set-sha requires <branch> <sha>"
  local path; path="$(manifest_path)"
  [ -f "$path" ] || die "manifest not initialized"
  local tmp; tmp="$(mktemp)"
  jq --arg b "$branch" --arg s "$sha" \
    '(.prs[] | select(.branch == $b) | .head_sha) |= $s' \
    "$path" > "$tmp"
  mv "$tmp" "$path"
}

self_test() {
  require jq
  require git
  local sandbox; sandbox="$(mktemp -d)"
  trap 'rm -rf "$sandbox"' RETURN
  (
    cd "$sandbox"
    git init -q
    git commit -q --allow-empty -m "root"
    "$0" init main feature-x >/dev/null
    "$0" add-pr --index 1 --branch feature-x/01 --base-branch main \
                --pr-number 1 --head-sha abc123 --loc 100 --purpose "first"
    "$0" set-sha feature-x/01 def456
    local count; count="$(jq '.prs | length' "$(./"$0" path 2>/dev/null || "$0" path)")"
    [ "$count" = "1" ] || die "self-test: expected 1 PR, got $count"
  )
  printf 'self-test: ok\n'
}

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
}

main() {
  require jq
  require git
  local sub="${1:-}"; shift || true
  case "$sub" in
    init) cmd_init "$@";;
    path) cmd_path;;
    show) cmd_show;;
    add-pr) cmd_add_pr "$@";;
    set-sha) cmd_set_sha "$@";;
    list-branches) cmd_list_branches;;
    reset) cmd_reset;;
    --help|-h|"") usage;;
    --self-test) self_test;;
    *) die "unknown subcommand: $sub";;
  esac
}

main "$@"
