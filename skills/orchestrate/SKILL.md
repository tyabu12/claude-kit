---
name: orchestrate
description: Project-agnostic feature orchestration — plan → issue → worktree → implement → review → PR, driven by a per-project profile. A project's own `orchestrate` skill shadows this one (project scope wins over global).
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, EnterWorktree, ExitWorktree
argument-hint: "[description | issue-number | phase N]"
---

# /orchestrate

Generic orchestration skeleton: plan → issue → worktree → implementation → review → PR, with
model-tiered delegation and issue-comment resumption. The **project-specific bits** (test/lint
commands, commit-time gate, sensitive paths, TDD policy) come from a **project profile**, not from
this file.

> **Not a line-synced mirror.** A project-local skill with the same name (`orchestrate`) shadows
> this one (project scope wins over global; see Step 0 guard). There is **no obligation to keep
> this in sync** with any project's version — back-port *principles* only, never mechanics. A
> project that needs richer, self-contained orchestration should ship its own `orchestrate` skill.
>
> **Subagent budget (inlined so this skill is self-contained).** Hard output-token caps (not
> configurable): Opus 4.x 32,000 / Sonnet 4.x·5 64,000 / Haiku 4.x 8,192 / Fable 5 undocumented
> (quality lever, not budget). Split delegated work at soft ~800 changed lines OR ~8 files OR ~5
> review axes; hard-split above 1500 lines / 12 files / 7 axes. Budget exhaustion is silent (the
> final report just goes missing). For more depth read this kit's `rules/subagent-usage.md` (or
> `~/.claude/rules/subagent-usage.md` if installed); if absent, use the defaults above.

## Constants

- `PLAN_MARKER`: `<!-- claude-orchestrate-plan -->` — machine-readable marker embedded in issue plan
  comments for resumption detection. (Projects with their own `orchestrate` use their own marker; a
  plan created here is only resumable here.)
- `OWNER_REPO`: derived at runtime via `gh repo view --json nameWithOwner -q '.nameWithOwner'`.
  Resolve early in Step 0.

## The project profile

Project-specific parameters are read from **`.claude/orchestrate.md`** in the repo (a repo-tracked,
self-contained file — safe for other contributors, unlike a per-machine reference). Expected fields
(all optional; sensible fallbacks below):

| Field | Meaning | Fallback if absent |
|---|---|---|
| `test_command` | how to run the project's tests | infer from tooling (see Step 0), else ask |
| `lint_command` | lint/format/typecheck gate, if any | infer, else skip with a warning |
| `commit_gate` | `hook` (pre-commit hook enforces quality) or `none` | `none` → see gate note below |
| `tdd` | `required` / `optional` / `n-a` | `optional` (tests required, TDD not mandated) |
| `sensitive_paths` | extra globs that force an Opus reviewer | none (global base list still applies) |
| `qa_section` | project-specific manual-QA rules for the PR body | omit the section |
| `vcs` | `github` / `none` | detect via `gh auth status` + remote |

**Commit-gate note (do not skip):** when `commit_gate=none`, there is no automated quality gate at
commit time — so after a subagent's changes, the orchestrator MUST run `test_command` (and
`lint_command` if set) explicitly and confirm green **before** committing. When `commit_gate=hook`,
the hook is the gate and a diff spot-check suffices. Silent loss of this gate is the single most
dangerous failure mode of a generic orchestrator — never let a subagent's work reach a commit on a
spot-check alone in a `none` project.

**If the profile is missing:** infer `test_command` / `lint_command` from the project (Step 0),
**confirm the inferred values with the user at G1**, and then **offer to write `.claude/orchestrate.md`
with the confirmed values** so subsequent runs are silent. Do not auto-detect-and-proceed without
confirmation — a wrong `test_command` produces a false green and ships a broken commit.

## Step 0: Input Detection & Pre-flight

**Project-override note (first thing):** a project's own `.claude/skills/orchestrate/` shadows this
global skill automatically (same name, project scope wins), so this generic skeleton only runs when
the repo has no project-specific `orchestrate`. If you nonetheless reach here in a repo that clearly
ships bespoke orchestration under a *different* name, STOP and tell the user to invoke that instead
— it carries project-specific gates this generic skill lacks.

Interpret `$ARGUMENTS`:
- **`#N`**: Fetch issue via `gh issue view N`, use title/body as task spec. Check for an existing
  plan (Resumption Detection below).
- **`phase N`**: If the project has a roadmap doc (`docs/ROADMAP.md` or per profile), read ONLY that
  Phase section. Else treat as inline text.
- **(empty)**: Ask what to implement.
- **Other text**: Use as inline task description.

