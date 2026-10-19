# goto: jump to a directory by name.
#
#   goto          - list the names
#   goto <name>   - cd to its directory
#
# Names and directories come from goto.conf in the shell-config conf dir — see
# shell-config.zsh for where that is and the file's format. For example:
#
#   docs   ~/Documents
#   repos  $HOME/Development/Repos

goto() {
    if [[ -z "$1" ]]; then
        echo "Usage: goto <location>"
        _shell_config_list goto locations
        return 1
    fi

    local directory
    if ! directory="$(_shell_config_lookup goto "$1")"; then
        echo "Unknown location: $1" >&2
        return 1
    fi

    cd "$directory" || return 1
    echo "Changed to $directory"
}

_goto_complete() {
    local -a names
    names=(${(f)"$(_shell_config_names goto 2>/dev/null)"})
    compadd -a names
}
(( $+functions[compdef] )) && compdef _goto_complete goto
