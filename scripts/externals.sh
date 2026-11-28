#!/usr/bin/env bash
set -euo pipefail
awk '
function emit() {
    if (path != "") {
        if (checkout == "commit") { print "Unsupported checkout-type commit: " path > "/dev/stderr"; bad = 1 }
        else if (url == "") { print "External has no URL: " path > "/dev/stderr"; bad = 1 }
        else { printf "%s\t%s\t%s\t%s\n", path, url, tag, type; count++ }
    }
    path = url = tag = type = checkout = ""
}
{ sub(/$/, ""); sub(/[[:space:]]+#.*$/, "") }
/^externals:[[:space:]]*$/ { found = 1; active = 1; next }
active && /^[^[:space:]#]/ { emit(); active = 0 }
active && /^  [^[:space:]#][^:]*:/ {
    emit()
    line = substr($0, 3); colon = index(line, ":")
    path = substr(line, 1, colon - 1); url = substr(line, colon + 1)
    sub(/^[[:space:]]+/, "", url); sub(/[[:space:]]+$/, "", url)
    next
}
active && /^    (url|tag|type|checkout-type):/ {
    line = $0; sub(/^    /, "", line); colon = index(line, ":")
    key = substr(line, 1, colon - 1); value = substr(line, colon + 1)
    sub(/^[[:space:]]+/, "", value); sub(/[[:space:]]+$/, "", value)
    if (key == "url") url = value
    else if (key == "tag") tag = value
    else if (key == "type") type = value
    else checkout = value
}
END {
    if (active) emit()
    if (!found || !count) { print "Missing or empty externals block" > "/dev/stderr"; bad = 1 }
    if (bad) exit 1
}' "${1:-.pkgmeta}"
