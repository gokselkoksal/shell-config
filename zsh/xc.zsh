# xc — Xcode, simulator and cache helpers. Nothing to configure.
#
# Commands:
#   xc clean spm                  Clear SPM caches
#   xc clean derived [project]    Clear all derived data, or only data matching <project>
#   xc clean all                  Clear SPM caches and all derived data
#   xc sim shake                  Pick booted simulator(s) to shake (requires jq)
#   xc sim shake all              Shake all booted simulators (requires jq)
#   xc sim shake <UDID>           Shake a specific simulator
#   xc sim <anything else>        Passed through to xcrun simctl
#   xc open                       Open the .xcworkspace in the current directory
#   xc open -l, --list            List every workspace below the current directory
#   xc open -s, --search <q>      Open the workspace whose name contains <q>
#   xc version                    Show the active Xcode version
#   xc version path               Show the active Xcode developer path
#   xc version set <version>      Switch to /Applications/Xcode-<version>.app
#   xc version name <name>        Switch to /Applications/<name>.app
#   xc version reset              Switch to /Applications/Xcode.app

# ---- clean -----------------------------------------------------------------

_xc_clean_spm() {
  echo "Clearing SPM caches..."
  rm -rf ~/Library/Caches/org.swift.swiftpm
  rm -rf ~/Library/org.swift.swiftpm
  rm -rf ~/.swiftpm/cache
  echo "Done. SPM caches cleared."
}

_xc_clean_derived() {
  local target="$1"
  local base=~/Library/Developer/Xcode/DerivedData

  if [[ -n "$target" ]]; then
    # (N) is required: without it an unmatched glob aborts the function
    # before the error message below can run.
    local matches=("${base}"/${target}*(N))
    if (( ${#matches[@]} == 0 )); then
      echo "No derived data found matching: $target" >&2
      return 1
    fi
    for d in "${matches[@]}"; do
      echo "Removing: $d"
      rm -rf "$d"
    done
    echo "Done."
  else
    echo "Clearing all Derived Data..."
    rm -rf "$base"
    echo "Done. Derived Data cleared."
  fi
}

_xc_clean() {
  case "$1" in
    spm)     _xc_clean_spm ;;
    derived) _xc_clean_derived "$2" ;;
    # Independent operations: run both even if the first one fails.
    all)     _xc_clean_spm; _xc_clean_derived ;;
    *)       [[ -n "$1" ]] && echo "xc clean: unknown command '$1'" >&2
             _xc_usage >&2
             return 1 ;;
  esac
}

# ---- sim -------------------------------------------------------------------

# Prints one "<name>\t<udid>" line per booted simulator.
_xc_sim_booted() {
  xcrun simctl list devices booted --json | jq -r '.devices[][] | select(.state == "Booted") | [.name, .udid] | @tsv'
}

_xc_sim_post_shake() {
  local udid rc=0
  for udid in "$@"; do
    echo "Shaking $udid"
    xcrun simctl notify_post "$udid" com.apple.UIKit.SimulatorShake || rc=1
  done
  return $rc
}

