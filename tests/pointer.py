#!/usr/bin/env python3
"""A real pointer on the real bar, for the one gesture no other test can drive.

Everything else in this repository drives the widget against objects the tests
wrote. That is how the Omarchy 4.0.3 break got through green -- and the gesture
is the half of this plugin that a fake bar can least be trusted about, because
it depends on the host delivering a press to ITS MouseArea before this plugin's
passive pointer handler sees it. Nothing but a real button press can say whether
that ordering holds.

So this drives one. Absolute position comes from the compositor, the button and
the motion from a virtual pointer this file creates:

  * Hyprland 0.56 takes dispatchers through Lua -- `movecursor 100 100` fails
    with a syntax error from the Lua parser, `hl.dsp.cursor.move({x=,y=})` works.
  * A warp alone delivers no motion when the pointer is already at the target,
    and Qt hovers on motion, so every warp is followed by one pixel out and back.
  * `/dev/uinput` needs no root here: the seat's own user gets an ACL entry for
    it, which is why this file installs nothing and asks for nothing.

Two things about the bar's geometry are load-bearing and neither is obvious.

`debugBarGeometry` carries NO surface identity: `x` is window-local, there is no
monitor field, one surface's slots are not contiguous in the array, and the order
the surfaces register in changes between shell restarts. A run that assumed "the
Nth occurrence is the Nth monitor" pressed at a coordinate outside every monitor
and reported a silent pass. So the surface is identified by OPENING it: hover
each candidate mark until the members are drawn, and the surface that answered is
the one the pointer can reach.

And the `x` of a slot that is not drawn is stale rather than zero -- a collapsed
pocket's members keep the coordinate they had before they were hidden.

Used by tests/live.sh --gesture, which owns the assertions and the config
snapshot; this file owns the pointer and the geometry and nothing else.
"""

import fcntl
import json
import os
import struct
import subprocess
import sys
import time

UI_SET_EVBIT = 0x40045564
UI_SET_KEYBIT = 0x40045565
UI_SET_RELBIT = 0x40045566
UI_DEV_CREATE = 0x5501
UI_DEV_DESTROY = 0x5502

EV_SYN, EV_KEY, EV_REL = 0, 1, 2
REL_X, REL_Y = 0, 1
BTN_LEFT = 0x110

SELF = "jrmmhm.pocket"
CONFIG = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")),
                      "omarchy", "shell.json")

# Exit codes match tests/live.sh: 0 agreed, 1 disagreed, 2 nothing to ask.
OK, FAILED, SKIPPED = 0, 1, 2


class Unavailable(Exception):
    """There was nothing to ask, which is not a failure."""


class Pointer:
    """A virtual pointer that always releases its button and always goes away.

    The button matters more than the device: a script that dies between press and
    release leaves the operator's desktop with a held left button, and nothing on
    screen says why. Both the release and the teardown are in __exit__, so they
    run on an assertion, an exception and a Ctrl-C alike.
    """

    def __init__(self):
        try:
            self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        except OSError as error:
            raise Unavailable("/dev/uinput is not writable here (%s)" % error.strerror)

        self.pressed = False
        for event in (EV_KEY, EV_REL):
            fcntl.ioctl(self.fd, UI_SET_EVBIT, event)
        fcntl.ioctl(self.fd, UI_SET_KEYBIT, BTN_LEFT)
        for axis in (REL_X, REL_Y):
            fcntl.ioctl(self.fd, UI_SET_RELBIT, axis)

        # The legacy uinput_user_dev write rather than UI_DEV_SETUP: name[80],
        # input_id, ff_effects_max, then four 64-entry absolute-axis arrays this
        # device has no use for.
        os.write(self.fd, struct.pack("80sHHHHI" + "256i", b"omarchy-pocket-test-pointer",
                                      3, 0x1D6B, 0x0001, 1, 0, *([0] * 256)))
        fcntl.ioctl(self.fd, UI_DEV_CREATE)
        # The compositor has to notice the new device before it will route its
        # events. Measured: events emitted immediately after UI_DEV_CREATE are
        # dropped, and a drag that starts with a dropped press is a click.
        time.sleep(0.6)

    def __enter__(self):
        return self

    def __exit__(self, *_):
        try:
            self.release()
        finally:
            fcntl.ioctl(self.fd, UI_DEV_DESTROY)
            os.close(self.fd)

    def _emit(self, kind, code, value):
        os.write(self.fd, struct.pack("llHHi", 0, 0, kind, code, value))
        os.write(self.fd, struct.pack("llHHi", 0, 0, EV_SYN, 0, 0))
        time.sleep(0.02)

    def nudge(self):
        self._emit(EV_REL, REL_X, 1)
        self._emit(EV_REL, REL_X, -1)

    def warp(self, x, y):
        hyprctl("hl.dsp.cursor.move({x=%d,y=%d})" % (x, y))
        time.sleep(0.15)
        self.nudge()

    def press(self):
        self.pressed = True
        self._emit(EV_KEY, BTN_LEFT, 1)
        time.sleep(0.15)

    def release(self):
        if not self.pressed:
            return
        self.pressed = False
        self._emit(EV_KEY, BTN_LEFT, 0)
        time.sleep(0.15)

    def nudge_by(self, dx):
        """Move by dx in small steps, without claiming to know where that lands."""
        step = 3 if dx > 0 else -3
        moved = 0
        while abs(dx - moved) > 3:
            self._emit(EV_REL, REL_X, step)
            time.sleep(0.012)
            moved += step

    def glide_to(self, target_x, tries=60):
        """Walk to an absolute x by real motion, correcting from the real position.

        Two things forbid the obvious implementations. A warp is exact but a
        drag needs MOTION -- measured: a drag whose last step was a warp landed
        the bar's own insertion line correctly while the pocket kept the position
        it had before, and the drop then meant nothing at all, intermittently.
        And adding up relative steps is not exact, because they go through the
        pointer acceleration curve. So: relative steps, and ask the compositor
        where they actually landed after each one.
        """
        for _ in range(tries):
            at = position()[0]
            delta = target_x - at
            if abs(delta) <= 1:
                return True
            step = max(-8, min(8, delta))
            self._emit(EV_REL, REL_X, step)
            time.sleep(0.02)
        return abs(position()[0] - target_x) <= 3


