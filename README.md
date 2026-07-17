# claude-kit

A shareable kit of Claude Code assets — skills, agents, hooks, and rules — for
orchestrating multi-step work, running bias-resistant review, and keeping
Claude Code's own configuration and memory hygienic. It can be installed as a
Claude Code **plugin** or wired directly into `~/.claude/` via **symlinks**;
see the two install sections below (they are not equivalent — read the
"rules/ is a co-install dependency" section).

## Contents

**Skills** (`skills/`):
- `orchestrate` — feature orchestration: plan → issue → worktree → implement → review → PR.
- `promote-memories` — triage per-user memory into durable rules and retire shipped trackers.
- `review-claude-config` — health check for Claude Code configuration files.
- `risk-review` — multi-perspective, bias-resistant risk review of a diff or design decision.
- `work-log` — extract and format a work log from conversation history.

**Agents** (`agents/`):
- `critic` — bias-resistant reviewer using pre-mortem axis generation and rubric-based evaluation.
- `implementer` — executes implementation work from a finalized plan.

**Hooks** (`hooks/`):
- `block-force-push.sh` — PreToolUse guard that blocks `git push --force` to protected branches.
- `gated-runner.sh` — runs a wrapped hook only when the Bash command matches a given prefix (e.g. `gh pr `).
- `pre-pr-docs-check.sh` — pre-PR docs freshness check.
- `post-pr-reflection.sh` — post-PR reflection prompt.
- `_pr-lib.sh` — shared helpers used by the PR-related hooks above.

The hook *scripts* live in `hooks/`; their plugin *registration* lives in
`hooks-plugin/` (its own plugin root, with `hooks/hooks.json` plus symlinks to
the scripts), so the `claude-kit` plugin can ship without the hooks.

**Rules** (`rules/`) — see the co-install section below before assuming these are installed.

## Install as a plugin

The marketplace splits the kit into two plugins so a project can take the
skills/agents without the hooks:

- `claude-kit` — the 5 skills and 2 agents. No hooks.
- `claude-kit-hooks` — the PR-workflow hooks (`hooks/hooks.json`). Install
  this **only if** your project does not already register its own force-push
  guard / PR docs-check / PR reflection hooks — otherwise both copies fire on
  every matching tool call.

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

Wire it as a pre-push hook (or a CI job) once this repo is made public or
shared beyond the author's own machine.
