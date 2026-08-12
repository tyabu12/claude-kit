#!/usr/bin/env python3
"""UserPromptSubmit hook: session-hygiene nudges to curb context-cost drift.

Reads the hook input JSON on stdin, inspects the session transcript's last
assistant turn (timestamp / model / context size), and injects advisory
context so Claude proactively suggests:
  1. a fresh session when resuming after a long idle gap (the prompt cache
     has expired — continuing pays a full cache rebuild of the whole context),
  2. a session boundary when context exceeds 200k tokens (every subsequent
     tool call re-reads the full context as cacheRead),
  3. reverting from a lingering Fable main session once the hard call is done
     (Fable cacheRead is 2x Opus).

Every notice asks for one thing and one thing only: a suggestion to the
*user*. Never a unilateral change of plan — notice 1 in particular fires at
the *start* of a request and proposes redirecting it, so it must read as
"say so", not "refuse to do it here". That is why every injection is wrapped
with an explicit counter-line: showing a model its own remaining-context
number is the most common trigger for self-truncation (summarizing early,
cutting scope, over-delegating). Keep that shape when editing the strings,
and keep the counter-line compatible with all three — see #21.

The notices are model-facing only (nobody reads this injection in the UI), so
they are written in English: same instruction, fewer tokens than the Japanese
they replaced. What the model then says to the *user* is governed by that
user's own CLAUDE.md language rule, not by this file.

Notices are informational only — the hook never blocks the prompt. All
failures degrade to silence (exit 0, no output). Thresholds are informed by
OTel analysis (2026-08): idle-gap cold rebuilds averaged ~370k cacheWrite
tokens per resume, and 87% of main-thread cost came from 200k+ context turns.
"""
import json
import os
import sys
import tempfile
import time
from datetime import datetime

IDLE_GAP_SECS = 45 * 60      # prompt cache is long expired past this
IDLE_MIN_CTX = 50_000        # below this a cold rebuild is cheap; stay quiet
CTX_WARN = 200_000           # per-turn cacheRead becomes the dominant cost
CTX_STEP = 100_000           # re-notify only when crossing another 100k
FABLE_RENOTIFY_SECS = 60 * 60  # remind about a lingering Fable main at most hourly
TAIL_BYTES = 256 * 1024      # transcript tail window to scan

# Counter-line appended to every injection. It has to license the suggestion each
# notice asks for (including notice 1's "do this in a fresh session") while denying
# the model any unilateral trimming of its own work — hence "make the suggestion,
# that is all it asks for", rather than a blanket "carry on regardless".
FOOTER = ('The above is cost information. Make the suggestion it names — that is all it '
          'asks for — and otherwise carry the current request through as usual, at the '
          'scope it was given.')


def state_dir():
    d = os.path.join(tempfile.gettempdir(), 'claude-session-hygiene')
    try:
        os.makedirs(d, mode=0o700, exist_ok=True)
        return d
    except Exception:
        return None


def load_state(session_id):
    d = state_dir()
    if not d:
        return {}, None
    path = os.path.join(d, f'{session_id}.json')
    try:
        with open(path) as f:
            return json.load(f), path
    except Exception:
        return {}, path


def save_state(path, state):
    if not path:
        return
    try:
        with open(path, 'w') as f:
            json.dump(state, f)
    except Exception:
        pass


def last_assistant_turn(transcript_path):
    """Return (epoch_ts or None, model, ctx_tokens) from the newest assistant
    entry in the transcript tail; None if none found."""
    try:
        size = os.path.getsize(transcript_path)
        with open(transcript_path, 'rb') as f:
            f.seek(max(0, size - TAIL_BYTES))
            tail = f.read().decode('utf-8', errors='replace')
    except Exception:
        return None
    for line in reversed(tail.splitlines()):
        if '"assistant"' not in line or '"usage"' not in line:
            continue
        try:
            entry = json.loads(line)
        except Exception:
            continue
        if entry.get('type') != 'assistant':
            continue
        message = entry.get('message') or {}
        usage = message.get('usage') or {}
        ctx = sum(int(usage.get(k) or 0) for k in (
            'input_tokens', 'cache_read_input_tokens', 'cache_creation_input_tokens'))
        if ctx <= 0:
            continue
        ts = None
        raw_ts = entry.get('timestamp')
        if raw_ts:
            try:
                ts = datetime.fromisoformat(str(raw_ts).replace('Z', '+00:00')).timestamp()
            except Exception:
                pass
        return ts, str(message.get('model') or ''), ctx
    return None


def build_notices(turn, state, now):
    ts, model, ctx = turn
    notices = []

    gap = (now - ts) if ts else 0
    if gap >= IDLE_GAP_SECS and ctx >= IDLE_MIN_CTX:
        notices.append(
            f'The prompt cache has expired — about {int(gap // 60)} min since the last '
            f'turn. Continuing this session costs a ~{ctx // 1000}k-token cache rebuild '
            '(cacheWrite). If this request is wrap-up work (CI / merge checks, cleanup) '
            'or otherwise needs little of the existing context, suggest to the user that '
            'they do it in a fresh session.')

    if ctx >= CTX_WARN:
        bucket = ctx // CTX_STEP
        if bucket > int(state.get('ctx_bucket', 0)):
            state['ctx_bucket'] = bucket
            notices.append(
                f'Context is at ~{ctx // 1000}k tokens; from here every tool call bills '
                'that much again as cacheRead. When the current task reaches a boundary, '
                'suggest moving to a fresh session. Delegation stays on the usual '
                'CLAUDE.md criteria — do not delegate more because of this notice.')

    if model.startswith('claude-fable'):
        last = float(state.get('fable_notified_at', 0))
        if now - last >= FABLE_RENOTIFY_SECS:
            state['fable_notified_at'] = now
            notices.append(
                'The main session is running on Fable, whose cacheRead price is 2x Opus. '
                'If the hard call is already settled (implementation, verification and '
                'cleanup are what is left), suggest /model opus or a fresh session to '
                'the user.')

    return notices


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    transcript_path = data.get('transcript_path')
    if not transcript_path or not os.path.isfile(transcript_path):
        return
    turn = last_assistant_turn(transcript_path)
    if not turn:
        return

    state, state_path = load_state(data.get('session_id', 'unknown'))
    notices = build_notices(turn, state, time.time())
    save_state(state_path, state)
    if not notices:
        return

    body = '\n'.join(f'- {n}' for n in notices)
    print(json.dumps({
        'hookSpecificOutput': {
            'hookEventName': 'UserPromptSubmit',
            'additionalContext': f'<session-hygiene>\n{body}\n{FOOTER}\n</session-hygiene>',
        }
    }, ensure_ascii=False))


if __name__ == '__main__':
    main()
