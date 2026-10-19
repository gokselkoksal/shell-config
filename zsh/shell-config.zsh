# shell-config: what the other helpers in this set share.
#
# Per-machine lists — goto's directories, sshto's hosts — live outside the synced
# files, in one <helper>.conf per helper under the conf dir, so the helpers
# themselves hold no paths or hosts and the same files work on every machine.
#
# Conf dir: $SHELL_CONFIG_HOME, else ${XDG_CONFIG_HOME:-~/.config}/shell-config.
#
# Conf format: one entry per line, a name, whitespace, then the value to the end
# of the line. Blank lines and lines starting with # are skipped. In the value a
# leading ~ and $VARIABLES are expanded — the file is trusted like ~/.zshrc, so
# put nothing in it you would not put there. sync.sh drops a <helper>.conf.example
# beside each conf file and never writes the conf file itself.
#
# Everything here is read when a helper runs, not when the shell starts, so a
# conf edit takes effect in the next call and the load order of these files does
# not matter.

_shell_config_home() {
    print -r -- "${SHELL_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/shell-config}"
}

# Path of helper $1's conf file.
_shell_config_file() {
    print -r -- "$(_shell_config_home)/$1.conf"
}

# Prints helper $1's entries as "name<TAB>value" lines. Returns 1 with no output
# when the conf file does not exist.
_shell_config_entries() {
    local conf name value
    conf="$(_shell_config_file "$1")"
    [[ -f "$conf" ]] || return 1
    while read -r name value || [[ -n "$name" ]]; do
        [[ -z "$name" || "$name" == \#* ]] && continue
        if [[ -z "$value" ]]; then
            print -r -- "shell-config: $conf: '$name' has no value, skipped" >&2
            continue
        fi
        value="${value/#\~/$HOME}"
        value="${(e)value}"
        print -r -- "$name"$'\t'"$value"
    done < "$conf"
}

# Prints the names in helper $1's conf, one per line.
_shell_config_names() {
    local name value
    _shell_config_entries "$1" | while IFS=$'\t' read -r name value; do
        print -r -- "$name"
    done
}

# Prints the value for name $2 in helper $1's conf; returns 1 if there is none.
# The first match wins.
_shell_config_lookup() {
    local name value
    # zsh runs the last part of a pipeline in the current shell, so this return
    # leaves the function, not just the loop.
    _shell_config_entries "$1" | while IFS=$'\t' read -r name value; do
        if [[ "$name" == "$2" ]]; then
            print -r -- "$value"
            return 0
        fi
    done
    return 1
}

# Prints the "Available …" list for helper $1 as "name -> value" lines, or where
# to configure it when its conf file is missing or empty. $2 is the word for the
# entries ("locations").
_shell_config_list() {
    local conf name value width=0
    local -a names values
    conf="$(_shell_config_file "$1")"
    _shell_config_entries "$1" | while IFS=$'\t' read -r name value; do
        names+=("$name")
        values+=("$value")
        (( ${#name} > width )) && width=${#name}
    done
    if [[ ! -f "$conf" ]]; then
        print -r -- "No $2 configured: create $conf (see $conf.example)."
    elif (( ${#names} == 0 )); then
        print -r -- "No $2 configured: $conf has no entries (see $conf.example)."
    else
        print -r -- "Available $2:"
        local i
        for (( i = 1; i <= ${#names}; i++ )); do
            printf '  %-*s -> %s\n' "$width" "${names[i]}" "${values[i]}"
        done
    fi
}

# Completion for helper $1: offers each name with its value as the description.
# $2 is the word for one entry ("location"). For use inside a completer only,
# since _describe exists only once compinit has run.
_shell_config_describe() {
    local name value
    local -a entries
    _shell_config_entries "$1" 2>/dev/null | while IFS=$'\t' read -r name value; do
        # _describe splits on the first unescaped colon.
        entries+=("${name//:/\\:}:${value}")
    done
    _describe "$2" entries
}
