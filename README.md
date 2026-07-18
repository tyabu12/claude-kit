# claude-kit

A shareable kit of Claude Code assets — skills, agents, hooks, and rules — for
orchestrating multi-step work, running bias-resistant review, and keeping
Claude Code's own configuration and memory hygienic. It can be installed as a
Claude Code **plugin** or wired directly into `~/.claude/` via **symlinks**;
see the two install sections below (they are not equivalent — read the
"rules/ is a co-install dependency" section).

## Contents

**Skills** (`skills/`):
- `dispatch` — batch fan-out: run independent small-to-medium tasks in parallel worktrees, each ending in a reviewed draft PR.
- `orchestrate` — feature orchestration: plan → issue → worktree → implement → review → PR.
- `promote-memories` — triage per-user memory into durable rules and retire shipped trackers.
- `risk-review` — multi-perspective, bias-resistant risk review of a diff or design decision.
- `skill-retro` — monthly evidence-driven retro of this kit's skills; proposes fixes as a draft PR.
- `work-log` — extract and format a work log from conversation history.
- `write-adr` — draft an ADR into the repo's existing ADR directory, matching that repo's own format, then verify it with a two-reviewer loop.

**Agents** (`agents/`):
- `critic` — bias-resistant reviewer using pre-mortem axis generation and rubric-based evaluation.
- `implementer` — executes implementation work from a finalized plan.
- `code-reviewer` — project-agnostic PASS/FAIL reviewer for `orchestrate`'s Step 4 gate; reads the
  project's `CLAUDE.md` plus the `.claude/rules/**` whose `paths:` match the changed files. A
  project's own `.claude/agents/code-reviewer.md` shadows it (project scope wins).

**Hooks** (`hooks/`):
- `block-force-push.sh` — PreToolUse guard that blocks `git push --force` to protected branches.
- `guard-secret-reads.sh` — turns Bash commands referencing secret paths (`.ssh/`, `.aws/`, `.env`, …) into a confirmation ask; closes the gap that `Read()` permission denies don't cover Bash.
- `gated-runner.sh` — runs a wrapped hook only when the Bash command matches a given prefix (e.g. `gh pr `).
- `pre-pr-docs-check.sh` — pre-PR docs freshness check.
- `pre-pr-review-gate.sh` — review gate with teeth: denies the first ready-making `gh pr` command per branch until a review skill (/code-review or /risk-review) has run.
- `post-pr-reflection.sh` — post-PR reflection prompt.
- `_pr-lib.sh` — shared helpers used by the PR-related hooks above.

The hook *scripts* live in `hooks/`; their plugin *registration* lives in
`hooks-plugin/` (its own plugin root, with `hooks/hooks.json` plus symlinks to
the scripts), so the `claude-kit` plugin can ship without the hooks.

> **Maintainer note — don't collapse this into one plugin root.** Two Claude
> Code plugin-loading behaviours force the split: (1) a marketplace entry's
> explicit component list does *not* suppress default component
> auto-discovery, so a single root's `hooks/hooks.json` is always picked up and
> the hooks can't be dropped; and (2) a `strict: false` entry conflicts with
> the mere *presence* of a `plugin.json`, even one that declares no components.
> Separate plugin roots are the only clean way to ship skills/agents without
> the hooks.

**Rules** (`rules/`) — see the co-install section below before assuming these are installed.

**Docs** (`docs/`) — on-demand reference, deliberately outside `rules/` so it costs no per-turn
context. **Neither install mode ships `docs/`** (`install.sh` symlinks `agents/`, `skills/`,
`hooks/`, `rules/` only; plugins carry even less), so these are read from this repo or on GitHub —
a skill that cites one inlines the load-bearing fact and treats the path as depth-only.
- `automation-output-contract.md` — the contract an unattended generator (a skill that files PRs or
  issues on its own) must satisfy so it never bankrupts the reviewer's attention; plus the `gh`
  read-surface traps for Draft-triage automation. No kit skill is a generator yet — this is a spec
  for the next one, and for consuming projects that copy it.
- `code-review-path-scoped-rules.md` — why path-scoped `.claude/rules/**` are invisible to local
  `/code-review`, and what `orchestrate` Step 4 does instead. Cited from `agents/code-reviewer.md`
  and `skills/write-adr/SKILL.md`.

## Install as a plugin

The marketplace splits the kit into two plugins so a project can take the
skills/agents without the hooks:

- `claude-kit` — the 7 skills and 3 agents. No hooks.
- `claude-kit-hooks` — the PR-workflow hooks (`hooks/hooks.json`). Install
  this **only if** your project does not already register its own force-push
  guard / PR review gate / PR docs-check / PR reflection hooks — otherwise
  both copies fire on every matching tool call.

```
/plugin marketplace add <owner>/claude-kit
/plugin install claude-kit@claude-kit
/plugin install claude-kit-hooks@claude-kit   # optional, see above
```

(For a private repository, substitute the git URL — this works with your
normal git credentials, no extra auth setup needed.)

Plugin-delivered skills and agents are namespaced (`/claude-kit:orchestrate`,
`claude-kit:critic`), so they never collide with a project's own same-named
assets.

To pin the marketplace for everyone who clones a consuming project, add to
that project's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "claude-kit": {
      "source": { "source": "github", "repo": "<owner>/claude-kit" }
    }
  },
  "enabledPlugins": { "claude-kit@claude-kit": true }
}
```

This delivers **skills and agents only** (plus hooks if you opted in).

## Install via symlinks (rules included)

```
./install.sh
```

This symlinks `agents/`, `skills/`, `hooks/`, and `rules/` from this repo into
`~/.claude/`, so edits here are live immediately — intended for the author's
own machine.

- `./install.sh doctor` — diagnose the current state of `~/.claude`'s
  top-level symlinks (OK / DANGLING / NOT-LINKED), useful after moving or
  removing this repo.
- `jq` is required for the hook guards (e.g. `block-force-push.sh`) to parse
  tool input; without it they fail open (silently no-op) rather than block
  anything. `install.sh` warns if `jq` is missing.

## ⚠ rules/ is a co-install dependency

Claude Code plugins **cannot distribute `rules/`** — `/plugin install` only
delivers skills, agents, and hooks. The `rules/*.md` files in this repo are
the canonical source, but they only reach `~/.claude/rules/` via
`./install.sh` or a manual copy.

If you installed claude-kit as a plugin only, the rules are simply absent.
The skills in this kit are written to degrade gracefully in that case —
falling back to inline defaults — but for full behavior, co-install the
rules with `./install.sh` (or copy `rules/*.md` into your own
`~/.claude/rules/` by hand).

## Scrubbing / privacy

This repo starts from fresh git history and contains no personal memory or
machine settings. `scripts/scrub-check.sh` is the committed leak-check gate —
run it before pushing:

```
./scripts/scrub-check.sh
```

It runs automatically in CI (`.github/workflows/ci.yml`) on every push to
`main` and every pull request, alongside shellcheck and manifest/symlink
integrity checks. You can also wire it as a local pre-push hook.

## License

[MIT](LICENSE)
