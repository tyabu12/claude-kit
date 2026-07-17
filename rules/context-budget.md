# Context Budget — Always-Loaded Files

Part of claude-kit and the **canonical source** of this rule. Applies to itself. Pairs with
`knowledge-layering.md` (which tier knowledge belongs in); this rule governs content discipline
*within* always-loaded files.

> Concept level — no volatile facts to keep numerically in sync. Consumer projects may keep
> project-scoped copies and should reconcile **from** here (one-way: kit → consumers; a consumer
> copy must never become the source).

## Scope

Always-loaded files — read into every agent session, so every line is paid on every turn:

- `~/.claude/CLAUDE.md` and `~/.claude/rules/*.md` **without** `paths:` frontmatter (global)
- a project's top-level `CLAUDE.md` and its `.claude/rules/*.md` without `paths:`
- `~/.claude/agents/*.md` and project `.claude/agents/*.md`

Path-scoped files (`paths:` frontmatter) load only on matching edits — the budget is looser there.

## Principle

Each addition must support the agent's **next decision**, not serve as reference material for a
human debugging later. Reference material belongs on-demand: `docs/**`, script header
doc-comments, PR/issue history.

## Classifier

Before adding, classify each paragraph:

- **Keep**: lead claim + the actionable command / path + a one-line pointer to the deeper doc.
- **Drop or relocate**: enumerated lists findable via `grep`, benchmarks, multi-paragraph
  rationale, rare-event walkthroughs, anecdotal incident detail, historical PR references,
  repeated file paths.

If a cheat-sheet entry balloons to ~3× its neighbors — or would still fire correctly with just
lead claim + command + pointer — compact it.

## `(#NNN)` / issue attribution

- **Drop**: bare parentheticals tagging *which* PR/issue introduced something.
- **Keep**: pointers directing the next reader *where to find missing context* (`see #N for the
  design discussion`, `ADR-007`).
- Existing inline `(#NNN)` is not precedent — apply the rule to the new addition and sweep cheap
  neighboring violations.
