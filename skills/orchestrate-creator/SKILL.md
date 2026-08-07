---
name: orchestrate-creator
description: Scaffold a project-owned /orchestrate skill into the current repo's .claude/skills/ from this kit's template — resolve the project's parameters (test/lint commands, commit gate, TDD policy, review agents, plan marker) at generation time and bake them in. Re-run on a previously generated skill to diff it against the current template and propose back-ports. Use when a project needs an orchestration workflow (plan → issue → worktree → implement → review → PR), or to upgrade one generated earlier.
allowed-tools: Read, Grep, Glob, Bash, Write, Edit, AskUserQuestion
argument-hint: "[upgrade]"
---

# /orchestrate-creator

Generate a **project-owned** `/orchestrate` skill at `.claude/skills/orchestrate/SKILL.md` from
`orchestrate-template.md` (in this skill's directory), then hand the new file to the project's
normal change workflow.

> **Why a creator instead of a runnable generic skill:** Claude Code resolves same-named skills as
> *personal overrides project* (documented: [skills — precedence](https://code.claude.com/docs/en/skills)),
> so a globally installed `orchestrate` would permanently shadow every project's own — with a
> mismatched `PLAN_MARKER` that breaks plan resumption. And the project-specific parts of an
> orchestration workflow (gates, markers, QA policy) are *structural*, beyond what a runtime
> profile can parameterize. So the kit ships the workflow as a generation-time template: each
> project bakes its own copy, owns it outright, and no global skill competes for the name.

## Step 0: Preconditions & mode

1. Must run inside a git repository — the *consumer* project, never this kit's own repo (the
   template lives here; generating into it is a mistake — stop and say so).
2. **Mode detect:** if `.claude/skills/orchestrate/SKILL.md` already exists in the repo → **Upgrade
   mode** (Step U). Else → **Fresh mode** (Steps 1–4). `$ARGUMENTS` containing `upgrade` forces
   Upgrade mode (error if there is nothing to upgrade).
3. **Collision check (the reason this skill exists):** if `~/.claude/skills/orchestrate/` exists —
   as a directory or symlink — warn before anything else: personal scope overrides project scope,
   so that skill will shadow the generated one on every bare `/orchestrate`. Tell the user to
   remove or rename it first; offer to continue generating anyway (the file is still useful once
   the collision is cleared).
4. **Legacy profile:** if `.claude/orchestrate.md` exists (the retired runtime-profile format),
   harvest `test_command` / `lint_command` / `commit_gate` / `tdd` / `sensitive_paths` /
   `qa_section` as parameter defaults, and note that the file can be deleted once the generated
   skill lands (its values are now baked in).

## Step 1: Resolve parameters (Fresh mode)

Infer what is inferable, then confirm everything in **one** gate — never auto-detect-and-proceed:
a wrong test command produces a false green in every future orchestrate run.

| Placeholder | How to resolve |
|---|---|
| `{{PROJECT_NAME}}` | repo name (`gh repo view --json name -q .name`, else directory name) |
| `{{MARKER_SLUG}}` | default: repo name, kebab-case. Must be project-unique — never the generic `claude-orchestrate`. If past plans were posted by the retired generic skill, ask: keep its `claude-orchestrate` marker for resumption continuity, or start clean (old plan comments become unresumable — usually fine) |
| `{{TEST_COMMAND}}` | legacy profile, else infer from tooling: `package.json` scripts, `Makefile`/`justfile` targets, `Cargo.toml`, `go.mod`, `Package.swift`, gradle. In a monorepo, commands differ per subproject — say so and pick per the dominant tree, or ask |
| `{{LINT_COMMAND_CELL}}` | same sources; if none, the literal `none` |
| `{{COMMIT_GATE}}` | `hook` if a real pre-commit gate exists (`.git/hooks/pre-commit`, `.pre-commit-config.yaml`, husky, lefthook — verify it runs tests/lint, not just formatting), else `none` |
| `{{TDD_POLICY}}` | ask: `required` / `optional` |
| `{{SENSITIVE_PATHS_SUFFIX}}` | ask for extra Opus-forcing globs; render as `, or any of: <globs>` — empty string if none |
| `{{CRITIC_AGENT}}` | project's own critic agent if one exists; else `claude-kit:critic` if the plugin is installed (verify the **namespaced** name resolves — a bare name proves nothing); else instruct the template consumer to use a general-purpose subagent with the critique prompt |
| `{{REVIEWER_AGENT}}` | `code-reviewer` if `.claude/agents/code-reviewer.md` exists in the repo (project scope); else `claude-kit:code-reviewer` |
| `{{ROADMAP_PATH}}` | roadmap doc if present (`docs/ROADMAP.md` or similar); controls the `phase N` input block |
| `{{QA_SECTION}}` | ask: manual-QA rule for PR bodies, or none |

Present the resolved table and ask **"Generate with these values?"**.

## Step 2: Generate

1. Read `orchestrate-template.md` from this skill's own directory (the directory this SKILL.md
   was loaded from — works for both plugin and symlink installs).
2. Compute the stamp: `shasum -a 256 <template-path> | cut -c1-12` → `{{TEMPLATE_SHA12}}`;
   today's date → `{{GENERATED_DATE}}`.
3. Resolve every `{{…}}` placeholder; for each `<!-- CREATOR:IF … --> / ELSE / END` block keep
   exactly one branch and delete all marker lines. Drop optional blocks whose condition is absent
   (no roadmap → no `phase N` input; no QA section → no QA bullet).
4. Write to `.claude/skills/orchestrate/SKILL.md`.

## Step 3: Verify (negative controls — run all)

1. `grep -nE '\{\{|CREATOR:' .claude/skills/orchestrate/SKILL.md` → **must print nothing**. Any
   hit is an unresolved slot; fix and re-grep.
2. Confirm the marker line: `grep -c "<!-- <marker>-plan -->"` ≥ 2 (Constants + the Step 2a
   heredoc) and that the generic `claude-orchestrate-plan` does not appear unless deliberately
   kept for continuity.
3. Remind the user: a skill file written mid-session is not reliably invocable in the session that
   wrote it — verify from a **fresh** session that `/orchestrate` lists with this project's
   description, not a global one.

## Step 4: Hand off

Do not commit from this skill. Hand the generated file to the project's normal change workflow
(branch → PR). If the project designates `/orchestrate` as its implementation entry point, this
file is the bootstrap exception — it is the entry point being created; a plain branch + PR is the
expected route. Suggest deleting a harvested legacy `.claude/orchestrate.md` in the same PR.

## Step U: Upgrade mode

1. Read the `generated-from:` stamp comment in the existing generated file. **No stamp** → the
   file is hand-written, not generated; offer a read-only comparison report against the template,
   change nothing.
2. Hash the current template (as in Step 2). **Equal to the stamp** → report "up to date", stop.
3. Otherwise read both files in full and propose **principle-level back-ports**: template
   improvements the project's copy lacks, item by item, each with the reason. Never overwrite
   wholesale — the project's customizations are the point of ownership; when a template change
   conflicts with a deliberate local edit, surface the conflict and let the user pick.
4. Apply the agreed edits, update the stamp line (new hash + date), then run Step 3's controls
   and Step 4's hand-off.
