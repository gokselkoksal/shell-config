# download: save a URL to the downloads folder. Nothing to configure.
#
#   download <url> [name]
#
# The folder is $XDG_DOWNLOAD_DIR when set, else ~/Downloads. The name is the
# URL's last path segment unless given; a URL that ends in / or has no path needs
# one. Fails on an HTTP error instead of saving the error page.

download() {
    if (( $# == 0 )) || [[ "$1" == -h || "$1" == --help ]]; then
        print -r -- "Usage: download <url> [name]"
        print
        print -r -- "  Saves the URL to \${XDG_DOWNLOAD_DIR:-~/Downloads}, named after the URL's last"
        print -r -- "  path segment unless a name is given."
        return 0
    fi

    local url="$1"
    local dir="${XDG_DOWNLOAD_DIR:-$HOME/Downloads}"

    # Last path segment of the URL, minus any query string or fragment.
    local name="${2:-${${${url##*/}%%\?*}%%\#*}}"
    if [[ -z "$name" || "$name" == "$url" ]]; then
        _shell_config_usage_error download "cannot tell a file name from '$url'; pass one"
        return
    fi
    if [[ "$name" == */* || "$name" == .* ]]; then
        _shell_config_usage_error download "'$name' is not a plain file name"
        return
    fi

    if [[ ! -d "$dir" ]]; then
        _shell_config_error download "downloads folder does not exist: $dir"
        return
    fi

    # -f fails on an HTTP error instead of saving the error page; -L follows redirects.
    if curl -fL --progress-bar "$url" --output "$dir/$name"; then
        print -r -- "$dir/$name"
    else
        _shell_config_error download "failed: $url"
    fi
}
