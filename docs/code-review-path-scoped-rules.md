# `/code-review` and path-scoped rules — a load-bearing finding

**Observation verified 2026-07-18; injection mechanism re-measured 2026-07-24 on Claude Code
2.1.218 (the 2026-07-18 explanation was wrong — see below); created-mid-session non-injection added
2026-07-29 on 2.1.220 (effect measured, mechanism not). Volatile — this is Claude Code
version-dependent behavior; re-verify on a Claude Code upgrade and whenever the orchestrate Step 4
reviewer prompt changes.**

## The finding

Several claims live here, measured on different dates; a 2026-07-24 re-probe falsified one and left
the others standing. Keep them apart — and keep each measured effect apart from the model fitted to
it.

**Observation (2026-07-18, assumed to still hold).** Claude Code's built-in **local** `/code-review`
reads and applies always-loaded context — the repo's `CLAUDE.md`, and by the same tier
`.claude/rules/*.md` with **no** `paths:` frontmatter — but does **NOT** apply **path-scoped** rules
(those with `paths:`) during a review. Stated precisely: **path-scoped rules are invisible to local
`/code-review`.** Cloud review (`/code-review ultra`, the managed GitHub App) additionally reads a
`REVIEW.md`; local `/code-review` does not. (We did not test whether `paths:`-less files load —
always-loaded by definition, so they should; untested.)

**Explanation — the original one is false.** This doc used to say path-scoped rules "load when a
matching file is *edited*; a review reads rather than edits, so they never fire." That mechanism is
wrong. Measured 2026-07-24 on Claude Code 2.1.218 (three fresh subagent probes + one main-session
check): a matching path-scoped rule *is* injected — from a **`Read` tool call's path argument** (all
matches at once; it fires even when the read targets a nonexistent path) — and **not** from
`Edit`/`Write` (those inject nothing; only `Read` does), nor from `Grep`, `Glob`, or any Bash
(`git diff`/`show`/`log`/`grep`). So "edit vs read" was the wrong axis: the trigger is the `Read`
tool specifically, and editing loads a rule only because an edit `Read`s the file first. Caveat: the
negatives are single-session and could in principle be a per-session injection de-dup artifact rather
than a genuine non-fire; the `Read` positive is robust (seen across fresh contexts, main and sub).

**A second gate — the effect: a rule file created mid-session does not inject in that session.**
Measured 2026-07-29 on Claude Code 2.1.220 (six fresh subagent probes against one editing session):
two newly created path-scoped rules injected on **no** matching `Read` in the session that authored
them, however well their `paths:` matched, while injecting normally in fresh subagent sessions
reading the same targets. That is the effect, and it is what the guidance below rests on.

*The mechanism is not measured.* A session-start snapshot of the rule set is the likeliest model,
but the same six probes fit "new files are never added to a live discovery list" or "discovery is
cached at first injection" equally well. Treat the snapshot as a working model, not as established —
this doc exists because the 2026-07-18 explanation was a model fitted to an observation and stated
as fact.

**Scope: creation is what was probed; editing an existing rule was not.** Do not extend the effect
to a `paths:` *edit* without measuring it — and note the two directions differ under the snapshot
model, which predicts the session keeps the **pre-edit** glob: *broadening* a glob would then look
absent on the newly-matched path, while *narrowing* one would have the rule keep firing on a path it
no longer covers. Absence is not even the expected symptom in the narrowing case. An attempt to
observe the edit case in the authoring session was confounded by the rule having already injected.

That same confound is why the de-dup caveat above stays open. Separating de-dup from the created-file
effect (fresh session, two distinct files matching one rule) returned a probe report that did not
distinguish "injected again" from "still in context". Treat per-session de-dup as **unconfirmed**,
not as an established second cause.

**What this does NOT explain: why local `/code-review` misses path-scoped rules.** The observation
stands; its cause is now open. `/code-review` may not drive the `Read` tool over changed files (it
may read the diff by another path), or it may de-dup. Do not paper over this with the new mechanism —
re-run the negative control below against the current Claude Code before relying on the observation.

## Why the orchestrate skill cares

`skills/orchestrate/SKILL.md` Step 4 does NOT use `/code-review`. It launches a `code-reviewer`
subagent whose prompt **explicitly** tells it to read the `.claude/rules/*.md` matching the changed
files. That explicit read is the *entire* mechanism by which project-specific review depth (which
lives in path-scoped rules to keep the always-loaded budget small — see `rules/context-budget.md`)
reaches the review. **If that one instruction is ever dropped from the Step 4 prompt, path-scoped
coverage silently vanishes** — no error, the review just stops applying those rules. The generic
`agents/code-reviewer.md` carries the same selective-read logic as a second line of defense.

## Negative control (re-runnable — run it when you touch the Step 4 prompt)

A guard's success case proves nothing; only a negative control does. Construct the thing the
mechanism claims to catch and confirm it fires.

> **Use a pre-existing rule, or start a fresh session after authoring one.** A `paths:` rule created
> for this control does not inject in the session that created it (see above), and `/code-review`
> runs in the **main session** (`.claude/rules/orchestrate.md`) — so it inherits that session's rule
> set. The exposure is **step 2**, whose pass condition is a *non*-flag: the expected non-flag then
> arrives with nothing measured, a false confirmation. Only half of step 2 is contaminated — the
> within-run contrast (that `/code-review` *does* flag the `CLAUDE.md` violation) still holds. Step 3
> is unaffected: its prompt reads the rule explicitly, so it never depends on auto-injection at all.

1. In a repo that has a **path-scoped-only** convention (a rule in `.claude/rules/` with `paths:`
   frontmatter, where the convention appears ONLY there and NOT in `CLAUDE.md`), plant a change that
   violates it — with **no comment in the diff naming the rule** (a naming hint contaminates the
   test: the reviewer then just follows the pointer). Example: a test-suite convention scoped to a
   test directory (e.g. a required per-suite trait) omitted from a newly added suite.
2. Run local `/code-review` on the diff. Expect: it does **NOT** flag the violation, but DOES flag
   any always-loaded (`CLAUDE.md`) convention the same diff breaks — that within-run contrast is the
   clean signal (it rules out "the reviewer merely de-prioritized a nit").
3. Run the orchestrate `code-reviewer` subagent (or launch it with the Step 4 prompt) on the same
   diff. Expect: it **DOES** flag the violation, because it explicitly read the matching rule.

If step 3 stops flagging, the Step 4 prompt's rule-reading instruction has regressed — fix it before
shipping. If step 2 *starts* flagging path-scoped rules, `/code-review` behavior has changed; revisit
this whole design (the orchestrate reviewer could then lean on `/code-review` more directly).

## Design consequence

This is why orchestrate keeps an **Agent-based** reviewer instead of delegating Step 4 to
`/code-review`: only an Agent gives an injection point ("read these rules") that reaches path-scoped
depth. See `agents/code-reviewer.md` (the generic reviewer + selective-read logic) and Step 4 of
`skills/orchestrate/SKILL.md`.
