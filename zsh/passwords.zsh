# Passwords in the macOS keychain. Nothing to configure.
#
#   add-password <service>      - add or update a password (asked for, never typed
#                                 on the command line, so it stays out of history
#                                 and the process list)
#   get-password <service>      - print it
#   delete-password <service>   - remove it
#
# Every item is a generic password for the current account ("$USER"), so the three
# always act on the same keychain item.

add-password() {
    if [[ -z "$1" ]]; then
        echo "Usage: add-password <service>" >&2
        return 1
    fi

    local pw
    read -rs "pw?Password for '$1': "
    echo

    if [[ -z "$pw" ]]; then
        echo "Aborted: empty password." >&2
        return 1
    fi

    # -U updates the item if the service already exists instead of failing.
    security add-generic-password -U -a "$USER" -s "$1" -w "$pw"
}

get-password() {
    if [[ -z "$1" ]]; then
        echo "Usage: get-password <service>" >&2
        return 1
    fi

    security find-generic-password -a "$USER" -s "$1" -w
}

delete-password() {
    if [[ -z "$1" ]]; then
        echo "Usage: delete-password <service>" >&2
        return 1
    fi

    security delete-generic-password -a "$USER" -s "$1"
}
