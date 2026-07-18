---
name: skill-retro
description: "Monthly evidence-driven retrospective of this kit's skills. Gathers evidence — friction logs from ~/.claude/skill-feedback/, skill-invocation traces from session transcripts, outcome data from dispatch-created PRs, and official-docs drift — then proposes SKILL.md fixes ONLY where evidence exists, delivered as a draft PR to the claude-kit repo. No evidence → no change. Reviews itself too (dogfooding). Designed to run monthly, manually or as a scheduled routine, via /skill-retro."
argument-hint: "(none — runs one monthly retro pass)"
disable-model-invocation: true
---

# /skill-retro

One evidence-driven retro pass over this kit's skills. The core rule:
**no evidence, no change** — skills are never rewritten on calendar cadence or
taste; every proposed edit must cite a concrete friction, outcome, or docs
drift. This skill is itself in scope (dogfooding).

Respond in the user's conversation language. Skip narration between tool
calls — this may run unattended as a scheduled routine.

## 1. Enumerate scope

Skills = directories with a `SKILL.md` in the claude-kit checkout's `skills/`.
Locate the checkout: if `~/.claude/skills` is a symlink (the kit's symlink
install), follow it to the repo root; otherwise ask the user where the
claude-kit checkout lives. If no writable checkout exists (plugin-only
install), still run the evaluation and report the verdicts — skip only the
PR delivery step. Also note the always-loaded rules skills
rely on (the kit's `rules/*.md`, and the user's global CLAUDE.md sections such
as Plan & Delegate / Skill Feedback Capture) — the thing that needs fixing may
be a rule, not a skill.

## 2. Gather evidence (cheap first, expensive only if warranted)

1. **Friction logs** — read `~/.claude/skill-feedback/*.md`. This is the
   primary signal (self-reported deviations, user corrections, uncovered
   judgment calls).
2. **Invocation traces** — mine `~/.claude/projects/*/` session logs for the
   last month: count invocations per skill (search for skill names /
   `<command-name>` markers). For skills with hits, sample at most **10
   excerpts total** across all skills, preferring sessions where the user's
   next message after skill output looks corrective. Do not read whole
   transcripts.
3. **Outcome data** (only if /dispatch was used this month) — for open or
   recently merged PRs on `dispatch/*` branches (`gh pr list --search`), note
   CI failures and review-comment counts: a high rate means dispatch's
   verification or review stage is leaking defects.
4. **Docs drift** — ONLY for skills that had activity or friction this month:
   collect their load-bearing assumptions about Claude Code behavior (e.g.
   skill invocation rules, worktree isolation semantics, hook events,
   permission rule syntax, subagent output caps) and verify them in ONE
   batched check against current official docs — via a `claude-code-guide`
   subagent if that agent type is available, else one WebFetch pass over the
   relevant docs pages.

**Early exit:** if friction logs are empty AND invocation traces show no
corrective signals AND outcomes are clean, print one line
(e.g. `🔁 no evidence this month — no skill changes (N skills, M invocations)`)
and stop. Skip the docs-drift check entirely in that case.

## 3. Synthesize per-skill verdicts

For each skill: **no change** (state why in ≤1 line) or **proposed fix** —
each proposed edit paired with its evidence (feedback line, transcript
excerpt, outcome stat, or docs citation). Distinguish:
- fix the skill (instructions unclear / wrong assumption)
- fix a kit rule or the user's global rule instead (friction shared across
  skills) — kit rules go in the same PR; global-CLAUDE.md fixes are reported
  as recommendations (they live in the user's dotfiles, outside this repo)
- retire/merge (skill unused for 2+ retros and duplicated elsewhere — propose,
  never delete unilaterally)

## 4. Deliver as a draft PR to claude-kit

If there are proposed edits:

1. In the kit checkout: branch `skill-retro/YYYY-MM` from the default branch
   (never commit to main directly).
2. Apply the SKILL.md / rules edits, keeping README.md's Contents list in
   sync.
3. Run `./scripts/scrub-check.sh` — it must PASS before pushing (per-user
   evidence must not leak into the shared repo: cite dates and session
   projects, not absolute personal paths or transcript contents).
4. Commit (repo conventions), push, `gh pr create --draft --assignee @me`.
   PR body: one section per skill — **evidence → change** pairs, so the human
   can judge each edit independently.
5. Archive consumed feedback lines: move them from
   `~/.claude/skill-feedback/<skill>.md` into
   `~/.claude/skill-feedback/archive/YYYY-MM.md` so next month's retro starts
   clean. Leave unaddressed lines in place.

Final report: verdict table (skill / evidence / verdict) + PR URL if created.

## Constraints

- Never edit skills in place on main — all changes go through the draft PR.
- Token guard: one pass, at most one docs-drift check (one subagent call or
  one WebFetch batch), at most 10 transcript excerpts. Do not loop or
  re-verify.
- Evidence citations in the PR must be specific (dated feedback line, session
  date, PR number, doc URL) — no "feels outdated".
