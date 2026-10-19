# xc: Xcode, simulator and cache helpers. Nothing to configure.
#
# Run `xc` for the command list. `xc sim <anything but shake>` passes through to
# `xcrun simctl`. Picking a simulator to shake needs jq; everything else needs
# only Xcode.

typeset -ga _xc_commands=(
    'clean spm'                  'Clear SPM caches'
    'clean derived [project]'    'Clear all derived data, or only the folders matching <project>'
    'clean all'                  'Clear SPM caches and all derived data'
    'sim shake [all|<udid>]'     'Shake booted simulators: pick from a list, all, or one (needs jq to list)'
    'sim <simctl args…>'         'Pass through to xcrun simctl'
    'open [<query>|--list]'      'Open the workspace here, or the one below here whose name matches'
    'version'                    'Show the active Xcode version'
    'version path'               'Show the active Xcode developer path'
    'version use <version|app>'  'Switch to /Applications/Xcode-<version>.app, or /Applications/<app>.app'
    'version reset'              'Switch to /Applications/Xcode.app'
)

xc() {
    _shell_config_dispatch xc "$@"
}

# ---- clean -----------------------------------------------------------------

_xc_clean_spm() {
    rm -rf ~/Library/Caches/org.swift.swiftpm ~/Library/org.swift.swiftpm ~/.swiftpm/cache
    print -r -- "Cleared SPM caches"
}

