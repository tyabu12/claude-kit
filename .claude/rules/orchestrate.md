---
paths: ["skills/orchestrate-creator/**", "agents/code-reviewer.md"]
---
# Maintaining the orchestrate review gate

The Step 4 reviewer prompt — in `skills/orchestrate-creator/orchestrate-template.md`, inherited by
every project `orchestrate` skill generated from it — tells the `code-reviewer` subagent to
**selectively** read the `.claude/rules/*.md` whose `paths:` match the changed files. That explicit
read is load-bearing: the built-in `/code-review` does NOT auto-load path-scoped rules, so if this
instruction is ever dropped, path-scoped review coverage silently vanishes (no error) — in every
project that generates from the template afterwards.

Don't "simplify" Step 4 into a bare `/code-review` call. The blocker is not that you cannot instruct
it — free-text after the command *is* followed. It's that `/code-review` runs in the **main session**
(one run: 11 tool calls, ~100k context, which Step 5 still needs), emits no stable `Verdict` line for
the gate to parse, and lives in a hand-typed argument rather than a committed, reviewable definition.

**When you edit the Step 4 prompt (`skills/orchestrate-creator/orchestrate-template.md`) or
`agents/code-reviewer.md`'s selective-read logic, re-run the negative control in
`docs/code-review-path-scoped-rules.md`** — a guard's success case proves nothing; only the negative
control does. The finding is Claude Code version-dependent (last re-measured 2026-07-29), so also
re-verify on a Claude Code upgrade.
