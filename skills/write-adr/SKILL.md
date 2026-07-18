---
name: write-adr
description: Draft a new Architecture Decision Record into the repo's ADR directory (new files only — not for amending an existing ADR). Use when asked to write an ADR, record an architecture decision, or document a design trade-off.
allowed-tools: Read, Grep, Glob, Write, Edit, Agent
argument-hint: "<title>"
---

# /write-adr

Draft an Architecture Decision Record for: `$ARGUMENTS`

Project-agnostic: the repo's **existing ADRs are the format spec**. This skill discovers them
rather than imposing a house style, so a repo that says `## Trade-offs` where another says
`## Consequences` keeps its own convention with no configuration.

**Scope: new ADRs only.** Amending an existing ADR is ordinary editing — the numbering, template
discovery, and review loop here all assume a file that does not exist yet. If the user wants a
change to an already-written ADR, edit it directly instead of invoking this.

A project with its own `write-adr` skill shadows this one (project scope wins) — expected, and
there is no obligation to keep the two in sync.

## Step 1 — Discover

1. **ADR directory**: glob for a directory containing `ADR-*.md` / `adr-*.md` — try
   `docs/decisions/`, `docs/adr/`, `doc/adr/`, `docs/architecture/decisions/`. A bare
   `NNN-*.md` naming also counts, but only if the directory *also* looks like a decision log (an
   `INDEX.md` of decisions, or files whose headings read as decisions) — a numeric-prefix glob
   alone matches ordinary numbered docs (`001-getting-started.md`) and would drop an ADR into an
   unrelated series. If several directories match, ask. **If none exists**, ask the user where to
   write and use the skeleton in Step 2.
2. **The numbering scheme, then the main sequence.** First decide what the numbers *are*: a flat
   monotonic counter (`ADR-007`), or date/year-encoded (`ADR-2026-01`, `ADR-20260718`). Everything
   below assumes flat — **if the scheme is date-encoded, do not apply any gap heuristic**; derive
   the next id from the scheme itself (today's date) and pick the template by recency.

   For a flat scheme, list the numbers and look for outliers **before** doing arithmetic on them.
   Repos park entries at sentinel numbers (`ADR-9999`, `ADR-0000`) for deliberately-unnumbered
   decisions; naive `max + 1` on `ADR-001..027` **plus** `ADR-9999` yields `ADR-10000` and corrupts
   the sequence permanently. A gap of ≥ 50 above the contiguous run is a **candidate** sentinel, not
   a verdict — the gap alone cannot tell a parked entry from a reserved subsystem block (100–199) or
   a renumbered history. So: **when any candidate is found, state your reading and ask the user to
   confirm before writing.** Corroborate with the file's content — a sentinel usually reads as a
   deliberately-unnumbered decision, not as the sequence's next entry.
3. **Template ADR**: the highest-numbered ADR **in the main sequence** (confirmed sentinels
   excluded). Read it in full — section names, ordering, status/date header shape, and numbering
   width (`ADR-007` vs `0007`) are the spec for the new file. Note its path as `TEMPLATE_PATH`.
   **Highest is not always most representative**: if that ADR is visibly atypical (many more
   sections than its neighbours, one-off headings like "Dead code removed in passing"), say so and
   take the common structure across the two or three most recent instead — do not propagate a
   bespoke document's shape into every future ADR.
4. **Next number**: main-sequence max + 1, in the template's zero-padding and filename shape.
   Then **check for reservations before claiming it**: an ADR index, `CLAUDE.md`, or a
   `CONTRIBUTING` section may record a number as *reserved / not yet written* with no file on disk,
   which a file listing cannot see. Grep the repo for the candidate number and for
   `reserved|not yet written` near ADR references; if the number is spoken for, take the next free
   one and report the skip.
5. **Project ADR rule file** (optional): look for `.claude/rules/adr*.md` or a `CONTRIBUTING`
   section on ADRs. If found, read it and note its path as `ADR_RULES_PATH` — it takes precedence
   over anything inferred from the template.
6. **Context**: read `CLAUDE.md` if present. If the repo has a roadmap/phase doc and the decision is
   phase-scoped, read only the relevant section.

Report the resolved directory, next number, template, and any sentinel or reserved number skipped,
before writing. **Immediately before `Write`, confirm the target path does not already exist**
(re-glob if Step 1 and Step 2 are not contiguous in the same turn — two `/write-adr` runs in
parallel would otherwise compute the same number). If it exists, stop and report rather than
writing.

## Step 2 — Draft

**Apply `ADR_RULES_PATH` here, at draft time — not only at review time.** Its standards (typically:
verify each fact-claim you cite as you write it; prefer a mechanism contract over a pinned
threshold) are cheap to honour while drafting and expensive to retrofit once Step 3 finds them
violated.

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
  rationale self-contained? Are the consequences honest about costs, not only benefits? Is anything
  load-bearing left implicit?

  Do **not** bake house opinions into this prompt (for instance, that a pinned numeric acceptance
  threshold should be restated as a mechanism contract). That is a real standard in some repos and
  wrong in others, and asserting it here would make a project-agnostic skill emit false-positive
  review noise. Such opinions reach the reviewers through `ADR_RULES_PATH`, which is exactly what
  that pass-through is for.

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
