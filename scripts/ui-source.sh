#!/usr/bin/env bash
# Usage: scripts/ui-source.sh update            clone or refresh Blizzard's UI source (live + forever)
#        scripts/ui-source.sh grep <regex> [live|forever]
set -euo pipefail

ROOT="${WOW_UI_SOURCE:-$HOME/.local/share/wow}"
REPO=https://github.com/Gethe/wow-ui-source

dir_for() { [[ "$1" == live ]] && echo "$ROOT/wow-ui-source" || echo "$ROOT/wow-ui-source-$1"; }

case "${1:-}" in
    update)
        mkdir -p "$ROOT"
        for branch in live forever; do
            dir=$(dir_for "$branch")
            if [[ -d "$dir/.git" ]]; then
                git -C "$dir" fetch -q --depth 1 origin "$branch"
                git -C "$dir" reset -q --hard FETCH_HEAD
            else
                git clone -q --depth 1 --single-branch --branch "$branch" "$REPO" "$dir"
            fi
            echo "$branch: $(git -C "$dir" log -1 --format='%h %s') -> $dir"
        done
        ;;
    grep)
        [[ -n "${2:-}" ]] || { echo "usage: $0 grep <regex> [live|forever]" >&2; exit 1; }
        dir=$(dir_for "${3:-live}")
        [[ -d "$dir" ]] || { echo "missing $dir, run: $0 update" >&2; exit 1; }
        grep -rnE --include='*.lua' --include='*.xml' "$2" "$dir/Interface" | sed "s#^$dir/##" | head -200
        ;;
    *) echo "usage: $0 update | grep <regex> [live|forever]" >&2; exit 1 ;;
esac
