#!/usr/bin/env bash
# Usage: scripts/check.sh
set -euo pipefail
cd "$(dirname "$0")/.."

LUAC="${LUAC:-$(command -v luac5.1 || command -v luac)}"
failed=0
entries=$(bash scripts/externals.sh .pkgmeta)
while IFS=$'\t' read -r library _; do
    if [[ ! -d "$library" ]]; then
        echo "Libraries missing; run scripts/libs.sh first." >&2
        exit 1
    fi
done <<<"$entries"

mapfile -t files < <(git ls-files --cached --others --exclude-standard -- '*.lua' ':!:Libs/**')
for f in "${files[@]}"; do
    "$LUAC" -p "$f" || failed=1
done
echo "compile: ${#files[@]} files"

lua5.1 .tools/check-toc.lua KlausisLittleHelpers.toc || failed=1

scripts/test.sh || failed=1

if command -v luacheck >/dev/null; then
    luacheck --no-color -q . || failed=1
else
    if [[ -n "${CI:-}" ]]; then
        echo "luacheck not installed"
        failed=1
    else
        echo "luacheck not installed, skipped"
    fi
fi

if git ls-files --cached --others --exclude-standard -z -- '*.lua' '*.toc' '*.sh' '*.py' '*.md' ':!:Libs/**' | xargs -0 grep -nIP '[^\x00-\x7F]'; then
    echo "non-ASCII characters found"
    failed=1
fi

exit "$failed"
