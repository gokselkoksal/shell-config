# sshto: ssh to a host by name.
#
#   sshto          - list the names
#   sshto <name>   - ssh to it
#
# Names and targets come from sshto.conf in the shell-config conf dir — see
# shell-config.zsh for where that is and the file's format. The target is what
# ssh gets: user@host, or a Host alias from ~/.ssh/config. For example:
#
#   studio  me@studio-mac-mini
#   box     devbox

sshto() {
    if [[ -z "$1" ]]; then
        echo "Usage: sshto <host>"
        _shell_config_list sshto hosts
        return 1
    fi

    local target
    if ! target="$(_shell_config_lookup sshto "$1")"; then
        echo "Unknown host: $1" >&2
        return 1
    fi

    echo "Connecting to $target..."
    ssh "$target"
}

_sshto_complete() {
    local -a names
    names=(${(f)"$(_shell_config_names sshto 2>/dev/null)"})
    compadd -a names
}
(( $+functions[compdef] )) && compdef _sshto_complete sshto
