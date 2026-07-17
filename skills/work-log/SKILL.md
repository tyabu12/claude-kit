---
name: work-log
description: Extract and format a work log from conversation history under ~/.claude/projects/. Argument is the number of days to look back (default 7).
argument-hint: "[days]"
model: sonnet
---

Extract and format a work log from the conversation history under `~/.claude/projects/`.

## Parameters

- Days: `$ARGUMENTS` (defaults to 7 when unspecified)

## Steps

Run the script below to obtain the raw data.
Replace the value of DAYS with the number of days from the parameter above.

```bash
DAYS=7
if ! echo "$DAYS" | grep -qE '^[0-9]+$'; then
  echo "Error: DAYS must be a positive integer" >&2
  exit 1
fi
HOME_PREFIX=$(echo "$HOME" | sed 's|/|-|g')

for dir in ~/.claude/projects/${HOME_PREFIX}-*; do
  [ -d "$dir" ] || continue
  project=$(basename "$dir" | sed "s|^${HOME_PREFIX}-||" | sed 's|^$|(root)|')
  find "$dir" -maxdepth 1 -name "*.jsonl" -mtime -${DAYS} -print0 | while IFS= read -r -d '' f; do
    python3 -c "
import json, sys, re
with open(sys.argv[1]) as fh:
    for line in fh:
        try:
            obj = json.loads(line)
            if obj.get('type') == 'user':
                msg = obj.get('message', {})
                content = msg.get('content', '')
                if isinstance(content, list):
                    texts = [c.get('text','') for c in content if c.get('type')=='text']
                    content = ' '.join(texts)
                content = re.sub(r'<system-reminder>.*?</system-reminder>', '', content, flags=re.DOTALL).strip()
                if content and len(content) > 5:
                    ts = obj.get('timestamp', '')[:10]
                    print(ts + '||' + sys.argv[2] + '||' + content[:200].replace(chr(10), ' '))
                    break
        except Exception:
            pass
" "$f" "$project" 2>/dev/null
  done
done | sort -r
```

## Output format

Format the raw data you obtained as follows:

1. Title: `## 作業ログ（直近 N 日間）`
2. One section per date (newest first)
3. Group entries by project within each date
4. For each session, summarize the purpose of the work in a single line, derived from the first user message
5. Skip noise (e.g. `[Request interrupted]`, `<local-command-caveat>`, or content consisting only of `<command-message>`)
6. End with a summary table (total session count per project)

Produce all output in Japanese.
