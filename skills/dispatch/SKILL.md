---
name: dispatch
description: "Fan out multiple independent tasks in the current repo to worktree-isolated implementer subagents running in parallel. Each task: implement → auto-detected verification (just/make/gradle/swift/npm/composer/cargo/pytest/dotnet) → commit → push → draft PR (assigned + labeled) → critic review of the diff. One approval gate on the dispatch plan; issue-backed tasks get self-assigned and labeled in-progress. Use when the user has a batch of small-to-medium independent, well-specified tasks (backlog items, issue numbers, cleanup lists) to run in parallel. For a single large feature that needs planning and design judgment, use /orchestrate instead."
argument-hint: "[bullet-list of tasks | path/to/tasks.md | #123 #124 ...]"
disable-model-invocation: true
---

# /dispatch

Parallel fan-out for a batch of independent tasks in the **current repository**.
This skill ends at draft PRs plus a review verdict per task; marking PRs ready,
merging, and follow-up on later CI/review comments stay with the user.

Respond in the user's conversation language. Skip narration between tool calls.

> **Subagent budget (inlined so this skill is self-contained).** Hard output-token caps (not
> configurable): Opus 4.x 32,000 / Sonnet 4.x·5 64,000 / Haiku 4.x 8,192 / Fable 5 undocumented
> (quality lever, not budget). Keep each dispatched task within ~800 changed lines. For more depth
> read this kit's `rules/subagent-usage.md` (or `~/.claude/rules/subagent-usage.md` if installed).

## Pre-flight

1. `git status` — report a dirty worktree; dispatch itself never touches the
   user's current checkout (subagents work in their own worktrees).
