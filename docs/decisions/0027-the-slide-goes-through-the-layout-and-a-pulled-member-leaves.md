# 27. The slide goes through the layout, and a member pulled off the bar leaves

- Status: accepted
- Date: 2026-11-05
- Amends [0023](0023-the-neighbours-slide-with-the-reveal.md): where a layout
  sizes the slots, the extent is driven through the slot's
  `Layout.maximumWidth` (`maximumHeight` on a vertical bar) and handed back
  with `-1`; the reset of `width` and `height` stays for a `Row` or `Column`
- Resolves two items [0026](0026-omarchy-4-5-and-the-fold-off-the-run.md)
  left open: the neighbours that no longer slid, and the member pulled off the
  bar that stayed named in `members`
- Narrows the structural anchor test of
  [0015](0015-the-host-answers-by-capability-now.md) (`anchoredByStructure()`)
  to slots no layout sizes
- Owns every number below; the README and the CHANGELOG name this file

## Context

Omarchy 4.5.0, quickshell 0.3.2, Qt 6.12.0, one monitor: eDP-1, 1152×720
logical, bar on top, the pocket in `right` with six members on the bar and one
that is not (`io.github.ilyazar.syncthing`).

**1. The neighbours jumped.** 4.5.0 lays each section out with a `GridLayout`
(`Bar.qml::ModuleList`). A layout does not read a child's `width`: it sizes it
from its `Layout.*` hints, and the host binds the slot's
`Layout.preferredWidth: implicitWidth` (`Bar.qml::ModuleSlot`), the slot's full
size. The pocket wrote `width`, the next layout pass overruled it, and the
moment the members became visible the layout gave them their whole room: the
tray jumped by the run's length in one frame, opening and closing (0026, "Seen
on 4.5.0").

**2. A member pulled off the bar stayed named.** A widget let go of more than
`Style.spaceReal(48)` past the bar strip is removed by the host
(`Bar.qml::removeBarDrag`); closer than that the drag settles and the widget
goes back (`settleBarDrag`). `removeBarDrag` sets `barRemoval` first, which
makes the slot's `removalPending` true, then clears the drag, and the entry
leaves the layout only after the widget's poof has played
(`commitBarRemoval`, from `poofTimer`, 620 ms). Off the strip the pocket saw no
target and kept the member.

**3. Found on the way: a member in `center` was refused.** The structural
anchor test told the ≤4.0.x centre-anchor slot apart by a parent without
`spacing`. A `GridLayout` has no `spacing` either, and 4.5.0 has no centre
anchor at all, so every member in the `center` section was reported as the
anchor and never hidden. `centerBegin` and `centerEnd` were not affected.

## Decision

**The pocket caps the size; the host still prefers it.** A Qt Quick layout
gathers each child's minimum, preferred and maximum and clamps an explicit
preferred size into [minimum, maximum]
(`qquicklayout.cpp::effectiveSizeHints_helper`, `normalizeHints`). So the
pocket writes the slot's `Layout.maximumWidth` (`maximumHeight` on a vertical
bar) with `Model.revealExtent()`, and the host's own `preferredWidth` binding
stays where it is. Measured offscreen on Qt 6.12.0 with a slot carrying the
host's two lines:

| Pocket writes | Slot width | Next slot's x |
|---|---|---|
| nothing | 40 | 70 |
| `maximumWidth` 0, 10, 20, 30 | 0, 10, 20, 30 | 30, 40, 50, 60 |
| `maximumWidth` −1 | 40 (reads back `Infinity`) | 70 |
| then the widget grows to 70, shrinks to 0 | 70, 0 | 100, 30 |
| `width` 33 under a maximum of 5 | 5 | 35 |

The last row is the defect: a written width does not survive the layout.

