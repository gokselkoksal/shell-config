# 00-shell-config: what the other helpers in this set share. The 00- makes
# oh-my-zsh, which loads custom/*.zsh alphabetically, load it first.
#
# Two things live here:
#
# 1. A dispatcher, so every helper with subcommands has the same shape and the
#    same contract, from one table per helper:
#
#      typeset -ga _xc_commands=(
#          'clean spm'          'Clear SPM caches'
#          'open [<query>]'     'Open a workspace'
#      )
#      xc() { _shell_config_dispatch xc "$@" }
#
#    `xc clean spm` runs _xc_clean_spm, `xc open foo` runs _xc_open foo: the
#    leading words of each key, up to the first <arg>, [opt] or -flag, name the
#    function. Two-word commands are tried before one-word ones. Arguments the
#    table does not cover go to _xc_fallback, if defined. Usage and completion
#    are generated from the same table, so there is no second list to keep in
#    sync. Contract, for every helper:
#
#      bare, -h, --help        usage on stdout, exit 0
#      unknown command,        one "<helper>: …" line and the usage on stderr,
#        missing argument        exit 2 (_shell_config_usage_error)
#      failure at runtime      one "<helper>: …" line on stderr, exit 1
#                                (_shell_config_error)
#      success                 silent, unless the output is the result
#
# 2. Conf-file reading. Per-machine lists — goto's directories — live outside
#    the synced files, in one <helper>.conf per helper under the conf dir, so
#    the helpers hold no paths and the same files work on every machine.
#
#    Conf dir: $SHELL_CONFIG_HOME, else ${XDG_CONFIG_HOME:-~/.config}/shell-config.
#
#    Conf format: one entry per line, a name, whitespace, then the value to the
#    end of the line. Blank lines and lines starting with # are skipped. In the
#    value a leading ~/ and $VARIABLES are expanded; command substitution is
#    refused. sync.sh drops a <helper>.conf.example beside each conf file and
#    never writes the conf file itself.
#
#    Entries are read when a helper runs, not when the shell starts, so a conf
#    edit takes effect in the next call.

# --- dispatch -----------------------------------------------------------------

