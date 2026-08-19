# Delegation & Model Tiering

Part of claude-kit and the **canonical source** of this rule. Claude Code-specific mechanics.
Pairs with `subagent-usage.md`, which owns the per-response **output cap** and how big a slice one
subagent may take; this rule owns **whether** to delegate, **which model** to hand it to, and how
the main session escalates. Consumer copies reconcile one-way (kit → consumer).

> **Two different senses of "budget".** Model choice is the primary lever on **token cost** — price
> per token and quota burn — so default to the cheapest tier that meets the task. It is *not* a
> lever on the **output cap**: that is fixed per model, and only `CLAUDE_CODE_MAX_OUTPUT_TOKENS`
> moves it (`subagent-usage.md`). Never pick a tier hoping for a bigger report.

## Whether to delegate

For implementation tasks spanning multiple files, draft a plan first. Each step states three
things: whether to delegate at all, the executor (main session / `implementer` / `Explore`), and
the model for that invocation.

- **Keep it in the main session** when the diff is small (1–2 files), the work is iterative
  (debugging, tweaking), or writing a self-contained delegation prompt would cost more than doing
  the work directly.
- **Delegation prompts must be self-contained OR carry fetchable pointers** — target paths, project
  conventions, acceptance criteria, or references the subagent fetches itself (issue/PR URL, ADR or
  doc path) with an instruction to read them first. Prefer pointers over hand-copying long context.
- **Run independent tasks concurrently**, and instruct subagents to skip narration between tool
  calls. Slice size is `subagent-usage.md`'s call.
- **Name the tier in the reply** whenever you delegate to a non-default model (e.g. "delegated this
  to a Sonnet subagent") so cost allocation is visible without opening `/stats`.

## Tiers

| Tier | Use for |
|---|---|
| 📖 **Fable** (`model: "fable"`) | Second opinion of last resort — approval rule below |
| 🎭 **Opus** | Reasoning-heavy: root-cause analysis, architecture/design calls, code-review judgment, creative or content planning |
| 🎵 **Sonnet** (`model: "sonnet"`) | Well-specified execution: text/style transforms, template application, bulk edits, search-and-replace, straightforward code generation. **Prefer this when unsure** |
| 🍃 **Haiku** (`model: "haiku"`) | Lookup: file/code exploration, simple fact-checks, grep-like searches |

If a Sonnet/Haiku subagent underperforms, bump that *task type* up a tier and record it here, so the
boundary refines over time rather than being re-guessed per session.

**Fable** sits above Opus and is the scarcest, most constrained tier. **Always get the user's
explicit approval before spawning a Fable subagent — never auto-spawn one** (a user who already
selected Fable as the main model has given it). Reach for it last, only as a second opinion on:
a design call the main model has written out its analysis for and still cannot settle; a
**hard-to-walk-back** action (force-push, key rotation, deleting production data, a breaking
public-API change, or an irreversible / wide-blast-radius external send such as a mass email or a
public release — *not* routine PR/comment/chat posts); a root-cause hunt where two hypotheses have
already missed; or a tie-break when lower-tier reviews disagree. Pass the raw diff or options and
withhold your own conclusion, so the check stays independent. Never spawn Fable from Fable (`fork`
included); one consult per decision — take the verdict and move on. It complements mechanical safety
(backups, dry-run, staged rollout); it does not replace it.

## Effort

Reasoning **effort** is the second dial, subordinate to model choice — it scales token volume within
a model, not the per-token price. Keep the default `high` everywhere, main session included; do not
micro-manage `/effort` mid-session. Two standing deviations:

1. `implementer` pins `effort: medium` in its frontmatter — finalized-spec execution needs no
   judgment-depth thinking, and effort cannot be passed per `Agent` invocation (frontmatter or
   session level only). If medium underperforms (extra review rounds), bump it back to `high` and
   note it here.
2. `xhigh` is a deliberate single-shot escalation on the hardest judgment calls — same model, one
   rung before a Fable consult. **Never raise review subagents (`code-reviewer` / `critic`) to
   `xhigh`**: higher effort inflates output tokens against the caps in `subagent-usage.md`.

## Escalation & de-escalation

The main-session model changes only when the user runs `/model`. Spawning a subagent at any tier is
the only *automatic* lever — prefer it over grinding a mismatched main model.

- **Down** — once a plan is approved and the remainder is well-specified implementation, delegate it
  rather than executing on the main model. If the work must stay iterative in the main session,
  suggest `/model sonnet`. (Sessions that start on Opus get this natively with `/model opusplan`.)
- **Up** — when work proves harder than scoped (2+ failed fix attempts, or a subtle
  correctness-critical design call), escalate *by subagent first*: if the hard sub-problem states
  self-contained cheaply — subagents inherit none of the conversation — hand it to an Opus subagent.
  Reserve a Fable consult for the hardest, hard-to-walk-back calls under the approval rule above.
  Only when the problem cannot be cleanly detached, suggest `/model opus` instead.
- **Throttle** — suggest a `/model` switch at most once per phase transition. If declined or
  ignored, proceed on the current model without re-asking.
- **Fable revert** — a Fable main session is strictly temporary. Once the hard call is resolved, or
  the rest is mechanical (implementation, CI wait, merge, cleanup), suggest `/model opus` or a fresh
  session. From a Fable main context, keep Fable's own turns minimal: push execution and exploration
  down with an explicit `model:` (never `fork`, which inherits Fable) — while still not burning
  Fable turns writing delegation prompts for edits it could just make.
