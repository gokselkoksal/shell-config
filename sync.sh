#!/usr/bin/env bash
# Syncs this repo's zsh/ helpers into oh-my-zsh's custom directory, where
# oh-my-zsh loads every *.zsh at shell start. This repo is the source of truth.
#
# Syncing is all this does. Setting a checkout up — prerequisites and git hooks —
# is bootstrap.sh, which never syncs. The hooks it installs call this script when
# the default branch is pushed or pulled; otherwise run it by hand.
#
# Sync only ever writes what it owns, so it never asks before writing:
#   - In the custom directory, the files named in its manifest. Anything else
#     there — your own *.zsh, oh-my-zsh's plugins/ and themes/ — is left alone.
#   - In the conf directory, each <helper>.conf.example. The <helper>.conf files
#     beside them are yours and are never written.
# Anything in the way of what it is about to write fails the run before it writes
# anything at all.
#
# Destinations, each overridable the way the shell itself resolves it:
#   custom dir:  $ZSH_CUSTOM, else $ZSH/custom, else ~/.oh-my-zsh/custom
#   conf dir:    $SHELL_CONFIG_HOME, else ${XDG_CONFIG_HOME:-~/.config}/shell-config
#
# Usage: ./sync.sh

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSH_SRC="$SRC_DIR/zsh"
CONF_SRC="$SRC_DIR/config"

OWNER="gokselkoksal-shell-config"
MANIFEST=".$OWNER.manifest"

CUSTOM_DIR="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}"
CONF_DIR="${SHELL_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/shell-config}"

