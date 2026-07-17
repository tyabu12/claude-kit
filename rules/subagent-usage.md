# Subagent Usage — Output-Cap Discipline

Part of claude-kit. Claude Code-specific mechanics — the generic "delegate / split / parallelize"
spirit may live in a user's global `~/.claude/CLAUDE.md`; this file stands alone and is the depth
behind any one-line cap mention there.

> The **volatile facts** here — the cap table (32K/64K/8192), the split thresholds (800/8/5 soft,
> 1500/12/7 hard), and the `#24055` status — are canonical in this kit. Any consumer project that
> mirrors them must reconcile **from** this file when they change (one-way: kit → consumer).

## The cap

Every subagent (any `Agent`-tool launch — `implementer`, `critic`, `Explore`, custom agents)
runs under a hard **output-token cap**, NOT configurable via frontmatter or
`CLAUDE_CODE_MAX_OUTPUT_TOKENS` (that env var applies to the main session only). Raising
`maxTurns` does not help — the cap is on output tokens, not turns.

| Model | Max output tokens |
|-------|-------------------|
| Opus 4.x | **32,000** |
| Sonnet 4.x / 5 | **64,000** |
| Haiku 4.x | 8,192 |
| Fable 5 | undocumented — treat a `fable` override as a quality lever, not a budget one |

Tracked upstream: [anthropics/claude-code#24055](https://github.com/anthropics/claude-code/issues/24055) — revalidate when it ships.

## Caller-side scope discipline

Bound the delegated work so the final report fits the budget:

- **Soft budget** (split if over): ~800 changed lines OR ~8 files OR ~5 review axes per
  invocation, whichever is tighter.
- **Hard split** (always split): >1500 lines, >12 files, or >7 axes — these reliably truncate
  before the final report.

Between soft and hard, prefer splitting. Budget exhaustion is **silent** — intermediate text
returns, the final report just goes missing — so err toward smaller.

## Sonnet override (the budget escape valve)

`Agent(model: "sonnet")` unlocks the 64K budget over an agent's default. Use for scope-bound,
mechanical-checklist work (a large mass-rename review, bulk generation). Do **not** use it for
judgment-heavy work (architecture critique, design trade-offs) — there, prefer a stronger model
plus a scope-split over a cheaper model with more room.

## Agent self-defense

Review-style agents should carry an inline scope check that bails with a `SCOPE_TOO_LARGE`
signal *before* any tool use when the soft budget is exceeded. Defense in depth: because
exhaustion is silent, the duplication with the caller-side rule is intentional.
