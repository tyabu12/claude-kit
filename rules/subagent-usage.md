# Subagent Usage — Output-Cap Discipline

Part of claude-kit. Claude Code-specific mechanics — the generic "delegate / split / parallelize"
spirit may live in a user's global `~/.claude/CLAUDE.md`; this file stands alone and is the depth
behind any one-line cap mention there.

> **Everything numeric here is kit-canonical**, and a consumer mirror reconciles **from** this file,
> never the reverse. The cap table (32K/64K/8192) and the `#24055` status are Claude Code's limits.
> The split thresholds below are **derived from them** — pinned to the smallest practical budget,
> assuming prose-dense report output — which makes them recomputable, not tunable.
>
> The one genuinely local input is **report density per changed line**: 800 lines of generated
> fixtures produce a far shorter report than 800 lines of dense source. That licenses bounding a
> call **tighter**, never looser, and it belongs at the call site — the numbers inlined in
> `agents/`/`skills/` are the floor, so a caller who wants less scope splits smaller rather than
> editing them.

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

Bound the delegated work so the final report fits the budget (defaults — see the header):

- **Soft budget** (split if over): ~800 changed lines OR ~8 files OR ~5 review axes per
  invocation, whichever is tighter.
- **Hard split** (always split): >1500 lines, >12 files, or >7 axes — at this size the report
  reliably loses its substance before the run completes.

Between soft and hard, prefer splitting. Budget exhaustion is **silent** — intermediate text
returns, the report's substance goes missing — so err toward smaller.

**What exhaustion looks like.** *Not* a missing summary: review agents are built to emit their
verdict/summary **first** under cap pressure, so it survives exactly when the run is truncated.
Look instead for **detail missing behind a present summary**, which is mechanically checkable as a
**count mismatch** — the summary claims more issues, axes, or findings than the body actually
writes out, or names them with no evidence attached. Corroborate with intermediate tool output
present and no `SCOPE_TOO_LARGE`. That combination is the signal to **split and re-run** — a report
that is short *and internally consistent* is just short, and needs nothing.

## Sonnet override (the budget escape valve)

`Agent(model: "sonnet")` unlocks the 64K budget over an agent's default. Use for scope-bound,
mechanical-checklist work (a large mass-rename review, bulk generation). Do **not** use it for
judgment-heavy work (architecture critique, design trade-offs) — there, prefer a stronger model
plus a scope-split over a cheaper model with more room.

## Agent self-defense

Review-style agents should carry an inline scope check that bails with a `SCOPE_TOO_LARGE`
signal *before* any tool use when the soft budget is exceeded. Defense in depth: because
exhaustion is silent, the duplication with the caller-side rule is intentional.
