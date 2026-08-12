#!/usr/bin/env bash
# install.sh — symlink this kit's dirs into ~/.claude/ for live-edit consumption
# on the author's own machine. Run `./install.sh doctor` to diagnose existing links.
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
BACKUP_ROOT="${HOME}/.claude-kit-backup"

# link <src> <dst>: create a directory symlink at dst -> src, backing up
# or repairing whatever is already there.
link() {
  local src="$1" dst="$2"

  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    echo "ok    $dst -> $src"
    return
  fi

  if [ -L "$dst" ] && [ ! -e "$dst" ]; then
    echo "warn  $dst is a dangling symlink (was -> $(readlink "$dst")); removing" >&2
    rm "$dst"
  fi

  if [ -e "$dst" ] || [ -L "$dst" ]; then
    local ts backup_dir
    ts="$(date +%Y%m%d%H%M%S)"
    backup_dir="${BACKUP_ROOT}/${ts}"
    mkdir -p "$backup_dir"
    echo "back  $dst -> $backup_dir/$(basename "$dst")"
    mv "$dst" "$backup_dir/"
  fi

  ln -s "$src" "$dst"
  echo "link  $dst -> $src"
}

# doctor: scan ~/.claude for expected + arbitrary top-level symlinks and report status.
doctor() {
  local status=0
  local checked=""

  for name in agents skills hooks rules kit-docs memory; do
    checked="$checked $name"
    local dst="${CLAUDE_DIR}/${name}"
    if [ -L "$dst" ]; then
      local target
      target="$(readlink "$dst")"
      if [ -e "$dst" ]; then
        echo "OK         ${dst} -> ${target}"
      else
        echo "DANGLING   ${dst} -> ${target} (target missing)"
        status=1
      fi
    elif [ -e "$dst" ]; then
      echo "NOT-LINKED ${dst} (real file/dir)"
    elif [ "$name" = "memory" ]; then
      : # not linked by this script — reported only when it already exists
    else
      # A link a release added but this machine never installed — without this
      # branch doctor prints nothing and exits 0.
      echo "MISSING    ${dst} (no symlink — run ./install.sh)"
      status=1
    fi
  done

  # Also scan any other direct children of ~/.claude that are symlinks.
  if [ -d "$CLAUDE_DIR" ]; then
    for entry in "$CLAUDE_DIR"/*; do
      [ -e "$entry" ] || [ -L "$entry" ] || continue
      local base
      base="$(basename "$entry")"
      case " $checked " in
        *" $base "*) continue ;;
      esac
      if [ -L "$entry" ]; then
        local target
        target="$(readlink "$entry")"
        if [ -e "$entry" ]; then
          echo "OK         ${entry} -> ${target}"
        else
          echo "DANGLING   ${entry} -> ${target} (target missing)"
          status=1
        fi
      fi
    done
  fi

  exit "$status"
}

if [ "${1:-}" = "doctor" ]; then
  doctor
fi

# Refuse to install from a git worktree: link() would repoint every ~/.claude entry at
# it, and removing it later silently dangles all of them — including rules/, loaded in
# every session of every project. (.git is a file in a worktree, a directory in the main
# checkout.) Deliberately below `doctor`, which is read-only and safe from anywhere.
if [ -f "${KIT_DIR}/.git" ]; then
  echo "error: ${KIT_DIR} is a git worktree." >&2
  echo "       Installing from here would point ~/.claude at it; every link would" >&2
  echo "       dangle once the worktree is removed. Run install.sh from the main" >&2
  echo "       checkout instead." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "warn: jq not found — hooks under hooks/ (force-push guard etc.) parse tool" >&2
  echo "      input with jq and will silently no-op (fail-open) without it." >&2
  echo "      Recommend: brew install jq" >&2
fi

mkdir -p "$CLAUDE_DIR"

link "${KIT_DIR}/agents" "${CLAUDE_DIR}/agents"
link "${KIT_DIR}/skills" "${CLAUDE_DIR}/skills"
link "${KIT_DIR}/hooks" "${CLAUDE_DIR}/hooks"
link "${KIT_DIR}/rules" "${CLAUDE_DIR}/rules"
# Nothing under ~/.claude/kit-docs/ is auto-loaded, so this costs no per-turn context;
# it exists so a docs/ citation in an always-loaded rule resolves from any project.
link "${KIT_DIR}/docs" "${CLAUDE_DIR}/kit-docs"