# Usage: xc sim shake [all|UDID]   (no argument: pick from a list)
_xc_sim_shake() {
  local target="$1"

  # A UDID needs no lookup, so it works without jq.
  if [[ -n "$target" && "$target" != "all" ]]; then
    _xc_sim_post_shake "$target"
    return $?
  fi

  # Without jq there is no list to pick from, but "booted" is a target simctl
  # resolves itself when exactly one simulator is up.
  if (( ! $+commands[jq] )); then
    if [[ -z "$target" ]]; then
      _xc_sim_post_shake booted
      return $?
    fi
    echo "xc: jq not found (brew install jq)" >&2
    return 1
  fi

  local lines=("${(@f)$(_xc_sim_booted)}")
  # (@f) on empty output yields one empty element
  lines=("${(@)lines:#}")
  if (( ${#lines[@]} == 0 )); then
    echo "No booted simulators." >&2
    return 1
  fi

  local names=() udids=() line
  for line in "${lines[@]}"; do
    names+=("${line%%$'\t'*}")
    udids+=("${line##*$'\t'}")
  done

  if [[ "$target" == "all" ]] || (( ${#udids[@]} == 1 )); then
    _xc_sim_post_shake "${udids[@]}"
    return $?
  fi

  echo "Booted simulators:"
  echo ""
  local i
  for i in {1..${#udids[@]}}; do
    echo "  $i. ${names[$i]} (${udids[$i]})"
  done
  echo ""

  local choice
  read -r "choice?Select simulator(s) to shake (e.g. 1 3, or 'a' for all): "

  local picked=() tok
  if [[ "${choice:l}" == a || "${choice:l}" == all ]]; then
    picked=("${udids[@]}")
  else
    for tok in ${=choice//,/ }; do
      if ! [[ "$tok" =~ ^[0-9]+$ ]] || (( tok < 1 || tok > ${#udids[@]} )); then
        echo "Invalid selection: $tok" >&2
        return 1
      fi
      picked+=("${udids[$tok]}")
    done
    if (( ${#picked[@]} == 0 )); then
      echo "Nothing selected." >&2
      return 1
    fi
  fi

  _xc_sim_post_shake "${picked[@]}"
}

_xc_sim() {
  case "$1" in
    shake) _xc_sim_shake "$2" ;;
    "")    _xc_usage >&2
           return 1 ;;
    *)     xcrun simctl "$@" ;;
  esac
}

# ---- version ---------------------------------------------------------------

# Switches the active Xcode to /Applications/<name>.app
_xc_version_name() {
  if [[ -z "$1" ]]; then
    echo "Usage: xc version name <app-name>" >&2
    return 1
  fi

  local app="/Applications/$1.app"

  # Validate before invoking sudo, so a typo fails fast and visibly
  # instead of silently pointing xcode-select at a missing path.
  if [[ ! -d "$app" ]]; then
    echo "Error: $app does not exist." >&2
    local installed=(/Applications/Xcode*.app(N))
    if (( ${#installed[@]} )); then
      echo "Installed Xcode versions:" >&2
      printf '  %s\n' "${installed[@]:t:r}" >&2
    fi
    return 1
  fi

  sudo xcode-select -s "$app/Contents/Developer" && xcode-select --print-path
}

_xc_version() {
  case "$1" in
    "")    xcodebuild -version ;;
    path)  xcode-select --print-path ;;
    set)   if [[ -z "$2" ]]; then
             echo "Usage: xc version set <version>" >&2
             return 1
           fi
           _xc_version_name "Xcode-$2" ;;
    name)  _xc_version_name "$2" ;;
    reset) _xc_version_name Xcode ;;
    *)     echo "xc version: unknown command '$1'" >&2
           _xc_usage >&2
           return 1 ;;
  esac
}

# ---- open ------------------------------------------------------------------

_xc_open_close_others() {
  # Skip if Xcode isn't running
  pgrep -x Xcode >/dev/null 2>&1 || return 0

  local dir="$1"
  local target="$2"
  local open_paths

  open_paths=$(osascript - "$dir" "$target" 2>/dev/null <<'APPLESCRIPT'
on run argv
  set dirPath to item 1 of argv
  set targetPath to item 2 of argv
  set output to ""
  tell application "Xcode"
    repeat with doc in (every workspace document)
      set p to path of doc
      if p starts with dirPath and p is not equal to targetPath then
        set output to output & p & linefeed
      end if
    end repeat
  end tell
  return output
end run
APPLESCRIPT
)

  [[ -z "$open_paths" ]] && return 0

  echo "Xcode has other workspace(s) open from this directory:"
  echo "$open_paths" | while IFS= read -r p; do
    [[ -n "$p" ]] && echo "  - $p"
  done

  local confirm
  read -r "confirm?Close before opening? (y/N): "
  if [[ "$confirm" == [yY]* ]]; then
    osascript - "$dir" "$target" >/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
  set dirPath to item 1 of argv
  set targetPath to item 2 of argv
  tell application "Xcode"
    -- Collect first, then close: mutating the collection while iterating
    -- over it can skip documents.
    set toClose to {}
    repeat with doc in (every workspace document)
      set p to path of doc
      if p starts with dirPath and p is not equal to targetPath then
        set end of toClose to doc
      end if
    end repeat
    repeat with doc in toClose
      close doc
    end repeat
  end tell
end run
APPLESCRIPT
    echo "Closed."
  fi
}

_xc_open_find_all() {
  find . \
    \( -name .build -o -name .swiftpm -o -name .git -o -name node_modules \
       -o -name DerivedData -o -name Pods -o -name React \
       -o -name Carthage -o -name "*.xcodeproj" \) -prune \
    -o -name "*.xcworkspace" -print \
    | sed 's|^\./||' | sort -t/ -k1,1
}

_xc_open_open() {
  local ws="$1"
  _xc_open_close_others "$(pwd)" "$(pwd)/$ws"
  echo "Opening $ws"
  open "$ws"
}

_xc_open_select() {
  local workspaces=("$@")

  # Nothing to pick between — just open it.
  if (( ${#workspaces[@]} == 1 )); then
    _xc_open_open "${workspaces[1]}"
    return $?
  fi

  echo "Workspaces found:"
  echo ""
  local i
  for i in {1..${#workspaces[@]}}; do
    echo "  $i. ${workspaces[$i]}"
  done
  echo ""

  local choice
  read -r "choice?Select a workspace (1-${#workspaces[@]}): "

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#workspaces[@]} )); then
    echo "Invalid selection." >&2
    return 1
  fi

  _xc_open_open "${workspaces[$choice]}"
}


_xc_open() {
  local mode="default"
  local query=""

  case "${1-}" in
    "")        mode="default" ;;
    -l|--list) mode="list" ;;
    -s|--search)
      mode="search"
      query="${2-}"
      if [[ -z "$query" ]]; then
        echo "Usage: xc open -s <query>" >&2
        return 1
      fi
      ;;
    -h|--help)
      _xc_usage
      return 0
      ;;
    *)
      echo "xc open: unknown option '$1'" >&2
      _xc_usage >&2
      return 1
      ;;
  esac

  if [[ "$mode" == "default" ]]; then
    local root_ws=(*.xcworkspace(N))
    if (( ${#root_ws[@]} == 0 )); then
      echo "No Xcode workspaces found in $(pwd)" >&2
      return 1
    fi
    _xc_open_open "${root_ws[1]}"
    return 0
  fi

  local workspaces=()

  echo "Scanning for workspaces..."

  while IFS= read -r ws; do
    workspaces+=("$ws")
  done < <(_xc_open_find_all)

  if (( ${#workspaces[@]} == 0 )); then
    echo "No Xcode workspaces found in $(pwd)" >&2
    return 1
  fi

  if [[ "$mode" == "search" ]]; then
    local matches=()
    local ws name
    for ws in "${workspaces[@]}"; do
      name="${ws:t}"
      if [[ "${name:l}" == *"${query:l}"* ]]; then
        matches+=("$ws")
      fi
    done

    if (( ${#matches[@]} == 0 )); then
      echo "No workspaces matching \"$query\"" >&2
      return 1
    fi

    _xc_open_select "${matches[@]}"
    return $?
  fi

  _xc_open_select "${workspaces[@]}"
}

# ---- dispatch --------------------------------------------------------------

_xc_usage() {
  echo "Usage:"
  echo "  xc clean spm                  Clear SPM caches"
  echo "  xc clean derived [project]    Clear all derived data, or only data matching <project>"
  echo "  xc clean all                  Clear SPM caches and all derived data"
  echo "  xc sim shake                  Pick booted simulator(s) to shake (requires jq)"
  echo "  xc sim shake all              Shake all booted simulators (requires jq)"
  echo "  xc sim shake <UDID>           Shake a specific simulator"
  echo "  xc sim <anything else>        Passed through to xcrun simctl"
  echo "  xc open                       Open the .xcworkspace in the current directory"
  echo "  xc open -l, --list            List every workspace below the current directory"
  echo "  xc open -s, --search <q>      Open the workspace whose name contains <q>"
  echo "  xc version                    Show the active Xcode version"
  echo "  xc version path               Show the active Xcode developer path"
  echo "  xc version set <version>      Switch to /Applications/Xcode-<version>.app"
  echo "  xc version name <name>        Switch to /Applications/<name>.app"
  echo "  xc version reset              Switch to /Applications/Xcode.app"
}

xc() {
  case "$1" in
    clean)   shift; _xc_clean "$@" ;;
    sim)     shift; _xc_sim "$@" ;;
    open)    shift; _xc_open "$@" ;;
    version) shift; _xc_version "$@" ;;
    ""|-h|--help) _xc_usage ;;
    *)       echo "xc: unknown command '$1'" >&2
             _xc_usage >&2
             return 1 ;;
  esac
}

# ---- completion ------------------------------------------------------------

_xc() {
  local -a cmds
  case $CURRENT in
    2)
      cmds=(
        'clean:Clear SPM caches and derived data'
        'sim:Simulator helpers'
        'open:Open an Xcode workspace'
        'version:Show or switch the active Xcode'
      )
      _describe 'command' cmds ;;
    3)
      case "${words[2]}" in
        clean)   cmds=('spm:Clear SPM caches' 'derived:Clear derived data' 'all:Clear SPM caches and derived data') ;;
        sim)     cmds=('shake:Shake simulators') ;;
        open)    cmds=('-l:List workspaces' '--list:List workspaces' '-s:Open workspace by name' '--search:Open workspace by name') ;;
        version) cmds=('path:Show developer path' 'set:Switch to Xcode-<version>' 'name:Switch to /Applications/<name>.app' 'reset:Switch to Xcode.app') ;;
      esac
      (( ${#cmds[@]} )) && _describe 'subcommand' cmds ;;
    4)
      case "${words[2]} ${words[3]}" in
        "clean derived")
          local -a projects
          projects=(~/Library/Developer/Xcode/DerivedData/*(N:t))
          _describe 'project' projects ;;
        "sim shake")
          cmds=('all:All booted simulators')
          if (( $+commands[jq] )); then
            local line
            for line in "${(@f)$(_xc_sim_booted 2>/dev/null)}"; do
              [[ -n "$line" ]] && cmds+=("${line##*$'\t'}:${line%%$'\t'*}")
            done
          fi
          _describe 'target' cmds ;;
        "version set")
          local -a versions
          versions=(/Applications/Xcode-*.app(N:t:r))
          versions=("${versions[@]#Xcode-}")
          _describe 'version' versions ;;
        "version name")
          local -a apps
          apps=(/Applications/Xcode*.app(N:t:r))
          _describe 'app' apps ;;
      esac ;;
  esac
}
if (( $+functions[compdef] )); then
  compdef _xc xc
fi
