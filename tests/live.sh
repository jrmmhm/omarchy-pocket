#!/usr/bin/env bash
# The only check in this repository that asks the RUNNING shell whether the
# plugin is doing anything.
#
# Every other test drives the widget against objects the tests themselves wrote,
# and that is exactly how the Omarchy 4.0.3 break got through: the suite was
# green, 373 assertions, while the pocket sat on a live bar hiding nothing at
# all. A fake bar cannot notice that the real one stopped answering.
#
# So this asks the bar. `omarchy-shell shell debugBarGeometry` reports, per
# module slot and per surface, whether it is drawn. A collapsed pocket whose
# members are drawn is the failure this file exists to name.
#
# Deliberately NOT part of tests/run.sh: it needs a running Omarchy shell with
# this plugin configured and its members collapsed, which is a machine and not a
# checkout. Run it by hand after `omarchy-restart-shell`, or from a session that
# has one.
#
#   bash tests/live.sh            # expects the pocket collapsed
#   bash tests/live.sh --open     # expects it fanned out (pinned or hovered)
#   bash tests/live.sh --gesture  # DRIVES a real drag; writes and restores the config
#
# Exit 0 = the bar agrees with the setting. Exit 1 = it does not. Exit 2 = there
# was nothing to ask.
#
# `--gesture` is the only mode here that writes anything, and it is the only
# check in this repository that can see the drag break. Every other test drives
# the drop rule against a fake bar, and the rule is not the risky half: the
# gesture rests on the host delivering a press to ITS MouseArea before this
# plugin's passive pointer handler sees it, on an overlay surviving the rebuild a
# drop causes, and on a chain -- glass.pressed, localDrop, dropIntent,
# commitDrop -- that a green suite says nothing about. It ships broken or it
# ships working, and only a real button press knows which.
#
# What it does to the machine, and how it undoes it: it snapshots shell.json,
# prints the path before touching anything, drags one member past the mark and
# then back onto it, and restores the snapshot from a trap that also runs on a
# failed assertion, an error and a Ctrl-C. The pointer releases its button and
# destroys itself from the same kind of guard on the Python side, because a
# script that dies mid-drag would otherwise leave the operator's desktop with a
# held mouse button. The one state it deliberately does not restore is the
# member ORDER inside `members`: the round trip leaves the widget against the
# mark and the pocket rewrites the list to layout order, which is documented
# behaviour -- the snapshot is what puts it back.
set -u

WANT_OPEN=0
WANT_GESTURE=0
case "${1:-}" in
  --open) WANT_OPEN=1 ;;
  --gesture) WANT_GESTURE=1 ;;
esac

if ! command -v omarchy-shell >/dev/null 2>&1; then
  echo "LIVE SKIPPED (omarchy-shell is not installed)"
  exit 2
fi

if [ "$(omarchy-shell shell ping 2>/dev/null)" != "ok" ]; then
  echo "LIVE SKIPPED (no shell is answering)"
  exit 2
fi

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"
if [ ! -f "$CONFIG" ]; then
  echo "LIVE SKIPPED (no shell.json at $CONFIG)"
  exit 2
fi

GEOMETRY="$(omarchy-shell shell debugBarGeometry 2>/dev/null)"
if [ -z "$GEOMETRY" ]; then
  echo "LIVE SKIPPED (the shell returned no bar geometry)"
  exit 2
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --------------------------------------------------------------- the gesture

restore_config() {
  [ -n "${BACKUP:-}" ] || return 0
  [ -f "$BACKUP" ] || return 0
  # The bar persists its own move after the pocket has written, so a restore that
  # lands in the middle of that is overwritten by it. Give the shell a moment to
  # go quiet, then put the file back and read it again to prove it took.
  sleep 1
  cp "$BACKUP" "$CONFIG"
  sleep 1
  if ! cmp -s "$BACKUP" "$CONFIG"; then
    echo "LIVE WARNING (the config did not come back; the snapshot is at $BACKUP)"
    return 1
  fi
  return 0
}

members_now() {
  python3 "$HERE/pointer.py" report 2>/dev/null | sed -n 's/.*members=//p'
}

holds() {
  case ",$1," in *",$2,"*) return 0 ;; esac
  return 1
}

