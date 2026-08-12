# Subagent output caps — how the numbers were obtained

**Measured 2026-08-12 on Claude Code 2.1.228.** Volatile — these are Claude Code's per-model request
parameters, and they have already moved once (the previous table in `rules/subagent-usage.md` was
right for the 4.x generation and wrong for every Claude 5 model). Re-run the procedure below on a
Claude Code upgrade. This doc is the depth behind that rule, which carries only the numbers and the
decision they drive.

**Do not extrapolate a pre-5 cap from the Claude 5 row.** The gap is not uniform across families:
Opus 4.6-4.8 already sat at 64,000, while Sonnet 4.x was at 32,000 and Haiku 3.5 at 8,192. A new
generation means re-reading the catalog, not scaling the old numbers.

## What the cap actually is

Claude Code sets `max_tokens` per request from a per-model `default`/`upper` pair, held in a
hand-maintained catalog baked into the CLI binary:

```js
max_tokens = min(callerOverride ?? effective, effective)
effective  = clamp(CLAUDE_CODE_MAX_OUTPUT_TOKENS ?? default, …, upper)
```

Three consequences, all of which the old rule got wrong:

1. **There is no subagent-specific cap.** The request builder has no main-session/subagent branch,
   and the `Agent` tool passes no override — the only overrides in the binary are small ones for
   auxiliary calls (conversation titles and the like, at 128/500/1024/4096).
2. **A caller override can only lower the cap**, never raise it — it is wrapped in `min(…, effective)`.
3. **`CLAUDE_CODE_MAX_OUTPUT_TOKENS` is read from `process.env` at request-build time**, with no
   agent/main distinction, clamped to the model's `upper`. It is the one real budget lever.

A separate hard clamp of 64,000 exists but applies **only to the non-streaming fallback path** (the
retry used when stream creation fails), not to normal requests.

## Extracting the catalog

The catalog is a JS object literal in the compiled binary, introduced by the comment
`"Hand-maintained baked-in model catalog"`. Brace-match it out, then read it with a regex — it has
unquoted keys, so `json.load` will not parse it:

```sh
python3 - <<'EOF'
import re
data = open('/path/to/claude/versions/<VERSION>', 'rb').read()
anchor = data.find(b'Hand-maintained baked-in model catalog')
assert anchor != -1, 'catalog comment not found — the CLI renamed it; re-find the anchor'
start = data.rfind(b'{', 0, anchor)
d = 0
for j in range(start, start + 400_000):
    if data[j:j+1] == b'{': d += 1
    elif data[j:j+1] == b'}':
        d -= 1
        if d == 0: break
else:
    raise SystemExit('unbalanced braces — raise the 400,000-byte window')
s = data[start:j+1].decode('utf-8', 'replace')
for p in re.split(r'(?=\{id:")', s[s.find('models:'):]):
    mid = re.match(r'\{id:"([^"]+)"', p)
    mo = mid and re.search(r'max_output_tokens:\{([^}]*)\}', p)
    if mid: print(f'{mid.group(1):28} {mo.group(1) if mo else "-"}')
EOF
```

Two caveats. A remote `model-capabilities.json` can override the baked values at runtime (raising
`upper`, lowering `default`); none was cached on this machine, so the baked catalog was
authoritative here — check for one before trusting the extraction. And the brace counter does not
skip braces inside string or regex literals, which minified JS is full of, so a future build can
desync it: sanity-check that the model ids it prints look like a complete roster.

## The controls

Reading a number out of a binary says what the code intends to send, not what a subagent
experiences. Four controls were run; what they collectively fail to establish is flagged after.

**1. Direct readout — cheap, no truncation needed.** Claude Code reports its own resolved cap:

```sh
claude -p --model opus --output-format json "ok" | jq '.modelUsage[].maxOutputTokens'
```

Opus 5 → 64,000, Sonnet 5 → 64,000, Haiku 4.5 → 32,000, matching the extracted catalog exactly —
which is what licenses reading Fable 5's row off the same table instead of spending a Fable session
on a config lookup. The field reports `default`, so it will not show a `CLAUDE_CODE_MAX_OUTPUT_TOKENS`
override; control 2 covers that.

**2. Forced truncation — the control that must redden.** A readout only proves what the CLI
*believes*. Forcing the cap low makes truncation happen on demand:

```sh
CLAUDE_CODE_MAX_OUTPUT_TOKENS=1200 claude -p --model haiku --output-format stream-json --verbose \
  "Count from 1 to 600, one line per number, formatted as 'N - alpha bravo charlie delta echo
   foxtrot'. All 600 lines, no preamble, no tools, do not stop early."
```

The run spent **exactly 4,800 output tokens = 4 × 1,200** — one response plus three recovery
attempts — then surfaced `API Error: Claude's response exceeded the 1200 output token maximum.` The
same prompt with the variable unset completed in one uninterrupted 8,043-token response. That pins
the env var being honoured, reaching the wire, and the retry count of 3 in a single run. What makes
it a control rather than a demo: it *reddened*, and the error text names the cap, so the assertion
and the measurement are the same string.

**3. The env var reaching a subagent.** Control 2 forces the cap in a *main* session, which does not
establish the composite claim. Run separately: a `claude -p` session at
`CLAUDE_CODE_MAX_OUTPUT_TOKENS=1200` launched one Haiku subagent via the `Agent` tool. The
subagent's own transcript (`isSidechain: true`) records four assistant messages with
`stop_reason: max_tokens` at **`output_tokens: 1200`** each — the forced value, in the subagent's
own requests, retried the documented three times. The variable is not main-session-only. Find that
evidence with the scan snippet below; subagent transcripts are the `agent-*.jsonl` files.

