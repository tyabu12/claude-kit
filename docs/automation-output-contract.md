# Output Contract for unattended generators

**On-demand doc, not an always-loaded rule.** It binds only while authoring or running an
automation skill that files PRs/issues on its own — always-loaded files must earn their per-turn
cost by supporting the *next* decision, and this does not. **No kit skill is a generator yet**: this
is a spec for the next one, reached from the README rather than from an inbound link. Link it from a
generator skill when one lands here.

A **generator** is any skill that runs unattended (scheduled or one-shot) and produces artifacts a
human must review — a docs-fix PR, an issue, a digest. The scarce resource it spends is not compute
but **the reviewer's attention**. This contract is what keeps a generator from bankrupting it.

Extracted from a working generator family and ported as principles; each project keeps its own
mechanics.

> **Copying this doc into a project?** Take § The contract, § Backpressure and § `gh` traps.
> **Drop § What lives where and this box** — they address the kit↔project boundary and invert in
> meaning once the file sits in a project ("here" would then denote the copy). Every claim in the
> sections you keep is self-contained; there are no paths to fix up.

## The contract

0. **PRs are always Draft, and a generator never actuates.** It opens Drafts (`--draft` as the
   first flag), never marks one ready, never merges, never closes an issue, never pushes to a
   default branch, never force-pushes. **This is an invariant to enforce mechanically** — a guard
   hook, an allowlist that omits the actuating commands — not an intention. Rule 3's exemption
   below rests on it, so a generator that can mark its own PR ready has silently left the contract.
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
   non-mechanical re-introduces a mandatory reviewer pass. **Precondition**: a detector that cannot
   report the exact offset of what it found does not qualify for the auto-fix path at all —
   "replace the first match" is the free-text replace this rule bans, however mechanical the value.
4. **Backpressure.** Each generator caps its own work-in-progress (an illustrative default: at most
   one open auto-fix Draft at a time — the value is project-owned, see § What lives where), and the
   family carries an **aggregate ceiling** across generators. See § Backpressure.
5. **Manual-first.** Detectors run dry-run by default. Trust the output only after a human has
   eyeballed it for a given repo state — and never let a skill self-register its own schedule;
   scheduling is a separate, deliberate human act.
6. **Conservative *output*, exhaustive detection — filter at the output stage and account for the
   drops.** The precision bias itself is right and stays: a wrong auto-fix PR, a false issue, a
   wrong "ready to merge" (which a human may rubber-stamp), or a wrong "discard this" (which
   destroys queued work) all cost more than a missed finding — they spend reviewer attention *and*
   erode trust in the generator; a miss only defers work. What that bias must **not** do is move
   upstream into the detector. Split the pass in two:
   - **Detection is for coverage — do not filter here.** Enumerate every candidate with a
     **confidence** and a **counter-evidence** line attached — rule 2's fields, produced here rather
     than first thought about at filing time, so the output stage has something to rank on. A "be
     conservative" / "only report high-severity" instruction spent on a *model-driven* detector does
     not buy a more careful search; it leaves the investigation identical and converts fewer of its
     results into reported findings (§ Why detection must not self-filter). The only legitimate
     detection-stage suppression is a **mechanical** one, and each must name what it excluded: an
     enumerated by-design / do-not-flag roster, an evidence precondition (no exact anchor, no
     concrete before → after ⇒ not a finding), or a **declared** per-run quota. A deterministic
     detector — a script, not a model — may carry its threshold in code; that is a reviewable
     predicate, not a judgment made invisibly per run.
   - **The output stage filters, conservatively, and leaves a trail.** Vet, dedup and rank here.
     When evidence is short of decisive, route to the human-judgment bucket rather than up to
     "ready" or down to "discard". Then publish the arithmetic — **found / filtered / deduped /
     surfaced**, plus what was capped or not covered — and persist each rejection with its reason
     where the *next* run can see it (a ledger). A finding dropped without a count is
     indistinguishable from one never found: the next run re-derives it, drops it again, and nobody
     ever learns the filter is set too tight.

### Why detection must not self-filter

Rule 6's split is a model-behaviour fact, not a style preference, and it is recent. Claude 5-series
models apply a filtering instruction literally, and Anthropic's own guides say what that costs.
Sonnet 5's § "Code review harnesses": given *"only report high-severity issues"* or *"be
conservative"*, the model "may investigate the code just as thoroughly, identify the bugs, and then
not report findings it judges to be below your stated bar" — "precision typically rises, but measured
recall can fall even though the model's underlying bug-finding ability has improved." Opus 5's guide
gives the remedy in one line: "ask it to report everything and filter in a separate pass instead."
Their recommended finding-stage wording asks for coverage outright, and for "your confidence level
and an estimated severity so a downstream filter can rank them" — which is what rule 6's first
bullet requires.

