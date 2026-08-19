# Session Hygiene

Part of claude-kit and the **canonical source** of this rule. Claude Code-specific mechanics; the
nudges themselves are emitted by this kit's `hooks/session-hygiene.py` (UserPromptSubmit).

Treat task completion as a session boundary — a long idle gap or a 200k+ main context makes
continuing cost more than restarting.

**Act at the boundary, not before it.** Finish the task in hand at full scope — no early
summarizing, no scope-cutting, no mid-task hand-off — then suggest a fresh session. Context size
never overrides the delegation criteria in `delegation.md`: a large context is not a reason to
delegate work that belongs in the main session, nor to skip a delegation that pays off.

The statusline shows the running context size, and the `session-hygiene` hook fires on these
thresholds with the numbers attached. Act on what it reports rather than re-deriving the math.
