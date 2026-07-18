---
name: write-adr
description: Draft an Architecture Decision Record into the repo's existing ADR directory, matching that repo's own ADR format, then verify it with a two-reviewer loop. Use when the user asks to write an ADR, record a decision, or document an architecture trade-off.
allowed-tools: Read, Grep, Glob, Write, Edit, Agent
argument-hint: "<title>"
---

# /write-adr

Draft an Architecture Decision Record for: `$ARGUMENTS`

Project-agnostic: the repo's **existing ADRs are the format spec**. This skill discovers them
rather than imposing a house style, so a repo that says `## Trade-offs` where another says
`## Consequences` keeps its own convention with no configuration.

A project with its own `write-adr` skill shadows this one (project scope wins) — expected, and
there is no obligation to keep the two in sync.

## Step 1 — Discover

1. **ADR directory**: glob for a directory containing `ADR-*.md` / `adr-*.md` / `[0-9][0-9][0-9]*.md`
   — try `docs/decisions/`, `docs/adr/`, `doc/adr/`, `docs/architecture/decisions/`. If several
   match, ask. **If none exists**, ask the user where to write and use the skeleton in Step 2.
2. **Template ADR**: the **highest-numbered existing ADR** in that directory. Read it in full — its
   section names, ordering, status/date header shape, and numbering width (`ADR-007` vs `0007`) are
   the spec for the new file. Note its path as `TEMPLATE_PATH`.
3. **Next number**: highest existing number + 1, in the template's zero-padding and filename shape.
4. **Project ADR rule file** (optional): look for `.claude/rules/adr*.md` or a `CONTRIBUTING`
   section on ADRs. If found, read it and note its path as `ADR_RULES_PATH` — it takes precedence
   over anything inferred from the template.
5. **Context**: read `CLAUDE.md` if present. If the repo has a roadmap/phase doc and the decision is
   phase-scoped, read only the relevant section.

Report the resolved directory, next number, and template before writing.

## Step 2 — Draft

Write the new ADR following `TEMPLATE_PATH`'s structure. Keep it concise and LLM-friendly: explicit
sections, rationale stated rather than implied.

If no template exists, use this skeleton:

```markdown
# ADR-NNN: <Title>

> **Status:** Accepted
> **Date:** YYYY-MM-DD
> **Context:** One-line summary of why this decision is needed.

## Context
What is the issue motivating this decision?

## Options
| Option | Pros | Cons |
|--------|------|------|
| **A** | … | … |

## Decision
What is the change being proposed / done?

## Rationale
Why this option over the alternatives?

## Consequences
What becomes easier or more difficult?
```

**Options table**: include it when real alternatives were considered, with the reason each was
rejected. Omit it for a decision with no meaningful alternative — an Options table padded with
strawmen is worse than none.

Get today's date from `date +%F`, never from memory.

## Step 3 — Review loop

Launch **two subagents in parallel**, read-only (they must not modify files). Each prompt MUST embed
the resolved paths. **Why this is not optional:** a subagent inherits none of this session's
context, and a path-scoped `.claude/rules/*.md` (one with `paths:` frontmatter) does **not**
auto-load for it — those load on a matching *edit*, and a review only reads. Passing the paths
explicitly is therefore the entire mechanism by which project ADR standards reach the reviewers;
omit it and the standards vanish with no error. (Depth, if this kit is installed via symlink rather
than as a plugin: `docs/code-review-path-scoped-rules.md`.)

Each prompt carries: the new ADR's path, `TEMPLATE_PATH`, `ADR_RULES_PATH` if found (with "read it
first and apply it"), and "return findings only — no edits, no file dumps".

- **Reviewer A — Accuracy.** Verify every cited `file:line`, rule section, doc reference, and
  external/SDK assertion actually says what the ADR claims. Confirm the Options table lists the
  alternatives that were genuinely considered, each with a stated reason for rejection. Confirm the
  filename and numbering match the directory's convention.
- **Reviewer B — Clarity.** Read as a future maintainer with no memory of the discussion: is the
  rationale self-contained? Are the consequences honest about costs, not only benefits? Flag any
  acceptance criterion pinned to a brittle threshold (e.g. `≥ N% on model X`) that would be better
  stated as a mechanism contract — a pinned number silently expires.

**Model choice**: Reviewer A is largely mechanical verification — a cheaper tier is appropriate.
Reviewer B is a judgment read — keep it on the session model or better. Both are far inside the
subagent output cap (hard, non-configurable: Opus 32K / Sonnet 64K / Haiku 8192 output tokens) for a
single document; no scope split is needed here. Depth if installed via symlink:
`rules/subagent-usage.md`.

## Step 4 — Converge

1. Revise the ADR for the findings, then re-run the reviewers on the revision.
2. Repeat until no new findings. **Hard limit: 3 iterations** — stop at 3 even if findings remain.
3. Report: the final ADR path, the iteration count, and any findings left **unresolved**. Do not
   silently drop them; an unresolved finding is a result, not a failure to hide.
