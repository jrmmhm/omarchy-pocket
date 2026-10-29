# 23. The neighbours slide with the reveal

- Status: accepted
- Date: 2026-10-28
- Extends [0002](0002-members-belong-on-one-side.md)'s mechanism: the pocket
  still never moves an entry, but it now drives the slots' extent as well as
  their `visible`
- Owns every number below; the README and the CHANGELOG name this file

## Context

PR #23 (by a contributor) made the widgets beside the run slide instead of
jumping. The members used to fade and grow in place while the room they take
appeared in one frame on open and vanished in one frame on close, so the tray's
chevron jumped by the run's whole length. The PR drives each member slot's
extent along the bar (width, or height on a vertical bar) with that member's
share of the reveal, `Model.revealExtent()`, and gives the host's sizing back
once the member is fully out and on release.

Omarchy 4.0.6, quickshell 0.3.2, Qt 6.12.0, Hyprland 0.56.2. One monitor:
eDP-1, 1152×720 logical, bar on top, the pocket in `right` with six members on
the bar and one that is not.

**Method.** Two fresh-context reviewers attacked the plan first: one the code
change, one the live test plan. The live runs used the uinput pointer of
`tests/pointer.py` (with a right and a middle button added inline),
`omarchy-shell shell debugBarGeometry` sampled every ~23 ms, IPC for summons
and reloads, and `grim` for panels, the tooltip and the mark. Every
comparison ran the same script against three builds, switched by pointing the
plugin symlink at a checkout and restarting the shell: `main` (81c9049), the PR
as submitted (2c20087), and the PR with the fix below. `shell.json` was
snapshotted first and restored byte-identically after every run that wrote it.

## The defect in the PR: a size handed back by a binding stops with the pocket

The PR handed the size back as `Qt.binding(function () { return slot.implicitWidth })`,
created inside the pocket. Such a binding belongs to the context that made it,
and it stops evaluating when that context is destroyed. A hot reload
(`rescanPlugins`, which a plugin update and the plugin file watcher also take)
unloads the pocket while the member slots stay, so a member the old pocket gave
back keeps the width it had at that moment.

- Offline, a slot released by a pocket that is then unloaded through a `Loader`
  kept width 50 when its implicit width went to 70 (`Qt.binding`), and followed
  to 70 with a held `Binding` element or with a reset.
- Live: a member taken in by a drag after the last shell start (so the reloaded
  pocket no longer holds it, see the last section) and then reloaded. With the
  PR its slot stayed at width 0 while its widget was visible with width 21; it
  was gone from the bar until the next restart. With the fix it came back at
  21 and followed its widget to 0 and back to 21.

**Decision: hand the size back by reset.** Assigning `undefined` to `width` and
`height` resets them, and an item whose size is not set follows its implicit
size natively, in no QML context at all. Considered and rejected: held
`Binding` elements with `restoreMode: Binding.RestoreBindingOrValue`. They
restore the host's own binding, but two of them on one property must be
released in reverse order, and one direct write while they are active drops
the restore for good; the reset has neither failure. Its cost: it restores
"follow the implicit size", not whatever the host had declared. On 4.0.6 those
are the same, because `ModuleSlot` declares `width: implicitWidth` and
`height: implicitHeight`. `tests/qml/extent.qml` unloads a collapsed pocket and
asserts the member follows its own size afterwards; it fails on the PR as
submitted.

The PR also re-created a binding on every frame for each member that had
already arrived while the others were still moving. A reset of a size that is
already reset changes nothing.

## What was measured