**4. The subagent path — a lower bound, not the cap.** A Haiku subagent told to emit ~4,500 literal
lines inside a **single** `Write` call produced one assistant message with `stop_reason: tool_use`
and **`output_tokens: 27,493`** — 3.4× the 8,192 the old table claimed for Haiku, falsifying it on
the subagent path itself rather than by inference from a main session.

It did **not** force truncation there: the subagent split the work across three `Write` calls, so it
stayed under 32,000 and reported `LIMIT_MSG=no`. That is a fact about the fixture, not the cap — an
agent that chunks its own tool calls cannot be made to overflow this way, and a probe wanting the
exact subagent cap needs one that cannot chunk (a single final message, whose size then lands in the
orchestrator's context, which is why it was not run). This lower bound, control 3, and consequences
1 and 3 above together license treating the model's cap as the subagent's; the exact subagent
ceiling is inferred, not measured.

### What the controls do not establish

**The ceiling column.** Every control forces the cap *downward*. Nothing exercises a *raise*
(64,000 → 128,000) — the direction a reader would actually use the variable for — and
`modelUsage.maxOutputTokens` cannot show it: that field reports the catalog `default`, stayed at
64,000 under `CLAUDE_CODE_MAX_OUTPUT_TOKENS=999999`, and emitted no clamp warning. Verifying a raise
means getting a model to emit more than 64,000 tokens in one response. Hence the `†` markers in
`rules/subagent-usage.md` on the ceiling column and on Fable 5's cap: catalog-extracted, not observed.

**The cap biting in real use.** A scan of the 1,317 local transcripts predating this work found the
largest single response to be 24,073 tokens (Fable 5) and **zero** responses with
`stop_reason: max_tokens` — which is why the rule stops deriving its split thresholds from the cap.
Re-run that scan today and it reports 27,493 and a cluster of `max_tokens` stops, every one of them
from the controls above: the measurement contaminated the corpus it was measuring. (No count is
quoted here on purpose — each probe run moves it.) Scope a re-run to transcripts predating the probe
date, or list the offending files and subtract them:

```sh
python3 -c "
import json,glob,os
biggest, stops = 0, []
for f in glob.glob(os.path.expanduser('~/.claude/projects/**/*.jsonl'), recursive=True):
    for line in open(f, errors='replace'):
        if '\"output_tokens\"' not in line: continue
        try: m = json.loads(line).get('message')
        except: continue
        if not isinstance(m, dict): continue
        biggest = max(biggest, (m.get('usage') or {}).get('output_tokens') or 0)
        if m.get('stop_reason') == 'max_tokens': stops.append((f, m.get('model')))
print('largest single response:', biggest)
print('max_tokens stops:', len(stops))
for s in dict.fromkeys(stops): print('  ', s[0], s[1])
"
```

## How a cap hit behaves now

Since 2.1.228 a `stop_reason: "max_tokens"` is not a silent one-shot loss. The query loop detects it
and retries up to 3 times, injecting a meta message into the agent's own context:

> Output token limit hit. Resume directly — no apology, no recap of what you were doing. Pick up
> mid-thought if that is where the cut happened. Break remaining work into smaller pieces.

Only after those attempts does `API Error: Claude's response exceeded the N output token maximum.`
reach the user. So the old rule's premise — a report whose substance silently goes missing — now
costs extra turns and a seam mid-report instead, which is what the rule's count-mismatch heuristic
is for. That heuristic works because the kit's review agents are instructed to emit their **verdict
first** and trim per-issue detail under pressure (`agents/code-reviewer.md`, "emit the Review Summary
(with the Verdict line) FIRST"): the summary is written before the body it summarises, so a cut lands
in the body and leaves the header over-claiming. An agent that summarised last would give no such
tell — the heuristic is a property of these agent definitions, not of the platform.

## Why the split thresholds were held

The rule used to present ~800 lines / ~8 files / ~5 axes (hard-split 1500 / 12 / 7) as *derived*
from the cap, "pinned to the smallest practical budget" of 8,192. That figure is the catalog's
`claude-3-5-haiku` row (`max_output_tokens:{default:8192,upper:8192}`) and never applied to a model
the kit can spawn; the real floor is Haiku 4.5's 32,000. Re-deriving strictly would multiply every
threshold by about four — 3,200 changed lines to one reviewer.

They were held instead, and the rule no longer claims a derivation. The cap was never the binding
constraint at these scopes (see the transcript scan above), so a number that would not have changed
had the cap been right was not really derived from it; what the thresholds buy is **review
attention**, which does not scale with `max_tokens`. The consequence for future edits: revise them
on evidence about review quality — a reviewer that misses things at 800 lines, or does fine at 1,500
— and not by recomputing when a cap moves. A future cap change updates the table and leaves the
thresholds alone unless it drops *below* them.

That is also why the thresholds stay **kit-canonical** rather than becoming a per-project knob: the
attention they are bounding is a *subagent's* at a given scope, identical for everyone who installs
the kit. A threshold becomes project-owned only when the thing it bounds is the *maintainer's* own
attention or tolerance — the test in `~/.claude/kit-docs/automation-output-contract.md`.

## Upstream

[anthropics/claude-code#24055](https://github.com/anthropics/claude-code/issues/24055) — still
**open** as of 2026-08-12 (last activity 2026-07-15); it asks for the cap to be configurable for
subagents. Its title still quotes 32,000, a 4.x-generation figure, which is part of what made the
old table look plausible.
