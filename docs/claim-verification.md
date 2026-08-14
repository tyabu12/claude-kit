# Claim verification — which source settles which claim

Depth behind `rules/knowledge-layering.md` § "Verify before you lock it", which carries the
discipline and the three moments it fires at; the per-shape checks live here. Nothing here is
version-dependent, so there is no re-measurement trigger — it accretes as new failure shapes appear.

The organising fact: **a claim is checked by whoever authors it, or by nobody.** A reviewer checks
whether the code is correct and whether a rule's content is sensible — not whether the check a rule
prescribes actually passes, and not whether the stated reason for a mechanism is true. So a false
claim ships intact and the next reader inherits it as fact.

## Claims you lean on

Verify each against its authoritative source *before* the plan locks.

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

Authored at implementation *or review-fix* time, and executed by nobody. Four shapes, none
expressible as a `Verify by` lookup:

- **Why-comment on a mechanism** → delete the mechanism and run the tests. Green means the claim
  is false, or the tests never covered it. Its *destination* is a separate question — see
  § "A comment written for the reviewer" below.
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

## A comment written for the reviewer

Backs `rules/knowledge-layering.md` § "Anti-pattern: a comment written for the reviewer". A comment
whose only content is what *this* change did is addressed to a reviewer, who reads the PR body
anyway, rather than to the next editor, who does not.

**Do not key the rule on wording.** The tempting discriminator is tense — "must stay identical to X"
constrains, "was left identical to X" reports — and it was measured over 169 comment blocks from two
model generations. It needed to decide 17 of them and got 4 wrong, because:

- It reads the sentence's grammatical head, not its payload. "…lives in `LeafIcon.swift`, which owns
  the default this file used to apply" is a stale move record with a present-tense main clause;
  "…live in `Foo+Bar.swift` to keep this file under the length budget" is a live navigational
  breadcrumb with identical grammar.
- It cannot see duplication at all — a measured figure copy-pasted to a second package is the defect,
  and every word of it is a legitimate present-tense fact.
- Backward-looking clauses are frequently load-bearing: a forward rule reading "any key added *after
  that* bumps the version" is unparseable once the history clause it refers to is gone.

The unit of deletion is the **block**, so a per-clause flag on a block-level artifact misfires — in
that corpus, on ~7% of all load-bearing blocks, and systematically on the longest ones, which are
the comments whose loss causes the mistakes the convention exists to prevent.

**The form that survived the negative control**: flag only when *every* sentence in the block is a
backward-looking report, or when the block restates a figure that has a canonical site elsewhere. On
the same corpus that caught every true instance with no false positives.

The duplicated-figure shape needs a **repo-side grep**, not a review agent: a review that splits a
large diff by file or axis gives no shard sight of all the sites, so the property is invisible by
construction. Frame the grep as *new code must not add hits*, with the existing count recorded as an
acknowledged baseline — the *reframe* disposition, not a must-return-zero.

**Length is the commoner defect.** Across the same corpus one generation wrote ~45% more comment
lines per block, and ~50% more blocks per commit, at an unchanged A/B/C/D distribution — the same
content, longer. That is compressible with no information loss, and it is a cheaper and far safer
correction than any rule that proposes deleting a category of content.

## Reading a probe's outcome

**It gets misread in both directions.** Assert that the mutation's anchor matched — a `replace` that
silently no-ops leaves the original behaviour and reads as verified. And treat a probe that stays
**green** as a finding about the *fixtures*, not a redundant guard: a suite only reddens on states
its fixtures build, so name the state the guard defends and confirm something constructs it before
concluding anything.

## The rule-assertion case

A rule file is where authored claims concentrate, because a rule *is* a set of assertions about the
repo — and unlike a why-comment, the next reader runs them. Two reasons behind the rule's one-line
version: a self-quoted byte/line delta is re-measured on the **final** commit because review
fixes move it, and a diverged assertion left silently in place is the one wrong answer because that
reader is the one who finds it.

A detector a rule *ships* is the sharpest case, because it runs against the file that defines it.
The `rg` in `rules/knowledge-layering.md` § "Anti-pattern: memory refs in repo-tracked files"
returned exactly one hit on the day it landed: that section's own prose example of the banned form,
which is the *form being defined*, not a reference. The three dispositions are not equally cheap
here — an inline carve-out is the rule's own remedy but adds a line to an **always-loaded** file
*and* is itself a `file:line` assertion that re-breaks whenever the line moves, and narrowing the
pattern to dodge one example is brittle by construction. Rewriting the example with a `<name>`
placeholder takes the detector to zero without weakening it; if a later edit writes a concrete
lowercase filename back in, the grep fires and the next editor picks a disposition again — the
mechanism working, not a regression. **Any doc quoting that example inherits the same
constraint**, this one included.

It still shipped with a blind spot, and the negative control is what missed it: the first form
recursed with `rg`, which skips hidden directories, so `.claude/**` — rules, skills, agents — went
unscanned, and the control sat at the repo root, inside the guard's existing reach, reddening
without testing the question. **Scope a control to the claim's habitat, not just its pattern.**

The deeper error was the *file set*: a recursive grep answers "which files lie here", the rule asks
"which are repo-tracked", and the two diverge both ways — a tracked file under an ignored directory
is missed, never-committed scratch is falsely flagged. `--hidden` closes that instance and leaves
the class open; the fix was to enumerate with `git ls-files --cached --others --exclude-standard`,
as `scripts/scrub-check.sh` already did — two mechanisms answering the same question differently is
drift waiting to happen. **When a detector's file set is not the claim's file set, no flag fixes it.**

It surfaced only when the detector ran against a repo it was not written in — the cheapest general
form of this check, since the authoring repo is where a self-referential detector is least able to
fail. The hit there was that repo's copy of the prose example, still spelling a concrete filename:
the constraint above reaches consumer mirrors, which must import the placeholder rewrite along with
the detector, or report their own rule file as a violation. Sequence and measurements: #30, #32.

One shape has no in-session probe at all: a rules file created mid-session never injects in that
session, so verify it from fresh subagent probes against a positive control. Mechanism, scope limits
and re-runnable probes: `~/.claude/kit-docs/code-review-path-scoped-rules.md`.