def hyprctl(*args):
    return subprocess.run(["hyprctl", "dispatch", *args],
                          capture_output=True, text=True).stdout.strip()


def position():
    raw = subprocess.run(["hyprctl", "cursorpos"], capture_output=True, text=True).stdout
    x, _, y = raw.partition(",")
    try:
        return int(x.strip()), int(y.strip())
    except ValueError:
        raise Unavailable("the compositor did not report a cursor position")


def shell_ipc(*args):
    return subprocess.run(["omarchy-shell", "shell", *args],
                          capture_output=True, text=True).stdout


def geometry():
    raw = shell_ipc("debugBarGeometry")
    if not raw.strip():
        raise Unavailable("the shell returned no bar geometry")
    return json.loads(raw)


def monitors():
    raw = subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True, text=True).stdout
    if not raw.strip():
        raise Unavailable("hyprctl reported no monitors")
    return [(m["name"], m["x"], m["y"]) for m in json.loads(raw)]


def by_occurrence(slots, index):
    """The Nth slot of every id, which is one surface's worth once index is known."""
    seen, out = {}, {}
    for slot in slots:
        nth = seen.get(slot["id"], 0)
        seen[slot["id"]] = nth + 1
        if nth == index:
            out[slot["id"]] = slot
    return out


def entry():
    config = json.load(open(CONFIG))
    layout = ((config.get("bar") or {}).get("layout") or {})
    for region, entries in layout.items():
        if not isinstance(entries, list):
            continue
        for item in entries:
            if isinstance(item, dict) and item.get("id") == SELF:
                return region, item
    raise Unavailable("this shell.json has no %s entry" % SELF)


def members():
    _, item = entry()
    raw = item.get("members", "")
    if isinstance(raw, str):
        return [x for x in raw.replace(",", " ").split() if x]
    return [x for x in raw if isinstance(x, str)]


def settle(reads=2, pause=0.35, tries=14):
    """Wait until the geometry stops changing.

    Fanning out is animated (`animationDuration` in BarWidget.qml) and a drop
    rebuilds every widget on every monitor, so a reading taken too early
    describes a bar that is still moving -- and a drag
    computed from it aims at a slot that has since slid sideways.
    """
    last, stable = None, 0
    for _ in range(tries):
        current = geometry()
        if current == last:
            stable += 1
            if stable >= reads - 1:
                return current
        else:
            stable = 0
        last = current
        time.sleep(pause)
    return last