2. Detect the base branch (`origin/HEAD`, fallback `main`).
3. Detect the **verification command**, in priority order — record what you find
   and include it verbatim in every delegation prompt:
   1. Commands documented in the repo's CLAUDE.md / AGENTS.md (build/test section)
   2. `justfile` → `just test` (+ lint/analyze recipes if present)
   3. `Makefile` → `make test`
   4. `gradlew` / `build.gradle(.kts)` → `./gradlew test`
   5. `Package.swift` → `swift test`
   6. `package.json` scripts → `npm test` (or the repo's package manager)
   7. `composer.json` scripts → `composer test` / `composer analyze`
   8. `Cargo.toml` → `cargo test`
   9. `pyproject.toml` / `pytest.ini` → `pytest`
   10. `*.sln` / `*.csproj` → `dotnet test`
   If nothing is found, say so and ask the user for the command before dispatching.
4. **Verification weight**: judge whether the command is resource-heavy —
   device simulators/emulators, local LLM inference, large native builds, or
   anything the repo's CLAUDE.md flags as memory-hungry. Heavy verification
   caps *concurrency*, not batch size (see Workflow step 3).
5. `gh auth status` must pass (draft PRs are created via gh).
6. **Ownership + PR-target check**: if the `origin` owner is not the
   authenticated user's own account (`gh api user`) or an owner the user has
   already confirmed in this session, ask before dispatching — this skill
   pushes branches and creates PRs. Then run
   `gh repo view --json isFork,parent,nameWithOwner`: if the repo is a fork,
   `gh pr create` defaults to targeting the PARENT repo — confirm the intended
   PR target with the user. Record the resolved target as `PR_REPO`
   (owner/repo) and pass it explicitly via `-R` in every `gh pr` call, so a
   fork can never silently open PRs against someone else's upstream.

## Workflow

1. **Parse the argument** into a task list:
   - Bullet list text → one task per bullet.
   - A file path → read it; one task per top-level bullet/heading.
   - `#N` issue numbers → `gh issue view N` on the current repo; the issue body
     is the task spec.
   - Empty → ask the user.
2. **Independence check**: if two tasks plausibly touch the same files, merge
   them into one task (same worktree) rather than risking conflicting PRs.
3. **Build the dispatch plan** — a table with one row per task:
   branch name (`dispatch/<slug>`, or the repo's documented branch convention),
   task summary, target files (best guess), model (per the global Plan &
   Delegate policy if installed; else: opus for hard logic, sonnet for
   well-specified work, haiku for mechanical edits), estimated size, and PR
   labels (issue-backed: carry the issue's labels; otherwise pick from
   `gh label list` — existing labels only, never create).
   Caps, stated in the plan:
   - **Batch**: max 5 tasks per dispatch (if more were given, propose the top 5
     and hold the rest for a second round).
   - **Concurrency**: all at once by default; if pre-flight judged verification
     heavy, propose running in waves (default wave size 2) so parallel test
     runs don't exhaust memory. The user can override either cap at approval.
4. **Plan critique** (cheap, high ROI — catches rework before 5 worktrees
   exist): run ONE `critic` subagent on the dispatch plan itself. Its axes:
   task independence (hidden file overlaps, hidden dependencies between
   tasks), spec completeness of each delegation prompt, verification-command
   fitness, model assignments. Model by batch stakes (haiku/sonnet for
   routine batches, opus for risky ones). Fold its findings into the plan
   table. If the batch touches auth / payment / migrations / deploy paths,
   also offer the user a full /risk-review of the plan before dispatching —
   but don't run it unasked.
5. **Gate — plan approval**: show the table plus the critic's findings and
   stop. Dispatch nothing until the user approves. This is the single
   approval for the whole batch.
6. **Mark issues in-progress** (issue-backed tasks only, right after approval):
   `gh issue edit <n> --add-assignee @me`, and if the repo has an
   in-progress-style label (`doing` / `in progress` / `wip` — check
   `gh label list`), add it. Never create new labels.
7. **Execute in parallel** (within the approved wave size): launch one
   `implementer` subagent per task in the background, each with worktree
   isolation and the chosen model. Every delegation prompt must be
   self-contained: task spec, target paths, repo conventions pointer
   (CLAUDE.md), the verification command from pre-flight, branch name, and
   these standing orders:
   - implement within ~800 changed lines (report and stop if it will exceed)
   - run the verification command; if it is red, STOP — do not commit, push,
     or open a PR; report the failure instead
   - commit (repo's commit-message conventions), push the branch
   - `gh pr create --draft -R <PR_REPO> --base <base branch> --assignee @me`
     (both from pre-flight — never rely on gh's default PR target) with the
     labels from the plan (`--label` per label) and a body that states what
     was verified; issue-backed tasks include `Closes #<n>` in the body
   - never touch the base branch, never force-push, never mark the PR ready
   - skip narration; final report = branch, PR URL, test result, deviations
8. **Review each completed task**: as each draft PR lands, review that
   branch's diff (`git fetch` + `git diff <base>...<branch>` from the main
   checkout). Choose the review mode dynamically — note that the /code-review
   and /risk-review *skills* operate on the current checkout, so inside
   dispatch their intent is reproduced with `critic` subagents instead:
   - **Implementation-heavy diff** → one `critic` with a correctness lens
     (/code-review equivalent): hunt real bugs — logic errors, edge cases,
     broken contracts, test gaps — and try to refute its own findings before
     reporting.
   - **Design / ops / docs-heavy or wide-blast-radius diff** (migrations,
     auth, payment, deploy/runbook) → one `critic` with pre-mortem risk axes
     (a lighter /risk-review equivalent).
   - **Diff spans both natures** → both lenses, as two parallel
     critics (this is the per-task maximum).
   Model chosen by the task's stakes. Classify the outcome per task:
   - **Clear** (no findings, or nits only): if this kit's pre-PR review gate
     hook (`pre-pr-review-gate.sh`) is installed, mark the branch as
     already-reviewed so the later ready-making step is not double-gated.
     Marker recipe (harmless no-op if the gate is not installed):
     ```bash
     ROOT=$(git rev-parse --show-toplevel)   # run from the MAIN checkout, not the worktree
     BRANCH=<the task branch from the plan table>
     KEY=$(printf '%s' "$ROOT:$BRANCH" | shasum | cut -d' ' -f1)
     mkdir -p "${TMPDIR:-/tmp}/claude-pr-review-gate" && touch "${TMPDIR:-/tmp}/claude-pr-review-gate/$KEY"
     ```
     Honesty note: the gate keys on the checkout root + current HEAD at
     ready time, so this pre-pass only takes effect when the later
     ready-making command runs from the main checkout WITH that branch
     checked out. In any other context (e.g. `gh pr ready <n>` while on the
     base branch) the gate may still fire once — that residual deny is
     safe: it re-arms, the retry passes.
   - **Needs work** (real findings): do NOT touch the marker (the gate stays
     armed so a post-fix review is still forced); list the findings in the
     report. No auto-fix — fixes go through a follow-up session on that
     branch.
9. **Collect and report**: as subagents finish, assemble the result table —
   task / branch / PR URL / verification result / review verdict / deviations.
   Failed tasks get one retry with the failure context — but make the retry
   idempotent: first check what already exists (`git ls-remote` for the
   branch, `gh pr list --head <branch>` for a PR) and instruct the retry to
   RESUME from there (fix and push to the existing branch / reuse the
   existing PR), never to recreate from scratch. After the one retry, report
   and leave the task to the user.
10. **Teardown**: list leftover worktrees (`git worktree list`) and state the
    cleanup contract in the final report — worktrees for open draft PRs are
    kept (the review-fix session needs them); worktrees for failed/abandoned
    tasks should be removed (`git worktree remove <path>`, plus deleting the
    branch if nothing was pushed). Never leave leftovers unreported.
    End with the hand-off note: ready-making is the human's call (clear tasks
    have pre-passed the review gate; needs-work tasks re-arm the gate after
    fixes), and later CI failures or review comments are follow-up sessions,
    not this skill's loop.

## Constraints

- Draft PRs only. Marking PRs ready / merge / comment reply are out of scope for this skill.
- GitHub metadata: assignee is always `@me`; use existing repo labels only —
  never create labels, never assign other users.
- Token guard: hard limits — 5 tasks per dispatch, one plan critic per
  dispatch, at most two critics per task diff (2 only when using both lenses,
  otherwise 1), one retry per failed task. Do not loop. If the batch needs
  more depth, tell the user to run /dispatch again.
