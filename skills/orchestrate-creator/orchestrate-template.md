---
name: orchestrate
description: {{PROJECT_NAME}} feature orchestration — plan → issue → worktree → implement → review → PR, with model-tiered delegation and issue-comment resumption.
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, EnterWorktree, ExitWorktree
argument-hint: "[description | issue-number{{PHASE_HINT}}]"
---

<!-- generated-from: claude-kit skills/orchestrate-creator/orchestrate-template.md sha256:{{TEMPLATE_SHA12}} generated:{{GENERATED_DATE}} -->

# /orchestrate

Orchestrate the full development workflow for {{PROJECT_NAME}}: plan → issue → worktree →
implementation → review → PR.

> **Project-owned file.** Generated once by claude-kit's `/orchestrate-creator` (see the stamp
> comment above); after that it belongs to this repo — edit it freely, kit updates never touch it.
> To pull in later template improvements, run `/claude-kit:orchestrate-creator` again: it detects
> the stamp, diffs this file against the current template, and proposes back-ports as a normal PR.
>
> **Subagent budget (inlined so this skill is self-contained).** Per-response output-token caps
> (Claude Code 2.1.228): Opus 5 · Sonnet 5 · Fable 5 64,000 / Haiku 4.5 32,000; pre-5 models vary
> either way (8,192 to 64,000). Model choice is a cost lever, not a budget lever — Sonnet buys no
> headroom over Opus.
> Split delegated work at soft ~800 changed lines OR ~8 files OR ~5 review axes; hard-split above
> 1500 lines / 12 files / 7 axes — that bound is about review attention, not tokens. A cap hit is
> not silent: it auto-resumes up to 3 times, leaving a seam mid-report whose tell is a count
> mismatch (summary claims more findings than the body writes out). For more depth read this repo's
> `.claude/rules/subagent-usage.md` or `~/.claude/rules/subagent-usage.md`, if either exists; else
> use the defaults above.

## Constants

- `PLAN_MARKER`: `<!-- {{MARKER_SLUG}}-plan -->` — machine-readable marker embedded in issue plan
  comments for resumption detection. **Project-unique by construction** — a marker shared with
  another skill or repo makes resumption pick up foreign plans; never change it to a generic name.
- `OWNER_REPO`: derived at runtime via `gh repo view --json nameWithOwner -q '.nameWithOwner'`.
  Resolve early in Step 0.

## Project parameters (baked at generation)

| Parameter | Value |
|---|---|
| Test command | `{{TEST_COMMAND}}` |
| Lint command | {{LINT_COMMAND_CELL}} |
| Commit-time gate | {{COMMIT_GATE}} |
| TDD | {{TDD_POLICY}} |
| Plan-critique agent | `{{CRITIC_AGENT}}` |
| Review agent | `{{REVIEWER_AGENT}}` |

<!-- CREATOR:IF commit_gate=hook -->
**Commit-gate note:** a pre-commit hook enforces quality at commit time — after a subagent's
changes, a diff spot-check suffices before committing; the hook is the gate.
<!-- CREATOR:ELSE (commit_gate=none) -->
**Commit-gate note (do not skip):** there is no automated quality gate at commit time — so after a
subagent's changes, the orchestrator MUST run `{{TEST_COMMAND}}` (and the lint command, if set)
explicitly and confirm green **before** committing. Silent loss of this gate is the single most
dangerous failure mode of an orchestrator — never let a subagent's work reach a commit on a
spot-check alone.
<!-- CREATOR:END -->

## Step 0: Input Detection & Pre-flight

Interpret `$ARGUMENTS`:
- **`#N`**: Fetch issue via `gh issue view N`, use title/body as task spec. Check for an existing
  plan (Resumption Detection below).
<!-- CREATOR:IF roadmap=present -->
- **`phase N`**: Read ONLY that Phase section of `{{ROADMAP_PATH}}`.
<!-- CREATOR:END -->
- **(empty)**: Ask what to implement.
- **Other text**: Use as inline task description.

