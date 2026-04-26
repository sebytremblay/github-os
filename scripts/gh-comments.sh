#!/usr/bin/env bash
#
# gh-comments.sh — thin wrapper over `gh api` for review comments + threads.
#
# GitHub exposes two different surfaces for code review:
#   - REST review comments:  /repos/{owner}/{repo}/pulls/{pr}/comments
#   - GraphQL review threads: needed for resolvedState and resolving threads
#
# This script normalizes both into a single JSON stream per PR so the workflow
# skills do not have to re-learn the GitHub API every time.
#
# Usage:
#   gh-comments.sh list <pr-number>            # JSON array of comments with thread ids
#   gh-comments.sh resolve-thread <thread-id>  # mark a review thread resolved
#   gh-comments.sh post-changelog <pr-number> <markdown-body>
#   gh-comments.sh reply <comment-id> <pr-number> <markdown-body>
#   gh-comments.sh --help
#   gh-comments.sh --self-test
#
# Requires: gh (authenticated), jq.

set -euo pipefail

die() { printf 'gh-comments: %s\n' "$*" >&2; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

owner_repo() {
  gh repo view --json owner,name -q '.owner.login + "/" + .name' 2>/dev/null \
    || die "unable to resolve owner/repo — run from inside a gh-authenticated repo"
}

cmd_list() {
  local pr="${1:-}"; [ -n "$pr" ] || die "list requires <pr-number>"
  local or; or="$(owner_repo)"; local owner="${or%/*}"; local repo="${or#*/}"
  local rest_json
  rest_json="$(gh api --paginate "repos/$owner/$repo/pulls/$pr/comments")"
  local gql_json
  gql_json="$(gh api graphql -f query='
    query($owner:String!, $repo:String!, $pr:Int!) {
      repository(owner:$owner, name:$repo) {
        pullRequest(number:$pr) {
          reviewThreads(first:100) {
            nodes {
              id
              isResolved
              comments(first:50) { nodes { databaseId } }
            }
          }
        }
      }
    }' -F owner="$owner" -F repo="$repo" -F pr="$pr")"
  jq -n --argjson rest "$rest_json" --argjson gql "$gql_json" '
    ($gql.data.repository.pullRequest.reviewThreads.nodes // []) as $threads
    | $rest | map(
        . as $c
        | ($threads[] | select(.comments.nodes[]?.databaseId == $c.id)) as $t
        | {
            id: $c.id,
            path: $c.path,
            line: ($c.line // $c.original_line),
            body: $c.body,
            author: $c.user.login,
            html_url: $c.html_url,
            commit_id: $c.commit_id,
            thread_id: ($t.id // null),
            resolved: ($t.isResolved // false)
          }
      )'
}

cmd_resolve_thread() {
  local thread="${1:-}"; [ -n "$thread" ] || die "resolve-thread requires <thread-id>"
  gh api graphql -f query='
    mutation($id:ID!) {
      resolveReviewThread(input:{threadId:$id}) {
        thread { id isResolved }
      }
    }' -F id="$thread" >/dev/null
}

cmd_post_changelog() {
  local pr="${1:-}"; shift || true
  local body="${1:-}"; [ -n "$pr" ] && [ -n "$body" ] || die "post-changelog requires <pr-number> <body>"
  gh pr comment "$pr" --body "$body"
}

cmd_reply() {
  local comment_id="${1:-}"; local pr="${2:-}"; local body="${3:-}"
  [ -n "$comment_id" ] && [ -n "$pr" ] && [ -n "$body" ] \
    || die "reply requires <comment-id> <pr-number> <body>"
  local or; or="$(owner_repo)"; local owner="${or%/*}"; local repo="${or#*/}"
  gh api "repos/$owner/$repo/pulls/$pr/comments/$comment_id/replies" \
    -X POST -f body="$body" >/dev/null
}

self_test() {
  require gh
  require jq
  gh auth status >/dev/null 2>&1 || die "self-test: gh is not authenticated"
  printf 'self-test: ok\n'
}

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

main() {
  require gh
  require jq
  local sub="${1:-}"; shift || true
  case "$sub" in
    list) cmd_list "$@";;
    resolve-thread) cmd_resolve_thread "$@";;
    post-changelog) cmd_post_changelog "$@";;
    reply) cmd_reply "$@";;
    --help|-h|"") usage;;
    --self-test) self_test;;
    *) die "unknown subcommand: $sub";;
  esac
}

main "$@"
