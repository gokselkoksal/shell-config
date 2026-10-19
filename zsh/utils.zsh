# Odds and ends. Nothing to configure.
#
#   download-gif <url> [filename]   - save a GIF to the downloads folder
#
# The downloads folder is $XDG_DOWNLOAD_DIR when set, else ~/Downloads.

download-gif() {
    if [[ -z "$1" ]]; then
        echo "Usage: download-gif <url> [filename]" >&2
        return 1
    fi

    local dir="${XDG_DOWNLOAD_DIR:-$HOME/Downloads}"

    # Last path segment of the URL, minus any query string.
    local name="${2:-${${1##*/}%%\?*}}"
    [[ "$name" == *.[gG][iI][fF] ]] || name="${name:-download}.gif"

    # -f fails on an HTTP error instead of saving the error page; -L follows redirects.
    if curl -fL --progress-bar "$1" --output "$dir/$name"; then
        echo "Saved to $dir/$name"
    else
        echo "Download failed: $1" >&2
        return 1
    fi
}
