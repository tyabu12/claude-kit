---
name: work-log
description: Extract and format a work log from conversation history under ~/.claude/projects/. Argument is the number of days to look back (default 7).
argument-hint: "[days]"
---

`~/.claude/projects/` 配下の会話履歴から作業ログを抽出・整形してください。

## パラメータ

- 日数: `$ARGUMENTS`（未指定時は 7）

## 手順

以下のスクリプトを実行して生データを取得してください。
DAYS の値は上記パラメータの日数に置き換えてください。

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

## 出力フォーマット

取得した生データを以下の形式に整形してください:

1. タイトル: `## 作業ログ（直近 N 日間）`
2. 日付ごとのセクション（新しい順）
3. 各日付内はプロジェクト別にグルーピング
4. 各セッションの内容は最初のユーザーメッセージから作業の目的を1行で簡潔に要約
5. ノイズ（`[Request interrupted]`、`<local-command-caveat>`、`<command-message>` のみ等）はスキップ
6. 末尾にサマリーテーブル（プロジェクト別セッション数の合計）

出力はすべて日本語で行ってください。