Two consequences worth stating plainly. The loss is **invisible**: a run that surfaces three
findings looks the same whether the detector found three or thirty, so the failure never announces
itself. And it is **worst on a harness carried over from an older model**, where the conservative
wording was chosen when it bought a genuinely shallower pass. If a generator truly has only one
pass, the guides' fallback applies — state the bar as a concrete predicate (their example: report
any bug that could cause incorrect behavior, a test failure, or a misleading result; omit only nits
like pure style or naming), never as a qualitative "important".

Verified 2026-08-12 against
[prompting-claude-opus-5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5.md)
and
[prompting-claude-sonnet-5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5.md).
Re-check on a model-generation change — this is the kind of claim that expires.

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

The **aggregate** ceiling is advisory — the per-generator hard caps remain the real bound, so *its*
read-then-act race (two generators both observe `n` and both proceed to `n+2`) is benign. Wire it in
before it binds: the next generator then inherits backpressure for free instead of being retrofitted.

**A per-generator cap is a different matter — do not inherit that benignity.** A cap of "at most one
open Draft" assumes a single writer; two overlapping runs can each observe zero and both open one.
Either serialize runs (never schedule a generator so it can overlap itself) or re-check after
acting — push the branch, re-query for a sibling, and abandon without opening a PR if one won the
race.

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
- **`mergeable` or `mergeStateStatus` can be `UNKNOWN`** — GitHub computes merge state lazily, only
  when a merge is contemplated, so an untouched Draft may return it. It is not an error. Treat
  **either** field being `UNKNOWN` as unknown and route to human judgment. When neither is:
  `DIRTY` = conflicts, `BEHIND` = behind base, `CLEAN`/`UNSTABLE` = mergeable (`UNSTABLE` means
  non-required checks are failing or pending — still mergeable).
  ```bash
  gh pr view <N> --json mergeable,mergeStateStatus
  ```

**Verification status.** Verified 2026-07-18 against **`gh 2.95.0`**, by negative control on public
repos rather than by the success case (a green PR exits 0 either way and proves nothing):

| Claim | Evidence |
|---|---|
| bare `gh pr checks` exits **1** on failing | `cli/cli#13870` → exit 1; `--json bucket` → exit 0, `{"fail":2,"pass":7,"skipping":12}` |
| bare `gh pr checks` exits **8** on pending | `microsoft/vscode#326424` → exit 8; `--json` → exit 0 |
| zero checks ⇒ `null` | property of `add` over an empty array: `echo '[]' \| jq '[.[].bucket]\|group_by(.)\|map({(.[0]):length})\|add'` → `null`. No PR needed |
| Draft merge state | **not** reliably `UNKNOWN`: three open Drafts in `microsoft/vscode` all returned `MERGEABLE`/`BLOCKED`. Hence the softened wording above — the conservative *handling* is what matters and holds either way |

These are version-dependent CLI behaviours; re-check on a `gh` upgrade. Probing needs no local PR —
`gh pr checks -R <public/repo> <N>` reaches any public repository read-only.

## What lives where — kit-side only, drop this section when copying

When splitting this contract between the kit and a consuming project, "concept vs number" is the
wrong axis — a `gh` exit code is a number that belongs here. Use this test instead, which yields a
unique answer:

> **Would this value differ for another repo or another maintainer? Yes → project-canonical. Is it
> identical for everyone who installs the kit? → kit-canonical.**

- Kit-canonical: the seven rules above, the backpressure *concept*, and the `gh` traps including
  their exit codes — `gh` behaves the same for every installer. (Same test puts the subagent
  output-token caps kit-side: they are Claude Code's limits, not anyone's preference. The split
  thresholds beside them in `rules/subagent-usage.md` land kit-side too, but by a different route:
  they rest on a *subagent's* review attention at a given scope — a model property, uniform across
  installers — not on a maintainer's, which is what makes the WIP ceiling below project-owned.)
- Project-canonical: the aggregate ceiling's **value** (a review-attention budget that differs per
  maintainer), each generator's own cap, and the **branch predicate** identifying automation PRs (it
  encodes one repo's generator roster). Keep these canonical in the project; they are not mirrored
  here.

Apply the test to the value's **dependency**, not to anyone's wish to change it — "a reasonable
maintainer would tune this" is not the test, or every inconvenient limit becomes a default. A
threshold is project-owned only when the value it rests on differs per repo or maintainer (a WIP
ceiling rests on one human's review attention), and it must name that dependency. A threshold
derived from a platform limit stays kit-canonical and is **recomputed, never retuned**, however much
a looser one would be convenient.

A consuming project should keep a **self-contained copy** of this doc under its own
`.claude/rules/` or `docs/` rather than pointing at the kit path — a kit path does not exist for
other contributors or in CI, so a repo-tracked file that cites one carries a dead link. Reconcile
the copy **from** this file, one-way; a consumer copy must never become the source. What to strip on
copy is in the box at the top.
