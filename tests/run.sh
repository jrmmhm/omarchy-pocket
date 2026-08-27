#!/usr/bin/env bash
# The suite for this plugin, and the single command the /implement commit gate
# accepts for this repository.
#
# Success line, asserted by that gate:
#   "ALL TESTS PASSED (N assertions, 0 failures)"
# Printed by model-test.js itself, so a crashed run prints nothing recognizable
# rather than an empty success.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Ahead of the node suite on purpose: model-test.js prints the success line the
# commit gate matches, and a QML failure after it would leave that line standing
# as the last word on a red run. Skips itself where Quickshell is absent.
if ! bash "$ROOT/tests/qml/run.sh"; then
  echo "TESTS FAILED (qml harness)"
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "TESTS FAILED (node is not installed)"
  exit 1
fi

node "$ROOT/tests/model-test.js"
