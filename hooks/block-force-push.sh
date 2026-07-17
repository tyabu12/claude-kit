#!/usr/bin/env bash
#
# block-force-push.sh — PreToolUse(Bash) safety guard.
#
# Blocks (exit 2) any Bash tool call that force-pushes: a `git push`
# carrying a force flag (--force / --force-with-lease / --force-if-includes,
# short -f / -uf / -fv clusters, or a +refspec).
#
# Why: this runs as an UNCONDITIONAL global guard so an agent session —
# especially one running under `defaultMode: auto`, where tool calls are
# not individually confirmed — can never force-push over remote history.
# Permission allowlists are PREFIX matches and cannot forbid a suffix, so
# `git push -u origin foo --force` sails through the allowlist; this hook
# is the mechanical backstop. It stacks with any project-level force-push
# guard on purpose — redundant safety guards are additive, never deferred.
#
# Detection is TOKENIZED, not substring-based. The command is split into
# segments (`; & | && || newline`, backslash-continuations rejoined) and
# each segment is walked token by token as a small state machine:
#   1. wrapper phase — skip a leading run of `VAR=value` assignments and
#      command wrappers (`env`/`sudo`/`command`/`nohup`/`doas`, and the
#      arg-taking `timeout`/`nice`/`ionice`/`stdbuf` with their option and
#      one positional arg). Any other bare word (e.g. `echo`) means this
#      segment is not a git invocation → stop, so quoted/heredoc prose
#      mentioning "git push" is never scanned.
#   2. subcommand phase — the first word is `git`; skip git GLOBAL options,
#      including the ones that take a SEPARATE argument (`-c k=v`, `-C dir`,
#      `--git-dir dir`, `--work-tree dir`, `--namespace x`, `--super-prefix
#      x`, `--config-env x`). The first non-option word is the subcommand;
#      scan for force only if it is `push`.
#   3. force phase — any `--force*`, an `-*f*` short cluster, or a
#      `+refspec` in the push args → block.
# Tokenizing (not the old literal `git push` substring gate) is what closes
# `git -c k=v push --force`, `git --no-pager push -f`, `timeout 5 git push
# -f`, and double-space `git␠␠push --force`: standard shapes an agent emits
# that the substring gate let sail through untouched.
#
# Residuals (still conservative, all fail toward a benign over-block, never
# a missed force-push we could tokenize):
#   - Segmentation is deliberately quote-blind, so a `git push … --force`
#     that lives INSIDE a quoted --body / heredoc prose still trips the
#     guard. Use `--body-file` / `git commit -F file`, split the compound,
#     or run it manually in a terminal; hooks gate the agent, never the
#     human.
#   - Unusual arg-form wrappers (`sudo -u bob git push -f`, wrappers not in
#     the known set) stop the wrapper phase early and fall through unscanned.
#
# bash 3.2-safe: no here-strings, no `${var^^}` / `${var,,}`, no `mapfile`,
# no arrays. awk / tr / process substitution are all 3.2-safe.
#
# Missing `jq` or malformed JSON falls through to a silent allow (exit 0) —
# see install.sh, which warns when `jq` is absent (the guard cannot inspect
# commands without it). The real gate for non-Bash/garbage input is the
# permission system itself.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -z "$COMMAND" ] && exit 0

block() {
  echo "BLOCKED by block-force-push.sh: $1" \
       "If a human genuinely intends this, run it manually in a terminal." >&2
  exit 2
}

# scan_segment — tokenize ONE command segment and block if it is a
# force-push. Walks words in a single pass with a 3-phase state machine
# (wrapper -> subcmd -> force); see the header for the phase contract.
# `set -f` stops the unquoted `for word in $1` from globbing against cwd.
scan_segment() {
  set -f
  local state=wrapper skip_next=0 argwrap=0 word
  for word in $1; do
    if [ "$skip_next" = 1 ]; then skip_next=0; continue; fi
    case "$state" in
      wrapper)
        case "$word" in
          git)                          state=subcmd ;;
          [A-Za-z_]*=*)                 : ;;              # VAR=value assignment
          env|sudo|command|nohup|doas)  argwrap=0 ;;      # no-arg wrapper
          timeout|nice|ionice|stdbuf)   argwrap=1 ;;      # takes a positional arg
          -*)                           : ;;              # a wrapper's own option
          *)
            # A bare non-git word: the positional arg of an arg-taking
            # wrapper (`timeout 5`), else a foreign command (`echo`) that
            # means this segment is not a git invocation — stop scanning.
            if [ "$argwrap" = 1 ]; then argwrap=0
            else set +f; return 0; fi
            ;;
        esac
        ;;
      subcmd)
        case "$word" in
          -c|-C|--git-dir|--work-tree|--namespace|--super-prefix|--config-env)
                    skip_next=1 ;;                        # global opt + separate arg
          -*)       : ;;                                  # other global opt (--no-pager, -p, =-attached)
          push)     state=force ;;
          *)        set +f; return 0 ;;                   # some other subcommand — not a push
        esac
        ;;
      force)
        case "$word" in
          --force*)     set +f; block "force push (--force*) is forbidden for agent sessions." ;;
          -[A-Za-z]*)   case "$word" in *f*) set +f; block "force push (-f cluster: $word) is forbidden for agent sessions." ;; esac ;;
          +*)           set +f; block "force push via +refspec ($word) is forbidden for agent sessions." ;;
        esac
        ;;
    esac
  done
  set +f
  return 0
}

# Fast path: no `push` substring anywhere → cannot be a force-push, skip
# the awk/tr segmentation entirely (keeps the common Bash call cheap).
case "$COMMAND" in
  *push*) : ;;
  *) exit 0 ;;
esac

# Split COMMAND into segments and tokenize-scan each:
#   1. awk rejoins `\`-continued lines so a push whose force flag is on the
#      next physical line stays in one segment.
#   2. tr splits on `; & |` (so `&&` / `||` break too); embedded newlines
#      are themselves separators. Quote-blind by design — over-splitting a
#      quoted body only ever shrinks a segment's word set, never lets a
#      push flag escape its segment.
#   3. `while read` over PROCESS SUBSTITUTION (not a pipe) keeps the loop in
#      the current shell so block()'s `exit 2` propagates.
#   4. The `*git*` pre-filter skips non-git segments cheaply; scan_segment
#      itself bails on any segment whose command is not `git`.
while IFS= read -r seg; do
  case "$seg" in
    *git*) scan_segment "$seg" ;;
  esac
done < <(printf '%s' "$COMMAND" \
  | awk '{ if (sub(/\\$/, "")) printf "%s ", $0; else print }' \
  | tr ';&|' '\n\n\n')

exit 0