Derive: `TASK_TYPE` (`feat`/`fix`, default `feat`); `SLUG` (kebab-case, `^[a-z0-9][a-z0-9-]{0,36}$`;
sanitize or ask if it doesn't match).

### Resumption Detection (`#N` only)

1. Fetch issue comments, find `PLAN_MARKER`:
   ```bash
   gh api "repos/${OWNER_REPO}/issues/N/comments" --jq '.[] | select(.body | contains("<!-- {{MARKER_SLUG}}-plan -->")) | {id, body}' | tail -1
   ```
   Use the **last** match.
2. If found: set `RESUMING=true`, `ISSUE_NUMBER=N`, capture `COMMENT_ID`. Parse checkboxes
   (`- [x]` done vs `- [ ]` remaining), identify `NEXT_ITEM`. Extract `TASK_TYPE`, branch,
   `REVIEWER_MODEL`, `SESSION_MODEL` from the `## Metadata` block (normalize to lowercase
   `opus`/`sonnet`; default `opus` if a field is absent). Derive `SLUG` from the branch.
   - **Coupling re-check:** if the resumed plan has any `🎭` item but `REVIEWER_MODEL=sonnet` or
     `SESSION_MODEL=sonnet`, warn and offer to upgrade to Opus before continuing. If it is all
     `🎵` with `REVIEWER_MODEL=sonnet`, re-confirm each item is strictly within the 🎵 simple
     criteria — the label alone does not establish that (Step 1.3) — and offer the same upgrade.
   - If **all items checked**: do **not** silently proceed to review. A fully-checked *last* plan
     usually means its PR already merged — and on an **umbrella issue** that accumulates several
     historical plan comments, `tail -1` lands on that finished plan, so auto-proceeding re-reviews
     completed work instead of planning the new work the user actually wants. Ask: *"#N's last plan
     is complete (its PR likely merged) — resume-review it, or start a NEW plan for new work on
     #N?"* Only ensure you are on the branch/worktree and **skip to Step 4** on explicit
     "resume-review"; otherwise treat as a fresh task (fall through to Step 1).
   - Report "Found plan on #N. {DONE}/{TOTAL} complete. Resuming from item {NEXT_ITEM}." **Skip
     Steps 1 and 1b** → go to Step 2.
3. If no plan: proceed normally.

**Pre-flight** (in order):
1. `gh auth status` — if unauthenticated, run in **degraded mode**: no issue, no checkpoint sync,
   **no resumption** (say so explicitly). Skip all `gh` steps; the plan lives only in-session.
2. `git status` — warn on uncommitted changes.
3. Verify on default branch (skip if `RESUMING`): `DEFAULT_BRANCH=$(gh repo view --json
   defaultBranchRef -q '.defaultBranchRef.name')` (fallback `git symbolic-ref refs/remotes/origin/HEAD`
   in degraded mode). If not on it, offer `git switch`.
4. `git pull --ff-only origin "$DEFAULT_BRANCH"` — warn on failure, don't block. Skip if `RESUMING`.
5. If already in a worktree, suggest `ExitWorktree` first (unless resuming into the matching one).

## Step 1: Plan — Gate G1

1. Read the repo's `CLAUDE.md` / conventions and (if phase work) the relevant roadmap section.
2. Format the plan as a numbered checkbox list, one item = one planned commit. Label each item by
   the model tier that implements it:
   - 🎵 **simple** — delegated to a Sonnet subagent: existing-pattern reuse, test-only changes
     following an existing pattern, type/error additions, doc comments, minor fixes.
   - 🎭 **complex** — implemented by the orchestrator (session model): new design patterns,
     cross-layer changes, work near architectural boundaries, anything needing non-obvious judgment.
   - **The 🎭 list wins outright** — it names the *nature* of the work, not its difficulty, so a
     matching item stays 🎭 however settled its spec is. The tie-breaker resolves only items that
     match neither list.
   - **Tie-breaker — ask which doubt it is.** Not "is this too hard for Sonnet?": as of the
     Claude 5 generation (2026-08), difficulty or size alone no longer promotes an item. Ask
     whether it is **fully specifiable in a self-contained prompt** — a 🎵 subagent inherits none
     of this conversation. Concrete test: can you fill Step 3's 🎵 prompt slots *now* without
     making a new design decision — target file(s), plus either an existing pattern to mirror or
     an acceptance condition? No → 🎭. Yes, and merely hard → 🎵. **Can't tell → 🎭.** Also promote
     a 🎵 to 🎭 when subagent + verify overhead exceeds the work itself (single-line edits, tiny
     doc tweaks).

   ```
   - [ ] 1. 🎵 <description> (`<primary-file-path>`)
   - [ ] 2. 🎭 <description> (`<primary-file-path>`)
   ```
   Present to the user; store as `PLAN_BODY`.
3. **Assign a reviewer model** (single choice for the whole PR). Force **Opus** if any item touches
   the **sensitive base** — CI/build infra, auth/secrets/crypto, public API or protocol
   signatures, IaC (Terraform/k8s), migrations, `.claude/**` tooling, security/privacy surface{{SENSITIVE_PATHS_SUFFIX}}.
   Otherwise **Sonnet** is acceptable only if every item is strictly within the 🎵 simple criteria.
   **Test that independently — a 🎵 label does not certify it.** The tie-breaker also routes
   "specifiable but merely hard" items to 🎵, and those are not strictly simple; if the plan has
   one, the reviewer is Opus (keep `Session: Sonnet` — the cost lever survives).
   **Coupling rule:** any 🎭 item ⇒ reviewer MUST be Opus — a 🎭 label means non-obvious judgment
   or an architectural boundary, where a missed defect is most expensive. Record in
   `## Metadata` as `- **Reviewer**: Opus (reason: …)`; store the reason tail as `REVIEWER_RATIONALE`.
4. **Assign a session model** (label-driven only): any 🎭 item → `Session: Opus`; all 🎵 →
   `Session: Sonnet` (recommended — the cost lever; the implementation tail runs at Sonnet rates,
   while the reviewer is set by step 3's own strictly-simple test, not by this choice). Record as
   `- **Session**: Sonnet (reason: all items 🎵)`; store `SESSION_RATIONALE`. **Coupling:** a Sonnet
   session override is rejected when any item is 🎭 (warn, keep Opus).
5. **Ask: "Proceed with this plan, reviewer-model, session-model?"**
   For single-commit changes, combine G1 and G2, but still run Step 1b first.

## Step 1b: Plan Critique (REQUIRED unless `RESUMING`)

Launch a `{{CRITIC_AGENT}}` subagent to review the plan for blind spots.

> **Prompt:** "Review this implementation plan. Focus on: scope creep, missing edge cases,
> integration risks with existing modules, assumptions not validated against the codebase, and —
> if the plan declares a reviewer-model choice — whether that choice matches the sensitivity of the
> touched paths. Read the repo's `CLAUDE.md` for context.
> Task: {TASK_DESCRIPTION}
> Plan: {PLAN_BODY}
> Output your full two-stage evaluation (axes, evaluation, summary table, top actions)."

- **Any Critical verdict:** present the report, **ask "revise or proceed?"**. Revise → back to
  Step 1, regenerate, re-run 1b.
- **OK/Warning only:** present the summary as context, proceed to Step 2.

## Step 2: Issue + Worktree — Gate G2

### 2a: Issue & Plan Comment

- **`RESUMING`:** skip.
- **Degraded mode (unauthenticated):** skip; keep the plan in-session (no resumption).
- **From `#N`:** post the plan as a comment on `#N`:
  ```bash
  COMMENT_ID=$(gh api "repos/${OWNER_REPO}/issues/N/comments" \
    -f body="$(cat <<'ORCH_PLAN'
  <!-- {{MARKER_SLUG}}-plan -->
  ## Implementation Plan

  {PLAN_BODY}

  ## Metadata
  - **Type**: {TASK_TYPE}
  - **Branch**: `{TASK_TYPE}/{SLUG}`
  - **Reviewer**: {REVIEWER_MODEL} (reason: {REVIEWER_RATIONALE})
  - **Session**: {SESSION_MODEL} (reason: {SESSION_RATIONALE})
  ORCH_PLAN
  )" --jq '.id')
  ```
  Title-case model names in Metadata; Step 0 normalizes on read.
- **Otherwise (new task):** create an issue (`gh issue create --title "{EMOJI} {TASK_TYPE}: {TITLE}"
  --assignee "@me" [--label "$LABEL"] --body …`), extract `ISSUE_NUMBER`, then post the plan as the
  first comment (capture `COMMENT_ID`). **Label fallback:** if `--label` fails (label absent in the
  repo), retry without it (or offer to create the label) — never block on a missing label.

### 2b: Worktree Setup

- **`RESUMING`:** find existing worktree (`git worktree list | grep {SLUG}`) → `EnterWorktree`; else
  recreate from the remote branch; else fresh. If `SESSION_MODEL=sonnet`, prompt `/model sonnet`
  first, then **ask "Resume from item {NEXT_ITEM}/{TOTAL}?"**
- **Normal:**
  1. "Issue #{ISSUE_NUMBER} created. Branch: `{TASK_TYPE}/{SLUG}`" (or, degraded, just the branch).
  2. If `SESSION_MODEL=sonnet`, tell the user to run `/model sonnet` now (or keep Opus). Then **ask
     "Create worktree and start?"**
  3. `EnterWorktree` with `name: "{TASK_TYPE}/{SLUG}"` (on collision, check `git ls-remote --heads
     origin <branch>`, append `-2`).
  4. Rename to conventional format: `git branch -m "$(git branch --show-current)" "{TASK_TYPE}/{SLUG}"`.
  5. Verify: `git branch --show-current`.

**Worktree path hygiene** (holds for the rest of the session): the original checkout stays on another
branch, so a tool that resolves to it instead of this worktree acts on the wrong tree silently.
Non-isolation subagents (Step 3 implementer, Step 4 reviewer) inherit this
worktree's cwd — but cwd inheritance for a non-isolation subagent is **not documented as guaranteed**
(it has resolved to the *original* checkout in practice, yielding an empty phantom diff that reads as a
false FAIL). So don't rely on it: capture the root once with `WORKTREE_ROOT=$(git rev-parse --show-toplevel)`
and **embed `git -C {WORKTREE_ROOT}`** into every subagent prompt that runs git (Step 3 implementer,
Step 4 reviewer) — never a bare `git` the subagent resolves against its own cwd, and never a `$(…)` it
re-runs or a reused pre-worktree path. Same rule for absolute Edit/Write paths: resolve them under
`{WORKTREE_ROOT}`, and invalidate any carried over from a *pre-worktree* tool result.

## Step 3: Implementation

Follow the plan. If `RESUMING`, start from `NEXT_ITEM`. Per item (`K` = plan item number):

### 🎭 Complex — orchestrator implements directly

<!-- CREATOR:IF tdd=required -->
1. Write the test first — TDD is required in this project. Skip only for docs-only / test-only items.
<!-- CREATOR:ELSE (tdd=optional) -->
1. If the item is code with a test surface, write the test first. Skip for docs-only / test-only
   items.
<!-- CREATOR:END -->
2. Run `{{TEST_COMMAND}}` (targeted to the item's tests where possible) — confirm red (TDD).
3. Write the implementation.
4. Run `{{TEST_COMMAND}}` — confirm green.
5. Commit (project's commit convention).
6. **Checkpoint sync** (skip in degraded mode) — check off item `K` in the plan comment:
   ```bash
   BODY=$(gh api "repos/${OWNER_REPO}/issues/comments/${COMMENT_ID}" --jq '.body')
   UPDATED=$(echo "$BODY" | sed "s/^- \[ \] ${K}\./- [x] ${K}./")
   gh api "repos/${OWNER_REPO}/issues/comments/${COMMENT_ID}" -X PATCH -f body="$UPDATED" --jq '.url'
   ```
   On `gh` failure, **warn and continue** — never block on a sync failure.

### 🎵 Simple — delegate to a Sonnet subagent

Launch `Agent(model: "sonnet")` **without `isolation`** (shares the worktree). Subagents run
**sequentially**, never in parallel. Give it `Read, Grep, Glob, Bash, Write, Edit` — NOT
`EnterWorktree`/`ExitWorktree`. Bound the delegated scope so the item stays reviewable in one pass
— split at soft ~800 changed lines / ~8 files / ~5 axes, hard-split above 1500 / 12 / 7 (see the
budget note at the top of this file).

> **Prompt template:** "You are implementing item {K} of a plan for this project.
> Work inside `{WORKTREE_ROOT}` — treat every path below as rooted there and run tests/git via
> `-C {WORKTREE_ROOT}` (or `cd` there first); do not rely on inherited cwd.
> **Read the repo's `CLAUDE.md` first** — follow all its conventions.
> **Task:** {ITEM_DESCRIPTION}. **Target file(s):** {PRIMARY_FILE_PATH}.
> **Reference:** {existing similar file to mirror, if any}.
> Procedure: if implementation, follow the project's testing convention — write/adjust the test,
> run `{{TEST_COMMAND}}` (targeted), confirm it fails, implement, run again, confirm it passes. If
> docs-only or test-only, make the change directly. **Do NOT commit** — leave changes unstaged; the
> orchestrator reviews and commits. If tests still fail after your best effort, return a summary of
> what you tried and the error output."

**After the subagent returns:**
1. `git status` — verify expected changes only.
2. Read `git diff` fully before writing the commit message.
<!-- CREATOR:IF commit_gate=hook -->
3. **Gate:** a convention spot-check suffices — the pre-commit hook enforces the rest.
<!-- CREATOR:ELSE (commit_gate=none) -->
3. **Gate:** run `{{TEST_COMMAND}}` (and the lint command) yourself and confirm green — there is no
   commit-time hook to catch a failure.
<!-- CREATOR:END -->
4. Commit.
5. Checkpoint sync (same PATCH as above; skip in degraded mode).

**Fallback (subagent could not make tests pass):** take over immediately — do not retry Sonnet.
`git stash -u` to save partial work, then escalate **by session model**: `SESSION_MODEL=opus` →
orchestrator finishes it via the 🎭 flow; `SESSION_MODEL=sonnet` → delegate to
`Agent(subagent_type: "implementer", model: "opus")` (no `isolation`) with the item spec + the
error output; on return, review the diff and commit. If Opus also fails, report and offer
`/model opus` + retry directly.

**After all items,** run full verification from the main session: run `{{TEST_COMMAND}}` (full),
then the lint command if the project has one. On failure, fix, verify locally, commit with
`🐛 fix:`, re-run. **Hard limit: 3 iterations** — if still failing, report and ask whether to
proceed to Step 4.

> **Carve-out — no-source branches:** when the branch changed nothing the suite actually exercises
> (docs-only, rules-only, comment-only), a full run is zero-signal — often many minutes for no
> information. Scope to the impacted subset, or skip the suite with a one-line reason stated in the
> PR, and still run the lint command if it covers the touched files (prose/markdown linters do).

## Step 4: Review — Gate G3

**Before launching the reviewer,** `git fetch origin {DEFAULT_BRANCH}` and check `git rev-list --count
HEAD..origin/{DEFAULT_BRANCH}` — a long session can span hours during which `{DEFAULT_BRANCH}` advances.
If the count is non-zero, offer a rebase before review; treat it as **mandatory** when the diff touches
large generated / data files (lockfiles, generated code, schema dumps), where a rebase or
non-conflicting auto-merge can drop upstream entries without surfacing a conflict.

Launch a `{{REVIEWER_AGENT}}` subagent with `model: $REVIEWER_MODEL` (lowercase `opus`/`sonnet`, from
Metadata; defaults Opus). The reviewer MUST emit a `**Verdict**: PASS | FAIL` line — the gate loop
below parses it; a reviewer that omits it breaks the gate. Split large diffs to keep review quality
— soft ~800 lines / ~8 files / ~5 axes, hard above 1500 / 12 / 7 (see the budget note at the top of
this file).

> **Prompt:** "Review all changes on this feature branch. Run **`git -C {WORKTREE_ROOT} diff
> {DEFAULT_BRANCH}...HEAD`** for the full diff (all commits since branching) — use the `-C` path, do
> not rely on cwd; a bare `git` can resolve to the original checkout and show an empty phantom diff.
> Read every changed file in full. Read the repo's
> `CLAUDE.md`, and only the `.claude/rules/*.md` whose `paths:` frontmatter matches a changed file
> (plus any rule that has no `paths:`) — path-scoped rules are NOT auto-loaded during a review, and
> reading every rule wastes budget on a large rule set, so this explicit selective read is
> load-bearing. Evaluate against the project's conventions plus general correctness/quality. Output
> your review in your standard format, including a `**Verdict**: PASS | FAIL` line."

**Review-verify-fix loop:**
1. **PASS** → Step 5.
2. **FAIL:** (a) launch 1 read-only verify agent to filter false positives (e.g. force-unwrap
   flagged in test code that's exempt); (b) build the Review Action Summary table (`# | Issue |
   Severity | Verification | Action | Reason`) and present it; (c) capture
   `FIX_BASE=$(git rev-parse HEAD)`, then fix confirmed issues, skip false positives; (d) re-run
   the reviewer **scoped to the fix**: prompt it with `git diff {FIX_BASE}...HEAD` plus the prior
   FAIL items, verifying each fix and its immediate blast radius — not the whole branch.
   Full-branch re-review only when a fix touched files outside the previously reviewed set.
3. **Hard limit: 3 iterations** — if still FAIL, report remaining issues.

## Step 5: PR Creation

Degraded mode: skip — report the branch is ready to push/PR manually, stop.

Base branch: `gh repo view --json defaultBranchRef -q '.defaultBranchRef.name'`. Label from the
dominant commit prefix (`feat→enhancement`, `fix→bug`, `docs→documentation`, `refactor→refactor`,
`test→testing`, `chore→chore`, `ci→ci`, `perf→performance`); add `security` if security-related.
**If the label doesn't exist in the repo, drop it** (same fallback as Step 2a).

Present the PR draft (informational; created automatically, no gate):
- Title: emoji prefix + Conventional format, < 70 chars.
- Body: summary bullets + test plan + issue link (omit in degraded mode). Use `Closes #N` **only when
  this PR completes the issue**; for a non-final PR of a multi-PR / umbrella issue, use `Part of #N`
  so merging it does not prematurely auto-close the issue.
<!-- CREATOR:IF qa_section=given -->
- Manual-QA section (render as a PR-body rule): {{QA_SECTION}}
<!-- CREATOR:END -->

**Push and create as two separate Bash calls** — never combine with `&&` (a leading `git push`
breaks the `gh pr create --base`-anchored PR hooks):
```bash
git push -u origin <branch>
```
```bash
gh pr create --base "$BASE_BRANCH" --assignee "@me" [--label "$LABEL"] \
  --title "..." --body "$(cat <<'ORCH_PR'
## Summary
...
## Test plan
...
ORCH_PR
)"
```
After creation: print the PR URL; "wait for required checks, then merge manually."

## Step 6: Cleanup

**After merge** (guidance only — do NOT auto-execute): `ExitWorktree` action `"remove"`;
`git switch <default-branch> && git pull`.

> **Post-merge `remove` may refuse:** squash / rebase merge gives the merged commit a **new SHA**, so
> the worktree's local commits read as unmerged by ancestry and `ExitWorktree(action: "remove")`
> refuses — as it also can *before* the post-merge `pull`, when local `{DEFAULT_BRANCH}` doesn't yet
> contain the merge. Once the user confirms the merge landed, re-invoke with `discard_changes: true`.
