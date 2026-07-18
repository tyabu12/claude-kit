#!/usr/bin/env bash
#
# pre-pr-review-gate.sh — automated review gate, fired just before a
# PR becomes reviewable.
#
# Inner script for a `Bash(gh pr *)` PreToolUse hook. gated-runner.sh
# coarse-gates to `gh pr ` and exports the command; this script then
# runs only for *ready-making* actions (see is_ready_making in
# _pr-lib.sh): a non-draft `gh pr create`, or a `gh pr ready`. A
# `gh pr create --draft` is skipped — the gate is deferred to the
# later `gh pr ready`.
#
# Behaviour once it runs:
#   - First ready-making attempt on a branch → deny the command with a
#     permissionDecision, instructing Claude to run a review skill
#     first (/code-review or /risk-review, chosen by diff nature) and
#     then retry.
#   - A marker file is written at deny time, keyed on repo root +
#     branch, so the retry (and any later attempt on the same branch,
#     e.g. after review fixes were committed) passes silently. One
#     deny per branch — this is a nudge-with-teeth, not a loop.
#     The marker is written AFTER the deny is emitted: a transient
#     failure between the two then re-arms the gate (a harmless second
#     deny) instead of leaving a marker with no deny ever issued —
#     which would be a permanent silent bypass for that branch.
#
# Unlike the advisory nudges (pre-pr-docs-check / post-pr-reflection),
# this gate does NOT defer via project_owns_pr_hooks: a project that
# wires its own docs-check hook would otherwise silently lose the only
# review enforcement. Like the safety guards, it stacks.
#
# Markers live under $TMPDIR (cleared on reboot), so the gate re-arms
# across reboots at worst. Token cost is bounded: at most one review
# per branch per PR-opening.
#
# Fails open: any unexpected error → exit 0 (no gate). The script can
# never permanently block PR creation — the deny reason itself tells
# Claude how to proceed.

set -Eeuo pipefail
trap 'exit 0' ERR

_lib="$(dirname "${BASH_SOURCE[0]}")/_pr-lib.sh"
[ -r "$_lib" ] || exit 0
# shellcheck source=/dev/null
source "$_lib"

# Only gate when the PR is actually becoming reviewable.
is_ready_making || exit 0

# Not in a git repo? Nothing to review — bail quietly.
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$ROOT" ] || exit 0

BRANCH=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
[ -n "$BRANCH" ] || exit 0

MARKER_DIR="${TMPDIR:-/tmp}/claude-pr-review-gate"
mkdir -p "$MARKER_DIR"
KEY=$(printf '%s' "$ROOT:$BRANCH" | shasum | cut -d' ' -f1)
MARKER="$MARKER_DIR/$KEY"

# Already gated this branch once — pass through silently.
[ -e "$MARKER" ] && exit 0

# Deny this attempt, then arm the pass-through for the retry. Order
# matters: see the header — failing between the two must fail toward
# "gate fires again", never "gate never fired".
jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "Pre-PR review gate: no automated review has run on this branch yet. Before making this PR reviewable, run ONE review skill, chosen by the nature of the branch diff: /code-review for implementation-heavy diffs (hunting correctness bugs in code); /risk-review for design/architecture/ops/docs-heavy or wide-blast-radius changes (migrations, auth, payment, deploy/runbook docs). If the diff clearly spans both natures, prefer /risk-review. Address any findings that matter, then retry this exact gh pr command — the gate fires only once per branch. Exception: if the user explicitly asked to skip the review, just retry now."
  }
}'

touch "$MARKER"

exit 0
