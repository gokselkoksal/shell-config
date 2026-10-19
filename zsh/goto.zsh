# goto: jump to a directory by name.
#
#   goto          - list the names
#   goto <name>   - cd to its directory
#
# Names and directories come from goto.conf in the shell-config conf dir — see
# 00-shell-config.zsh for where that is and the file's format. For example:
#
#   docs   ~/Documents
#   repos  $HOME/Development/Repos
#
# Every entry is also a zsh named directory, so ~docs and ~repos/koin work in any
# command, with zsh's own completion. Those are set when this file loads and
# refreshed on every goto call, so a conf edit reaches them without a new shell.
# A name has to be a valid identifier (letters, digits, _) to become one; other
# names still work with goto.

# Defines ~name for each entry of goto.conf.
_goto_hash_dirs() {
    local name value
    _shell_config_entries goto 2>/dev/null | while IFS=$'\t' read -r name value; do
        [[ "$name" =~ '^[A-Za-z_][A-Za-z0-9_]*$' ]] || continue
        hash -d "$name=$value"
    done
}

goto() {
    _goto_hash_dirs

    if [[ "$1" == -h || "$1" == --help ]]; then
        print -r -- "Usage: goto [<name>]"
        print
        print -r -- "  goto          list the names"
        print -r -- "  goto <name>   cd to its directory; ~<name> works in any command too"
        return 0
    fi

    if [[ -z "$1" ]]; then
        _shell_config_list goto locations
        return 0
    fi

    local directory
    _shell_config_lookup goto "$1" >/dev/null
    case $? in
        2)
            local conf
            conf="$(_shell_config_file goto)"
            _shell_config_error goto "no locations configured: create $conf (see $conf.example)"
            return
            ;;
        1)
            _shell_config_error goto "unknown location '$1'; run goto for the list"
            return
            ;;
    esac
    directory="$(_shell_config_lookup goto "$1")"

    if [[ ! -d "$directory" ]]; then
        _shell_config_error goto "directory for '$1' does not exist: $directory"
        return
    fi

    cd "$directory"
}

_goto_complete() {
    _shell_config_describe goto location
}
if (( $+functions[compdef] )); then
    compdef _goto_complete goto
fi

_goto_hash_dirs
