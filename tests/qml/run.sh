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
# The bar's own drop-target arithmetic, linked rather than copied for the same
# reason the plugin is: neighbourhood.qml asserts what THIS host answers, and a
# copy would go on passing after the host changed its mind.
ln -s "$SHELL_DIR/plugins/bar" "$WORK/host"

# `model` is listed in both branches on purpose. It needs nothing from the host
# at all -- it runs Model.js in Qt's V4 engine and asserts against it -- so a
# shell that costs us the neighbourhood sweep must not silently cost us this one
# too. A case that quietly stops running is the kind of green tests/run.sh warns
# about in its own header.
CASES="model steer steer-readonly neighbourhood"
if [ ! -f "$SHELL_DIR/plugins/bar/BarModel.js" ]; then
  echo "QML SKIPPED (neighbourhood: this shell has no plugins/bar/BarModel.js to sweep against)"
  CASES="model steer steer-readonly"
fi

status=0
for name in $CASES; do
  cp "$HERE/$name.qml" "$WORK/$name.qml"

  # neighbourhood.qml needs a real window -- Model.ownsSlot() refuses every slot
  # to an instance that does not know its surface -- and a real window must not
  # appear on the user's screens in the middle of a test run. The other two need
  # none and keep the platform they were written for.
  #
  # Captured rather than piped: Quickshell does not exit through a pipe here.
  if [ "$name" = "neighbourhood" ]; then
    output="$(QT_QPA_PLATFORM=offscreen timeout 60 qs -p "$WORK/$name.qml" 2>&1)"
  else
    output="$(timeout 60 qs -p "$WORK/$name.qml" 2>&1)"
  fi

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
