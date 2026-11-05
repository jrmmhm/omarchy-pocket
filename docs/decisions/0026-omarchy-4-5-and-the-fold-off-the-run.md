# 26. Omarchy 4.5, and the fold off the run

- Status: accepted, revised the same day after the live run found the centre
  sections oscillating (section "Revised after the live run")
- Date: 2026-11-05
- Supersedes the fold guard of [0005](0005-a-pocket-drives-only-its-own-screens-slots.md)
  and option B's rejection in [0007](0007-the-two-host-limits-measured.md):
  the pocket now folds as soon as the pointer leaves the mark and its members
- Amends [0015](0015-the-host-answers-by-capability-now.md): the overlay's
  HoverHandler now says whether the pointer is over the run, not the bar
- Owns every number below; the README and the CHANGELOG name this file

## Context

Omarchy went from 4.0.6 to 4.5.0 on this machine on 2026-11-05 (quickshell
0.3.2, Qt 6.12.0). A first test of 0.6.2 on it found three things, and the
diff of the two packages' `shell/` trees explains each of them. The release
notes name the same three changes: "Improve dragging and arranging bar
widgets" (#15517), "Allow removing a bar widget by dragging it off the bar"
(#6782) and "Normalize bar icon size and alignment" (#15065).

**1. No widget went in or out by dragging.** In 4.0.6 the slot's
`onReleased` called `clearBarDrag()` at once. In 4.5.0 it calls
`settleBarDrag()`: the released widget's ghost glides to where it lands, and
`clearBarDrag()` runs only when it gets there (`barSettleAnimation`, 180 ms;
synchronous where Hyprland's animations are off). The pocket's overlay sees
the button come up at the start of the glide. Its drop target went with it,
`dropDecision()` answered "no target, nothing to do", and that answer replaced
the one the release had meant before the drag ended and `commitDrop()` read
it. The host moved the widget all the same, so a member dragged past the mark
landed on the far side and stayed a member. The order is the engine's: Qt
delivers a release to the exclusive grabber before the passive ones
(`QQuickDeliveryAgentPrivate::deliverUpdatedPoints`), which is why 4.0.6, which
cleared the drag inside that first delivery, never showed it.

The same version made each bar window span its whole screen and paint the bar
as a strip along one edge (`BarPanel`'s `barStrip`). The pocket's "off the bar
is no target" test compared against the window, so a release below the strip
still counted as a drop.

**2. The mark sat off the middle.** `Ui/OpticalGlyph.qml` now fits a bar icon
to its painted bounds. Measured offscreen with the real `BarIconButton` and
JetBrainsMono Nerd Font in a 27×26 slot, ink centre against the slot's
(13.5, 13.0):

| Glyph, rotation | 4.0.6 | 4.5.0 |
|---|---|---|
| `U+F01D8` dots-horizontal, 0° (closed) | (14.0, 12.5) | (13.5, 11.0) |
| `U+F01D8`, 90° (open) | (14.5, 13.5) | (16.0, 13.0) |
| `U+F01D9` dots-vertical, −90° | (14.0, 13.5) | (13.5, 13.0) |
| `U+F01D9`, 0° | (14.5, 12.0) | (13.5, 13.0) |

The host's own `opticalCenterErrorX/Y` read 0 for all of them.

**3. The pocket folded only once the pointer left the whole bar.** Nothing
changed in the host here: that was the guard 0005 and 0007 kept, against an
oscillation and for parity with the host's centre reveal. The user asked for
the pocket to fold as soon as the pointer leaves the mark and its members.

## Decision

**The release seals the intent.** On the overlay's path, `onDropIntentChanged`
records an intent only while the overlay holds the button down, and the
moment the button comes up during a drag the intent is sealed until the drag
ends. Asked of the overlay directly, because which of the two handlers runs
first on the release is the engine's choice. Sealed rather than only gated,
because a press during the glide is what makes the host finish it, and that
press must not re-aim a drop already released. A host that publishes the drag
itself is untouched.

**The strip is the bound.** A drop counts only over the item the bar paints
itself in: the pocket's ancestor directly under the surface root. On 4.5.0
that is `barStrip`, a notch floor included; on 4.0.x it is the loader that
filled the window, which was the strip. Found by structure, so no size or
edge has to be known.

**The mark is the upright dots, laid flat.** `U+F01D9` turned by
`(vertical ? 90 : 0) − 90 + revealProgress × 90` is the picture `U+F01D8`
turned by `(vertical ? 90 : 0) + revealProgress × 90` was, at every angle, and
it is centred to the pixel on 4.5.0 and as close as before on 4.0.6.
`tests/qml/glyph.qml` asks the pixels, with 1 px of tolerance.

**The pocket folds off the run.** The fold timer no longer waits for the
pointer to leave the bar. It folds on the second tick in a row (120 ms each)
on which nothing holds the pocket open: no hover on the mark or a member, the
pointer not over the run, no pin, no member's panel, no drag. The run is the
span along the bar from the mark to the last member drawn in its own section,
across the whole depth of the strip, and where the pointer is comes from the
overlay's surface HoverHandler (`pointerOnRun()`). A lock takes the pointer's
say away here as it does in `holdOpen`. A host that publishes its drag builds
no overlay and still publishes `barHovered`, and there the pocket waits for
the bar as before.

Folding cannot slide the mark back under a pointer that has left the run:
every widget moves towards its section's anchor, and in `centerEnd` and the
centre box, where the mark itself moves, it moves towards the run it ends.
What does move under such a pointer is the neighbour it rests on. That is the
cost, and the parity with the host's centre reveal 0007 named is given up for
it.

## Revised after the live run

The first build folded on hover alone, and dropped the overlay's HoverHandler
as unused. Its argument above covered folding and not opening. In `centerEnd`
(and the centre box) opening the pocket puts the members before the mark and
slides the mark away from the pointer that opened it. The member that slides
under that still pointer reports no hover, because Qt hovers on motion, and
the mark no longer did either. The pocket folded, the mark slid back under the
pointer, and it opened again: open and shut in turn, about every 0.8 s, for as
long as the pointer rested there, measured on the live bar with the run in
`centerEnd`. 0005's guard had been hiding exactly this.

So the HoverHandler is back, with `rearmHover()` and `retire()` and the probes
in `tests/qml/facade.qml` that pin them, and the fold asks it whether the
pointer is over the run rather than over the bar. After the slide the pointer
is over a member, inside the run, and the pocket stays open. The PointHandler,
and the overlay's ownership rules of 0017, are unchanged.

## Alternatives

- **Freeze the last drop target instead of the intent.** It needs state in a
  binding and changes the mark's light during the glide too. The seal sits at
  the one place that keeps the result.
- **Port the host's new drop rules** (`ownRoomTarget`, the centre box's
  reach, the tray drawer's zone) into the pocket's `localDrop`. They change
  whether a drop is "in" or "out" only at the edges of the centre box and of
  the tray drawer, at the price of three more copies of host arithmetic. Left
  as the known gap below.
- **The strip from `barSize`.** The facade's `barSize` is the configured size;
  a notch floor makes the strip thicker on that screen, and the facade does
  not say by how much.
- **Correct `U+F01D8` by a measured offset, or draw the dots ourselves.** The
  first breaks the next time the host's fitting changes; the second is more
  code than a glyph that is already centred.
- **Hover alone, without the HoverHandler.** The first build; it oscillates in
  the centre sections (above).
- **The old guard, "wait until the pointer leaves the bar", kept for the centre
  sections only.** It needs the same HoverHandler and gives the pocket two
  rules depending on where it sits.

## Consequences

- A drop near the edge of the centre box or of the tray's drawer can be read
  "in" or "out" differently from where the host places the widget.
- A widget pulled more than 48 px off the bar is removed from the layout by
  the host (#6782). The pocket reads that release as no drop, so a member
  removed this way stays named in `members`, and the tooltip reports it as
  missing. Not handled; noted for a later version.
- A drag the host cancels (a layout written mid-drag, 0024's refusal of a
  self-drag) still commits the last intent, as it did before.
- The mark's glyph is measured with JetBrainsMono Nerd Font only, the one
  installed here; Nerd Fonts carry the same Material Design set.
- Fetching a widget from elsewhere on the bar folds the pocket on the way, so a
  widget dropped on the mark's near half usually joins the collapsed group, at
  its far end rather than beside the mark. Measured: dragged from the right of
  the mark in `right`, it landed first in the run.
- A long run in `centerEnd` on a narrow screen reaches the right section, and
  4.5.0 opens the tray's drawer over it during every drag
  (`Bar.qml::traySectionDragActive`). A drop aimed at the mark there lands in
  the tray's section, for the host and the pocket alike: measured with six
  members at 1152 logical px, the drawer at x = 880 over the mark at 878.

## Seen on 4.5.0 and not acted on

- The section rows are a `GridLayout` now, which sizes each slot from its
  `Layout.preferredWidth`. 0023's sliding neighbours rest on writing the
  slot's `width`, and no longer slide: measured, the tray beside the run jumps
  by the run's whole length in the first frame of the reveal (907 → 687).
- `moduleSettings` moved from the slot to the new `WidgetHost`, so 0025's
  repair never engages on 4.5.0; the host now hands a widget its entry's
  settings again whenever they change.

## The live run

`tests/live.sh --full --system` on eDP-1 alone (1152×720 logical), Omarchy
4.5.0, Hyprland animations on unless the block turns them off: 87 checks, 87
passed, `shell.json` restored byte for byte. The blocks:

- display: shut, nothing drawn; the mark's ink 0.0 px across and 0.03 px down
  from the slot's middle shut, 0.0–0.3 px across open; the tooltip names the
  six members, both clicks and the member not on the bar;
- fold: off the mark onto the next widget, off the outermost member onto the
  widget before the run, down off the bar; held along the bottom edge of the
  strip, zig-zagging across the members, out and back within 0.1 s, resting on
  the mark; no reopening after any fold within 3 s;
- pin and lock: left and middle click, right click with the pointer on the
  mark, a left click on a locked pocket, a right click on a pinned one, each
  written to this screen's name;
- drag: out past the mark, the far half refused, in on the near half and lit,
  a reorder inside the run with `members` following the bar, out by the clock,
  a release 20 px below the bar, a press during the glide, a widget dropped
  beside the shut pocket, the mark's own drag refused, a 1.5 s drag across the
  bar with the pocket held open, and a member pulled off the bar (removed by
  the host, still named, nothing broken);
- panels: a member's panel holds the pocket open and folds it when closed,
  summoned by IPC it opens the pocket, locked or not; another panel opens
  nothing;
- reload: a rescan keeps the pin and writes nothing stale; a restart hides the
  members again;
- system: animations off; the pocket in `left`, `centerEnd` (fold and rest
  only, see Consequences) and `centerBegin`; a vertical bar.

`tests/live.sh --gesture` and `tests/live.sh` passed on the same build.

## Review

A fresh-context review of the plan raised ten findings. Taken: the seal for a
press during the glide, a test for each order of release and drag end, the
strip found by structure, the second idle tick, the `retire()` call in
`detachOverlay()`, `docs/media.md`, and a 1 px glyph tolerance. Refused, with
the reasons above: porting the host's drop rules and drawing the dots. Its
suggestion to keep the HoverHandler and narrow the guard to the run was
refused at first and is what the live run made necessary. Noted, unchanged:
the cancelled drag, and the member removed off the bar, which the user left
out of this change.
