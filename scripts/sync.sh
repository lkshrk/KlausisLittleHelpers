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

entries=$(bash scripts/externals.sh .pkgmeta)
while IFS=$'\t' read -r library _; do
    if [[ ! -d "$library" ]]; then
        echo "Libraries missing; run scripts/libs.sh first." >&2
        exit 1
    fi
done <<<"$entries"

excludes=(--exclude='.*' --exclude='*.zip')
while IFS= read -r path; do
    excludes+=(--exclude="/${path%/}")
done < <(sed -n '/^ignore:/,/^[^[:space:]-]/s/^[[:space:]]*-[[:space:]]*//p' .pkgmeta | tr -d '\r')

dev_version() {
    local v
    if v=$(git describe --tags --match '[0-9]*.[0-9]*.[0-9]*' --dirty 2>/dev/null); then
        echo "$v"
        return
    fi
    if ! v=$(git rev-parse --short HEAD 2>/dev/null); then
        echo "dev-uncommitted"
        return
    fi
    git diff --quiet HEAD -- || v="$v-dirty"
    echo "dev-$v"
}
version=$(dev_version)

for flavor in "${flavors[@]}"; do
    addons="$WOW_DIR/$flavor/Interface/AddOns"
    [[ -d "$addons" ]] || { echo "missing $addons" >&2; exit 1; }
    dest="$addons/KlausisLittleHelpers"


    (( ${#dry[@]} )) || mkdir -p "$dest"
    rsync -a --delete --delete-excluded "${dry[@]}" --itemize-changes "${excludes[@]}" ./ "$dest/"

    if (( ${#dry[@]} )); then
        echo "$flavor: dry run, nothing written (version would be $version)"
    else
        # The packager fills this token on release; a local copy gets the git version instead.
        sed -i "s/@project-version@/$version/g" "$dest/KlausisLittleHelpers.toc"
        echo "$flavor: synced $version, /reload to load the changes"
    fi
done
