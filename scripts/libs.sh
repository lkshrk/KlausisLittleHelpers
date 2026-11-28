#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

force=0
if [[ ${1:-} == --force && $# == 1 ]]; then
    force=1
elif [[ $# != 0 ]]; then
    echo "Usage: scripts/libs.sh [--force]" >&2
    exit 2
fi

for tool in svn git; do
    if ! command -v "$tool" >/dev/null; then
        echo "Required tool not found: $tool" >&2
        exit 1
    fi
done

entries=$(bash scripts/externals.sh .pkgmeta)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/klh-libs.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT
while IFS= read -r entry; do
    IFS=$'\034' read -r path url tag type <<<"${entry//$'\t'/$'\034'}"
    if [[ -e "$path" && $force == 0 ]]; then
        echo "$path: present"
        continue
    fi
    echo "Fetching $path" >&2
    if [[ "$type" == svn || "$url" =~ ^https?://repos\.(wowace|curseforge)\.com/wow/[^/]+/(trunk(/.*)?|tags/.*)$ ]]; then
        if ! svn export --quiet "$url" "$tmp/library"; then
            echo "Failed to fetch $path" >&2
            exit 1
        fi
    else
        repo=$url
        subdir=""
        if [[ "$url" == *'.git/'* ]]; then
            repo=${url%%.git/*}.git
            subdir=${url#"$repo"/}
        fi
        if [[ -z "$tag" ]] || ! git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$tag" "$repo" "$tmp/clone"; then
            echo "Failed to fetch $path" >&2
            exit 1
        fi
        rm -rf "$tmp/clone/.git"
        source="$tmp/clone${subdir:+/$subdir}"
        if [[ ! -d "$source" ]]; then
            echo "Failed to fetch $path: missing $subdir" >&2
            exit 1
        fi
        mv "$source" "$tmp/library"
        rm -rf "$tmp/clone"
    fi
    mkdir -p "$(dirname "$path")"
    rm -rf "$path"
    mv "$tmp/library" "$path"
    echo "$path: fetched"
done <<<"$entries"
