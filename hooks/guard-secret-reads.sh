#!/usr/bin/env bash
#
# guard-secret-reads.sh — PreToolUse(Bash) speed bump for secret-file access.
#
# Why: `Read(~/.ssh/**)`-style permission denies gate ONLY the Read tool —
# under `defaultMode: auto`, `Bash(cat ~/.ssh/id_rsa)` or `grep KEY .env`
# reads the same secret without any prompt. This hook closes that gap by
# turning any Bash command that *mentions* a sensitive path into an "ask":
# the user confirms once, nothing is hard-blocked.
#
# This is a SPEED BUMP, not a security boundary. Detection is substring /
# regex on the command text, so a path assembled from variables or emitted
# by a subprocess sails through, and an implicit read (a tool that loads
# `.env` itself without naming it) is invisible. It exists to catch the
# common accidental shape — an agent casually cat/grep-ing a secret file —
# not a determined exfiltration. Plaintext secrets that matter should not
# be on the machine at all.
#
# Watched paths:
#   - `.ssh/`  `.aws/`  `.config/gcloud/`   (credential directories)
#   - `.env` / `.envrc` / `.env.<suffix>` as a standalone token (dotenv and
#     direnv files; `.env.example` and friends are also caught — the ask is
#     cheap and naming conventions are not a guarantee of emptiness)
#
# Fails open: missing jq / malformed JSON / no match → exit 0, no output.
# Emitting nothing means the permission system decides as usual.

set -Eeuo pipefail
trap 'exit 0' ERR

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -z "$COMMAND" ] && exit 0

MATCHED=""
if printf '%s' "$COMMAND" | grep -qE '\.ssh/'; then
  MATCHED=".ssh/"
elif printf '%s' "$COMMAND" | grep -qE '\.aws/'; then
  MATCHED=".aws/"
elif printf '%s' "$COMMAND" | grep -qE '\.config/gcloud/'; then
  MATCHED=".config/gcloud/"
elif printf '%s' "$COMMAND" | grep -qE "(^|[[:space:]/\"'=])\.env(rc|\.[A-Za-z0-9_-]+)?([[:space:]\"';|)&]|\$)"; then
  MATCHED=".env file"
fi

[ -z "$MATCHED" ] && exit 0

jq -n --arg m "$MATCHED" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: ("guard-secret-reads: this Bash command references a sensitive path (" + $m + "). Read()-style permission denies do not cover Bash, so confirm this access is intended. If it only touches a non-secret template (e.g. .env.example), approving is fine.")
  }
}'

exit 0