# Prints the command words of table key $1: the leading words up to the first
# <arg>, [opt] or -flag.
_shell_config_command_words() {
    local -a words out
    words=(${=1})
    local w
    for w in "${words[@]}"; do
        [[ "$w" == [\<\[-]* ]] && break
        out+=("$w")
    done
    print -r -- "${out[*]}"
}

# Prints helper $1's table keys ($2 = "keys") or descriptions ($2 = "descs"),
# one per line, in table order.
_shell_config_table() {
    local -a table
    table=("${(@P)${:-_${1}_commands}}")
    local i start=1
    [[ "$2" == descs ]] && start=2
    for (( i = start; i <= ${#table}; i += 2 )); do
        print -r -- "${table[i]}"
    done
}

# Usage for helper $1, from its table: every key with its description, aligned.
_shell_config_usage() {
    local helper="$1" key width=0
    local -a keys descs
    keys=(${(f)"$(_shell_config_table "$helper" keys)"})
    descs=(${(f)"$(_shell_config_table "$helper" descs)"})
    for key in "${keys[@]}"; do
        (( ${#key} > width )) && width=${#key}
    done
    print -r -- "Usage: $helper <command> [args]"
    print
    local i
    for (( i = 1; i <= ${#keys}; i++ )); do
        printf '  %s %-*s  %s\n' "$helper" "$width" "${keys[i]}" "${descs[i]}"
    done
}

# "<helper>: <message>" on stderr, exit status 1. For failures at runtime.
_shell_config_error() {
    print -r -- "$1: ${@[2,-1]}" >&2
    return 1
}

# "<helper>: <message>" and the usage on stderr, exit status 2. For a command
# the table does not have, or an argument it needs and did not get.
_shell_config_usage_error() {
    print -r -- "$1: ${@[2,-1]}" >&2
    _shell_config_usage "$1" >&2
    return 2
}

# Runs helper $1 with the command line in $2…, per the contract above.
_shell_config_dispatch() {
    local helper="$1"
    shift

    if (( $# == 0 )) || [[ "$1" == -h || "$1" == --help ]]; then
        _shell_config_usage "$helper"
        return 0
    fi

    local -a words
    words=(${(f)"$(_shell_config_table "$helper" keys | while IFS= read -r key; do _shell_config_command_words "$key"; done)"})

    local fn
    if (( $# >= 2 )) && (( ${words[(I)$1 $2]} )); then
        fn="_${helper}_${1//-/_}_${2//-/_}"
        shift 2
        "$fn" "$@"
    elif (( ${words[(I)$1]} )); then
        fn="_${helper}_${1//-/_}"
        shift
        "$fn" "$@"
    elif (( $+functions[_${helper}_fallback] )); then
        "_${helper}_fallback" "$@"
    else
        _shell_config_usage_error "$helper" "unknown command '$*'"
    fi
}

# Completion for helper $1, from its table: first words at position 2, second
# words at position 3, each with its description. Anything past the command
# words goes to _<helper>_complete_args, if defined, which sees $words and
# $CURRENT as any completer does. For use inside a completer only, since
# _describe exists only once compinit has run.
_shell_config_complete() {
    local helper="$1" key desc i
    local -a keys descs cmd entries
    keys=(${(f)"$(_shell_config_table "$helper" keys)"})
    descs=(${(f)"$(_shell_config_table "$helper" descs)"})

    case "$CURRENT" in
        2)
            # One entry per first word. A word that stands alone keeps its own
            # description; a group of two-word commands is described by its verbs.
            local -A desc_of
            local -a firsts verbs
            local first
            for (( i = 1; i <= ${#keys}; i++ )); do
                cmd=(${=$(_shell_config_command_words "${keys[i]}")})
                (( ${#cmd} )) || continue
                first="${cmd[1]}"
                (( ${+desc_of[$first]} )) || firsts+=("$first")
                if (( ${#cmd} == 1 )); then
                    desc_of[$first]="${descs[i]}"
                elif [[ -z "${desc_of[$first]}" || "${desc_of[$first]}" == *"${(j:, :)verbs}"* ]]; then
                    verbs=(${(s:, :)desc_of[$first]} "${cmd[2]}")
                    desc_of[$first]="${(j:, :)verbs}"
                fi
            done
            for first in "${firsts[@]}"; do
                entries+=("${first//:/\\:}:${desc_of[$first]}")
            done
            _describe 'command' entries
            ;;
        3)
            for (( i = 1; i <= ${#keys}; i++ )); do
                cmd=(${=$(_shell_config_command_words "${keys[i]}")})
                (( ${#cmd} == 2 )) && [[ "${cmd[1]}" == "${words[2]}" ]] || continue
                entries+=("${cmd[2]//:/\\:}:${descs[i]}")
            done
            (( ${#entries} )) && _describe 'command' entries
            (( $+functions[_${helper}_complete_args] )) && "_${helper}_complete_args"
            ;;
        *)
            (( $+functions[_${helper}_complete_args] )) && "_${helper}_complete_args"
            ;;
    esac
}

# --- conf files ---------------------------------------------------------------

_shell_config_home() {
    print -r -- "${SHELL_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/shell-config}"
}

# Path of helper $1's conf file.
_shell_config_file() {
    print -r -- "$(_shell_config_home)/$1.conf"
}

# Prints helper $1's entries as "name<TAB>value" lines. Returns 2 with no output
# when the conf file does not exist.
_shell_config_entries() {
    # A user's nounset would abort on an unset $VAR in a value and drop every
    # entry after it; a user's IFS would break the split below.
    setopt localoptions unset
    local IFS=$' \t\n\0'
    local conf name value
    conf="$(_shell_config_file "$1")"
    [[ -f "$conf" ]] || return 2
    while read -r name value || [[ -n "$name" ]]; do
        # A file saved with CRLF line endings would keep \r in every value.
        name="${name%$'\r'}"
        value="${value%$'\r'}"
        [[ -z "$name" || "$name" == \#* ]] && continue
        if [[ -z "$value" ]]; then
            print -r -- "shell-config: $conf: '$name' has no value, skipped" >&2
            continue
        fi
        # (e) would run these; a conf file should not execute anything.
        if [[ "$value" == *'$('* || "$value" == *'`'* ]]; then
            print -r -- "shell-config: $conf: '$name' contains command substitution, skipped" >&2
            continue
        fi
        # Only ~ alone or ~/… is the home directory; ~user/… is left to zsh.
        if [[ "$value" == '~' || "$value" == '~/'* ]]; then
            value="$HOME${value#\~}"
        fi
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

# Prints the value for name $2 in helper $1's conf. Returns 1 if there is none,
# 2 if the conf file does not exist. The first match wins.
_shell_config_lookup() {
    local name value
    [[ -f "$(_shell_config_file "$1")" ]] || return 2
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

# Completion for helper $1's conf: offers each name with its value as the
# description. $2 is the word for one entry ("location"). For use inside a
# completer only.
_shell_config_describe() {
    local name value
    local -a entries
    _shell_config_entries "$1" 2>/dev/null | while IFS=$'\t' read -r name value; do
        # _describe splits on the first unescaped colon.
        entries+=("${name//:/\\:}:${value}")
    done
    _describe "$2" entries
}
