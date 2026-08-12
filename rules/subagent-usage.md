# Subagent Usage — Output-Cap Discipline

Part of claude-kit. Claude Code-specific mechanics.

> **Kit-canonical, and the depth behind this rule — evidence, controls, re-measurement procedure —
> lives in `~/.claude/kit-docs/subagent-output-cap.md`.** Reconcile a consumer mirror against
> **rule + doc as a pair**, one-way (kit → consumer); a consumer copy must never become the source.
> Unlike the cap table below, the **split thresholds** move only on review-quality evidence, never
> on a cap change.

## The cap

Every subagent — any `Agent`-tool launch — runs under an **output-token cap per response**. It is
the *model's* cap, not a subagent-specific one, and `maxTurns` does not raise it: the cap is per
response, not per run.

| Model | Cap | Ceiling via `CLAUDE_CODE_MAX_OUTPUT_TOKENS` |
|-------|-----|---------------------------------------------|
| Opus 5 | **64,000** | 128,000 † |
| Sonnet 5 | **64,000** | 128,000 † |
| Fable 5 | **64,000** † | 128,000 † |
| Haiku 4.5 | **32,000** | 64,000 † |

Measured 2026-08-12 on Claude Code **2.1.228**; † = read from the shipped model catalog, not
behaviourally verified. Re-read a model's live cap on upgrade:

```sh
claude -p --model opus --output-format json "ok" | jq '.modelUsage[].maxOutputTokens'
```

`CLAUDE_CODE_MAX_OUTPUT_TOKENS` is the only real budget lever, and it **does** reach subagents.
Model choice is not one — pick for capability and cost. The one asymmetry that matters: do not hand
Haiku a report-heavy task on the assumption every model carries the same load.

## Caller-side scope discipline

Bound delegated work so the reviewer's **attention** holds, not so the report fits the cap — at
these sizes it fits comfortably.

- **Soft budget** (split if over): ~800 changed lines OR ~8 files OR ~5 review axes per invocation,
  whichever is tighter.
- **Hard split** (always split): >1500 lines, >12 files, or >7 axes.

Between soft and hard, prefer splitting. Go **tighter** at the call site when the diff is dense —
800 lines of generated fixtures report far shorter than 800 of dense source — but the numbers
inlined in `agents/`/`skills/` are the floor, never a licence to go looser.

**A split leaves a seam no shard owns.** Each invocation sees only its own slice, so anything
spanning the split — a mirrored count, a cross-reference, a claim one shard makes about another's
files — is unreviewed by construction. Name the seam's owner, or add a final pass over the whole.

## Spotting a cap hit

A hit is not silent: Claude Code auto-resumes the response, and what usually survives is a **seam**
mid-report — only if every resume also overflows does the run fail outright. So the tell is a
**count mismatch**: the summary claims more issues, axes, or findings than the body writes out, or
names them with no evidence attached. Split and re-run. A report that is short *and internally
consistent* is just short.

## Agent self-defense

Review-style agents should carry an inline scope check that bails with a `SCOPE_TOO_LARGE` signal
*before* any tool use when the soft budget is exceeded — deliberate duplication of the caller-side
rule, because exhaustion shows up as nothing louder than a seam.
