#!/usr/bin/env bash
# Prepares a checkout of this repo: verifies the tools sync.sh needs and installs
# this repo's git hooks. It does not sync — run ./sync.sh for that.
#
# Run it once per checkout, including every linked worktree — `git worktree add`
# copies nothing and runs nothing, so a new worktree is unprepared until this has
# run in it. Hooks live in the shared git dir, so a worktree normally finds them
# already installed; bootstrap says so rather than pretending it did new work.
#
# Idempotent: safe to re-run at any time, and the right thing to run after pulling
# a change to git-hooks/.
#
# Usage: ./bootstrap.sh

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$SRC_DIR/git-hooks"
SYNC="$SRC_DIR/sync.sh"

if [[ $# -gt 0 ]]; then
  echo "Usage: $(basename "$0")" >&2
  exit 2
fi

log() { echo "[bootstrap] $*"; }
warn() { echo "[bootstrap] WARNING: $*" >&2; }
fail() { echo "[bootstrap] ERROR: $*" >&2; exit 1; }

# --- prerequisites -----------------------------------------------------------

command -v git >/dev/null 2>&1 || fail "missing required command: git. Install it and re-run."
command -v zsh >/dev/null 2>&1 || fail "missing required command: zsh. The helpers are zsh functions."
log "Required commands present: git, zsh"

# Sync resolves the destination the same way; a missing oh-my-zsh is sync's to
# refuse, but better to hear it now.
custom_dir="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}"
if [[ -d "$custom_dir" ]]; then
  log "oh-my-zsh custom directory: $custom_dir"
elif [[ -d "$(dirname "$custom_dir")" ]]; then
  log "oh-my-zsh custom directory $custom_dir does not exist yet; sync will create it"
else
  warn "no oh-my-zsh at $(dirname "$custom_dir") — install it, or set ZSH_CUSTOM to a directory your shell loads, before running sync.sh"
fi

# Not required by the repo itself — checked so a helper that quietly degrades
# without one does not do it as a surprise.
if command -v xcrun >/dev/null 2>&1; then
  log "Optional command present: xcrun"
else
  warn "optional command 'xcrun' not found — xc will not work on this machine"
fi
if command -v jq >/dev/null 2>&1; then
  log "Optional command present: jq"
else
  warn "optional command 'jq' not found — 'xc sim shake' cannot list simulators to pick from (brew install jq)"
fi
if command -v security >/dev/null 2>&1; then
  log "Optional command present: security"
else
  warn "optional command 'security' not found — add-password, get-password and delete-password need the macOS keychain"
fi

[[ -f "$SYNC" ]] || fail "$SYNC not found — is this a complete checkout?"

# --- git hooks ---------------------------------------------------------------

# --git-common-dir, not --absolute-git-dir: in a linked worktree the latter points
# at .git/worktrees/<name>, which has no hooks/ of its own. It can be relative.
git_common="$(git -C "$SRC_DIR" rev-parse --git-common-dir 2>/dev/null || true)"

# Compare the two raw rev-parse answers, which git resolves the same way. Measuring
# one against an --absolute-git-dir instead mixes a logical path with a physical
# one, and calls any checkout reached through a symlink a worktree.
IS_WORKTREE=false
if [[ -n "$git_common" ]] \
  && [[ "$(git -C "$SRC_DIR" rev-parse --git-dir 2>/dev/null)" != "$git_common" ]]; then
  IS_WORKTREE=true
fi

if [[ -z "$git_common" ]]; then
  warn "$SRC_DIR is not a git checkout — skipping hooks"
elif ! git_common="$(cd "$SRC_DIR" && cd "$git_common" 2>/dev/null && pwd -P)"; then
  warn "could not resolve the git dir — skipping hooks"
elif [[ ! -d "$git_common/hooks" ]]; then
  warn "$git_common has no hooks directory — skipping hooks"
else
  if $IS_WORKTREE; then
    log "Linked worktree: hooks are shared, installing into $git_common/hooks"
  fi

  is_ours() { grep -q 'managed by bootstrap\.sh' "$1"; }

  install_hook() {
    local name="$1"
    local src="$HOOKS_DIR/$name"
    local dest="$git_common/hooks/$name"

    if [[ ! -f "$src" ]]; then
      warn "$src missing, not installing $name"
      return 0
    fi

    # -e is false for a dangling symlink, so test -L too or cp below dies.
    if [[ -L "$dest" ]] && [[ ! -e "$dest" ]]; then
      log "Removing broken symlink $dest"
      rm "$dest"
    fi

    if [[ -e "$dest" ]] && ! is_ours "$dest"; then
      warn "$dest exists and was not installed from this repo, leaving it alone"
      return 0
    fi

    if cmp -s "$src" "$dest"; then
      log "$dest already up to date"
      return
    fi

    cp "$src" "$dest"
    chmod +x "$dest"
    log "Installed $dest"
  }

  install_hook post-merge
  install_hook pre-push
fi

log "Done. Hooks sync on a push or pull of the default branch; run $SYNC for anything else."
