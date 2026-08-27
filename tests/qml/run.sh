#!/usr/bin/env bash
# Loads the real BarWidget.qml in Quickshell against a fake bar, and asserts the
# drop steering still steers. Run from tests/run.sh, ahead of the node suite, so
# that a red run here can never be followed by the node suite's success line.
#
# Skipped rather than failed when Quickshell or an Omarchy shell is not present:
# GitHub's runners have neither, and the CI workflow says so. The same bargain
# the qmlformat job already makes -- what this covers is covered locally or not
# at all, and that is still more than nothing, because nothing is what the node
# suite and qmlformat together can say about this file.
#
# The harness imports qs.Commons and qs.Ui, which only exist inside an installed
# shell, so the import tree is built here rather than checked in: symlinks to the
# shell's own modules, and one to this repository, so the file under test is the
# working tree and never a copy that can drift from it.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

if ! command -v qs >/dev/null 2>&1; then
  echo "QML SKIPPED (quickshell is not installed)"
  exit 0
fi

SHELL_DIR=""
for candidate in "${OMARCHY_PATH:-}/shell" /usr/share/omarchy/shell "$HOME/.local/share/omarchy/shell"; do
  if [ -d "$candidate/Commons" ] && [ -d "$candidate/Ui" ]; then
    SHELL_DIR="$candidate"
    break
  fi
done

if [ -z "$SHELL_DIR" ]; then
  echo "QML SKIPPED (no omarchy shell found to import qs.Commons and qs.Ui from)"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ln -s "$SHELL_DIR/Commons" "$WORK/Commons"
ln -s "$SHELL_DIR/Ui" "$WORK/Ui"
ln -s "$ROOT" "$WORK/plugin"

status=0
for name in steer steer-readonly; do
  cp "$HERE/$name.qml" "$WORK/$name.qml"
  # Captured rather than piped: Quickshell does not exit through a pipe here.
  output="$(timeout 60 qs -p "$WORK/$name.qml" 2>&1)"

  if printf '%s\n' "$output" | grep -q "Binding loop"; then
    echo "QML FAILED ($name: the engine reported a binding loop)"
    printf '%s\n' "$output" | grep "Binding loop" | head -3
    status=1
    continue
  fi

  if ! printf '%s\n' "$output" | grep -q "QML OK"; then
    echo "QML FAILED ($name)"
    printf '%s\n' "$output" | grep -E "FAIL:|QML FAILURES|expected:|actual:" | head -20
    status=1
    continue
  fi

  echo "QML PASSED ($name)"
done

exit "$status"