**Handed back by `-1`.** Qt documents `-1` as "back to the implicit maximum",
which for an item that is not itself a layout is no limit. A constant, so no
binding of the pocket's own is left on the slot and a hot reload cannot freeze
a member (0023). The host's preferred-size binding was never broken, so the
hole its comment guards against (a layout falling back to the old width when
the implicit size drops to nothing) cannot come back: the member followed its
widget to 0 above.

**Asked of the slot's parent.** `layoutSized()` is true when the slot's parent
is a `GridLayout`, `RowLayout` or `ColumnLayout`, asked every time, never of a
version. A `Row` or `Column` host keeps the `width` and `height` path,
character for character.

**A removal is the host's, and the pocket waits for it.** On the rising edge
of a drag the pocket notes the slot and whether it is one it hides
(`driven`). On the falling edge a slot that reports `removalPending === true`
means no drop; if it was a hidden member, its id and the number of layout
entries that carry it are noted (`awaitRemoval()`). When the layout next
changes with fewer such entries, the host has written the removal and the
pocket takes that one id out of `members` (`forgetRemoved()`): no reordering,
and a member missing for another reason stays. Without such a change within
`removalPatience` (3 s) the note lapses.

**The centre box is a section.** A slot a layout sizes is never taken for the
centre anchor.

## Alternatives

- **Write `Layout.preferredWidth`.** It replaces the host's binding, and
  handing back by `-1` would bring back the hole the host's binding is there
  to prevent. Restoring the binding needs a binding the pocket owns.
- **Write `implicitWidth`.** Also the host's binding.
- **A held `Binding` element.** Rejected in 0023 for its release-order and
  direct-write failures.
- **Forget the member at the release.** The host writes `shell.json` after
  the poof because persisting stalls the render loop, and a write at the
  release lands in the poof; a removal the host then never writes (a reload
  in those 620 ms, a layout changed under it) would leave the widget on the
  bar and out of the pocket.
- **Prune every member whose entry is gone from the layout.** That also drops
  a member that is merely missing, such as an uninstalled plugin.
- **Decide by id.** The host lets one id be added twice; pulling off the copy
  the pocket does not hide would have released the one it does.
- **Tell the centre box by `columnSpacing`.** A `Grid` positioner has that
  too; the layout test is the one `layoutSized()` already makes.

## Consequences

- A member grabbed while it is still sliding out keeps a capped room in the
  host's drag until the reveal ends (`ModuleSlot.alongLength` reads the capped
  preferred size). Visual, under 600 ms.
- A host that binds `Layout.maximumWidth` itself would lose that binding to
  the pocket's write, as one that bound `width` would have under 0023.
- A removal the host writes more than 3 s after the release is not followed.
- `forgetRemoved()` goes through `Model.toList()` like every gesture, so a
  hand-written `members` with an id the parser rejects comes back rewritten
  (the order repair refuses that case; a gesture is asked for).
- Found, not acted on: `Model.countEntries()`, and so `mayWrite()` and the
  tooltip's second-entry line, count `left`, `center` and `right` only. 4.5.0
  also has `centerBegin`, `centerEnd` and the tray's section, so a second
  Pocket entry there is not counted.

## The live run

To be filled from the run on the release candidate.

## Review

A fresh-context review of the plan raised eight findings, all taken or
recorded: the removal waits for the host's write instead of acting at the
release; it matches the hidden slot, not the id; a destroyed slot reads as no
removal; the centre fix gets its own commit and a live check (G37, `center`);
the two new host dependencies are named in the README; the live slide check
is judged by its largest step, with timestamps; the capped drag room is a
consequence above; the offscreen cases wait for the layout's polish and cover
a duplicate id. Its alternative for the centre (`columnSpacing`) was refused
above. The first live run then failed the opening slide everywhere at exactly
0.20 s: the sampler started after `Pointer.warp()` returned, which waits a
fifth of a second, so the first third of the reveal went unseen. The trigger
now runs on its own thread; the folding samples, taken the same way after a
fold delay, had shown the slide all along.
