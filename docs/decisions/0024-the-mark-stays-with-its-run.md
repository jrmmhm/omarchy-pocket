# 24. The mark stays with its run

- Status: accepted
- Date: 2026-10-28
- Replaces the README's "dragging the pocket itself does not take its members
  along" with a refusal, and records the colour fix found on the way
- Owns every number below; the README and the CHANGELOG name this file

## Context

Two reports from a hand test, both reproduced on `main` (81c9049) with a uinput
pointer:

1. The mark dragged to the right of `omarchy.bluetooth` left its members where
   they were. They fanned out left of `omarchy.agents`, apart from the mark.
2. The mark dragged, while open, between `agx.screen-time` and `mehiel.darky`
   stayed there. The run was split around it, and the members on the wrong
   side fanned out the other way.

The bar moves only the entry that is dragged. The placement repair that would
put a member back beside the mark needs `bar.shell.mutateShellConfig`, and from
Omarchy 4.0.3 on the plugin's `bar` is `Ui/PluginBarApi.qml`, whose `shell` is
`null`. So neither state can be repaired after the drop, and neither can the
drop be steered: the facade publishes no `barDrag*` property.

Omarchy 4.0.6, quickshell 0.3.2, Qt 6.12.0. eDP-1 (1152×720 logical) alone,
then with HDMI-A-1 (ASUS VG289, 1600×900 logical) beside it.

## Decision

While a member stands directly against the mark, on the side it fans out from,
a drag of the pocket's own slot is refused. `Model.hasRun()` decides; only the
neighbour counts, so a mark that already stands apart from its members can be
dragged back to them, and an empty one moves as before.

The refusal disables the pocket's slot for a moment. Disabling an item takes the
pointer grab from everything in it, so the bar's `MouseArea` receives
`canceled` instead of `released` and drops nothing. It runs from `Qt.callLater`:
the pocket learns of the drag inside `Bar.qml`'s position handler, at the line
that names the drag source, and the handler sets `dragging` after that line. A
cancel from inside would leave `dragging` set with no grab behind it, and the
next press on the mark would drop it wherever the pointer went.

The owner chose the mark staying with its run over a tooltip that only explains
the split. Moving the whole group now means dragging the members out, moving the
mark, and dragging them back in, or `omarchy bar move`.

## What was measured

Each row ran six times unless it says otherwise. `shell.json` was snapshotted
first and compared byte for byte after every run that could write it.

| # | Scenario | Result |
| :--- | :--- | :--- |
| 1 | Mark dragged away, collapsed, on eDP-1 | refused 6/6, config unchanged |
| 2 | Mark dragged between its members, open, on eDP-1 | refused 6/6 |
| 3 | Left click after each refusal pins, second click unpins | 6/6 |
| 4 | Pointer leaves the bar after a refusal | folds 12/12 |
| 5 | `tests/live.sh --gesture`, member out and back in | passed 6/6 |
| 6 | Mark with no member on the bar | moves 6/6 |
| 7 | Mark already apart from its members, dragged back to them | moves 6/6 |
| 8 | Fast flick: press, 8 moves in about 30 ms, release at once | refused 6/6; the same flick moved an empty mark 3/3 |
| 9 | Pocket and two members in `left`, collapsed and open | refused 6/6 |
| 10 | Drag-ghost layer during a refused drag | in 0–4 of about 670 polls (at most two frames), against 103 for an allowed drag |
| 11 | Two monitors, on each: hover, fold, pin, unpin, refusal | 3/3 per screen; the other screen's pocket untouched every time |
| 12 | Two monitors, gesture per connector | passed 3/3 per connector |

Row 8 is the race a reviewer raised: motion past the threshold and the release
in one batch of events, so that the release runs before the deferred refusal.
It did not happen in the six flicks tried, but nothing rules it out: a refusal
that finds the drag already over does nothing, and the drop stands. Row 10: while the ghost is mapped its
image has not been captured yet, so nothing is drawn in it.

## Found on the way: the theme colours read as nothing on Qt 6.12

QtQuick has a `Color` singleton of its own, and on Qt 6.12 it shadows the one
in `qs.Commons`: a bare `Color.accent` and `Color.urgent` are `undefined`,
while `Commons.Color.accent` through a qualified import is the theme's. The mark
lights in `Color.accent` when a drag would let a member go, so that colour was
never applied and the mark kept the colour of taking a widget in. The same
shadowing made `tests/qml/noslots.qml` and `tests/qml/neighbourhood.qml` fail on
every machine with Qt 6.12. Both now read the colours qualified, as `Bar.qml`
and `Ui/WidgetButton.qml` do, and the whole harness passes.

The lit colour during a drag could not be read off a screenshot: the drag ghost
of the dragged widget sits on the mark, because it follows the pointer. A pinned
mark showed `bar.active` (#f25577 in Solace Neon).
`tests/qml/neighbourhood.qml` holds the colour for letting a member go.

## Consequences

`tests/qml/selfdrag.qml` drives a pocket on both host shapes: the mark's drag is
refused after the naming handler and not inside it; a member's drag and a drag
already over are left alone; and a mark apart from its members can still be
dragged. `tests/model-test.js` holds `Model.hasRun()`.

What this does not cover:

- A drop of some other widget between two members of an open run. Membership
  does not change and the run is split the same way; the refusal is about the
  mark's own drag only.
- On Omarchy 4.0.2 and older, the placement repair could put a split run back
  together, and dragging the mark into its run was harmless there. The refusal
  applies on those hosts as well.
- Members that all hide themselves still count as a run: the mark cannot be
  dragged while none of them is drawn.
- A mark already apart from its members may be dragged, so it can still be
  dropped between them from there.
- Two configurations the tooltip already reports as mistakes: with a second
  pocket entry in the same section, `Model.hasRun()` judges the first entry for
  both; and a `centerAnchor` widget listed as a member, standing against the
  mark, counts as a run although it is never hidden.
- Touch input.
