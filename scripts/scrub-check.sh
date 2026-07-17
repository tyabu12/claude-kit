#!/usr/bin/env bash
# scrub-check.sh — committed leak-check gate for claude-kit.
# Scans all git-tracked-or-untracked files (excluding .git/ and this script)
# for personal-data leakage before the repo is pushed / made public.
# Exit 0 = clean, exit 1 = violation. Wire as a pre-push or CI gate.
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SELF="scripts/scrub-check.sh"
VIOLATIONS=0

# List of files to scan: tracked + untracked-but-not-ignored, minus .git/ and self.
# (Avoid `mapfile`/`readarray` — not available under macOS's stock bash 3.2.)
FILES=()
while IFS= read -r f; do
  FILES+=("$f")
done < <(git ls-files --cached --others --exclude-standard | grep -v '^\.git/' | grep -v -F "$SELF")

report() {
  # $1 = "file:line: matched line"
  echo "$1"
  VIOLATIONS=$((VIOLATIONS + 1))
}

is_allowlisted_author_file() {
  case "$1" in
    .claude-plugin/plugin.json|.claude-plugin/marketplace.json) return 0 ;;
    *) return 1 ;;
  esac
}

# --- 1. Forbidden patterns anywhere ---------------------------------------
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue

  if is_allowlisted_author_file "$f"; then
    continue
  fi

  # pastura (case-insensitive)
  while IFS=: read -r line content; do
    report "${f}:${line}: ${content}"
  done < <(grep -niE 'pastura' -- "$f" 2>/dev/null || true)

  # absolute personal paths
  while IFS=: read -r line content; do
    report "${f}:${line}: ${content}"
  done < <(grep -niE '/Users/' -- "$f" 2>/dev/null || true)

  # author name-fragment / email leaking outside the allowlisted files
  while IFS=: read -r line content; do
    report "${f}:${line}: ${content}"
  done < <(grep -niE 'tyabu|@gmail' -- "$f" 2>/dev/null || true)
done

# --- 1b. Verify allowlisted files contain the intended author email exactly once ---
INTENDED_EMAIL="tyabu1212@gmail.com"
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
  if [ ! -f "$f" ]; then
    report "${f}:0: expected allowlisted author file is missing"
    continue
  fi
  count="$(grep -o -F "$INTENDED_EMAIL" -- "$f" | wc -l | tr -d ' ')"
  if [ "$count" != "1" ]; then
    report "${f}:0: expected exactly one occurrence of ${INTENDED_EMAIL}, found ${count}"
  fi
  # Any other tyabu|@gmail hit that isn't the intended email is a violation.
  while IFS=: read -r line content; do
    if ! grep -qF "$INTENDED_EMAIL" <<<"$content"; then
      report "${f}:${line}: ${content}"
    fi
  done < <(grep -niE 'tyabu|@gmail' -- "$f" 2>/dev/null || true)
done

# --- 2. Forbidden files present --------------------------------------------
for f in "${FILES[@]}"; do
  case "$f" in
    memory/*|*/memory/*)
      report "${f}:0: forbidden path (memory/ directory must never be committed)"
      ;;
  esac
  case "$f" in
    settings.json|*/settings.json|settings.local.json|*/settings.local.json)
      report "${f}:0: forbidden path (personal settings file must never be committed)"
      ;;
  esac
done

# --- 3. Secret-ish patterns -------------------------------------------------
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue

  while IFS=: read -r line content; do
    report "${f}:${line}: ${content}"
  done < <(grep -nE -- '-----BEGIN .*PRIVATE KEY' -- "$f" 2>/dev/null || true)

  while IFS=: read -r line content; do
    report "${f}:${line}: ${content}"
  done < <(grep -niE -- "(api[_-]?key|secret|token)[[:space:]]*[:=][[:space:]]*['\"][A-Za-z0-9_-]{16,}" -- "$f" 2>/dev/null || true)
done

# --- Summary ----------------------------------------------------------------
if [ "$VIOLATIONS" -gt 0 ]; then
  echo "FAIL (${VIOLATIONS} violation(s))"
  exit 1
else
  echo "PASS"
  exit 0
fi
