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

Accepted cost: a far-side drop pays two bar rebuilds instead of one — measured
at about 3 s rather than 1.5 s on a three-monitor session, where a rebuild
re-instantiates every widget on every screen. Dropping from the side the members
are already on pays the usual single rebuild, which is what any widget reorder
costs in Omarchy with or without this plugin.

The open question is whether to spend host coupling to avoid it: overriding
`barDragAfter` and the drop-marker geometry during the drag would make the bar
place a far-side arrival correctly in the first place, halving the cost, at the
price of writing three of the bar's internal properties mid-gesture. If a future
Omarchy changed them, the override would simply stop applying and this invariant
would still guarantee the result — so the fast path could degrade to the slow one
rather than to a defect. Deferred, not rejected.
