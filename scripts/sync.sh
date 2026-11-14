#!/usr/bin/env bash
# Usage: scripts/sync.sh retail|forever|all [--dry-run]   (WOW_DIR overrides the game folder)
set -euo pipefail
cd "$(dirname "$0")/.."

WOW_DIR="${WOW_DIR:-/mnt/stuff/Games/World of Warcraft}"
target="${1:-}"
dry=()
[[ "${2:-}" == "--dry-run" ]] && dry=(--dry-run)

case "$target" in
    retail) flavors=(_retail_) ;;
    forever) flavors=(_forever_) ;;
    all) flavors=(_retail_ _forever_) ;;
    *) echo "usage: $0 retail|forever|all [--dry-run]" >&2; exit 1 ;;
esac

mapfile -t payload < <(lua5.1 -e '
for line in io.lines("LKS_UI.toc") do
    line = line:gsub("\r$", "")
    if line ~= "" and not line:find("^#") then print((line:gsub("\\", "/"))) end
end')
payload+=(LKS_UI.toc)
[[ -d media ]] && payload+=(media)

for flavor in "${flavors[@]}"; do
    addons="$WOW_DIR/$flavor/Interface/AddOns"
    [[ -d "$addons" ]] || { echo "missing $addons" >&2; exit 1; }
    dest="$addons/LKS_UI"
    [[ "$dest" == */Interface/AddOns/LKS_UI ]] || exit 1
    (( ${#dry[@]} )) || mkdir -p "$dest"
    rsync -a --delete --relative "${dry[@]}" --itemize-changes "${payload[@]}" "$dest/"
    echo "synced $flavor${dry:+ (dry run)}"
done
