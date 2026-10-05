# 22. Every screen tested, and the panel a keybinding opens

- Status: accepted
- Date: 2026-10-05
- Corrects [0020](0020-a-right-click-locks-the-pocket-shut.md)'s claim that a
  member's panel opened by keybinding opens the pocket: on Omarchy 4.0.3 and
  later it did not, until this decision
- Corrects [0021](0021-the-pin-and-the-lock-belong-to-a-screen.md)'s account of
  its residual write race, and does the unplug it left undone
- Narrows [0007](0007-the-two-host-limits-measured.md)'s "mirrored" to what
  Hyprland actually builds, and records that [0005](0005-a-pocket-drives-only-its-own-screens-slots.md)'s
  late fold no longer reaches a 4.0.3+ host
- Owns every number below; the README and the CHANGELOG name this file

## Context

PR #21 made the pin and the lock per screen and was tested on two monitors.
This decision tests every Pocket function on two and three monitors: side by
side, stacked, mirrored, unplugged and plugged back, and across a monitor
profile switch.

Omarchy 4.0.4, quickshell 0.3.1, Hyprland 0.56.2. Monitors: eDP-1 (laptop,
1152×720 logical), HDMI-A-1 ASUS VG289 (1600×900), DP-2 Ancor VS248
(1280×720, on USB-C), all at y=0, side by side.

**Method.** A source-level review came first. It traced twelve scenarios
through `BarWidget.qml`, `Model.js` and the host's `Bar.qml` before any pointer
moved. A fresh-context reviewer then attacked the trace. It corrected one
mechanism (the write race below), five line references and one claim about
≤4.0.2, and added a hover-latch candidate. After that the live runs started.

The live runs used a uinput pointer, `omarchy-shell shell debugBarGeometry`,
and screenshots for the tooltip. Each bar surface was identified by opening it:
`pinned` was written by hand for one screen name, and the surface that drew its
members was that screen's. That was necessary, not cautious. After a monitor
move, the order of the surfaces in `debugBarGeometry` changed.

`shell.json` was snapshotted first and restored byte-identically after every
run, by `os.replace`. The monitor profile files were snapshotted the same way.
Monitor layouts were changed only through `monitor-control`.

## What was measured

| # | Scenario | 2 monitors | 3 monitors | Verdict |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Hover opens; leaving onto another screen's bar folds; staying on the same bar holds | fold 6/6, hold 6/6 | fold 12/12, hold 42/42 | live |
| 2 | Pin and lock per screen, two restarts, lock on a pinned screen drops only its pin | yes | yes | live |
| 3 | Unplug and replug: the screen gets its state back, the others are untouched, a new screen is neutral | — | yes (VS248, same port) | live |
| 4 | Identical twins share one name, pin and lock | — | — | test |
| 5 | Mirror: surfaces, left click, pin and lock | — | yes | live |
| 6 | Stacked arrangement: hover, fold, left click | — | yes | live |
| 7 | Profile switch with a pinned, moving screen | — | yes | live |
| 8 | Drag out, back in and reorder, left and right sections, on every monitor | — | yes | live |
| 9 | Tooltip per screen | — | yes (screenshots) | live + test |
| 10 | A member's panel by keybinding | — | **defect**, fixed, 9/9 after | live |
| 11 | Hand edits, `omarchy bar set`, legacy boolean, unknown names | yes | yes | live + test |
| 12 | Clicks on two screens in quick succession; a click right after a drop | — | 20/20; 10/10 | live |

The details per row follow.

1. **Folds per screen.** On 4.0.3+ the fold guard is a hover handler on each
   surface's own root (0015). So with the pointer on screen B's bar, screen A's
   pocket folds. The README's "a pocket on another screen folds up late" is a
   ≤4.0.2 statement.
2. **Pin and lock per screen.** Left clicks pinned eDP-1, then ASUS VG289, then
   VS248, and the list grew in that order. All three reopened after a restart.
   A right click on the pinned eDP-1 locked it and dropped only its pin. A
   second restart kept every list.
   - With two monitors: a name in the list for an unplugged screen does nothing
     and is kept. A hover on a locked pocket does not open it.
3. **Unplug and replug.** VS248 was pinned by a real click and then unplugged.
   Its surface was gone about 1.8 s after the output, and the other two pockets
   stayed collapsed in every 30 ms sample. Replugged, it came back pinned, and
   the others stayed collapsed. Plugging VS248 in for the first time built a
   neutral pocket.