if [[ $# -gt 0 ]]; then
  echo "Usage: $(basename "$0")" >&2
  exit 2
fi

log() { echo "[sync-shell] $*"; }
warn() { echo "[sync-shell] WARNING: $*" >&2; }

if [[ ! -d "$ZSH_SRC" ]]; then
  echo "Error: $ZSH_SRC not found" >&2
  exit 1
fi

if [[ ! -d "$CONF_SRC" ]]; then
  echo "Error: $CONF_SRC not found" >&2
  exit 1
fi

# --- files ---------------------------------------------------------------------

# A manifest entry must be a single file name. Anything else — empty, a dot name,
# a path — could point outside the directory, so it is ignored rather than handed
# to rm.
valid_name() {
  [[ -n "$1" && "$1" != .* && "$1" != */* ]]
}

# Prints the file names recorded in the custom dir's manifest, one per line.
# Lines starting with # are the header.
read_manifest() {
  local manifest="$CUSTOM_DIR/$MANIFEST"
  local name

  [[ -f "$manifest" ]] || return 0
  while IFS= read -r name || [[ -n "$name" ]]; do
    [[ -n "$name" && "$name" != \#* ]] || continue
    if valid_name "$name"; then
      printf '%s\n' "$name"
    else
      warn "ignoring invalid entry '$name' in $manifest"
    fi
  done < "$manifest"
}

# Prints the helper files in this repo, one name per line.
repo_files() {
  local path
  for path in "$ZSH_SRC"/*.zsh; do
    [[ -f "$path" ]] && basename "$path"
  done
}

# Prints the example conf files in this repo, one name per line.
repo_examples() {
  local path
  for path in "$CONF_SRC"/*.conf.example; do
    [[ -f "$path" ]] && basename "$path"
  done
}

# Writes the manifest listing the names in $1, atomically.
write_manifest() {
  local manifest="$CUSTOM_DIR/$MANIFEST"

  {
    echo "# Written by $SRC_DIR/sync.sh — edit that repo, not the files listed here."
    echo "# Sync overwrites them and removes any that leave the repo."
    printf '%s\n' "$1"
  } > "$manifest.tmp"
  mv -f "$manifest.tmp" "$manifest"
}

# Copies $1 to $2 through a sibling temp file, so a run that dies part-way leaves
# the old file whole. Says what it did.
install_file() {
  local src="$1"
  local dest="$2"
  local tmp="$dest.sync-tmp"

  rm -f "$tmp"   # a leftover from a run that died part-way
  if [[ ! -e "$dest" ]]; then
    cp "$src" "$tmp" && mv -f "$tmp" "$dest"
    log "Added $dest"
  elif cmp -s "$src" "$dest"; then
    log "$dest already up to date"
  else
    cp "$src" "$tmp" && mv -f "$tmp" "$dest"
    log "Updated $dest"
  fi
}

# Sync owns exactly the files its manifest names, so those are the only ones it
# overwrites or removes. A file it never copied — yours, or another tool's — is
# never touched, which is what makes deleting without a prompt safe, including
# from a git hook. check_files has already ruled out overwriting one.
sync_files() {
  local managed name target

  mkdir -p "$CUSTOM_DIR"

  # check_files already warned about any invalid entries.
  managed="$(read_manifest 2>/dev/null)"

  # Claim every repo file before copying any. A run that dies part-way then still
  # owns what it added, rather than the next run calling it a clash.
  write_manifest "$(printf '%s\n%s\n' "$managed" "$REPO_FILES" | awk 'NF && !seen[$0]++')"

  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    install_file "$ZSH_SRC/$name" "$CUSTOM_DIR/$name"
  done <<< "$REPO_FILES"

  # Gone from the repo, and a previous run recorded copying it: remove it.
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    grep -Fxq -- "$name" <<< "$REPO_FILES" && continue
    target="$CUSTOM_DIR/$name"
    if [[ -L "$target" ]]; then
      warn "$target is now a symlink, not ours to remove; forgetting $name"
    elif [[ -e "$target" ]]; then
      rm -f "$target"
      log "Removed $target (no longer in $ZSH_SRC)"
    fi
  done <<< "$managed"

  # Only now, with the removals done, drop them from the manifest. A run that dies
  # before this still owns them and removes them next time.
  write_manifest "$REPO_FILES"

  log "Synced $CUSTOM_DIR"
}

# The .example files are always sync's: they exist to be copied from, and the
# header of each says so. The <helper>.conf beside each is never written; a
# missing one gets a hint, since without it the helper has nothing to offer.
sync_examples() {
  local name conf

  mkdir -p "$CONF_DIR"

  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    install_file "$CONF_SRC/$name" "$CONF_DIR/$name"
    conf="$CONF_DIR/${name%.example}"
    if [[ ! -e "$conf" ]]; then
      log "No $conf yet: copy $CONF_DIR/$name to $conf and fill it in"
    fi
  done <<< "$REPO_EXAMPLES"

  log "Synced $CONF_DIR"
}

# --- preflight -----------------------------------------------------------------

PROBLEMS=""
problem() {
  grep -Fxq -- "  $*" <<< "$PROBLEMS" || PROBLEMS+="  $*"$'\n'
}

# A symlink to a directory is followed; anything else at $1, or at a folder above
# it up to $HOME, cannot hold files, and writing under it would fail part-way
# through the run.
check_dir() {
  local dir="$1"

  while [[ "$dir" == "$HOME"/* ]]; do
    if [[ -L "$dir" && ! -e "$dir" ]]; then
      problem "$dir is a symlink to nothing"
      return 1
    fi
    if [[ -e "$dir" && ! -d "$dir" ]]; then
      problem "$dir is not a directory"
      return 1
    fi
    dir="$(dirname "$dir")"
  done
}

# The custom dir is created if missing, but only inside an oh-my-zsh that exists:
# writing ~/.oh-my-zsh/custom on a machine without oh-my-zsh installs nothing.
check_custom_dir() {
  check_dir "$CUSTOM_DIR" || return 0
  [[ -e "$CUSTOM_DIR" ]] && return 0
  if [[ ! -d "$(dirname "$CUSTOM_DIR")" ]]; then
    problem "$CUSTOM_DIR does not exist and neither does its parent — is oh-my-zsh installed? Set ZSH_CUSTOM to use another directory"
  fi
}

# A repo file whose name is taken by something sync never copied is a clash, and
# sync refuses to overwrite it.
check_files() {
  local managed name target

  check_dir "$CUSTOM_DIR" || return 0

  managed="$(read_manifest)"
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    target="$CUSTOM_DIR/$name"
    if grep -Fxq -- "$name" <<< "$managed"; then
      if [[ -L "$target" ]]; then
        problem "$target is recorded as synced but is now a symlink"
      elif [[ -e "$target" && ! -f "$target" ]]; then
        problem "$target is recorded as synced but is no longer a regular file"
      fi
    elif [[ -e "$target" || -L "$target" ]]; then
      problem "$target exists but sync did not put it there; move it away (it is probably the hand-copied version of this helper) or rename the file in this repo"
    fi
  done <<< "$REPO_FILES"
}

check_examples() {
  local name target

  check_dir "$CONF_DIR" || return 0

  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    target="$CONF_DIR/$name"
    if [[ -L "$target" ]]; then
      problem "$target is a symlink; writing it would replace the link with a plain file"
    elif [[ -e "$target" && ! -f "$target" ]]; then
      problem "$target is not a regular file"
    fi
  done <<< "$REPO_EXAMPLES"
}

# --- main ----------------------------------------------------------------------

REPO_FILES="$(repo_files)"
REPO_EXAMPLES="$(repo_examples)"

if [[ -z "$REPO_FILES" ]]; then
  echo "Error: no *.zsh files in $ZSH_SRC" >&2
  exit 1
fi

# Everything is checked before anything is written, so a problem in one
# destination leaves all of them exactly as they were.
check_custom_dir
check_files
check_examples

if [[ -n "$PROBLEMS" ]]; then
  echo "Error: nothing was synced:" >&2
  printf '%s' "$PROBLEMS" >&2
  exit 1
fi

sync_files
sync_examples

log "Done. Open a new shell, or run: source \${ZSH:-~/.oh-my-zsh}/oh-my-zsh.sh"
