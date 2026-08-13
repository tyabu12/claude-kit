# Knowledge Layering & Promotion

Part of claude-kit and the **canonical source** of this rule. Pairs with `context-budget.md`
(content discipline *within* a file); this rule covers **which tier** a piece of knowledge belongs
in, and how to move it up.

> **Kit-canonical; the depth behind § "Verify before you lock it" lives in
> `~/.claude/kit-docs/claim-verification.md`.** Reconcile a consumer mirror against **rule + doc as
> a pair**, one-way (kit → consumer); a consumer copy must never become the source.

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

Trigger triage on memory **count** or **total content size** (`cat memory/*.md | wc -c`), never the
built-in MEMORY.md *index*-size warning — index lines are one-liners, so it fires far too late.
Fold a promotion into a session already touching a rules file rather than opening a separate change,
and use the pass to diff each rule here against any consumer copies you maintain.

A pass **removes** as well as promotes — memory is not a durable store. Run the quick test first, so
one memory can be promoted *and* then retired the same round: delete a fully-SHIPPED `project_*`
tracker outright, trim a mixed one to its open-tracking stub, and prefer deletion when unsure.

Two steps nothing else enforces: update **every mirror** of a promoted fact in the same change, and
delete the source memory only **after** the rule lands — a repo PR cannot enforce a per-machine
deletion, so it belongs on a checklist. Dispositions, commands and the approval flow: the
`promote-memories` skill.

## Anti-pattern: memory refs in repo-tracked files

Per-user memory is **per-machine**. A reference of the form `` memory `<name>.md` `` inside a
**repo-tracked** file (a project's `CLAUDE.md`, an ADR, a source comment) is a **dead link** for
every other contributor and every other machine.

**This is also why a repo-tracked rule must stay self-contained** — do not slim a project's
`.claude/rules/` down to "see the maintainer's global rule": that global file does not exist for
other contributors or in CI. Global rules *add* a personal baseline; they never *replace* what a
shared repo needs to carry itself.

**Apply**: for rationale in a repo-tracked file, use an inline summary + a durable pointer
(`#N`, `ADR-NNN`). Memory refs are fine only in never-committed places (`~/.claude/CLAUDE.md`,
this file, conversational scratch).

**Detect** — new code must not *add* hits (the *reframe* disposition below, not a "must return 0").
Enumerate with `git ls-files`, never a recursive grep: that walk silently skips dot-dirs and
tracked-but-ignored files.

```sh
git ls-files -z --cached --others --exclude-standard \
  | xargs -0 grep -nHE 'memory `[a-z_]+\.md`'
```

## Verify before you lock it

One discipline, three moments where a claim becomes load-bearing and nobody downstream will check
it — a reviewer checks a rule's *content*, not the check it prescribes; a plan critique tests
internal consistency, not external truth:

- **Rule-commit** — an **executable assertion** (an asserted grep count, a cited `file:line`, a
  `(#N)`, a cross-doc heading anchor, a self-quoted byte/line delta) is run against current state
  before commit, and re-measured on the *final* commit. Sweep the violation, reframe the assertion,
  or name an explicit carve-out — never leave it.
- **Plan-lock** — verify every load-bearing claim against its authoritative source *before* the
  plan locks; a false one otherwise surfaces at code-review or in production.
- **Authoring** — a why-comment, guard, count, or gap list *you write* asserts behaviour that
  nobody executes. Delete the mechanism and see whether the tests notice; construct what a guard
  claims to catch and confirm it fires, since only a negative control proves anything. Two that get
  missed: when you fix an authored claim, **grep what cited it** — a count or classification built
  on it may now be false, and nothing points back at it; and a **gap list**, with the remedy you
  prescribe for it, inherits the blind spot of whatever it was drawn from.

When a check is too expensive to run, say the cause was not isolated. A reader can act on an
acknowledged gap; a wrong cause they can only inherit.

**A rules file created mid-session never injects in that session** — however correct its `paths:`,
a working glob and a broken one look identical there (both absent). Verify a new or re-scoped rule
from fresh subagent probes, one `Read` each, with a **positive** control (probes and mechanism:
`~/.claude/kit-docs/code-review-path-scoped-rules.md`).

Worked examples, which source settles which kind of claim, and how a *green* probe gets misread:
`~/.claude/kit-docs/claim-verification.md`.