4. **Twins.** No two identical monitors were available.
   `tests/qml/facade.qml` gives two pockets the same name:
   - a pin on one writes the name once and pins both;
   - a lock on the other locks both and drops the shared pin, in one write;
   - unlocking either unlocks both.
5. **Mirror.** `monitor-control --mirror` makes eDP-1 mirror the ASUS. Hyprland
   then lists eDP-1 as `mirrorOf` and leaves it out of `hyprctl monitors`, and
   the shell builds two surfaces, not three.
   - Pinning `eDP-1` by hand opens nothing while it is mirrored. A real left
     click on the visible bar pins `ASUS VG289`.
   - So mirroring produces no overlapping bar surfaces, and 0007's contested
     click (e5) needs outputs overlapped by hand. That case was not tested.
   - `--extend` with the pointer resting on the VS248 mark brought the third
     surface back. VS248 folded once the pointer left.
   - With `eDP-1` pinned before mirroring, the name stayed in the list while
     mirrored, and after `--extend` the laptop's pocket was open again.
6. **Stacked.** VS248 was moved to (1152,900) under the ASUS through a
   temporary `monitor-control` profile in free arrangement, then moved back.
   Hover opens and folds the lower bar's pocket. A left click there pins
   `VS248` only.
7. **Profile switch.** With VS248 pinned and moved back to (2752,0), its pocket
   stayed open through the remap, which is the latch of 0021. The other pockets
   were never drawn in 30 ms samples.
   - The adversarial review's candidate, hover left latched across a remap, did
     not reproduce. In the one move made with the pointer resting on the moving
     surface, the compositor moved the cursor to (2751,13) and the pocket
     folded. One observation, not a proof.
8. **Drags.** `tests/live.sh --gesture <connector>` passed on all three
   connectors with the pocket in the right section, and again with the pocket
   and its members moved into `left` by hand. A reorder inside the run (omaplug
   into the gap after darky) on each monitor left the membership unchanged and
   rewrote `members` in layout order. On the locked HDMI-A-1 the gesture
   reports itself skipped and names the lock.
9. **Tooltip.** On each screen, the second hover's tooltip was screenshotted:
   - unlocked: "Pocket holding 6 widgets", both click hints, "Not on this bar:
     io.github.ilyazar.syncthing";
   - the locked ASUS: "Pocket locked shut — holding 6 widgets" and "Right
     click: unlock".

   The other lines (anchor, foreign section, self-hidden, misplaced, second
   entry, unknown surface) are pure functions of the per-surface resolution and
   are held in `tests/model-test.js` and `tests/qml/model.qml`.