def open_pocket(pointer, wanted):
    """Hover each candidate mark until one pocket is actually open.

    Returns (index, monitor name, origin x, origin y, slots). Tries every
    (surface, monitor) pair rather than trusting an order: see the module note.
    """
    slots = settle()
    marks = [s for s in slots if s["id"] == SELF]
    if not marks:
        raise Unavailable("the pocket is configured but the bar has no slot for it")

    for index in range(len(marks)):
        surface = by_occurrence(slots, index)
        mark = surface.get(SELF)
        if not mark or mark["width"] <= 0:
            continue
        for name, origin_x, origin_y in monitors():
            pointer.warp(origin_x + mark["x"] + mark["width"] // 2, origin_y + mark["y"] + 13)
            time.sleep(0.9)
            after = by_occurrence(settle(), index)
            drawn = [i for i in wanted if after.get(i, {}).get("width", 0) > 0]
            if len(drawn) == len(wanted):
                return index, name, origin_x, origin_y, after
    raise Unavailable("no pocket opened under the pointer on any surface")


def park(pointer, origin_x, origin_y):
    """Take the pointer off the bar.

    Left on it, `pointerOnBar` stays true and the fold timer returns early on
    every tick, so the pocket hangs open for the rest of the session -- which is
    indistinguishable from a bug this plugin has actually shipped, and made a
    later tests/live.sh run report six members drawn while collapsed.
    """
    pointer.warp(origin_x + 400, origin_y + 400)
    time.sleep(1.2)


def drag(pointer, origin_x, origin_y, index, source, mark_x, target_for):
    """Press on `source`, move well away, then land exactly on `target_x`.

    Two steps for two different jobs. The first move is what makes it a drag at
    all: the host starts one on accumulated distance past a four-pixel threshold,
    and a press and release without motion between them is a click. The second is
    the landing, and it has to be both exact and made of real motion -- see
    glide_to(), which is where the difference was measured.

    Only the move BEFORE the press is a warp. Once the host holds the grab, every
    step is relative.

    The target is computed from a reading taken DURING the drag, not from the one
    the surface was chosen with, and that is not caution: the pocket folds as soon
    as the pointer leaves the mark, folding narrows the section, and the mark
    itself slides by the width of everything it was holding. A target measured
    while the pocket was open points at empty bar by the time the drop lands --
    which is a test that reports the plugin wrote nothing, correctly, about a
    gesture that never touched the mark. Measured that way three times out of
    three before this line existed.
    """
    start = origin_x + source["x"] + source["width"] // 2
    y = origin_y + source["y"] + source["height"] // 2
    pointer.warp(start, y)
    pointer.press()
    # Away from the mark first, whichever side of it this widget is on, so the
    # host crosses its drag threshold before anything is aimed at.
    pointer.nudge_by(90 if source["x"] >= mark_x else -90)
    time.sleep(0.3)

    target_x = target_for(by_occurrence(settle(), index))
    if not pointer.glide_to(target_x):
        raise Unavailable("the pointer could not be steered onto the gap")
    time.sleep(0.5)
    pointer.release()
    time.sleep(1.2)


def mark_gap(surface, origin_x, inner):
    """An absolute x two pixels inside one of the mark's own two edges.

    Two pixels, because the bar resolves a drop to the nearest slot EDGE and the
    mark's two edges mean opposite things: the far one takes a member out, the
    near one -- the side the group is on -- takes a widget in. Aiming at the
    middle of the mark would be aiming at the boundary between the two answers.
    See docs/decisions/0008.
    """
    mark = surface[SELF]
    return origin_x + (mark["x"] + 2 if inner else mark["x"] + mark["width"] - 2)


def grab(surface, widget_id):
    slot = surface.get(widget_id)
    if not slot or slot["width"] <= 0:
        raise Unavailable("%s is not drawn, so there is nothing to grab" % widget_id)
    return slot


def main(argv):
    if not argv:
        print("usage: pointer.py <report|drag-out|drag-in> [widget-id]", file=sys.stderr)
        return SKIPPED

    command = argv[0]
    try:
        if command == "report":
            region, _ = entry()
            print("region=%s members=%s" % (region, ",".join(members())))
            return OK

        wanted = members()
        if not wanted:
            raise Unavailable("the pocket holds no members to drag")

        with Pointer() as pointer:
            index, name, origin_x, origin_y, surface = open_pocket(pointer, wanted)
            mark_x = surface[SELF]["x"]
            try:
                if command == "drag-out":
                    # Past the mark, which is the gesture the README describes:
                    # "drag a member past the middle of the mark and it comes
                    # out". Defaults to the member nearest the mark, the one
                    # whose gap the drop rule is most easily wrong about.
                    who = argv[1] if len(argv) > 1 else wanted[-1]
                    drag(pointer, origin_x, origin_y, index, grab(surface, who), mark_x,
                         lambda fresh: mark_gap(fresh, origin_x, inner=False))
                    print("dragged %s past the mark on %s" % (who, name))
                elif command == "drag-in":
                    who = argv[1]
                    drag(pointer, origin_x, origin_y, index, grab(surface, who), mark_x,
                         lambda fresh: mark_gap(fresh, origin_x, inner=True))
                    print("dragged %s onto the mark on %s" % (who, name))
                else:
                    print("unknown command %s" % command, file=sys.stderr)
                    return SKIPPED
            finally:
                park(pointer, origin_x, origin_y)
        return OK

    except Unavailable as reason:
        print("POINTER SKIPPED (%s)" % reason, file=sys.stderr)
        return SKIPPED


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