| # | Scenario | Result |
| :--- | :--- | :--- |
| 1 | Open and fold, horizontal | tray x 648→607 opening and 684→826 folding, monotonic, intermediate values in every sample; the mark and everything right of it constant |
| 2 | Open and fold, vertical (`position left`) | heights slide, widths stay 28; each slot's y + height meets the next within 1 px (rounding) |
| 3 | Pocket and two members in `left` | the mark stays; the members after it lead, the ones left in `right` follow, the tray there slides |
| 4 | Ten rapid hover reversals each way | end states clean: collapsed is width 0 and not drawn, open is width = item width, no gaps beyond 1 px |
| 5 | Pin, lock, middle click, restart | as the README says, every step; the pin survives a restart |
| 6 | Drag out and back in, reorder inside the run | `tests/live.sh --gesture` passed; a reorder rewrote `members` in layout order; the mark lit in the theme accent during the drag |
| 7 | Members removed and re-added by `setBarWidget`, collapsed, open, mid-open, mid-fold | a removed member is drawn at full width at once; a re-added one follows the pocket's state; no gaps |
| 8 | Hot reload collapsed, hover-open, pinned, mid-open, mid-fold | every end state clean and without gaps (whether the pin survives is the last section's); a self-hiding member followed its widget 0↔21 while open and after each reload |
| 9 | `togglePanelAt right 1…7` at +30, +100, +250, +700 ms after the hover, and collapsed | the same widgets as `main` at every delay |
| 10 | A member's panel by `summon`, from collapsed | 50 of 50 centred within 1 px at 2.5 s; one earlier run read 55 px off at 0.9 s and did not reproduce |
| 11 | Shell CPU over 20 open/fold cycles, three runs each | `main` 2.00–2.06 s, the PR 2.81–2.87 s, the fix 2.79–2.85 s |
| 12 | A press on a member while it slides | **`main` 0 of 20, the slide 5 of 20** — see the next section |

Row 8: in a trace logged from inside the pocket over eight reloads of the PR,
the old pocket released every member before the new one was created, every
time. That
order is what lets the README promise that a reload hands every widget back
before the new copy takes over.

Row 11: the slide relayouts the bar on every frame of the animation, about
20 ms of CPU per open or fold on this machine. The fix costs the same as the
PR.

## Accepted limit: a press on a sliding member can start a drag

The bar decides that a press became a drag by comparing the pointer's position
inside the pressed slot with where it was at the press. A slot that slides under
a still pointer moves the pointer inside it. The next real motion event — any
hand makes one during a click — then measures the whole slide as motion, and
past `Style.space(4)` the bar starts a drag. The release drops the widget where
the pointer is, and the bar writes the new layout.

Measured on the outermost member, which travels furthest: a press 0.27 s after
the hover began started a drag 5 of 5 times and moved `omaplug` out of the run,
in front of the tray. Presses at the other delays tried never did. Its remaining
travel after the hover began was 41 px at 0.21 s, 13 px at 0.30 s, 3 px at
0.40 s. Inner members travel less. A press on the tray, which slides too, never
started a drag in 10 tries.

Accepted by the owner rather than designed around: the window is the first
third of a second, a hand that sees the members before it clicks is slower than
that, and what goes wrong is a placement one drag undoes. Considered and
rejected: sliding only on the fold, which keeps the jump on open; and refusing
presses on a sliding slot, which would also swallow clicks. The cause is the
host's threshold being measured in slot coordinates, so the clean fix is the
host's.

## Found on the way, not caused by this change: a reload forgets inline settings

After a hot reload the pocket reads `pinned` and `members` as they were when
the shell last started. A pin set, a pin released, or a member dragged in after
that start is not seen by the reloaded pocket until the next restart: a pin
released before the reload reopens the pocket and holds it open, a member taken
in after it is drawn while the pocket is closed. `main` behaves the same way in
every run: a pin set 3 of 3, a pin released 2 of 2, a member dragged in 1 of 1.
It is left for a separate change.

> **Resolved 2026-10-29 by [0025](0025-a-reload-reads-the-entry-from-the-file.md).**
> The cause is the host's (omacom/omarchy#7691); the reloaded pocket now takes
> its entry from `shell.json`.

## Consequences

The README says the slots are narrowed as well as hidden, names the press
during the slide under "Good to know", and no longer claims a hot reload
rebuilds the slots. `tests/qml/extent.qml` holds the hand-back across an
unloaded pocket.

What this does not cover:

- More than one monitor, a real keyboard and a real mouse. The owner tests
  these by hand.
- A theme change. Nothing here reads a colour.
- A drag deliberately started while the members still slide. It runs through
  the same threshold as the press above.

**Lesson.** A reload that loses state looks exactly like a reload that breaks
the change under test. Two of the "defects" first seen here were the inline
settings above, and only the same script against `main` told them apart. When a
reload is part of a scenario, run it on the base first.
