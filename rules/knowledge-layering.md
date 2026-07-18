# Knowledge Layering & Promotion

Part of claude-kit and the **canonical source** of this rule. Pairs with `context-budget.md`
(content discipline *within* a file); this rule covers **which tier** a piece of knowledge belongs
in, and how to move it up.

> Consumer projects may keep project-scoped copies of this file and should reconcile **from** here
> (one-way: kit → consumers; a consumer copy must never become the source).

## Where knowledge belongs

Choose by **who needs to read it** and **how stable it is**:

| Tier | Audience | Edit cycle |
|---|---|---|
| Per-user memory (`~/.claude/.../memory/`) | This user, this machine | Per-session, Claude-writable |
| Global `~/.claude/CLAUDE.md` + `~/.claude/rules/` | This user, every project on this machine | Hand-edited in dotfiles, versioned |
| Project `CLAUDE.md` + `.claude/rules/` | All contributors, per-project | PR-reviewed, checked into the repo |
| Project `docs/**` | All contributors, on-demand | PR-reviewed |

**Quick test before saving a memory:** *"Would a new contributor with no prior context reliably
re-derive this from the code / docs / tooling?"*

- **Yes** → memory (rapid capture only — it's derivable on demand).
- **No** → a rules file. Then pick the tier by audience: a lesson true across *all my projects*
  (a tool's quirk, a personal workflow rule) → global `~/.claude/rules/`; a lesson specific to
  *one project* → that project's `.claude/rules/` (path-scoped if domain-specific).

**User-preference carve-out**: feedback flavored as personal preference stays in memory
regardless of how generic it is — it is `user_*`-flavored, not a derivable fact.

## Promotion & retirement

Triggers, by fire-rate reliability:

1. **Periodic triage** (most reliable) — trigger on memory **count** or **total content size**
   (`cat memory/*.md | wc -c`), NOT the built-in MEMORY.md *index*-size warning: index lines are
   one-liners, so it fires far too late to rely on. Or every few months. Size-rank memories; the
   largest are promotion candidates, SHIPPED trackers are retire candidates. Also diff each rule
   here against any consumer-project copies you maintain, as a backstop for a missed mirror update
   (the volatile facts in `subagent-usage.md` are the ones that matter).
2. **Rule-aware bundling** — if the current session already touches a rules file, fold a related
   promotion into the same change rather than opening a separate one.
3. **At save time** (best-effort) — for a new `feedback_*` save, apply the quick test; if it
   routes to rules, prefer creating the rule alongside. Memory is the rapid-capture form; the
   rule is the durable form.

### Retire, don't only promote

A triage pass also *removes* memory — memory is not a durable store. A `project_*` tracker whose
work has fully SHIPPED (no open items, outcome now derivable from code/git/docs) is **DELETED**; a
mixed shipped+open one is **TRIMMED** to its open-tracking stub (both memory-direct — no PR).
Promotion and retirement compose: run the quick test **first** to promote any durable lesson, then
delete/trim the residue — a memory can be promoted *and* deleted the same round. **Prefer
deletion**: memory holds only watch-list / 様子見 / genuinely-ephemeral items, so when promoting
*or* when tracked work completes, actively check whether the memory can go rather than keeping it.

### Procedure

1. Draft the addition at concept level (invariant + why + pointer), routed through
   `context-budget.md`'s classifier if the target is always-loaded.
2. Strip per-user provenance (`Source memory: …` lines) before committing a repo-tracked file.
3. If the content is mirrored elsewhere (an agent's cheat sheet, a CLAUDE.md parenthetical),
   update every mirror in the same change — mirrors drift silently otherwise.
4. Only after the rule lands, delete the source memory (a repo PR can't enforce a per-machine
   memory deletion — track it on a checklist).

## Anti-pattern: memory refs in repo-tracked files

Per-user memory is **per-machine**. A reference of the form `` memory `foo.md` `` inside a
**repo-tracked** file (a project's `CLAUDE.md`, an ADR, a source comment) is a **dead link** for
every other contributor and every other machine.

**This is also why a repo-tracked rule must stay self-contained** — do not slim a project's
`.claude/rules/` down to "see the maintainer's global rule": that global file does not exist for
other contributors or in CI. Global rules *add* a personal baseline; they never *replace* what a
shared repo needs to carry itself.

**Apply**: for rationale in a repo-tracked file, use an inline summary + a durable pointer
(`#N`, `ADR-NNN`). Memory refs are fine only in never-committed places (`~/.claude/CLAUDE.md`,
this file, conversational scratch).

## Rule-writing self-check

When a rule includes an **executable assertion** — a grep with an asserted hit count, a cited
`file:line`, a `(#N)` claim, a cross-doc heading anchor — run it against current state **before
commit**. The writer is the only one who reliably does; reviewers check the rule's *content*, not
the *check it prescribes*. Reconcile any divergence by sweeping the violation, reframing the
assertion to match reality, or enumerating an explicit carve-out.

The same "verify before you lock it" discipline extends past rule assertions to **any load-bearing
claim a plan leans on**, checked **before plan-lock**: a plan critique checks internal consistency,
not external truth, so an externally-false-but-plausible claim passes it and surfaces only at
code-review or in production — the author is the one positioned to check. Verify each against its
authoritative source:

| Claim a plan leans on | Verify by |
|---|---|
| A doc/header comment asserting cross-file structure | grep the actual symbol/type — comments can be aspirational |
| A `§"Heading"` cross-doc reference | grep the target for the exact heading **and read under it**; add one if absent |
| "band-aid / dead-code" framing of a change | grep ALL producers + consumers across layers, not just the one the change scopes |
| A documented defect framed as **live** ("X `would` flow into Y") | grep every **writer** of the value, not just the reader — an upstream guard may already make it unreachable, in which case the comment is that guard's rationale, not a bug report. Subjunctive mood is the tell |
| An external standard (RFC, SEO, HTTP, OAuth) | WebSearch + WebFetch the authority; verbatim-cite before locking the plan |
| Vendor feature availability (free/paid tier) | WebFetch the canonical docs; verbatim-quote the "who can use this" box — never infer from search snippets |

### Claims you author are assertions too

The table covers claims you *lean on*. A **why-comment you write** is the same kind of claim —
it asserts runtime or library behaviour as the reason a mechanism exists — but it is authored at
implementation time and executed by nobody. Reviewers check whether the *code* is correct, not
whether the *stated reason* is true, so a false one ships and the next reader inherits it as fact.
Two shapes, neither expressible as a `Verify by` lookup:

- **Why-comment on a mechanism** → delete the mechanism and run the tests. Green means the claim
  is false, or the tests never covered it.
- **A detector / guard / gate** → construct the thing it claims to catch and confirm it fires. A
  guard's success case proves nothing; only a negative control does. Scope it to the claim it
  defends: a check narrower than that claim (a files-only loop behind a files-and-directories
  completeness claim), or one that silently skips its exemptions instead of declaring them,
  passes by construction.

When a check is too expensive to run, say the cause was not isolated. A reader can act on an
acknowledged gap; a wrong cause they can only inherit.
