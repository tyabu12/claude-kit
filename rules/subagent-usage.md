# Subagent Usage — Output-Cap Discipline

Part of claude-kit. Claude Code-specific mechanics — the generic "delegate / split / parallelize"
spirit may live in a user's global `~/.claude/CLAUDE.md`; this file stands alone and is the depth
behind any one-line cap mention there.

> **Kit-canonical; a consumer mirror reconciles from this file, never the reverse.** Two kinds of
> number live here and they age differently. The **cap table** is Claude Code's platform limit —
> recomputed on upgrade, never retuned. The **split thresholds** are a review-attention bound, and
> they stay kit-canonical because the attention they rest on is a *subagent's* at a given scope,
> identical for everyone who installs the kit — not a maintainer's, which is what would make a
> threshold project-owned (`docs/automation-output-contract.md` has that test). Evidence and the
> re-measurement procedure: `docs/subagent-output-cap.md`.
>
> The one genuinely local input is **report density per changed line**: 800 lines of generated
> fixtures produce a far shorter report than 800 lines of dense source. That licenses bounding a
> call **tighter**, never looser, and it belongs at the call site — the numbers inlined in
> `agents/`/`skills/` are the floor, so a caller who wants less scope splits smaller rather than
> editing them.

## The cap

Every subagent (any `Agent`-tool launch — `implementer`, `critic`, `Explore`, custom agents) runs
under an **output-token cap per response**. It is the *model's* cap, not a subagent-specific one:
the request builder has no main/subagent branch and the `Agent` tool passes no override. Raising
`maxTurns` does not help — the cap is per response, not per run.

| Model | Cap | Ceiling via `CLAUDE_CODE_MAX_OUTPUT_TOKENS` |
|-------|-----|---------------------------------------------|
| Opus 5 | **64,000** | 128,000 † |
| Sonnet 5 | **64,000** | 128,000 † |
| Fable 5 | **64,000** † | 128,000 † |
| Haiku 4.5 | **32,000** | 64,000 † |

Measured 2026-08-12 on Claude Code **2.1.228**; pre-5 generations are lower, so do not extrapolate
backwards. **† = read from the shipped model catalog, not behaviourally verified** — only the
unmarked caps were observed in a live run. Read any model's live cap in about two seconds, without
having to provoke a truncation:

```sh
claude -p --model opus --output-format json "ok" | jq '.modelUsage[].maxOutputTokens'
```

`CLAUDE_CODE_MAX_OUTPUT_TOKENS` is the only real budget lever, and it **does** reach subagents —
contrary to what this rule claimed before, and confirmed by forcing it low and watching a subagent
error out at the forced number. Tracked upstream:
[anthropics/claude-code#24055](https://github.com/anthropics/claude-code/issues/24055) (open).

## Caller-side scope discipline

Bound the delegated work so the reviewer's **attention** holds — not so the report fits the cap; at
these sizes it fits comfortably:

- **Soft budget** (split if over): ~800 changed lines OR ~8 files OR ~5 review axes per
  invocation, whichever is tighter.
- **Hard split** (always split): >1500 lines, >12 files, or >7 axes — at this size review quality
  degrades whatever the token budget permits.

Between soft and hard, prefer splitting.

**A split leaves a seam no shard owns.** Each invocation sees only its own slice, so anything
spanning the split — a mirrored count, a cross-reference, a claim one shard makes about another's
files — is unreviewed by construction. Name the seam's owner, or add a final pass over the whole.

## Why the thresholds are not cap-derived

They used to be, and the cap they were pinned to turned out never to apply to a spawnable model.
Re-deriving would have loosened them fourfold; they were held instead, because in real use nothing
has come near the cap and what they actually buy is review attention, which does not scale with a
model's `max_tokens`. Revise them on evidence about review quality — not by recomputing when a cap
moves. Numbers behind the call: `docs/subagent-output-cap.md`.

## What a cap hit looks like now

It is no longer silent: Claude Code detects `stop_reason: max_tokens`, nudges the agent to resume,
and retries up to **3** times before surfacing an `API Error: … exceeded the N output token
maximum.` The report survives — but it gains a **seam** where the cut happened.

Review agents emit their verdict first, so the tell is a **count mismatch**: the summary claims more
issues, axes, or findings than the body writes out, or names them with no evidence attached. That is
the signal to split and re-run. A report that is short *and internally consistent* is just short.

## Model choice is a cost lever, not a budget lever

`Agent(model: "sonnet")` no longer buys headroom — Sonnet 5 and Opus 5 are both 64,000 — so pick
the model for capability and cost, never to escape a budget. The one budget-relevant asymmetry is
**Haiku at half** (32,000): do not hand it a report-heavy task on the assumption every model carries
the same load. When work genuinely needs more room than the model has, split the scope.

## Agent self-defense

Review-style agents should carry an inline scope check that bails with a `SCOPE_TOO_LARGE`
signal *before* any tool use when the soft budget is exceeded. Defense in depth: because exhaustion
shows up only as a seam mid-report, the duplication with the caller-side rule is intentional.
