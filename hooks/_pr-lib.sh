#!/usr/bin/env bash
#
# _pr-lib.sh — shared helpers for the PR-lifecycle hook scripts.
# Sourced (not executed). Assumes gated-runner.sh has already exported
# $CLAUDE_TOOL_INPUT_COMMAND (the raw `gh pr ...` command string).

# is_ready_making — true when the command makes a PR reviewable by
# humans for the first time, i.e. the moment worth nudging on:
#   - `gh pr ready [...]`          draft -> ready promotion
#     (but NOT `gh pr ready --undo`, which reverts ready -> draft)
#   - `gh pr create [...]` WITHOUT --draft / -d   created ready
#
# A `gh pr create --draft` (still drafting) returns false, so the
# nudge is deferred until the later `gh pr ready`. Anything else
# (`gh pr view`, `list`, `diff`, ...) returns false.
#
# Flag detection strips quoted segments first, so a draft-looking
# token inside a value (e.g. `--title "add --draft support"`) is not
# mistaken for the real flag. The subcommand is matched anchored
# (exact or followed by a space) so `gh pr readyfoo` does not match.
is_ready_making() {
  local cmd="${CLAUDE_TOOL_INPUT_COMMAND:-}"

  # Drop '...' and "..." segments so flags inside --title/--body values
  # are not read as real flags. Worst case (nested/odd quoting) this
  # degrades to the raw string — a mis-nudge, never a PR-op failure.
  local flags
  flags=$(printf '%s' "$cmd" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g")

  case "$flags" in
    "gh pr ready"|"gh pr ready "*)
      case " $flags " in
        *" --undo"*) return 1 ;;
        *) return 0 ;;
      esac
      ;;
    "gh pr create"|"gh pr create "*)
      # Wrap in spaces so a flag at either end still matches. The explicit
      # `--draft=false` (pflag boolean form = create as ready) must be
      # checked BEFORE the bare `--draft` arm, since ` --draft=false `
      # contains the ` --draft` substring and would otherwise misread as
      # draft. Bare `--draft`, `--draft=true`, and `-d` remain draft.
      case " $flags " in
        *" --draft=false"*) return 0 ;;
        *" --draft"*|*" -d "*) return 1 ;;
        *) return 0 ;;
      esac
      ;;
  esac
  return 1
}

# project_owns_pr_hooks — true when the current repo wires its OWN gh-pr
# lifecycle hooks in .claude/settings.json. The generic global nudges
# (pre-pr-docs-check / post-pr-reflection) call this and defer when it is
# true, so a project that ships a richer, project-tuned PR hook is not
# double-nudged alongside the global baseline.
#
# Heuristic, not a parser: a repo that bothered to wire gh-pr hooks has its
# own opinions. Generic — matches any project by file content, no hardcoded
# paths. Deliberately advisory-only: safety guards (force-push) do NOT defer,
# they stack. Each step `|| return 1` so it fails closed to "project does not
# own" (→ global nudge fires) without relying on set -e edge cases.
project_owns_pr_hooks() {
  local root proj
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  proj="$root/.claude/settings.json"
  [ -f "$proj" ] || return 1
  grep -q '"hooks"' "$proj" 2>/dev/null || return 1
  grep -q 'gh pr' "$proj" 2>/dev/null || return 1
  return 0
}
