#!/usr/bin/env bash
# Usage: scripts/sync.sh retail|forever|all [--dry-run]   (WOW_DIR overrides the game folder)
set -euo pipefail
cd "$(dirname "$0")/.."

WOW_DIR="${WOW_DIR:-/mnt/stuff/Games/World of Warcraft}"

usage() { echo "usage: $0 retail|forever|all [--dry-run]" >&2; exit 1; }

target=""
dry=()
for arg in "$@"; do
    case "$arg" in
        retail|forever|all) [[ -z "$target" ]] || usage; target="$arg" ;;
        --dry-run) dry=(--dry-run) ;;
        *) usage ;;
    esac
done

case "$target" in
    retail) flavors=(_retail_) ;;
    forever) flavors=(_forever_) ;;
    all) flavors=(_retail_ _forever_) ;;
    *) usage ;;
esac

excludes=(--exclude='.*' --exclude='*.zip')
while IFS= read -r path; do
    excludes+=(--exclude="/${path%/}")
done < <(sed -n '/^ignore:/,/^[^[:space:]-]/s/^[[:space:]]*-[[:space:]]*//p' .pkgmeta | tr -d '\r')

for flavor in "${flavors[@]}"; do
    addons="$WOW_DIR/$flavor/Interface/AddOns"
    [[ -d "$addons" ]] || { echo "missing $addons" >&2; exit 1; }
    dest="$addons/LKS_UI"

    restart=""
    cmp -s LKS_UI.toc "$dest/LKS_UI.toc" || restart=1

    (( ${#dry[@]} )) || mkdir -p "$dest"
    rsync -a --delete --delete-excluded "${dry[@]}" --itemize-changes "${excludes[@]}" ./ "$dest/"

    if (( ${#dry[@]} )); then
        echo "$flavor: dry run, nothing written"
    else
        echo "$flavor: synced"
    fi
    if [[ -n "$restart" ]]; then
        echo "$flavor: LKS_UI.toc is new or changed; restart the game client, /reload does not reread it"
    else
        echo "$flavor: /reload to load the changes"
    fi
done
