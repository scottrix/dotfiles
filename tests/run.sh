#!/usr/bin/env bash
# Lint every script (if shellcheck is installed) and run tests/test-*.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
status=0
if command -v shellcheck > /dev/null; then
    shellcheck -x install lib/*.sh steps/*.sh bin/* tests/*.sh home/bin/* || status=1
else
    echo "shellcheck not installed; skipping lint"
fi
for t in tests/test-*.sh; do
    echo "== $t"
    bash "$t" || status=1
done
exit $status
