#!/usr/bin/env bash
#
# post-pr-reflection.sh — reflection reminder, fired right after a PR
# becomes reviewable.
#
# Inner script for a `Bash(gh pr *)` PostToolUse hook. gated-runner.sh
# coarse-gates to `gh pr ` and exports the command; this script then
# runs only for *ready-making* actions (see is_ready_making in
# _pr-lib.sh): a non-draft `gh pr create`, or a `gh pr ready`. This is
# the moment a human is present and the change is fresh — including
# the draft-first workflow, where the nudge lands at `gh pr ready`
# rather than never.
#
# Emits a `hookSpecificOutput.additionalContext` reminder covering
# three easy-to-forget wrap-up items:
#   1. Verification — restate how this change was verified (tests,
#      build, manual run), or note what still needs checking.
#   2. Observations — surface any concerns, surprises, or follow-up
#      suggestions noticed during the session.
#   3. Memory — note any memory files worth creating or updating from
#      what was learned this session.
#
# Generic across projects. Reads no stdin.
# hookEventName MUST be "PostToolUse" — this fires after the tool runs.

set -Eeuo pipefail
trap 'exit 0' ERR

# A missing source file is fatal in a non-interactive shell (neither
# `|| exit 0` nor the ERR trap can catch it), so guard with a readable
# check first — fail open if the shared lib is somehow absent.
_lib="$(dirname "${BASH_SOURCE[0]}")/_pr-lib.sh"
[ -r "$_lib" ] || exit 0
# shellcheck source=/dev/null
source "$_lib"

# Only reflect when the PR is actually becoming reviewable.
is_ready_making || exit 0

# Defer to a project that wires its own gh-pr hooks (avoid double-nudge).
if project_owns_pr_hooks; then exit 0; fi

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: "PR is ready for review. Before moving on, briefly reflect: (1) Verification — restate how this change was verified (tests / build / manual run), or note what still needs checking. (2) Observations — share any concerns, surprises, or follow-up suggestions noticed during this session. (3) Memory — note any memory files worth creating or updating from what was learned this session."
  }
}'

exit 0
