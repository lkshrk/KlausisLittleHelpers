#!/usr/bin/env bash
# Usage: scripts/errors.sh [retail|forever] [pattern] [--all-sessions]
set -euo pipefail
cd "$(dirname "$0")/.."

WOW_DIR="${WOW_DIR:-/mnt/stuff/Games/World of Warcraft}"
case "${1:-retail}" in
    retail) flavor=_retail_ ;;
    forever) flavor=_forever_ ;;
    *) echo "usage: $0 [retail|forever] [pattern] [--all-sessions]" >&2; exit 1 ;;
esac

shopt -s nullglob
svs=("$WOW_DIR/$flavor"/WTF/Account/*/SavedVariables/'!BugGrabber.lua')
(( ${#svs[@]} )) || { echo "no !BugGrabber SavedVariables under $flavor (install !BugGrabber, then /reload)" >&2; exit 1; }

for sv in "${svs[@]}"; do
    lua5.1 .tools/errors.lua "$sv" "${2:-KlausisLittleHelpers}" "${3:-}"
done
