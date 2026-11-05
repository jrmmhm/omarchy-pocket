# 26. Omarchy 4.5, and the fold off the run

- Status: accepted
- Date: 2026-11-05
- Supersedes the fold guard of [0005](0005-a-pocket-drives-only-its-own-screens-slots.md)
  and option B's rejection in [0007](0007-the-two-host-limits-measured.md):
  the pocket now folds as soon as the pointer leaves the mark and its members
- Amends [0015](0015-the-host-answers-by-capability-now.md): the overlay carries
  the drag's PointHandler only, and its HoverHandler is gone
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
on which nothing holds the pocket open: no hover on the mark or a member, no
pin, no member's panel, no drag. One idle tick is a pointer crossing a sliver
no slot covers, on a diagonal or under a widget shorter than the bar.

The oscillation 0005 guarded against does not exist. Folding moves every
widget towards its section's anchor: in `right` and `centerBegin` the mark
stays and what is before the run slides towards it; in `left` the mark stays
and what is after the run slides towards it; in `centerEnd` and the centre box
the mark itself slides, but towards the run it ends, never past the run's old
extent. A pointer that has left the run is never brought back onto the mark or
a member, and only a hover on one of them opens it. What does move under such
a pointer is the neighbour it rests on. That is the cost, and the parity with
the host's centre reveal 0007 named is given up for it.

The overlay's HoverHandler fed only that guard, and goes with it, with
`rearmHover()` and `retire()`. The PointHandler, and the overlay's ownership
rules of 0017, stay.

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
- **Keep the HoverHandler and narrow the guard to the run's span along the
  bar.** It keeps the handler whose stuck hover 0015 measured, to cover the
  slivers two idle ticks already cover.

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

## Seen on 4.5.0 and not acted on

- The section rows are a `GridLayout` now, which sizes each slot from its
  `Layout.preferredWidth`. 0023's sliding neighbours rest on writing the
  slot's `width`.
- `moduleSettings` moved from the slot to the new `WidgetHost`, so 0025's
  repair never engages on 4.5.0; the host now hands a widget its entry's
  settings again whenever they change.

## Review

A fresh-context review of the plan raised ten findings. Taken: the seal for a
press during the glide, a test for each order of release and drag end, the
strip found by structure, the second idle tick, the `retire()` call in
`detachOverlay()`, `docs/media.md`, and a 1 px glyph tolerance. Refused, with
the reasons above: porting the host's drop rules, drawing the dots, narrowing
the guard. Noted, unchanged: the cancelled drag, and the member removed off
the bar, which the user left out of this change.
