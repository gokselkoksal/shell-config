# xc: Xcode helpers.
#
# Any function named _xc_<noun>_<verb> becomes `xc <noun> <verb> [args...]`.
# `xc sim <anything else>` passes through to `xcrun simctl`.
#
#   xc sim shake [device]   - shake a simulator (default: booted)
#
# Nothing to configure.

_xc_sim_shake() {
    local device="${1:-booted}"
    xcrun simctl spawn "$device" notifyutil -p com.apple.UIKit.SimulatorShake
}

xc() {
    local fn="_xc_${1//-/_}_${2//-/_}"
    if [[ -n "$1" && -n "$2" ]] && (( $+functions[$fn] )); then
        shift 2
        "$fn" "$@"
    elif [[ "$1" = sim ]]; then
        shift
        xcrun simctl "$@"
    else
        echo "Usage: xc <noun> <verb> [args...]"
        echo "Available:"
        local f
        for f in ${(k)functions[(I)_xc_*_*]}; do
            f="${f#_xc_}"
            echo "  xc ${f%%_*} ${f#*_}"
        done
        return 1
    fi
}

_xc_complete() {
    local -a nouns verbs
    local f
    for f in ${(k)functions[(I)_xc_*_*]}; do
        f="${f#_xc_}"
        nouns+=("${f%%_*}")
        [[ "${f%%_*}" = "${words[2]}" ]] && verbs+=("${f#*_}")
    done
    case "$CURRENT" in
        2) compadd -- ${(u)nouns} ;;
        3) compadd -- $verbs ;;
    esac
}
(( $+functions[compdef] )) && compdef _xc_complete xc