10. **The panel a keybinding opens.** See the next section.
11. **Hand edits.**
    - `omarchy bar set jrmmhm.pocket locked "eDP-1, VS248"` was written as that
      string and reached the running pockets.
    - `--json` with an array of two or more names fails in the host IPC ("Too
      many arguments provided (4 required but 5 were provided.)", 3 of 3), and
      nothing is written. A one-element array arrives as a plain string.
    - A hand-written array `["VS248","DELL U2720Q"]` opened VS248, and the
      unknown name did nothing. A left click on eDP-1 wrote `["VS248","DELL
      U2720Q","eDP-1"]`: the shape and the unknown name were kept.
    - The legacy `locked: true` reads as locked nowhere. A right click replaced
      it with `"VS248"`.
12. **Write races.**
    - Clicks on two screens, the second 144 ms after the first (as fast as a
      warp lands): both names kept, 20 of 20.
    - A click right after a drop: see the last section.

## The defect: a keybinding panel left the pocket shut

`omarchy-shell shell summon omarchy.tailscale` is the path a panel hotkey
takes. It was run with each monitor focused. It opened the member's panel on
that monitor, from a slot the pocket was hiding, and the pocket stayed shut on
all three, the locked one included. 0020 and the README said the opposite.

**Cause.** `memberPanelOpen` compares `bar.activePopout` with each member's
widget. On 4.0.3+ the facade hands over every popout Pocket does not own as one
anonymous `{ foreign: true }` (`Bar.qml::syncPluginBarApiObjects`). The
comparison could not match, and `foreignPanelHold` only holds a pocket that is
already open. The facade case in `tests/qml` had handed the facade a member
object, which is a state 4.0.4 cannot produce. So the gap was invisible to the
suite.

**Options.**
- *A — ask the member.* Chosen. A keybinding opens the focused screen's copy
  (`BarModel.pickPanelSlot`). A widget built on `Ui/Panel.qml` reports
  `opened`. The resolution is this surface's slots, so only that screen's pocket
  can answer.
- *B — open every pocket on any foreign popout.* Rejected. It breaks "nothing
  opens by itself" on every screen at once.
- *C — a new pure predicate in `Model.js`.* Rejected in review. It is a
  duck-typing test on a live object, and its only callers are in the widget.

**Decision.** Under the marker, a resolved member counts as open when its
widget keeps the host's own panel contract and reports `opened === true`. The
contract is `open()` and `close()` functions plus an `opened` property, the
same test `Bar.qml::panelNavigationSlots()` makes. Three things guard it:

- A popout has to be live at all. A widget whose `opened` stays true cannot hold
  a pocket on its own.
- A widget without both functions does not count. An unrelated `opened` cannot
  open anything.
- Where the host hands over the object (≤4.0.2), only identity is asked, as
  before.

`foreignPanelHold` now holds only for a member that does not keep the contract.
For the others, `memberPanelOpen` answers exactly. The blanket hold had kept a
pocket open on one screen for a panel opened on another.

**After the fix,** live, three rounds over three monitors: the summon opened
only the focused monitor's pocket, the locked ASUS included, and a hide folded
it, 9 of 9. Closed by clicking the member's own icon, the pocket stays while
the pointer is on the bar and folds when it leaves.

`tests/qml/facade.qml` drives the facade's own marker. The base widget fails
there, and so do ten of eleven mutants. The survivor is equivalent: it tests
`!active` once more after the early return.

**What still holds open.** A member without the contract, here
`io.github.randazraik.xray`, makes any foreign popout hold an already open
pocket on every screen, a locked one included, until the popout closes.
Observed once by accident: a misplaced right click opened the tray's "Tray
icons" popup, and the three pockets the run had just pinned and unpinned stayed
open until it was closed.

## The write race, measured

0021 named a window: a pin or lock clicked within about 120 ms after a drop
could be undone by the host's deferred `injectProps()`. The review corrected
the mechanism. `registryLoader.onLoaded` injects at once and queues a second
injection, so every new instance has `bar` and `settings` from the start. All
the deferred injections run in one batch. Any inline write between the rebuild
and that batch carries the instance's whole entry, and that includes the
automatic `repairMemberOrder()`.

Measured on three monitors. After a drop, the shell answered no IPC for 2.5 to
2.9 s while it rebuilt three surfaces.

- **During that time.** Right clicks at +43 to +1544 ms after the release
  produced no write at all. A separate process polled `shell.json` every 4 ms
  and saw none. The click is lost, and nothing is reverted.
- **First landable click.** Clicked as soon as the shell answered (+2.6 to
  +3.0 s), the lock landed 10 of 10. A later right click on VS248 kept it, 10
  of 10.

On this machine the window cannot be reached with a real pointer. It stays
named in 0021 for a faster machine or a smaller bar.

## What this does not cover

- Outputs overlapped by hand, the only layout where 0007's contested left click
  remains possible.
- Two identical monitors on real hardware.
- Equal logical widths. None of these monitors share one.
- A host ≤4.0.2. The new term is gated on the facade's marker, and the identity
  case in `tests/qml/facade.qml` still passes.
- Hover left latched across a remap, beyond the one observation above.

## Lessons

**A click that lands nowhere reads exactly like a race that undoes it.** The
first ten "click right after a drop" runs counted 0 of 10 locks, and that
looked like the 0021 race. Three instrument faults produced it:

- the test pointer's device had no right button;
- widgets to the right of the mark change width with the session-attention
  marker, so a click position read during the drag missed the mark;
- a file-poll thread in the same process slowed the drag until no drop
  happened.

A poller in a separate process settled it. It showed no write at all, so there
was nothing to revert. Before blaming the host, watch the write path from
outside the process that drives the pointer.

**The facade hides whose panel is open, not that a panel is open.** When the
host stops naming an object, ask the object's own state through the contract
the host itself uses. Pocket already reads that surface's slots.