_xc_clean_derived() {
    local target="$1"
    local base=~/Library/Developer/Xcode/DerivedData

    if [[ -n "$target" ]]; then
        # (N): an unmatched glob would otherwise abort the function before the
        # message below.
        local -a matches
        matches=("$base"/${target}*(N))
        if (( ${#matches} == 0 )); then
            _shell_config_error xc "no derived data matching '$target'"
            return
        fi
        local d
        for d in "${matches[@]}"; do
            rm -rf "$d"
            print -r -- "Removed $d"
        done
    else
        rm -rf "$base"
        print -r -- "Cleared derived data"
    fi
}

_xc_clean_all() {
    # Independent operations: run both even if the first one fails.
    local rc=0
    _xc_clean_spm || rc=1
    _xc_clean_derived || rc=1
    return $rc
}

# ---- sim -------------------------------------------------------------------

# Prints one "<name>\t<udid>" line per booted simulator. Fails when simctl does,
# which is not the same as no simulator being booted.
_xc_sim_booted() {
    local json
    json="$(xcrun simctl list devices booted --json)" || return 1
    jq -r '.devices[][] | select(.state == "Booted") | [.name, .udid] | @tsv' <<< "$json"
}

_xc_sim_post_shake() {
    local udid rc=0
    for udid in "$@"; do
        xcrun simctl notify_post "$udid" com.apple.UIKit.SimulatorShake || rc=1
    done
    return $rc
}

_xc_sim_shake() {
    local target="$1"

    if (( ! $+commands[xcrun] )); then
        _shell_config_error xc "xcrun not found; is Xcode installed and selected?"
        return
    fi

    # A UDID needs no lookup, so it works without jq.
    if [[ -n "$target" && "$target" != all ]]; then
        _xc_sim_post_shake "$target"
        return
    fi

    # Without jq there is no list to pick from, but "booted" is a target simctl
    # resolves itself when exactly one simulator is up.
    if (( ! $+commands[jq] )); then
        if [[ -z "$target" ]]; then
            _xc_sim_post_shake booted
            return
        fi
        _shell_config_error xc "jq not found (brew install jq); needed to list simulators"
        return
    fi

    local -a lines
    local out
    if ! out="$(_xc_sim_booted)"; then
        _shell_config_error xc "xcrun simctl failed; is Xcode installed and selected?"
        return
    fi
    lines=("${(@f)out}")
    lines=("${(@)lines:#}")   # (@f) on empty output yields one empty element
    if (( ${#lines} == 0 )); then
        _shell_config_error xc "no booted simulators"
        return
    fi

    local -a names udids
    local line
    for line in "${lines[@]}"; do
        names+=("${line%%$'\t'*}")
        udids+=("${line##*$'\t'}")
    done

    if [[ "$target" == all ]] || (( ${#udids} == 1 )); then
        _xc_sim_post_shake "${udids[@]}"
        return
    fi

    print -r -- "Booted simulators:"
    print
    local i
    for (( i = 1; i <= ${#udids}; i++ )); do
        print -r -- "  $i. ${names[i]} (${udids[i]})"
    done
    print

    local choice
    read -r "choice?Select simulator(s) to shake (e.g. 1 3, or 'a' for all): "

    local -a picked
    local tok
    if [[ "${choice:l}" == a || "${choice:l}" == all ]]; then
        picked=("${udids[@]}")
    else
        for tok in ${=choice//,/ }; do
            if ! [[ "$tok" =~ ^[0-9]+$ ]] || (( tok < 1 || tok > ${#udids} )); then
                _shell_config_error xc "invalid selection '$tok'"
                return
            fi
            picked+=("${udids[tok]}")
        done
        if (( ${#picked} == 0 )); then
            _shell_config_error xc "nothing selected"
            return
        fi
    fi

    _xc_sim_post_shake "${picked[@]}"
}

# Everything under `xc sim` that is not shake goes to simctl.
_xc_sim() {
    if (( $# == 0 )); then
        _shell_config_usage_error xc "sim needs a command"
        return
    fi
    xcrun simctl "$@"
}

# ---- version ---------------------------------------------------------------

_xc_version() {
    xcodebuild -version
}

_xc_version_path() {
    xcode-select --print-path
}

# Switches the active Xcode to /Applications/Xcode-<arg>.app, else /Applications/<arg>.app.
_xc_version_use() {
    if [[ -z "$1" ]]; then
        _shell_config_usage_error xc "version use needs a <version> or <app> name"
        return
    fi

    local app
    if [[ -d "/Applications/Xcode-$1.app" ]]; then
        app="/Applications/Xcode-$1.app"
    elif [[ -d "/Applications/$1.app" ]]; then
        app="/Applications/$1.app"
    else
        # Fail here, visibly, rather than let sudo xcode-select point at nothing.
        _shell_config_error xc "neither /Applications/Xcode-$1.app nor /Applications/$1.app exists"
        local -a installed
        installed=(/Applications/Xcode*.app(N))
        if (( ${#installed} )); then
            print -r -- "Installed:" >&2
            printf '  %s\n' "${installed[@]:t:r}" >&2
        fi
        return 1
    fi

    sudo xcode-select -s "$app/Contents/Developer" && xcode-select --print-path
}

_xc_version_reset() {
    _xc_version_use Xcode
}

# ---- open ------------------------------------------------------------------

# Lists, and on request closes, the workspaces Xcode has open from under $1 other
# than $2. $1 must end in /, so a sibling folder with the same prefix (App vs
# AppKit) does not count as "under".
_xc_open_close_others() {
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

    print -r -- "Xcode has other workspaces open from this directory:"
    local p
    while IFS= read -r p; do
        [[ -n "$p" ]] && print -r -- "  - $p"
    done <<< "$open_paths"

    local confirm
    read -r "confirm?Close them before opening? (y/N): "
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
    fi
}

# Prints every workspace below the current directory, skipping build output,
# dependencies and the workspaces embedded in .xcodeproj bundles.
_xc_open_find_all() {
    find . \
        \( -name .build -o -name .swiftpm -o -name .git -o -name node_modules \
           -o -name DerivedData -o -name Pods -o -name React \
           -o -name Carthage -o -name "*.xcodeproj" \) -prune \
        -o -name "*.xcworkspace" -print \
        | sed 's|^\./||' | sort -t/ -k1,1
}

_xc_open_one() {
    local ws="$1"
    _xc_open_close_others "$PWD/" "$PWD/$ws"
    open "$ws"
}

# Opens the one workspace in $@, or asks which when there are several.
_xc_open_select() {
    local -a workspaces
    workspaces=("$@")

    if (( ${#workspaces} == 1 )); then
        _xc_open_one "${workspaces[1]}"
        return
    fi

    print -r -- "Workspaces found:"
    print
    local i
    for (( i = 1; i <= ${#workspaces}; i++ )); do
        print -r -- "  $i. ${workspaces[i]}"
    done
    print

    local choice
    read -r "choice?Select a workspace (1-${#workspaces}): "

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#workspaces} )); then
        _shell_config_error xc "invalid selection"
        return
    fi

    _xc_open_one "${workspaces[choice]}"
}

_xc_open() {
    local -a workspaces

    case "${1-}" in
        "")
            workspaces=(*.xcworkspace(N))
            if (( ${#workspaces} == 0 )); then
                _shell_config_error xc "no workspace in $PWD; try xc open --list"
                return
            fi
            _xc_open_select "${workspaces[@]}"
            return
            ;;
        -l|--list)
            workspaces=(${(f)"$(_xc_open_find_all)"})
            if (( ${#workspaces} == 0 )); then
                _shell_config_error xc "no workspaces below $PWD"
                return
            fi
            print -rl -- "${workspaces[@]}"
            return 0
            ;;
        -*)
            _shell_config_usage_error xc "open: unknown option '$1'"
            return
            ;;
    esac

    local query="$1"
    workspaces=(${(f)"$(_xc_open_find_all)"})
    if (( ${#workspaces} == 0 )); then
        _shell_config_error xc "no workspaces below $PWD"
        return
    fi

    local -a matches
    local ws
    for ws in "${workspaces[@]}"; do
        [[ "${ws:t:l}" == *"${query:l}"* ]] && matches+=("$ws")
    done
    if (( ${#matches} == 0 )); then
        _shell_config_error xc "no workspace matching '$query'; try xc open --list"
        return
    fi

    _xc_open_select "${matches[@]}"
}

# ---- completion ------------------------------------------------------------

# Arguments past the command words: the table covers the words themselves.
_xc_complete_args() {
    local -a items
    case "${words[2]} ${words[3]}" in
        "clean derived")
            (( CURRENT == 4 )) || return
            items=(~/Library/Developer/Xcode/DerivedData/*(N:t))
            (( ${#items} )) && _describe 'project' items
            ;;
        "sim shake")
            (( CURRENT == 4 )) || return
            items=('all:All booted simulators')
            if (( $+commands[jq] )); then
                local line
                for line in "${(@f)$(_xc_sim_booted 2>/dev/null)}"; do
                    [[ -n "$line" ]] && items+=("${line##*$'\t'}:${line%%$'\t'*}")
                done
            fi
            _describe 'target' items
            ;;
        "version use")
            (( CURRENT == 4 )) || return
            local -a apps
            apps=(/Applications/Xcode*.app(N:t:r))
            items=("${(@)${(@M)apps:#Xcode-*}#Xcode-}" "${apps[@]}")
            (( ${#items} )) && _describe 'version or app' items
            ;;
        "open "*)
            (( CURRENT == 3 )) && _describe 'option' '(--list:List workspaces below here)'
            ;;
    esac
}

_xc_complete() {
    _shell_config_complete xc
}
if (( $+functions[compdef] )); then
    compdef _xc_complete xc
fi
