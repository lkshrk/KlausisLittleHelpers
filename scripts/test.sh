#!/usr/bin/env bash
# Usage: scripts/test.sh   (runs every .tools/tests/*_test.lua)
set -euo pipefail
cd "$(dirname "$0")/.."

shopt -s nullglob
tests=(.tools/tests/*_test.lua)
lua5.1 .tools/tests/run.lua "${tests[@]}"
python3 .tools/tests/writ_data_test.py