if [ "$WANT_GESTURE" = "1" ]; then
  if [ ! -r "$HERE/pointer.py" ]; then
    echo "LIVE SKIPPED (gesture: tests/pointer.py is not here)"
    exit 2
  fi
  if ! command -v python3 >/dev/null 2>&1 || ! command -v hyprctl >/dev/null 2>&1; then
    echo "LIVE SKIPPED (gesture: needs python3 and hyprctl)"
    exit 2
  fi
  if [ ! -w /dev/uinput ]; then
    echo "LIVE SKIPPED (gesture: /dev/uinput is not writable, so there is no pointer to drive)"
    exit 2
  fi

  BEFORE="$(members_now)"
  if [ -z "$BEFORE" ]; then
    echo "LIVE SKIPPED (gesture: the pocket holds no members to drag)"
    exit 2
  fi

  # The subject is the member nearest the mark, which is the last id in a list
  # kept in layout order for every section but `left`. It is the one whose gaps
  # the drop rule is most easily wrong about: one of them is the boundary
  # between "reorder inside the run" and "leave the group".
  SUBJECT="${BEFORE##*,}"

  BACKUP="$(mktemp "${TMPDIR:-/tmp}/pocket-live-shell-json.XXXXXX")"
  cp "$CONFIG" "$BACKUP"
  echo "LIVE GESTURE (driving a real drag; shell.json snapshot at $BACKUP)"
  trap 'restore_config' EXIT INT TERM

  if ! python3 "$HERE/pointer.py" drag-out "$SUBJECT"; then
    echo "LIVE SKIPPED (gesture: the drag could not be driven)"
    exit 2
  fi
  AFTER_OUT="$(members_now)"
  if holds "$AFTER_OUT" "$SUBJECT"; then
    echo "LIVE FAILED (gesture: $SUBJECT was dragged past the mark and is still a member)"
    echo "  members: $AFTER_OUT"
    exit 1
  fi

  if ! python3 "$HERE/pointer.py" drag-in "$SUBJECT"; then
    echo "LIVE SKIPPED (gesture: the second drag could not be driven)"
    exit 2
  fi
  AFTER_IN="$(members_now)"
  if ! holds "$AFTER_IN" "$SUBJECT"; then
    echo "LIVE FAILED (gesture: $SUBJECT was dragged onto the mark and did not join)"
    echo "  members: $AFTER_IN"
    exit 1
  fi

  if ! restore_config; then
    exit 1
  fi
  trap - EXIT INT TERM
  rm -f "$BACKUP"
  echo "LIVE PASSED (gesture: $SUBJECT left the pocket and came back, config restored)"
  exit 0
fi

# python3 rather than jq: the shell already depends on a python3 being present
# for its own tooling, and this file should not add a dependency to run one
# check. The comparison itself is the point, not the parser.
GEOMETRY="$GEOMETRY" WANT_OPEN="$WANT_OPEN" CONFIG="$CONFIG" python3 - <<'PY'
import json, os, sys

want_open = os.environ["WANT_OPEN"] == "1"
config = json.load(open(os.environ["CONFIG"]))
geometry = json.loads(os.environ["GEOMETRY"])

SELF = "jrmmhm.pocket"


def members_of(cfg):
    bar = cfg.get("bar") or {}
    layout = bar.get("layout") or {}
    for region, entries in layout.items():
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if not isinstance(entry, dict) or entry.get("id") != SELF:
                continue
            raw = entry.get("members", "")
            if isinstance(raw, str):
                return region, [x for x in raw.replace(",", " ").split() if x]
            if isinstance(raw, list):
                return region, [x for x in raw if isinstance(x, str)]
    return None, []


region, members = members_of(config)
if region is None:
    print("LIVE SKIPPED (this shell.json has no %s entry)" % SELF)
    sys.exit(2)
if not members:
    print("LIVE SKIPPED (the pocket holds no members to check)")
    sys.exit(2)

# The pocket has to be on the bar at all before anything it does can be judged.
marks = [s for s in geometry if s["id"] == SELF]
if not marks:
    print("LIVE FAILED (the pocket is configured but the bar has no slot for it)")
    sys.exit(1)

# One verdict per member per surface. `visible` here is the bar's own effective
# answer: drawn, with a size.
#
# `itemVisible` cannot be used to spot a widget that hides itself, because
# QML's `visible` is EFFECTIVE -- a widget inside a slot the pocket has hidden
# reads false too. It only separates the two cases in the open state, where the
# pocket is showing every slot and anything still undrawn is undrawn by its own
# choice. Collapsed, there is nothing to separate: a self-hidden widget and a
# tucked-away one must both be undrawn, and that is exactly what is asserted.
failures = []
checked = 0
skipped = []
for slot in geometry:
    if slot["id"] not in members:
        continue
    drawn = slot["visible"]
    if want_open and not drawn and not slot.get("itemVisible", True):
        skipped.append(slot["id"])
        continue
    checked += 1
    if want_open and not drawn:
        failures.append("%s is not drawn while the pocket is open" % slot["id"])
    if not want_open and drawn:
        failures.append("%s is drawn while the pocket is collapsed" % slot["id"])

if checked == 0:
    print("LIVE SKIPPED (every member hides itself; nothing to judge)")
    sys.exit(2)

state = "open" if want_open else "collapsed"
if failures:
    print("LIVE FAILED (pocket %s, %d of %d member slots disagree)"
          % (state, len(failures), checked))
    for line in failures[:10]:
        print("  " + line)
    sys.exit(1)

note = ""
if skipped:
    note = " (%d hiding themselves, not judged: %s)" % (len(skipped), ", ".join(sorted(set(skipped))))
print("LIVE PASSED (pocket %s, %d member slots agree across %d surfaces)%s"
      % (state, checked, len(marks), note))
PY
