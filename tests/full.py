#!/usr/bin/env python3
"""Every feature of Pocket, driven on the running bar with a real pointer.

tests/live.sh asks the bar one question and tests/live.sh --gesture drives one
drag. This drives the rest: the reveal and the fold, the pin and the lock, every
kind of drop the README describes and the edges between them, a member's panel,
a reload, and -- with --system -- the same again with Hyprland's animations off,
on a vertical bar, and with the pocket in the left and centre sections.

It takes the operator's pointer for several minutes and writes shell.json. The
file is snapshotted before anything is touched and put back from a `finally`,
and every system setting a block changes is changed back the same way. Run it
from tests/live.sh --full, which says so before it starts.

Each check prints one line, PASS or FAIL, and the run ends with a count. Blocks
can be named to run only those: python3 tests/full.py display fold pin drag.

Screenshots of the mark go to $POCKET_SHOTS (default: a fresh directory under
$TMPDIR), for the checks a person has to look at: the lit and dimmed mark, and
the tooltip.

Single-surface by design: on several monitors it drives the first one hyprctl
lists, and the per-screen cases stay with docs/decisions/0022.
"""

import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pointer as P  # noqa: E402

RESULTS = []
SHOTS = os.environ.get("POCKET_SHOTS") or tempfile.mkdtemp(prefix="pocket-full-")


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print("%s  %s%s" % ("PASS" if ok else "FAIL", name, ("  -- " + detail) if detail else ""))
    sys.stdout.flush()


def note(text):
    print("      " + text)
    sys.stdout.flush()


# ------------------------------------------------------------------ the bar


def is_drawn(slot):
    """The bar's own answer: shown, with a size. Not the width alone, which a
    vertical bar's hidden slot keeps -- the pocket drives its height there."""
    return slot.get("visible") is True


