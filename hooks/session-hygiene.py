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

Every notice suggests something to the *user* at a task boundary and is
wrapped with an explicit counter-line, because showing a model its own
remaining-context number is the most common trigger for self-truncation
(summarizing early, cutting scope, over-delegating). Keep that shape when
editing the strings — see #21.

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

# Counter-line appended to every injection: the numbers above are cost info for
# a suggestion at the next boundary, never a cue to cut the work short.
FOOTER = ('上記はコスト情報であり、今の作業を中断・縮小する理由にはしない。'
          '現在の依頼は区切りまで通常どおり最後まで実行し、'
          '要約への早期移行・スコープ縮小・打ち切りはしないこと。')


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
            f'前回の応答から約{int(gap // 60)}分経過しており、プロンプトキャッシュは失効済み。'
            f'このセッションを続けると約{ctx // 1000}kトークンのキャッシュ再構築(cacheWrite)が発生する。'
            'この依頼が後始末(CI/マージ確認・クリーンアップ)や文脈をほぼ要しない軽作業なら、'
            '新しいセッションで行うことをユーザーに提案すること。')

    if ctx >= CTX_WARN:
        bucket = ctx // CTX_STEP
        if bucket > int(state.get('ctx_bucket', 0)):
            state['ctx_bucket'] = bucket
            notices.append(
                f'コンテキストが約{ctx // 1000}kトークンに達している。以降はツール呼び出し1回ごとに'
                f'同量の cacheRead 課金が発生する。タスクの区切りが来たら新セッションへの移行を'
                'ユーザーに提案すること(委譲するかどうかは通常どおりグローバル CLAUDE.md の基準で'
                '判断し、この通知を理由に増やさない)。')

    if model.startswith('claude-fable'):
        last = float(state.get('fable_notified_at', 0))
        if now - last >= FABLE_RENOTIFY_SECS:
            state['fable_notified_at'] = now
            notices.append(
                'メインセッションが Fable で動作中。Fable の cacheRead 単価は Opus の2倍のため、'
                'ハードな判断が済んでいる(残作業が実装・確認・後始末)なら、'
                '/model opus への切り戻しか新セッションをユーザーに提案すること。')

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