Derive: `TASK_TYPE` (`feat`/`fix`, default `feat`); `SLUG` (kebab-case, `^[a-z0-9][a-z0-9-]{0,36}$`;
sanitize or ask if it doesn't match).

**Load the profile:** read `.claude/orchestrate.md` if present. If absent, infer commands from
tooling — `package.json` scripts (`test`/`lint`/`typecheck`), `Makefile`/`justfile` targets,
`Cargo.toml` (`cargo test`/`cargo clippy`), `go.mod` (`go test ./...`/`golangci-lint`), etc. **In a
monorepo / multi-tool repo, commands differ per subproject** — do not assume one command covers the
repo; scope by the touched paths and confirm at G1.

### Resumption Detection (`#N` only)

1. Fetch issue comments, find `PLAN_MARKER`:
   ```bash
   gh api "repos/${OWNER_REPO}/issues/N/comments" --jq '.[] | select(.body | contains("<!-- claude-orchestrate-plan -->")) | {id, body}' | tail -1
   ```
   Use the **last** match.
2. If found: set `RESUMING=true`, `ISSUE_NUMBER=N`, capture `COMMENT_ID`. Parse checkboxes
   (`- [x]` done vs `- [ ]` remaining), identify `NEXT_ITEM`. Extract `TASK_TYPE`, branch,
   `REVIEWER_MODEL`, `SESSION_MODEL` from the `## Metadata` block (normalize to lowercase
   `opus`/`sonnet`; default `opus` if a field is absent). Derive `SLUG` from the branch.
   - **Coupling re-check:** if the resumed plan has any `🎭` item but `REVIEWER_MODEL=sonnet` or
     `SESSION_MODEL=sonnet`, warn and offer to upgrade to Opus before continuing.
   - If **all items checked**: ensure you are on the branch/worktree, report "All complete,
     proceeding to review", **skip to Step 4**.
   - Report "Found plan on #N. {DONE}/{TOTAL} complete. Resuming from item {NEXT_ITEM}." **Skip
     Steps 1 and 1b** → go to Step 2.
3. If no plan: proceed normally.

**Pre-flight** (in order):
1. `gh auth status` — if unauthenticated OR `vcs=none`, run in **degraded mode**: no issue, no
   checkpoint sync, **no resumption** (say so explicitly). Skip all `gh` steps; the plan lives only
   in-session.
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
   - **When in doubt → 🎭.** Also promote a 🎵 to 🎭 when subagent + verify overhead exceeds the
     work itself (single-line edits, tiny doc tweaks).

   ```
   - [ ] 1. 🎵 <description> (`<primary-file-path>`)
   - [ ] 2. 🎭 <description> (`<primary-file-path>`)
   ```
   Present to the user; store as `PLAN_BODY`.
3. **Assign a reviewer model** (single choice for the whole PR). Force **Opus** if any item touches
   the **global sensitive base** — CI/build infra, auth/secrets/crypto, public API or protocol
   signatures, IaC (Terraform/k8s), migrations, `.claude/**` tooling, security/privacy surface — OR
   any glob in the profile's `sensitive_paths`. Otherwise **Sonnet** is acceptable only if every
   item is strictly within the 🎵 simple criteria. **Coupling rule:** any 🎭 item ⇒ reviewer MUST be
   Opus. When in doubt, Opus. Record in `## Metadata` as `- **Reviewer**: Opus (reason: …)`; store
   the reason tail as `REVIEWER_RATIONALE`.
4. **Assign a session model** (label-driven only): any 🎭 item → `Session: Opus`; all 🎵 →
   `Session: Sonnet` (recommended — the cost lever; the implementation tail runs at Sonnet rates,
   and review quality is unaffected because the reviewer is assigned independently). Record as
   `- **Session**: Sonnet (reason: all items 🎵)`; store `SESSION_RATIONALE`. **Coupling:** a Sonnet
   session override is rejected when any item is 🎭 (warn, keep Opus).
5. **If the profile was inferred, not read:** present the inferred `test_command` / `lint_command` /
   `commit_gate` alongside the plan for confirmation, and offer to persist `.claude/orchestrate.md`.
6. **Ask: "Proceed with this plan, reviewer-model, session-model (and inferred profile, if any)?"**
   For single-commit changes, combine G1 and G2, but still run Step 1b first.

## Step 1b: Plan Critique (REQUIRED unless `RESUMING`)

Launch a `critic` subagent to review the plan for blind spots. (When this kit is consumed as a
plugin, the agent name is namespaced `claude-kit:critic`.)

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
- **Degraded mode (`vcs=none` / unauthenticated):** skip; keep the plan in-session (no resumption).
- **From `#N`:** post the plan as a comment on `#N`:
  ```bash
  COMMENT_ID=$(gh api "repos/${OWNER_REPO}/issues/N/comments" \
    -f body="$(cat <<'ORCH_PLAN'
  <!-- claude-orchestrate-plan -->
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

## Step 3: Implementation

Follow the plan. If `RESUMING`, start from `NEXT_ITEM`. Per item (`K` = plan item number):

### 🎭 Complex — orchestrator implements directly

1. If `tdd=required` (or the item is code with a test surface), write the test first. Skip for
   docs-only / test-only items.
2. Run `test_command` (targeted to the item's tests where possible) — confirm red (TDD).
3. Write the implementation.
4. Run `test_command` — confirm green.
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
`EnterWorktree`/`ExitWorktree`. Bound the delegated scope so the report fits the output cap —
split at soft ~800 changed lines / ~8 files / ~5 axes, hard-split above 1500 / 12 / 7 (this kit's
`rules/subagent-usage.md`, or `~/.claude/rules/subagent-usage.md` if installed, for depth).

> **Prompt template:** "You are implementing item {K} of a plan for this project.
> **Read the repo's `CLAUDE.md` first** — follow all its conventions.
> **Task:** {ITEM_DESCRIPTION}. **Target file(s):** {PRIMARY_FILE_PATH}.
> **Reference:** {existing similar file to mirror, if any}.
> Procedure: if implementation, follow the project's testing convention — write/adjust the test,
> run `{test_command}` (targeted), confirm it fails, implement, run again, confirm it passes. If
> docs-only or test-only, make the change directly. **Do NOT commit** — leave changes unstaged; the
> orchestrator reviews and commits. If tests still fail after your best effort, return a summary of
> what you tried and the error output."

**After the subagent returns:**
1. `git status` — verify expected changes only.
2. Read `git diff` fully before writing the commit message.
3. **Gate:** if `commit_gate=none`, run `test_command` (and `lint_command`) yourself and confirm
   green. If `commit_gate=hook`, a convention spot-check suffices (the hook enforces the rest).
4. Commit.
5. Checkpoint sync (same PATCH as above; skip in degraded mode).

**Fallback (subagent could not make tests pass):** take over immediately — do not retry Sonnet.
`git stash -u` to save partial work, then escalate **by session model**: `SESSION_MODEL=opus` →
orchestrator finishes it via the 🎭 flow; `SESSION_MODEL=sonnet` → delegate to
`Agent(subagent_type: "implementer", model: "opus")` (no `isolation`) with the item spec + the
error output; on return, review the diff and commit. If Opus also fails, report and offer
`/model opus` + retry directly.

**After all items,** run full verification from the main session: run `test_command` (full), then
`lint_command`. On failure, fix, verify locally, commit with `🐛 fix:`, re-run. **Hard limit: 3
iterations** — if still failing, report and ask whether to proceed to Step 4.

## Step 4: Review — Gate G3

Launch a `code-reviewer` subagent with `model: $REVIEWER_MODEL` (lowercase `opus`/`sonnet`, from
Metadata; defaults Opus). Split large diffs to avoid truncation — soft ~800 lines / ~8 files / ~5
axes, hard above 1500 / 12 / 7 (this kit's `rules/subagent-usage.md`, or
`~/.claude/rules/subagent-usage.md` if installed, for depth).

> **Prompt:** "Review all changes on this feature branch. Run `git diff {DEFAULT_BRANCH}...HEAD` for
> the full diff (all commits since branching). Read every changed file in full. Read the repo's
> `CLAUDE.md` and `.claude/rules/**` and evaluate against the project's conventions plus general
> correctness/quality. Output your review in your standard format."

**Review-verify-fix loop:**
1. **PASS** → Step 5.
2. **FAIL:** (a) launch 1 read-only verify agent to filter false positives (e.g. force-unwrap
   flagged in test code that's exempt); (b) build the Review Action Summary table (`# | Issue |
   Severity | Verification | Action | Reason`) and present it; (c) fix confirmed issues, skip false
   positives; (d) re-run the reviewer.
3. **Hard limit: 3 iterations** — if still FAIL, report remaining issues.

## Step 5: PR Creation

Degraded mode: skip — report the branch is ready to push/PR manually, stop.

Base branch: `gh repo view --json defaultBranchRef -q '.defaultBranchRef.name'`. Label from the
dominant commit prefix (`feat→enhancement`, `fix→bug`, `docs→documentation`, `refactor→refactor`,
`test→testing`, `chore→chore`, `ci→ci`, `perf→performance`); add `security` if security-related.
**If the label doesn't exist in the repo, drop it** (same fallback as Step 2a).

Present the PR draft (informational; created automatically, no gate):
- Title: emoji prefix + Conventional format, < 70 chars.
- Body: summary bullets + test plan + `Closes #N` (omit in degraded mode). If the profile has a
  `qa_section`, render it (concrete manual-QA steps or a one-line "not needed" + reason); else omit.

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
