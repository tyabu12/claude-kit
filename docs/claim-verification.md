# Claim verification — which source settles which claim

Depth behind `rules/knowledge-layering.md` § "Verify before you lock it", which carries the
discipline and the three moments it fires at; this doc carries the per-shape checks. Nothing here is
version-dependent, so it has no re-measurement trigger — it accretes as new failure shapes are met.

The organising fact: **a claim is checked by whoever authors it, or by nobody.** A reviewer checks
whether the code is correct and whether a rule's content is sensible — not whether the check a rule
prescribes actually passes, and not whether the stated reason for a mechanism is true. So a false
claim ships intact and the next reader inherits it as fact.

## Claims you lean on

Verify each against its authoritative source *before* the plan locks. A plan critique tests internal
consistency, so an externally-false-but-plausible claim passes review and surfaces only in
production.

| Claim a plan leans on | Verify by |
|---|---|
| A doc/header comment asserting cross-file structure | grep the actual symbol/type — comments can be aspirational |
| A `§"Heading"` cross-doc reference | grep the target for the exact heading **and read under it**; add one if absent |
| "band-aid / dead-code" framing of a change | grep ALL producers + consumers across layers, not just the one the change scopes |
| A documented defect framed as **live** ("X `would` flow into Y") | grep every **writer** of the value, not just the reader — an upstream guard may already make it unreachable, in which case the comment is that guard's rationale, not a bug report. Subjunctive mood is the tell |
| An external standard (RFC, SEO, HTTP, OAuth) | WebSearch + WebFetch the authority; verbatim-cite before locking the plan |
| Vendor feature availability (free/paid tier) | WebFetch the canonical docs; verbatim-quote the "who can use this" box — never infer from search snippets |
| A subagent's verdict on an external platform fact (SDK annotation, threading contract, API availability) | Re-derive it yourself — a verdict that *dismisses* a risk ends inquiry and is the expensive one to get wrong. Then run the prescribed check against a **known-positive control**: one that cannot redden is measuring nothing |

## Claims you author

A **why-comment you write** is the same kind of claim — it asserts runtime or library behaviour as
the reason a mechanism exists — but it is authored at implementation *or review-fix* time and
executed by nobody. Four shapes, none expressible as a `Verify by` lookup:

- **Why-comment on a mechanism** → delete the mechanism and run the tests. Green means the claim
  is false, or the tests never covered it.
- **A detector / guard / gate** → construct the thing it claims to catch and confirm it fires. A
  guard's success case proves nothing; only a negative control does. Scope it to the claim it
  defends: a check narrower than that claim (a files-only loop behind a files-and-directories
  completeness claim), or one that silently skips its exemptions instead of declaring them,
  passes by construction. And a control whose fixture a **sibling arm** can also reach reddens for
  the wrong reason — read *which* message fired, not the exit code, and re-key the fixture until
  only the guard can reach it.
- **A classification or count built on an earlier claim** → when you fix that claim, grep what
  cited it. Fixing one authored claim can *invalidate* another you authored earlier, and nothing
  points back at it; a concessive clause propping up a category ("it belongs here, just
  differently") is the tell that it already broke.
- **A gap list — and the remedy you prescribe for it** → each is an enumeration, inheriting the
  blind spot of whatever it was drawn from. A residue record drawn from the section naming one
  *kind* of gap cannot see the other kinds, and "re-run §X" is unpayable when §X never listed half
  the items. Re-derive from what changed, then check the remedy actually reaches it. Two sets
  written in sequence also read as a **partition** — state the overlap, or the reader does the
  arithmetic wrong, in the direction that understates residue.

## Reading a probe's outcome

**It gets misread in both directions.** Assert that the mutation's anchor matched — a `replace` that
silently no-ops leaves the original behaviour and reads as verified. And treat a probe that stays
**green** as a finding about the *fixtures*, not a redundant guard: a suite only reddens on states
its fixtures build, so name the state the guard defends and confirm something constructs it before
concluding anything.

When a check is too expensive to run, say the cause was not isolated. A reader can act on an
acknowledged gap; a wrong cause they can only inherit.

## The rule-assertion case

A rule file is where authored claims concentrate, because a rule *is* a set of assertions about the
repo. The shapes that need running against current state before commit: a grep with an asserted hit
count, a cited `file:line`, a `(#N)` attribution, a cross-doc heading anchor, and a self-quoted
byte/line delta — the last re-measured on the **final** commit, since review fixes move it.

Reconcile a divergence one of three ways: sweep the violation so the assertion becomes true, reframe
the assertion to match reality, or enumerate an explicit carve-out. Silently leaving the assertion
is the only wrong answer, because the next reader will run it.

**A rules file created mid-session never injects in that session** — however correct its `paths:`
frontmatter, a working glob and a broken one look identical there (both absent). Verify a new or
re-scoped rule from fresh subagent probes, one `Read` each, with a positive control. Mechanism,
scope limits and re-runnable probes: `~/.claude/kit-docs/code-review-path-scoped-rules.md`.
