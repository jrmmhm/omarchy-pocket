# 2. Members belong on one side of the pocket

- Status: accepted
- Date: 2026-08-27
- Extends: [0001](0001-pocket-writes-its-own-members.md)

## Context

0001 decided that a widget dropped onto the pocket joins it, and that the
decision reads the bar's own drop target. It left the drop rule split by edge:
the inner edge took a widget in, the outer edge did not.

Measured on a real bar, that split was wrong. The mark is one narrow icon, and
giving its two halves opposite meanings meant half of the thing you aim at did
the opposite of what aiming at it looks like — a widget approaching from the
far side had to be dragged *past* the pocket before it would arm. So the rule
changed: aiming at the pocket takes a widget in from either side.

That created a second problem. The bar places the dropped widget where its own
drop marker said, so a far-side arrival lands on the far side and then fans out
alone on one side of the mark while the rest of the group is on the other. It
reads as the pocket having lost it.

## Options

**A — Revert to the inner edge only.** Costs nothing and places every arrival
correctly. Rejected: it is the behaviour that was measured as wrong.

**B — Correct the placement as part of the drop.** Cannot work. The bar
persists its own move *after* this plugin has written, and would overwrite any
correction made first. That move also reassigns the layout, which destroys and
rebuilds every widget on every monitor, so the instance that wrote the
correction is gone before it could make a second attempt.

**C — Let members live on both sides and fan out around the mark.** No write at
all, and arguably honest. Rejected on the same evidence as A: a split group is
what the user reported as broken.

**D — Turn it into a standing invariant.** Chosen.

## Decision

Members belong on the side the pocket fans them out towards. A member that is
not there is moved back against the pocket — as a property of the
configuration, checked on sight, not as a step in any gesture.

This is what makes it work at all: the instance that can see the misplacement
is the one the drop's own rebuild created. It also repairs a hand-edited
config, which is the better half of the bargain.

Two properties keep it safe. It is **idempotent** — a member already on the
correct side is left exactly where the user put it, so it never fights the
ordering inside the run. And it **converges** — every pass moves one widget to
the correct side, and no rule moves one back.

The repair is deferred rather than run from its handler. A bar surface exists
per monitor, all of them reach the conclusion at the same instant, and an
inline write would rebuild the bar from inside the Repeater still creating the
delegates that asked for it.

This widens what the plugin writes from membership to order, which 0001 did not
foresee. It stays inside `bar.layout`, so the promise that no widget ever leaves
the layout is untouched.

## Consequences

Accepted cost: a far-side drop pays two bar rebuilds instead of one. Dropping
from the side the members are already on pays the usual single rebuild, which is
what any widget reorder costs in Omarchy with or without this plugin.

[0003](0003-steering-the-bar-s-own-drop-marker.md) removed that cost wherever
the override applies, which is every section but `left`. The invariant is
unchanged and still guarantees the result; it simply has nothing to repair.

This file owns the number. Measured on the user's three-monitor session by
sampling the shell process's CPU time across a write: **1.45 s** for a layout
order change (three samples, 1.45 / 1.47 / 1.45), against **0.05 s** for a
members-only change. The gap is what 0001 relies on when it writes membership
ahead of the bar's own move; it is also why a second order change is worth
arguing about at all. Every other file states the cost qualitatively and points
here.

Re-measured on 2026-08-27, after 0003, on the same session and the same way —
and this time counting the writes with inotify rather than sampling for them,
because a poll can miss two writes that land inside one interval:

| what | writes to `shell.json` | CPU | rebuilds |
| :--- | :--- | :--- | :--- |
| a members-only change | 1 | 0.07 s | 0 |
| one layout order change | 1 | 1.21 s | 1 |
| a hand-edited wrong side, repaired by the invariant | 2 | 2.53 s | 2 |
| a far-side drop, with the override | 2 | 2.28 s | 1 |

The last row is the point. Two writes, one of them the cheap members-only
change and one the layout move — the repair write is absent, and the repair is
demonstrably a write of its own: given a hand-edited config with a member on
the wrong side, exactly one further write appears and the member ends up
against the pocket. The `left` section still pays the two-rebuild row.

Two adjacent ideas were refused during the same work, and are recorded here so
they are not re-proposed as oversights.

**Expanding the pocket after a successful add**, as feedback that the widget
went somewhere. It cannot work: the drop's own layout write rebuilds every
widget, and `expanded` is per-instance session state that the rebuild discards
milliseconds later. The feedback lives in the mark lighting up *before* the
drop instead, which is the better place for it anyway.

**Teaching `resolution` to prefer a drawn slot** over the hidden placeholder the
bar builds for every center widget when `centerAnchor` is set. The obvious
implementation reads `slot.visible` inside the binding that decides which slot
to set `visible` on — a loop, and one that would oscillate rather than settle.
Refused; the consequence is a README caveat instead: a member in the `center`
section with an anchor configured may bind the placeholder and never hide.

Whether to spend host coupling to avoid the extra rebuild was left open here
and is answered in [0003](0003-steering-the-bar-s-own-drop-marker.md), which
also records what validating that candidate against `Bar.qml` changed about it.
