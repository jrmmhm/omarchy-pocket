# 1. Pocket writes its own `members`

- Status: accepted, extended by [0002](0002-members-belong-on-one-side.md)
- Date: 2026-08-27

## Context

Until now Pocket only read. It resolved the `members` setting against
`bar.moduleSlots` and flipped `visible`, `opacity` and `scale` on other
widgets' slots. It wrote nothing, and its README promised exactly that:
*"No network access, no subprocesses, no files written."*

Making membership a drag gesture breaks that promise, because membership has
to survive a restart and the only place it can live is the plugin's own entry
in `~/.config/omarchy/shell.json`.

Two facts decide how that write may happen. First, the bar already owns a
drag-and-drop of its own: dragging a widget reorders `bar.layout` and the bar
persists that itself through `shell.mutateShellConfig`, whose `FileView` has
`atomicWrites: true`. A sanctioned, atomic write path therefore exists, and
the old fear of "a half-written `shell.json`" was unfounded. Second, a write
that changes only inline widget settings does not rebuild the bar:
`applyBarConfig` routes it through `BarModel.inlineSettingsDelta` and patches
the running widgets in place. A `members` write is exactly such a write, so
Pocket survives its own.

## Options

**A — Sample the drag and write when it ends.** Watch `barDragSource`,
`barDragTarget` and the pointer position, decide on the transition to null.
Rejected in this form: `clearBarDrag()` is called from four places in
`Bar.qml` and only one of them is a drop, and Qt emits `MouseArea.canceled`
*instead of* `released` with nothing to tell them apart. Writing during that
notification also runs inside the bar's own release handler, where hiding the
slot that was just dropped revokes its mouse grab mid-handler.

**B — React to the committed layout instead of the drag.** Only a real drop
reassigns `layoutConfig`, so a cancelled drag would commit nothing. Rejected:
a drop that moves a widget to where it already was commits nothing either, and
that is a legitimate gesture whose result would be silently lost. The widget
instance is also destroyed by the rebuild the commit causes, so the intent
would have to survive outside it.

**C — Replace the member list with a boundary id** (`from: "…"`), deriving
membership from layout adjacency, so the bar's own reorder is the whole
feature and Pocket keeps writing nothing. Attractive, and its central insight
is adopted below. Rejected as the primary design because dragging the
*outermost* member out moves the boundary itself and empties the pocket in one
gesture, and because an explicit list is what the tooltip's diagnostics —
missing, refused, foreign, rejected ids — are built on.

**D — Sample the drag, but take the decision from the host's own drop
marker.** Chosen.

## Decision

Membership is decided by `bar.barDragTarget` and `bar.barDragAfter` — the same
two values the bar uses to draw its drop marker — and never by pointer
coordinates. Comparing `barDragTarget` against this instance's own slot is an
object identity test, so it is correct per monitor and per center-anchor
placeholder without any coordinate mapping.

Aiming at the Pocket takes a widget in, from either side. A member released on
the far side of it, or on any target that is neither the Pocket nor another
member, leaves. (This decision originally split the two edges — inner takes in,
outer does not — which 0002 replaces on measured evidence.)

The write goes through `bar.shell.mutateShellConfig`, touches only this
plugin's own layout entry — its `members` key here, and under 0002 the position
of a member that ended up on the wrong side — operates on the *raw*
setting so ids the parser rejects are not silently deleted from the user's
file, preserves the shape it found (a comma string stays a string), and is
refused outright when more than one Pocket entry exists in `bar.layoutConfig`.

Adopted from option C: the member list is kept in **layout order**, so the
reveal cascade always runs in the direction the widgets physically sit.

Accepted limitation: a drag cancelled from outside while the Pocket is armed
is indistinguishable from a drop and will take the widget in. It is recorded
in the README rather than papered over.

## Realization

Shipped in 0.2.0. `Model.js` holds the decision (`dropDecision`), the list it
produces (`nextMembers`, `orderMembers`, `withoutMember`, `membersValue`) and
the write itself (`setMembersOnEntry`); `BarWidget.qml` only observes the bar's
drag properties and calls them. Every refusal has a negative fixture beside it
in the suite.

The write refuses rather than scaffolds: if the section this pocket claims to
live in is absent from the config, there is nothing here to edit, and creating
it would be the host's business. That is what keeps "the only thing Pocket
writes is its own entry" literally true.

Two things had to be learned by running it rather than by reading the host.

The write must run *synchronously*, ahead of the bar's own move, because that
move rebuilds every widget on every monitor and a deferred callback would reach
for an instance that no longer exists. It is safe to run first: a members-only
change is an inline settings change, which the bar patches into the running
widgets instead of rebuilding them, at a fraction of the cost
([0002](0002-members-belong-on-one-side.md) owns the measurement).

And the widget just taken in must be held *visible* until the bar's release
handler has returned. Qt cancels a pressed `MouseArea` the moment its item goes
invisible, and that `MouseArea` is still mid-release: hiding the slot any earlier
revokes its grab, clears the bar's click suppression, and turns the drop into a
click on the widget that was dropped. Dropping the power widget into the pocket
would have opened the power menu.
