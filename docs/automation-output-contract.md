# Output Contract for unattended generators

**On-demand doc, not an always-loaded rule.** It binds only while authoring or running an
automation skill that files PRs/issues on its own, so it stays out of `rules/` per
`rules/context-budget.md` § Classifier. Skills that follow it should link here explicitly.

A **generator** is any skill that runs unattended (scheduled or one-shot) and produces artifacts a
human must review — a docs-fix PR, an issue, a digest. The scarce resource it spends is not compute
but **the reviewer's attention**. This contract is what keeps a generator from bankrupting it.

Origin: extracted from a working generator family in a consumer project. Ported here as principles;
each project keeps its own mechanics.

## The contract

1. **Mechanically-determined fix → one batched Draft PR.** A finding is auto-fixable only when the
   correct value is *uniquely determined by an authoritative source* (a version from a lockfile, a
   deployment target from a build setting). Batch every such fix from one run into a **single**
   Draft PR.
2. **Judgment-needed → issue only, never an auto-fix.** Anything whose fix requires a human
   decision is filed as an issue whose body carries a **confidence score** and an explicit
   **counter-evidence / "why this might be wrong"** section. This applies to every judgment output
   a generator emits, including recommendations to discard work.
3. **The auto-fix path edits authoritative-source-computed values only — never free-form prose —
   and splices at the detected token's exact offset, not by free-text replace.** This bound is what
   makes omitting a code-review pass safe (see below). A detector that wants to auto-fix something
   non-mechanical re-introduces a mandatory reviewer pass.
4. **Backpressure.** Each generator caps its own work-in-progress (e.g. at most one open auto-fix
   Draft at a time), and the family carries an **aggregate ceiling** across generators. See
   § Backpressure.
5. **Manual-first.** Detectors run dry-run by default. Trust the output only after a human has
   eyeballed it for a given repo state — and never let a skill self-register its own schedule;
   scheduling is a separate, deliberate human act.
6. **Conservative detection wins.** Prefer a miss over a wrong flag. A wrong auto-fix PR, a false
   issue, or a wrong "discard this" costs more than a missed finding — the first three spend
   reviewer attention *and* erode trust in the generator; the last only defers work.

### Why an auto-fix PR may skip a code-review pass

Not because the diff is small. The safety rests on two things: the PR is always **Draft** so a
human merge is the review gate, and rule 3 bounds the edit to a value with exactly one correct
answer — there is nothing for a reviewer to assess on a one-token swap. **If rule 3 is relaxed,
restore the reviewer pass.** A generator that writes arbitrary code (a feature implementer) never
qualifies for this exemption.

## Backpressure

Per-generator caps bound each *lane*; nothing watches the *sum*. As generators are added, each stays
within its local cap while the aggregate of unreviewed Drafts climbs past what one human absorbs.
The aggregate ceiling is that missing sum-level guard.

It is **advisory** — the per-generator hard caps remain the real bound, so the read-then-act race
(two generators both observe `n` and both proceed to `n+2`) is benign. Wire it in before it binds:
the next generator then inherits backpressure for free instead of being retrofitted.

**The ceiling value and the branch predicate that identifies automation-origin PRs are
project-owned, not kit-owned** — see § What lives where.

## `gh` read-surface traps (Draft-triage automation)

Empirically derived; each cost a debugging round.

- **`gh pr checks <N>` exits non-zero on pending (8) and failing (1)** — that is, on exactly the PRs
  a triage pass most needs to classify, so a bare call aborts a `set -e` loop. Use the JSON form,
  which exits 0 across states:
  ```bash
  gh pr checks <N> --json bucket --jq '[.[].bucket] | group_by(.) | map({(.[0]): length}) | add'
  ```
  Read: all `pass`/`skipping` ⇒ green; any `fail`/`cancel` ⇒ red; any `pending` ⇒ still running.
- **A PR with zero checks yields `null`** from that `add` over an empty array. `null` is
  *unknown*, **not** green — never promote it to a ready/mergeable bucket.
- **`mergeable` / `mergeStateStatus` of `UNKNOWN` is the normal state for an untouched Draft**, not
  an error — GitHub computes merge state lazily, only when a merge is contemplated. Treat `UNKNOWN`
  as unknown and route to human judgment. When non-`UNKNOWN`: `DIRTY` = conflicts, `BEHIND` = behind
  base, `CLEAN`/`UNSTABLE` = mergeable.
  ```bash
  gh pr view <N> --json mergeable,mergeStateStatus
  ```

**Verification status.** The `--json bucket` shape and its exit-0 behaviour on a green PR were
re-verified against live PRs on 2026-07-18. The pending-8 / failing-1 exit codes, the zero-check
`null`, and Draft `UNKNOWN` are carried over from empirical observation in the origin project
(validated there against real PRs at write time, 2026-07); they could not be re-run here because no
open or CI-in-flight PR existed at the time of writing. Re-verify opportunistically rather than
treating them as freshly confirmed.

## What lives where

When splitting this contract between the kit and a consuming project, the criterion is **not**
"concept vs number":

> **A fact about a universal tool is kit-canonical. A fact encoding one repo's budget or roster is
> project-canonical.**

- Kit-canonical: the six rules above, the backpressure *concept*, the `gh` traps — including their
  numeric exit codes, which are facts about `gh` (and see `rules/subagent-usage.md`, whose token
  caps are kit-canonical for the same reason: they are Claude Code's limits).
- Project-canonical: the aggregate ceiling's **value** (it encodes one human's review-attention
  budget) and the **branch predicate** identifying automation PRs (it encodes one repo's generator
  roster). Keep these canonical in the project, and do not mirror them here.

A consuming project should keep a **self-contained copy** of this doc under its own
`.claude/rules/` or `docs/` rather than pointing at the kit path: a kit reference is a dead link for
every other contributor and in CI (`rules/knowledge-layering.md` § Anti-pattern). Reconcile the copy
**from** this file, one-way; a consumer copy must never become the source.