class Bar:
    """The first monitor's bar surface, read through debugBarGeometry."""

    def vertical(self, s=None):
        return self.position in ("left", "right")

    def __init__(self):
        name, ox, oy = P.monitors()[0]
        self.screen, self.ox, self.oy = name, ox, oy
        self.position = subprocess.run(["omarchy", "bar", "position"], capture_output=True,
                                       text=True).stdout.strip() or "top"

    def slots(self):
        # One surface: every id's first slot. A centre widget built twice by a
        # centre anchor is the one case this would misread, and this bar has none.
        return P.by_occurrence(P.geometry(), 0)

    def mark(self, s=None):
        return (s or self.slots())[P.SELF]

    def centre(self, slot):
        return (self.ox + slot["x"] + slot["width"] // 2, self.oy + slot["y"] + slot["height"] // 2)

    def present(self, s=None):
        """Members the bar has a slot for, in layout order."""
        s = s or self.slots()
        return [m for m in P.members() if m in s]

    def drawn(self, s=None):
        s = s or self.slots()
        return [m for m in self.present(s) if is_drawn(s[m])]

    def is_open(self, s=None):
        s = s or self.slots()
        # A member that hides itself is never drawn, open or not.
        wanted = [m for m in self.present(s) if s[m].get("itemVisible", True) or is_drawn(s[m])]
        return bool(wanted) and all(is_drawn(s[m]) for m in wanted)

    def is_closed(self, s=None):
        return not self.drawn(s)

    def neighbours(self):
        """The drawn non-members right before the run and right after the mark,
        along the bar, as (before, after) slots or None."""
        s = self.slots()
        region = s[P.SELF]["section"]
        along = "y" if self.vertical(s) else "x"
        row = sorted((v for k, v in s.items() if v["section"] == region and is_drawn(v)
                      and k not in P.members()), key=lambda v: v[along])
        at = [v["id"] for v in row].index(P.SELF)
        before = row[at - 1] if at > 0 else None
        after = row[at + 1] if at + 1 < len(row) else None
        return before, after


def wait(predicate, timeout=2.0, step=0.1):
    end = time.time() + timeout
    while time.time() < end:
        try:
            if predicate():
                return True
        except (KeyError, ValueError):
            pass
        time.sleep(step)
    return False


def stays(predicate, duration=2.0, step=0.15):
    end = time.time() + duration
    while time.time() < end:
        if not predicate():
            return False
        time.sleep(step)
    return True


def shot(bar, name, slot=None, below=0, pad=4):
    """A PNG of a slot (the mark by default), `below` logical px of screen
    under the bar included, for the tooltip."""
    slot = slot or bar.mark()
    x = bar.ox + slot["x"] - pad
    y = bar.oy + slot["y"]
    w = slot["width"] + 2 * pad
    h = slot["height"] + below
    path = os.path.join(SHOTS, name + ".png")
    subprocess.run(["grim", "-g", "%d,%d %dx%d" % (x, y, w, h), path], capture_output=True)
    return path


def ink_offset(path, pad=4):
    """How far the mark's ink sits from the middle of its slot, in logical px,
    as (dx, dy), measured against the bar colour in the shot's corner."""
    try:
        from PIL import Image
    except ImportError:
        return None
    im = Image.open(path).convert("RGB")
    w, h = im.size
    bg = im.getpixel((1, 1))
    xs, ys = [], []
    for y in range(h):
        for x in range(w):
            p = im.getpixel((x, y))
            if sum(abs(p[i] - bg[i]) for i in range(3)) > 120:
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    scale = w / float(27 + 2 * pad)
    cx = (min(xs) + max(xs) + 1) / 2.0 / scale
    cy = (min(ys) + max(ys) + 1) / 2.0 / scale
    return cx - (pad + 27 / 2.0), cy - 26 / 2.0


def entry():
    return P.entry()[1]


def on_list(value, key):
    if isinstance(value, list):
        names = value
    else:
        names = [x.strip() for x in str(value or "").split(",")]
    return key in names


def ipc(*args):
    return subprocess.run(["omarchy-shell", "shell", *args], capture_output=True, text=True).stdout.strip()


def close_panels(bar):
    """Whatever panel a click opened, closed: an open panel takes every press
    on the screen, the bar's included."""
    for widget_id in bar.slots():
        ipc("hide", widget_id)
    time.sleep(0.5)


def wait_shell():
    return wait(lambda: ipc("ping") == "ok", timeout=20, step=0.5)


def has_geometry():
    try:
        return bool(P.geometry())
    except P.Unavailable:
        return False


# ------------------------------------------------------------------ gestures


def hover(ptr, xy, pause=0.25):
    ptr.warp(*xy)
    time.sleep(pause)


def park(ptr, bar):
    ptr.warp(bar.ox + 400, bar.oy + 400)
    wait(bar.is_closed, timeout=2.5)


def open_by_hover(ptr, bar):
    hover(ptr, bar.centre(bar.mark()))
    return wait(bar.is_open, timeout=2.5)


def settle_open(bar):
    """The geometry once the reveal has finished moving."""
    time.sleep(0.8)
    return P.by_occurrence(P.settle(), 0)


def drag(ptr, bar, source_id, target_x, target_y=None, hold=0.5, during=None, after_release=None):
    """Press on a widget, cross the host's threshold, glide to the target by
    real motion, and let go. `target_x` is a function of a fresh reading taken
    during the drag, because folding and the room the host opens both move
    things (see pointer.drag())."""
    s = bar.slots()
    src = s[source_id]
    if not is_drawn(src):
        raise P.Unavailable("%s is not drawn, nothing to grab" % source_id)
    x, y = bar.centre(src)
    ptr.warp(x, y)
    ptr.press()
    ptr.nudge_by(90 if src["x"] >= s[P.SELF]["x"] else -90)
    time.sleep(0.3)
    # Aimed again once the pointer is there, the way a person corrects: from
    # 4.5.0 on the host opens the dragged widget's room wherever a drop would
    # land, and that moves the target under a pointer on its way to it.
    # Twice still in a row, because the room can open a moment after the
    # pointer arrives.
    still = 0
    for _ in range(6):
        tx = target_x(bar.slots())
        if not ptr.glide_to(tx):
            ptr.release()
            raise P.Unavailable("could not steer the pointer to x=%d" % tx)
        time.sleep(0.45)
        still = still + 1 if abs(target_x(bar.slots()) - tx) <= 1 else 0
        if still >= 2:
            break
    if target_y is not None and not ptr.glide_to_y(target_y):
        ptr.release()
        raise P.Unavailable("could not steer the pointer to y=%d" % target_y)
    time.sleep(hold)
    if during:
        during()
    ptr.release()
    if after_release:
        after_release()
    time.sleep(1.4)


def sample_slide(bar, trigger, duration):
    """Every drawn non-member's position along the bar, timed, from just before
    `trigger()` until `duration` seconds after it.

    The trigger runs on a thread of its own: a warp waits a fifth of a second
    after moving the cursor (Pointer.warp), and sampled after it, the first
    third of the reveal went unseen and read as a jump."""
    along = "y" if bar.vertical() else "x"
    members = P.members()

    def read():
        s = bar.slots()
        return {k: v[along] for k, v in s.items() if k not in members and is_drawn(v)}

    rows = [(0.0, read())]
    t0 = time.time()
    worker = threading.Thread(target=trigger)
    worker.start()
    while time.time() - t0 < duration:
        rows.append((time.time() - t0, read()))
        time.sleep(0.02)
    worker.join()
    return rows


def check_slides(name, rows, required=True):
    """The widgets the reveal moves glide there: every one that moved passes
    through at least two positions in between, one way, and no single sample
    step covers three quarters of its travel. Decision 0026 measured the jump
    this replaces as the whole travel in one frame. `required`: there is a
    widget beside the run that has to move; a run at the outer end of its
    section has none."""
    moved = []
    for wid in sorted(rows[0][1]):
        xs = [p[wid] for _, p in rows if wid in p]
        if len(xs) < 2 or xs[0] == xs[-1]:
            continue
        start, end = xs[0], xs[-1]
        travel = abs(end - start)
        steps = [b - a for a, b in zip(xs, xs[1:])]
        one_way = all(st * (end - start) >= 0 for st in steps)
        biggest = max(abs(st) for st in steps)
        between = set(x for x in xs if min(start, end) < x < max(start, end))
        trail, last = [], None
        for t, p in rows:
            if wid in p and p[wid] != last:
                trail.append("%.2fs %s" % (t, p[wid]))
                last = p[wid]
        note("%s %s: %s" % (name, wid, ", ".join(trail)))
        moved.append((wid, len(between) >= 2 and one_way and biggest < 0.75 * travel,
                      "travel %s, largest step %s, %d in between, one way: %s"
                      % (travel, biggest, len(between), one_way)))
    if required:
        check("%s: something beside the run moves" % name, bool(moved))
    elif not moved:
        note("%s: nothing beside the run moves here" % name)
    for wid, ok, detail in moved:
        check("%s: %s slides rather than jumps" % (name, wid), ok, detail)


def mark_edge(bar, s, inner):
    """Two px inside the mark's near (inner=True) or far edge."""
    return P.mark_gap(s, bar.ox, inner)


# ------------------------------------------------------------------ config


CONFIG = P.CONFIG


def write_config(mutate):
    config = json.load(open(CONFIG))
    mutate(config)
    tmp = CONFIG + ".pocket-full"
    with open(tmp, "w") as handle:
        json.dump(config, handle, indent=2)
    os.replace(tmp, CONFIG)
    time.sleep(2.0)


def set_entry(**values):
    def mutate(config):
        for entries in ((config.get("bar") or {}).get("layout") or {}).values():
            for item in entries if isinstance(entries, list) else []:
                if isinstance(item, dict) and item.get("id") == P.SELF:
                    item.update(values)
    write_config(mutate)


# ------------------------------------------------------------------ blocks


def block_display(ptr, bar):
    print("\n== A. display")
    park(ptr, bar)
    check("A1 closed: no member is drawn", bar.is_closed(), "drawn=%s" % bar.drawn())

    off = ink_offset(shot(bar, "A2-closed"))
    check("A2 closed: the dots sit within 1 px of the slot's middle",
          off is not None and max(abs(off[0]), abs(off[1])) <= 1.0, "offset=%s" % (off,))

    # A4 the widgets beside the run, sampled while the reveal runs, out and
    # back (docs/decisions/0027).
    mark_xy = bar.centre(bar.mark())
    rows = sample_slide(bar, lambda: ptr.warp(*mark_xy), 1.2)
    check("A3 hover on the mark opens it", wait(bar.is_open, timeout=2.0), "drawn=%s" % bar.drawn())
    check_slides("A4 opening", rows)
    off = ink_offset(shot(bar, "A2-open"))
    check("A2 open: the dots sit within 1 px of the slot's middle",
          off is not None and max(abs(off[0]), abs(off[1])) <= 1.0, "offset=%s" % (off,))
    rows = sample_slide(bar, lambda: ptr.warp(bar.ox + 400, bar.oy + 400), 1.6)
    check("A4 folding: it folds", wait(bar.is_closed, timeout=2.0))
    check_slides("A4 folding", rows)
    hover(ptr, bar.centre(bar.mark()), pause=1.6)
    shot(bar, "A5-tooltip", slot=bar.mark(), below=140, pad=160)
    note("A5 tooltip shot: %s" % os.path.join(SHOTS, "A5-tooltip.png"))
    park(ptr, bar)


def block_fold(ptr, bar):
    print("\n== B. fold")
    park(ptr, bar)
    before, after = bar.neighbours()

    if after:
        open_by_hover(ptr, bar)
        hover(ptr, bar.centre(after), pause=0)
        check("B6 from the mark onto the next widget on the bar, it folds",
              wait(bar.is_closed, timeout=1.2), "onto %s" % after["id"])
        check("B6 and stays folded with the pointer resting there", stays(bar.is_closed, 1.5))

    if before:
        open_by_hover(ptr, bar)
        s = settle_open(bar)
        drawn = sorted((s[m] for m in bar.drawn(s)), key=lambda v: v["x"])
        outer = drawn[0] if not P.members_face_away() else drawn[-1]
        # Along the run by real motion, so the members' own hover carries it.
        y = bar.centre(s[P.SELF])[1]
        ptr.glide_to(bar.centre(outer)[0])
        check("B8 gliding along the members keeps it open", bar.is_open())
        nb = bar.slots()[before["id"]]
        ptr.glide_to(bar.centre(nb)[0])
        check("B7 from the outermost member onto the widget before the run, it folds",
              wait(bar.is_closed, timeout=1.2), "onto %s" % before["id"])
        check("B7 and does not open again while the pointer rests there (no oscillation)",
              stays(bar.is_closed, 3.0))
        del y

    # Along the bottom edge of the strip and diagonally across the run.
    open_by_hover(ptr, bar)
    s = settle_open(bar)
    drawn = sorted((s[m] for m in bar.drawn(s)), key=lambda v: v["x"])
    bottom = bar.oy + s[P.SELF]["y"] + s[P.SELF]["height"] - 2
    ptr.glide_to_y(bottom)
    ok = True
    for slot in reversed(drawn):
        ptr.glide_to(bar.centre(slot)[0])
        ok = ok and bar.is_open()
    check("B8 along the bottom edge of the strip across every member it stays open", ok)
    top = bar.oy + s[P.SELF]["y"] + 2
    ok = True
    for i, slot in enumerate(drawn):
        ptr.glide_to(bar.centre(slot)[0])
        ptr.glide_to_y(top if i % 2 else bottom)
        ok = ok and bar.is_open()
    check("B8 zig-zagging diagonally across the members it stays open", ok)

    # Out and straight back in, faster than two fold ticks.
    m = bar.centre(bar.slots()[P.SELF])
    hover(ptr, m, pause=0.3)
    ptr.warp(m[0], m[1] + 80)
    time.sleep(0.1)
    ptr.warp(*m)
    check("B9 off the bar and straight back within 0.1 s, it stays open", stays(bar.is_open, 1.0))

    check("B11 resting on the mark, it stays open", stays(bar.is_open, 2.0))

    ptr.warp(m[0], m[1] + 120)
    check("B10 off the bar downwards, it folds", wait(bar.is_closed, timeout=1.2))
    park(ptr, bar)


def block_pin(ptr, bar):
    print("\n== C. pin and lock")
    park(ptr, bar)
    key = bar.screen
    m = bar.centre(bar.mark())

    hover(ptr, m, pause=0.4)
    ptr.click(P.BTN_LEFT)
    time.sleep(0.6)
    check("C12 a left click pins this screen in shell.json",
          on_list(entry().get("pinned"), key), "pinned=%r" % entry().get("pinned"))
    shot(bar, "C12-pinned")
    park_spot = (bar.ox + 400, bar.oy + 400)
    ptr.warp(*park_spot)
    check("C12 pinned, it stays open with the pointer gone", stays(bar.is_open, 1.5))
    hover(ptr, bar.centre(bar.mark()), pause=0.4)
    ptr.click(P.BTN_LEFT)
    time.sleep(0.6)
    check("C12 a second left click releases the pin",
          not on_list(entry().get("pinned"), key), "pinned=%r" % entry().get("pinned"))
    ptr.warp(*park_spot)
    check("C12 released, it folds once the pointer leaves", wait(bar.is_closed, timeout=1.5))

    hover(ptr, bar.centre(bar.mark()), pause=0.4)
    ptr.click(P.BTN_MIDDLE)
    time.sleep(0.6)
    check("C13 a middle click pins too", on_list(entry().get("pinned"), key))
    ptr.click(P.BTN_MIDDLE)
    time.sleep(0.6)
    check("C13 and a second one releases it", not on_list(entry().get("pinned"), key))

    # Locked with the pointer on the mark: folds at once regardless.
    check("C14 (precondition) the pointer on the mark holds it open", wait(bar.is_open, 1.5))
    ptr.click(P.BTN_RIGHT)
    time.sleep(0.6)
    check("C14 a right click locks this screen", on_list(entry().get("locked"), key),
          "locked=%r" % entry().get("locked"))
    check("C14 locking folds it at once, with the pointer still on the mark",
          wait(bar.is_closed, timeout=1.0))
    shot(bar, "C14-locked")
    ptr.warp(*park_spot)
    time.sleep(0.4)
    hover(ptr, bar.centre(bar.mark()), pause=0.2)
    check("C14 locked, the pointer arriving on the mark does not open it", stays(bar.is_closed, 1.5))

    ptr.click(P.BTN_LEFT)
    time.sleep(0.6)
    check("C15 a left click on a locked pocket pins it open",
          on_list(entry().get("pinned"), key) and wait(bar.is_open, 1.5))
    check("C15 and it stays locked", on_list(entry().get("locked"), key))
    ptr.click(P.BTN_LEFT)
    time.sleep(0.6)
    check("C15 releasing that pin leaves it locked and shut",
          not on_list(entry().get("pinned"), key) and wait(bar.is_closed, 1.5))

    ptr.click(P.BTN_RIGHT)
    time.sleep(0.6)
    check("C (unlock) a second right click unlocks", not on_list(entry().get("locked"), key))
    ptr.click(P.BTN_LEFT)
    time.sleep(0.6)
    check("C16 (precondition) pinned again", on_list(entry().get("pinned"), key))
    ptr.click(P.BTN_RIGHT)
    time.sleep(0.6)
    e = entry()
    check("C16 a right click on a pinned pocket drops the pin and locks, in one step",
          on_list(e.get("locked"), key) and not on_list(e.get("pinned"), key),
          "locked=%r pinned=%r" % (e.get("locked"), e.get("pinned")))
    check("C16 and it folds", wait(bar.is_closed, 1.0))
    ptr.click(P.BTN_RIGHT)
    time.sleep(0.6)
    check("C (unlock) unlocked again", not on_list(entry().get("locked"), key))
    park(ptr, bar)


def nearest(bar):
    return P.nearest_member()


def layout_ids():
    region = P.entry()[0]
    return [i.get("id") if isinstance(i, dict) else i
            for i in json.load(open(CONFIG))["bar"]["layout"][region]]


def in_bar_order():
    """Whether `members` lists the members on the bar in the bar's order. A
    member with no entry on the bar has no place to be ordered by and is left
    out of the comparison."""
    ids = layout_ids()
    listed = [m for m in P.members() if m in ids]
    return listed == [i for i in ids if i in listed]


def check_order(name):
    check(name, wait(in_bar_order, timeout=3.0),
          "layout=%s members=%s" % ([i for i in layout_ids() if i in P.members()], P.members()))


def block_drag(ptr, bar):
    print("\n== D. drag")
    park(ptr, bar)
    _, after = bar.neighbours()
    subject = nearest(bar)

    # D18 out past the mark.
    open_by_hover(ptr, bar)
    drag(ptr, bar, subject, lambda s: mark_edge(bar, s, inner=False))
    check("D18 a member dragged past the mark leaves the pocket", subject not in P.members(),
          "members=%s" % P.members())
    park(ptr, bar)
    check("D18 and stays drawn with the pocket shut", is_drawn(bar.slots()[subject]))

    # D20 onto the far half: nothing.
    open_by_hover(ptr, bar)
    lit = {}
    drag(ptr, bar, subject, lambda s: mark_edge(bar, s, inner=True) if P.members_face_away()
         else mark_edge(bar, s, inner=False),
         during=lambda: lit.update(far=shot(bar, "D20-far-half")))
    check("D20 a widget on the mark's far half does not join", subject not in P.members(),
          "members=%s" % P.members())
    park(ptr, bar)

    # D19 onto the near half: in, with the mark lit before the release.
    open_by_hover(ptr, bar)
    drag(ptr, bar, subject, lambda s: mark_edge(bar, s, inner=True),
         during=lambda: lit.update(near=shot(bar, "D19-near-half-lit")))
    check("D19 a widget on the mark's near half joins", subject in P.members(),
          "members=%s" % P.members())
    check_order("D19 and is listed in the bar's order")
    note("D29 lit mark while taking in: %s; unlit far half: %s" % (lit.get("near"), lit.get("far")))
    park(ptr, bar)

    # D21 reorder inside the run: stays a member, `members` follows the bar.
    open_by_hover(ptr, bar)
    s = settle_open(bar)
    run = sorted((s[m] for m in bar.drawn(s)), key=lambda v: v["x"])
    if len(run) >= 3:
        first, second = run[0], run[1]
        drag(ptr, bar, run[-1]["id"],
             lambda fresh: bar.ox + fresh[second["id"]]["x"] + 2 if second["id"] in fresh else 0)
        check("D21 reordered inside the run, it stays a member", run[-1]["id"] in P.members(),
              "members=%s" % P.members())
        check_order("D21 and `members` follows the bar's order")
        del first
    park(ptr, bar)

    # D22 far away along the bar: out.
    subject = nearest(bar)
    open_by_hover(ptr, bar)
    clock = bar.slots().get("omarchy.clock")
    if clock:
        drag(ptr, bar, subject, lambda s: bar.ox + s["omarchy.clock"]["x"] + 2)
        check("D22 a member dropped far away on the bar (by the clock) leaves the pocket",
              subject not in P.members(), "members=%s" % P.members())
        park(ptr, bar)
        # And back for the next cases.
        open_by_hover(ptr, bar)
        drag(ptr, bar, subject, lambda s: mark_edge(bar, s, inner=True))
        check("D22 (restore) and comes back onto the near half", subject in P.members())
        park(ptr, bar)

    # D24 released just below the strip: nothing changes.
    subject = nearest(bar)
    open_by_hover(ptr, bar)
    m = bar.mark()
    below = bar.oy + m["y"] + m["height"] + 20
    before = P.members()
    drag(ptr, bar, subject, lambda s: mark_edge(bar, s, inner=False), target_y=below)
    check("D24 released 20 px below the bar, membership is unchanged", P.members() == before,
          "members=%s" % P.members())
    park(ptr, bar)

    # D26 a press during the host's glide.
    subject = nearest(bar)
    open_by_hover(ptr, bar)

    def repress():
        # Straight back into the run and down again, inside the 180 ms glide.
        ptr._emit(P.EV_REL, P.REL_X, -40 if not P.members_face_away() else 40)
        ptr.press()
        ptr.release()

    drag(ptr, bar, subject, lambda s: mark_edge(bar, s, inner=False), after_release=repress)
    check("D26 a press during the glide does not undo the release: the member is out",
          subject not in P.members(), "members=%s" % P.members())
    close_panels(bar)
    park(ptr, bar)
    open_by_hover(ptr, bar)
    drag(ptr, bar, subject, lambda s: mark_edge(bar, s, inner=True))
    check("D26 (restore) back in", subject in P.members())
    park(ptr, bar)

    # D23 a widget dropped beside the shut pocket goes in.
    if after:
        neighbour = after["id"]
        drag(ptr, bar, neighbour, lambda s: mark_edge(bar, s, inner=True))
        check("D23 a widget dropped against the shut pocket joins it", neighbour in P.members(),
              "members=%s" % P.members())
        check_order("D23 and is listed in the bar's order")
        park(ptr, bar)
        open_by_hover(ptr, bar)
        drag(ptr, bar, neighbour, lambda s: mark_edge(bar, s, inner=False))
        check("D23 (restore) and leaves again past the mark", neighbour not in P.members())
        park(ptr, bar)

    # D27 the mark itself cannot be dragged away from its run.
    layout_before = json.load(open(CONFIG))["bar"]["layout"]
    m = bar.mark()
    ptr.warp(*bar.centre(m))
    ptr.press()
    ptr.nudge_by(-120)
    time.sleep(0.5)
    ptr.nudge_by(-60)
    time.sleep(0.3)
    ptr.release()
    time.sleep(1.4)
    check("D27 the mark dragged away from its members does not move",
          json.load(open(CONFIG))["bar"]["layout"] == layout_before)
    park(ptr, bar)

    # D28 a slow drag across the bar keeps the pocket open throughout.
    subject = nearest(bar)
    open_by_hover(ptr, bar)
    s = bar.slots()
    src = s[subject]
    ptr.warp(*bar.centre(src))
    ptr.press()
    ptr.nudge_by(-90)
    open_ok = True
    others = [m for m in bar.drawn() if m != subject]
    for _ in range(6):
        time.sleep(0.25)
        ptr.nudge_by(-12)
        # The dragged member's own room folds away under the drag (4.5.0);
        # every other member has to stay drawn.
        now = bar.slots()
        open_ok = open_ok and all(is_drawn(now[m]) for m in others)
    # Back home: onto its own room, so nothing changes.
    ptr.glide_to(bar.centre(bar.slots()[subject])[0])
    time.sleep(0.4)
    ptr.release()
    time.sleep(1.4)
    check("D28 the pocket stays open through a slow 1.5 s drag across the bar", open_ok)
    check("D28 (restore) the member dropped back on its own room stays in", subject in P.members())
    park(ptr, bar)


def block_poof(ptr, bar):
    print("\n== D25. pulled off the bar (Omarchy removes the widget)")
    park(ptr, bar)
    subject = nearest(bar)
    members_before = P.members()
    off_bar = [m for m in members_before if m not in bar.slots()]
    open_by_hover(ptr, bar)
    m = bar.mark()
    drag(ptr, bar, subject, lambda s: mark_edge(bar, s, inner=False),
         target_y=bar.oy + m["y"] + m["height"] + 120)
    # The host writes the removal after its poof (620 ms), the pocket after it.
    time.sleep(1.5)
    layout = json.load(open(CONFIG))["bar"]["layout"]
    gone = all(subject not in [i.get("id") if isinstance(i, dict) else i for i in v]
               for v in layout.values() if isinstance(v, list))
    check("D25 the host removed %s from the layout" % subject, gone)
    after = P.members()
    check("D25 and %s is no longer named in members" % subject, subject not in after,
          "members=%s" % after)
    check("D25 nothing else in members changed, order and members not on the bar (%s) included"
          % ", ".join(off_bar), after == [x for x in members_before if x != subject],
          "before=%s after=%s" % (members_before, after))
    check("D25 nothing breaks: the pocket still folds and opens", open_by_hover(ptr, bar))
    park(ptr, bar)


def block_panels(ptr, bar):
    print("\n== E. panels")
    park(ptr, bar)
    s = bar.slots()
    candidates = [m for m in ("omarchy.tailscale",) if m in s]
    if not candidates:
        note("E skipped: no member with a panel of its own")
        return
    member = candidates[0]

    open_by_hover(ptr, bar)
    s = settle_open(bar)
    hover(ptr, bar.centre(s[member]), pause=0.3)
    ptr.click(P.BTN_LEFT)
    time.sleep(1.0)
    shot(bar, "E30-panel", slot=s[member], below=300, pad=200)
    ptr.warp(bar.ox + 400, bar.oy + 400)
    check("E30 a member's panel opened from the pocket holds it open", stays(bar.is_open, 1.5))
    ipc("hide", member)
    check("E30 once the panel closes, the pocket folds", wait(bar.is_closed, timeout=2.0))

    ipc("toggle", member, "{}")
    check("E31 the member's panel summoned by IPC (as its keybinding does) opens the pocket",
          wait(bar.is_open, timeout=2.0))
    ipc("hide", member)
    check("E31 and closing it folds the pocket again", wait(bar.is_closed, timeout=2.0))

    set_entry(locked=bar.screen)
    ipc("toggle", member, "{}")
    check("E31 locked, the member's panel still opens the pocket", wait(bar.is_open, timeout=2.0))
    ipc("hide", member)
    check("E31 locked, it folds when the panel closes", wait(bar.is_closed, timeout=2.0))
    set_entry(locked="")

    ipc("toggle", "omarchy.clock", "{}")
    check("E32 a panel that is not a member's does not open the pocket", stays(bar.is_closed, 1.5))
    ipc("hide", "omarchy.clock")
    park(ptr, bar)


def block_reload(ptr, bar):
    print("\n== F. reload")
    park(ptr, bar)
    m = bar.centre(bar.mark())
    hover(ptr, m, pause=0.4)
    ptr.click(P.BTN_LEFT)
    time.sleep(0.6)
    ptr.warp(bar.ox + 400, bar.oy + 400)
    check("F (precondition) pinned", on_list(entry().get("pinned"), bar.screen))
    members_before = P.members()

    ipc("rescanPlugins")
    time.sleep(3.0)
    # With a second monitor the shell can report no bar at all for longer
    # than that while it rebuilds both surfaces.
    wait(has_geometry, timeout=15.0, step=0.25)
    check("F33 after a plugin rescan the pin still holds it open", wait(bar.is_open, timeout=3.0))
    hover(ptr, bar.centre(bar.mark()), pause=0.4)
    ptr.click(P.BTN_LEFT)
    # Polled, not read once: the host persists shell.json on its own time, and
    # a single read 0.8 s after the click sometimes came too early (decision
    # 0027 has the measured spread).
    t_click = time.time()
    released = wait(lambda: not on_list(entry().get("pinned"), bar.screen), timeout=3.0, step=0.02)
    e = entry()
    check("F33 the first click after the rescan releases the pin",
          released, "pinned=%r after %.2f s" % (e.get("pinned"), time.time() - t_click))
    check("F33 and writes the members back unchanged", P.members() == members_before,
          "members=%s" % P.members())
    ptr.warp(bar.ox + 400, bar.oy + 400)
    check("F33 and it folds", wait(bar.is_closed, timeout=2.0))

    subprocess.run(["omarchy-restart-shell"], capture_output=True)
    wait_shell()
    time.sleep(4.0)
    check("F34 after a shell restart every member is hidden again", wait(bar.is_closed, timeout=5.0))
    check("F34 and the pin stays released", not on_list(entry().get("pinned"), bar.screen))
    park(ptr, bar)


def animations_on():
    raw = subprocess.run(["hyprctl", "-j", "getoption", "animations:enabled"],
                         capture_output=True, text=True).stdout
    try:
        return json.loads(raw).get("bool") is not False
    except ValueError:
        return True


def block_system(ptr, bar):
    print("\n== G. system settings")
    # Put back as found, not as assumed: the toggle lives outside shell.json.
    animations_were_on = animations_on()
    position_was = bar.position
    # G35 animations off: the host lands a drop synchronously.
    subprocess.run(["omarchy", "toggle", "animations", "off"], capture_output=True)
    time.sleep(2.0)
    try:
        subject = nearest(bar)
        open_by_hover(ptr, bar)
        drag(ptr, bar, subject, lambda s: mark_edge(bar, s, inner=False))
        check("G35 animations off: a member dragged past the mark leaves", subject not in P.members())
        park(ptr, bar)
        open_by_hover(ptr, bar)
        drag(ptr, bar, subject, lambda s: mark_edge(bar, s, inner=True))
        check("G35 animations off: and comes back on the near half", subject in P.members())
        park(ptr, bar)
    finally:
        subprocess.run(["omarchy", "toggle", "animations", "on" if animations_were_on else "off"],
                       capture_output=True)
        time.sleep(2.0)

    # G37 the pocket in the left section (members after the mark), and in
    # centerEnd (members before it), where folding slides the mark itself.
    def move_run(region, at):
        def mutate(config):
            layout = config["bar"]["layout"]
            members = P.members()
            for name, entries in layout.items():
                if not isinstance(entries, list):
                    continue
                layout[name] = [i for i in entries
                                if (i.get("id") if isinstance(i, dict) else i) not in members + [P.SELF]]
            source = json.load(open(MASTER))["bar"]["layout"]
            moved = [i for entries in source.values() if isinstance(entries, list) for i in entries
                     if (i.get("id") if isinstance(i, dict) else i) in members + [P.SELF]]
            pocket = [i for i in moved if isinstance(i, dict) and i.get("id") == P.SELF]
            rest = [i for i in moved if i not in pocket]
            run = pocket + rest if region == "left" else rest + pocket
            target = layout.setdefault(region, [])
            layout[region] = target[:at(target)] + run + target[at(target):]
        return mutate

    # The drags are left out in centerEnd. On a narrow screen a long run there
    # reaches the right section, and from 4.5.0 on the tray's drawer opens
    # over it during every drag (Bar.qml::traySectionDragActive), so a drop
    # aimed at the mark lands in the tray's section -- for the host and the
    # pocket alike. centerBegin carries the drags for the centre.
    # `center` itself, the box centred on the bar, re-centres as the run grows:
    # the mark and both sides move. Its members were refused as the centre
    # anchor on 4.5.0 until 0027; fold and rest only, as for centerEnd.
    for region, label, at, drags in (("left", "left", lambda t: len(t), True),
                                     ("centerEnd", "centre", lambda t: min(2, len(t)), False),
                                     ("centerBegin", "centre-begin", lambda t: len(t), True),
                                     ("center", "centre box", lambda t: len(t), False)):
        write_config(move_run(region, at))
        time.sleep(2.0)
        try:
            park(ptr, bar)
            check("G37 %s: shut, no member is drawn" % label, bar.is_closed())
            mark_xy = bar.centre(bar.mark())
            rows = sample_slide(bar, lambda: ptr.warp(*mark_xy), 1.2)
            check("G37 %s: hover opens it" % label, wait(bar.is_open, timeout=2.5))
            check_slides("G37 %s opening" % label, rows, required=False)
            # In the centre, opening slides the mark from under the pointer
            # that opened it; it has to stay open, not open and fold in turn.
            check("G37 %s: resting where the mark was, it stays open (no oscillation)" % label,
                  stays(bar.is_open, 3.0, step=0.05))
            before, after = bar.neighbours()
            if after:
                hover(ptr, bar.centre(after), pause=0)
                check("G37 %s: onto the widget after the run, it folds and does not reopen" % label,
                      wait(bar.is_closed, 1.2) and stays(bar.is_closed, 3.0), "onto %s" % after["id"])
            if before:
                open_by_hover(ptr, bar)
                hover(ptr, bar.centre(bar.slots()[before["id"]]), pause=0)
                check("G37 %s: onto the widget before the run, it folds and does not reopen" % label,
                      wait(bar.is_closed, 1.2) and stays(bar.is_closed, 3.0), "onto %s" % before["id"])
            if not drags:
                park(ptr, bar)
                continue
            subject = P.nearest_member()
            open_by_hover(ptr, bar)
            drag(ptr, bar, subject, lambda s: mark_edge(bar, s, inner=False))
            check("G37 %s: past the mark takes a member out" % label, subject not in P.members())
            park(ptr, bar)
            open_by_hover(ptr, bar)
            drag(ptr, bar, subject, lambda s: mark_edge(bar, s, inner=True))
            check("G37 %s: the near half takes it back in" % label, subject in P.members())
            park(ptr, bar)
        finally:
            restore(MASTER)

    # G36 a vertical bar.
    subprocess.run(["omarchy", "bar", "position", "left"], capture_output=True)
    wait_shell()
    time.sleep(4.0)
    try:
        vb = Bar()
        vb_mark = vb.mark()
        note("G36 vertical: mark at %s" % vb_mark)
        ptr.warp(vb.ox + 600, vb.oy + 400)
        time.sleep(1.0)
        check("G36 vertical: shut, no member is drawn", vb.is_closed())
        shot(vb, "G36-vertical-closed")
        mark_xy = vb.centre(vb.mark())
        rows = sample_slide(vb, lambda: ptr.warp(*mark_xy), 1.2)
        check("G36 vertical: hover opens it", wait(vb.is_open, 2.5))
        check_slides("G36 vertical opening", rows)
        shot(vb, "G36-vertical-open")
        rows = sample_slide(vb, lambda: ptr.warp(vb.ox + 600, vb.oy + 400), 1.6)
        check("G36 vertical: off the bar it folds", wait(vb.is_closed, 2.0))
        check_slides("G36 vertical folding", rows)
    finally:
        subprocess.run(["omarchy", "bar", "position", position_was], capture_output=True)
        wait_shell()
        time.sleep(4.0)


# ------------------------------------------------------------------ main


MASTER = None


def restore(path):
    shutil.copyfile(path, CONFIG)
    time.sleep(2.0)
    return open(path, "rb").read() == open(CONFIG, "rb").read()


BLOCKS = [("display", block_display), ("fold", block_fold), ("pin", block_pin),
          ("drag", block_drag), ("panels", block_panels), ("reload", block_reload),
          ("poof", block_poof), ("system", block_system)]


def main(argv):
    global MASTER
    wanted = [a for a in argv if not a.startswith("--")]
    run = [(n, f) for n, f in BLOCKS if (not wanted or n in wanted)]
    if "--system" not in argv and not wanted:
        run = [(n, f) for n, f in run if n != "system"]

    if ipc("ping") != "ok":
        print("FULL SKIPPED (no shell is answering)")
        return P.SKIPPED
    MASTER = os.path.join(SHOTS, "shell.json.snapshot")
    shutil.copyfile(CONFIG, MASTER)
    print("FULL (shell.json snapshot at %s, shots in %s)" % (MASTER, SHOTS))

    try:
        with P.Pointer() as ptr:
            bar = Bar()
            for name, block in run:
                try:
                    block(ptr, bar)
                except P.Unavailable as reason:
                    check("%s could be driven" % name, False, str(reason))
                finally:
                    # Every block starts from the same file.
                    restore(MASTER)
                    park(ptr, bar)
    finally:
        ok = restore(MASTER)
        print("\nconfig restored: %s" % ("yes" if ok else "NO -- the snapshot is at " + MASTER))

    failed = [n for n, ok in RESULTS if not ok]
    print("\nFULL %s (%d checks, %d failed)" % ("PASSED" if not failed else "FAILED",
                                               len(RESULTS), len(failed)))
    for name in failed:
        print("  FAIL " + name)
    return P.OK if not failed else P.FAILED


def interrupted(*_):
    # A SIGTERM raises like a Ctrl-C does, so every `finally` above -- the
    # button released, the settings and shell.json put back -- still runs.
    raise KeyboardInterrupt()


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, interrupted)
    sys.exit(main(sys.argv[1:]))
