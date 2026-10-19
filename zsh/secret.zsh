# secret: secrets in the macOS keychain. Nothing to configure.
#
#   secret set <service>    - add or update one; the value is asked for by
#                             security itself, so it never appears on a command
#                             line, in history or in the process list
#   secret get <service>    - print it
#   secret copy <service>   - put it on the clipboard without printing it
#   secret rm <service>     - remove it
#   secret list             - the services this tool stores
#
# Each one is a generic password for the current account ("$USER") with a fixed
# comment, which is how list and rm find exactly the items this tool created and
# nothing else in the keychain.

typeset -ga _secret_commands=(
    'set <service>'   'Add or update a secret; the value is prompted for'
    'get <service>'   'Print a secret'
    'copy <service>'  'Copy a secret to the clipboard'
    'rm <service>'    'Remove a secret'
    'list'            'List the services this tool stores'
)

_SECRET_TAG="shell-config secret"

_secret_need_service() {
    [[ -n "$1" ]] && return 0
    _shell_config_usage_error secret "$2 needs a <service>"
}

# True when $1 is an item this tool created. find-generic-password's -j does not
# filter, so the tag is checked in the attributes it prints.
_secret_owned() {
    local attrs
    attrs="$(security find-generic-password -a "$USER" -s "$1" 2>/dev/null)" || return 1
    [[ "$attrs" == *"\"icmt\"<blob>=\"$_SECRET_TAG\""* ]]
}

_secret_set() {
    _secret_need_service "$1" set || return
    # -U updates an existing item instead of failing. -w with no value makes
    # security read the secret from the terminal, twice, with echo off.
    security add-generic-password -U -a "$USER" -s "$1" -j "$_SECRET_TAG" -w \
        || _shell_config_error secret "could not store '$1'"
}

_secret_get() {
    _secret_need_service "$1" get || return
    security find-generic-password -a "$USER" -s "$1" -w 2>/dev/null \
        || _shell_config_error secret "no secret for '$1'"
}

_secret_copy() {
    _secret_need_service "$1" copy || return
    local value
    value="$(security find-generic-password -a "$USER" -s "$1" -w 2>/dev/null)" \
        || { _shell_config_error secret "no secret for '$1'"; return; }
    printf '%s' "$value" | pbcopy
}

_secret_rm() {
    _secret_need_service "$1" rm || return
    if ! _secret_owned "$1"; then
        _shell_config_error secret "no secret for '$1' (items not created by secret are left alone)"
        return
    fi
    security delete-generic-password -a "$USER" -s "$1" >/dev/null 2>&1 \
        || _shell_config_error secret "could not remove '$1'"
}

# Prints the services of the items this tool created, one per line. dump-keychain
# lists attributes only, never values, and does not prompt.
_secret_services() {
    security dump-keychain 2>/dev/null | awk -v tag="\"$_SECRET_TAG\"" -v acct="\"$USER\"" '
        /^keychain: / { if (ours && mine && svc != "") print svc; ours = 0; mine = 0; svc = "" }
        /"icmt"<blob>=/ { if (index($0, tag)) ours = 1 }
        /"acct"<blob>=/ { if (index($0, acct)) mine = 1 }
        /"svce"<blob>=/ { sub(/.*"svce"<blob>="/, ""); sub(/"$/, ""); svc = $0 }
        END { if (ours && mine && svc != "") print svc }
    ' | sort -u
}

_secret_list() {
    _secret_services
}

secret() {
    _shell_config_dispatch secret "$@"
}

_secret_complete_args() {
    case "${words[2]}" in
        get|copy|rm)
            (( CURRENT == 3 )) || return
            local -a services
            services=(${(f)"$(_secret_services)"})
            (( ${#services} )) && _describe 'service' services
            ;;
    esac
}

_secret_complete() {
    _shell_config_complete secret
}
if (( $+functions[compdef] )); then
    compdef _secret_complete secret
fi
