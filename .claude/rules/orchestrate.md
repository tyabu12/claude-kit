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

# Maintaining the model-routing defaults

**Don't re-add a blanket "when in doubt, go up a tier."** That shape is a booster for generations
that followed instructions loosely; Claude 5 applies it literally, so it fires harder than it was
ever tuned for and cancels the one cost lever Step 1 has. Promotion must name its trigger — the
structural 🎭 criteria, an unfillable 🎵 prompt slot, or the strictly-simple test — never a bare
feeling of unease. See #19 for the analysis.

**A 🎵 label does not certify that an item is "strictly within the 🎵 simple criteria."** The Step 1.2
tie-breaker also routes *specifiable but merely hard* items to 🎵. Anything that consumes the label
as a proxy for simplicity — Step 1.3's reviewer test, Step 0's resumption re-check — must state the
simplicity test separately and run it. If you ever change what 🎵 admits, grep for every rule that
cites the label and re-derive it; #19 shipped a first draft where one commit's own relaxation
falsified the premise a second hunk in the same commit was resting on.

**Back-port to already-generated projects: needed, not urgent (judged 2026-08-12, #19).** The
routing change alters cost/rigor allocation, so consumer copies genuinely want it — but an
un-upgraded copy stays *correct*, merely biased toward Opus, so no sweep of consumers is warranted.
Pick it up through Step U on each project's next `/claude-kit:orchestrate-creator` run; the template
hash changed, so the drift is detectable there by construction.
