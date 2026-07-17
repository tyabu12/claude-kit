---
name: promote-memories
description: Triage per-user memory — promote durable entries into a rules file (global ~/.claude/rules/ or a project's .claude/rules/) AND retire (delete/trim) SHIPPED trackers — select candidates, classify, draft at concept level, self-check, and hand off to the project's PR workflow for any promotion.
allowed-tools: Read, Grep, Glob, Bash, Write, Edit, Agent
argument-hint: "[focus cluster | (empty for full triage)]"
---

# /promote-memories

Run a memory triage round — **promote** durable lessons to rules and **retire** (delete/trim)
SHIPPED trackers. The canonical procedure lives in this kit's `rules/knowledge-layering.md`
(§ Where knowledge belongs, § Promotion & retirement, § Rule-writing self-check) — installed as
`~/.claude/rules/knowledge-layering.md`; if present, read it first and let it win where the two
disagree. If absent, the operational steps below stand alone.

Typical trigger: memory count or total content size (see knowledge-layering § Promotion &
retirement), or a user-requested periodic triage. `$ARGUMENTS` may name a focus cluster to skip
the full triage.

## Step 1: Triage

1. Size-rank the memory files for the active workspace:
   ```bash
   ls -S ~/.claude/projects/<workspace>/memory/*.md | xargs wc -c | sort -rn | head -25
   ```
2. For each candidate, apply knowledge-layering.md's quick test ("would a new contributor
   re-derive this?") and the `user_*` carve-out (personal-preference feedback stays in memory).
3. **Classify each into a disposition** — run the promotion quick-test *first*, so one memory can
   be both promoted and then retired:
   - **PROMOTE** — durable, non-derivable lesson → extract to rules (Steps 2-4).
   - **DELETE** — a `project_*` tracker whose work has fully SHIPPED (no open items, outcome now
     derivable) → retire the file; extract any durable lesson via PROMOTE first, then delete.
   - **TRIM** — shipped bulk plus a few live items → rewrite to the open-tracking stub.
   - **KEEP** — active tracking with open work → leave as-is.
4. For **PROMOTE** candidates: cluster by target file and **pick the tier per candidate** — a
   cross-project lesson → global `~/.claude/rules/`; a single-project lesson → that project's
   `.claude/rules/` (path-scoped if domain-specific). Additions to always-loaded files route
   through `context-budget.md`'s classifier first. **Grep the target before drafting** — promote
   only the delta; defer clusters whose target file does not exist yet.
5. Present the disposition slate to the user (PROMOTE / DELETE / TRIM / KEEP, with reasons; defer
   where relevant). Wait for approval. Then: **PROMOTE** → Steps 2-4; **DELETE / TRIM** → operate
   on memory directly (no PR; on DELETE, prune the file's MEMORY.md index line and fix any
   `[[wikilink]]` that pointed to it).

## Step 2: Draft

- **Concept register** — compress the narrative, keep the invariant and a pointer. But PRESERVE
  non-derivable negative claims: anti-pattern / "wrong fixes" lists, "don't do X" caveats — those
  are usually the entire value of the memory.
- Strip per-user provenance and memory references (knowledge-layering.md § Anti-pattern) from any
  repo-tracked target. A repo-tracked rule must stay self-contained — never point it at the
  maintainer's per-machine global rule.
- Update every mirror of the content in the same change.

## Step 3: Self-check (before handing off)

Execute every load-bearing assertion in the drafts against **current state**, not the memory's
snapshot: run every grep / path / line-anchor; `gh pr view N` for every `(#N)` cite. Reframe the
draft to match what you observe — memories age (files move, IDs get renamed, spike facts never
landed).

## Step 4: Land the change

Hand the approved drafts to the project's implementation workflow: if the project defines a PR
orchestration entry point (e.g. `/orchestrate`), use it; a global-rules change under
`~/.claude/rules/` goes through whatever repo provides those rules (for example this kit, or a
personal dotfiles repo) via that repo's normal PR/commit flow. This skill does not commit on its
own.

## Step 5: Post-merge local cleanup (operator checklist)

Gate on the change actually landing, then **print** (never auto-run) this checklist:

1. One `command rm` line per promoted memory file (`command rm` because an interactive `rm`
   aliased to `rm -i` silently no-ops non-interactively). Show for confirmation first.
2. Shorten remaining over-long MEMORY.md index lines — this relieves the built-in *index*-size
   warning (which fires too late to rely on); the primary triage triggers are count + content-size,
   which retirement (DELETE / TRIM) addresses directly.
3. Re-check the triage triggers (count / content-size); if still over, queue the next round from
   the deferred clusters.
