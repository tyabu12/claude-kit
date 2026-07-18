#!/usr/bin/env bash
#
# pre-pr-docs-check.sh — documentation update reminder, fired just
# before a PR becomes reviewable.
#
# Inner script for a `Bash(gh pr *)` PreToolUse hook. gated-runner.sh
# coarse-gates to `gh pr ` and exports the command; this script then
# runs only for *ready-making* actions (see is_ready_making in
# _pr-lib.sh): a non-draft `gh pr create`, or a `gh pr ready`. A
# `gh pr create --draft` is skipped — the nudge is deferred to the
# later `gh pr ready`. Behaviour once it runs:
#
#   - Compare the branch against its PR base (see base-branch
#     detection below). If any documentation-ish path changed
#     (CLAUDE.md, AGENTS.md, .claude/rules/, README, docs/) → silent
#     no-op (exit 0, no stdout): assume docs were already considered.
#   - Otherwise → emit a `hookSpecificOutput.additionalContext` JSON
#     nudging the operator to check for doc drift before the PR opens.
#
# Generic across projects — no hardcoded default branch, no
# project-specific doc layout. Base branch is resolved in this order:
#   1. `--base <x>` parsed from the actual `gh pr create` command
#      (exposed by gated-runner.sh via $CLAUDE_TOOL_INPUT_COMMAND).
#   2. origin/HEAD (the remote's default branch).
#   3. First of main / master / develop that exists locally.
#   4. Literal "main" as a last resort.
#
# Reads no stdin. Fails open: any unexpected error → exit 0 (no
# nudge). The `trap` below makes that literal, and the script never
# exits 2, so it can never block PR creation.

set -Eeuo pipefail
trap 'exit 0' ERR

# A missing source file is fatal in a non-interactive shell (neither
# `|| exit 0` nor the ERR trap can catch it), so guard with a readable
# check first — fail open if the shared lib is somehow absent.
_lib="$(dirname "${BASH_SOURCE[0]}")/_pr-lib.sh"
[ -r "$_lib" ] || exit 0
# shellcheck source=/dev/null
source "$_lib"

# Only nudge when the PR is actually becoming reviewable.
is_ready_making || exit 0

# Defer to a project that wires its own gh-pr hooks (avoid double-nudge).
if project_owns_pr_hooks; then exit 0; fi

# Not in a git repo? Nothing to compare — bail quietly.
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$ROOT" ] || exit 0
cd "$ROOT"

base_branch() {
  # 1. Explicit --base from the gh pr create command. Strip '...'/"..."
  # segments first (same guard as is_ready_making) so a `--base`-looking
  # token inside a quoted --title/--body value can't leak in as the base.
  # A quoted base value degrades to auto-detection below — fail-open, in
  # keeping with the advisory-only nature of this nudge.
  local from_cmd
  from_cmd=$(printf '%s' "${CLAUDE_TOOL_INPUT_COMMAND:-}" \
    | sed "s/'[^']*'//g; s/\"[^\"]*\"//g" \
    | sed -n 's/.*--base[= ]\{1,\}\([^ ]\{1,\}\).*/\1/p')
  if [ -n "$from_cmd" ]; then echo "$from_cmd"; return; fi

  # 2. Remote default branch. `|| true` keeps fail-open explicit rather
  # than relying on set -e not firing inside command substitution.
  local head
  head=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null \
    | sed 's@^origin/@@' || true)
  if [ -n "$head" ]; then echo "$head"; return; fi

  # 3. First conventional branch that exists.
  local c
  for c in main master develop; do
    if git show-ref --verify --quiet "refs/heads/$c"; then echo "$c"; return; fi
  done

  # 4. Last resort.
  echo main
}

BASE=$(base_branch)

# `git diff BASE...HEAD` = changes on this branch since it diverged.
# If BASE can't be resolved to a ref, fall open (no nudge).
CHANGED=$(git diff "$BASE...HEAD" --name-only 2>/dev/null || true)

# On the base branch itself (empty diff / direct-to-main repos) there
# is no branch story to tell — skip.
[ -n "$CHANGED" ] || exit 0

if ! printf '%s\n' "$CHANGED" \
  | grep -qE 'CLAUDE\.md|AGENTS\.md|(^|/)rules/[^/]*\.md|(^|/)README|(^|/)docs/'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: "No documentation file (CLAUDE.md, AGENTS.md, rules/*.md at any depth, README, docs/) was changed on this branch. Before opening the PR, check for doc drift: if this change adds or alters a convention, public API, setup step, or behaviour worth recording, update the relevant docs first."
    }
  }'
fi

exit 0
