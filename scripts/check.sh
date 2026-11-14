#!/usr/bin/env bash
# Usage: scripts/check.sh   (EUI_REPO=path overrides ~/Dev/EllesmereUI for the guardrails)
set -euo pipefail
cd "$(dirname "$0")/.."

LUAC="${LUAC:-$(command -v luac5.1 || command -v luac)}"
failed=0

mapfile -t files < <(git ls-files --cached --others --exclude-standard -- '*.lua' ':!:Libs/**' ':!:.tools/guardrails.py')
for f in "${files[@]}"; do
    "$LUAC" -p "$f" || failed=1
done
echo "compile: ${#files[@]} files"

lua5.1 .tools/check-toc.lua LKS_UI.toc || failed=1

if command -v luacheck >/dev/null; then
    luacheck --no-color -q . || failed=1
else
    echo "luacheck not installed, skipped"
fi

EUI_REPO="${EUI_REPO:-$HOME/Dev/EllesmereUI}"
if [[ -f "$EUI_REPO/.tools/guardrails.py" ]]; then
    # guardrails.py checks the repository its parent folder belongs to, so it runs from a copy here.
    mkdir -p .tools
    cp "$EUI_REPO/.tools/guardrails.py" .tools/guardrails.py
    root=$(git rev-list --max-parents=0 HEAD | tail -n 1)
    LUAC="$LUAC" python3 .tools/guardrails.py --base "$root" || failed=1
else
    echo "EllesmereUI guardrails not found at $EUI_REPO, skipped"
fi

exit "$failed"
