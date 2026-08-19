# Skill Feedback Capture

Part of claude-kit and the **canonical source** of this rule. Claude Code-specific; feeds this kit's
`/skill-retro`, which is the only place skills are actually edited.

While executing any custom skill — this kit's or a project's own — append ONE dated line to
`~/.claude/skill-feedback/<skill-name>.md` (create the directory and file if missing) whenever:

- you deviate from the skill's instructions,
- the user corrects the flow, or
- you hit a judgment call the skill does not cover.

Format: `- YYYY-MM-DD: <one sentence>`

**Capture the friction; do not edit the skill inline.** Skill changes go through the monthly
`/skill-retro` review, evidence-first — an inline fix made mid-task has no evidence trail and
bypasses that gate.
