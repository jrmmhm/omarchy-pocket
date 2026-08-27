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

This file owns the number, and every other file states the cost qualitatively
and points here.

**One layout order change costs 1.2 to 1.5 s of shell CPU. A members-only
change costs under 0.1 s and is not a rebuild at all.** Measured on the user's
three-monitor session by sampling the shell process's `utime + stime` across a
write, with the shell otherwise idle: 1.45 / 1.47 / 1.45 s on 2026-08-26, and
1.21 / 1.36 s on 2026-08-27; 0.05 s and 0.07 s for members-only on those same
days. The spread across sessions is the honest precision of this measurement,
and nothing in either decision turns on the third digit. The gap between the
two is what 0001 relies on when it writes membership ahead of the bar's own
move; it is also why a second order change is worth arguing about at all.

Re-measured on 2026-08-27, after 0003. The writes are counted with inotify
rather than sampled for, because a poll can miss two writes that land inside
one interval — and the claim below is a write count:

| what | writes to `shell.json` | rebuilds | CPU |
| :--- | :--- | :--- | :--- |
| a members-only change, shell idle | 1 | 0 | 0.07 s |
| one layout order change, shell idle | 1 | 1 | 1.21 s |
| a hand-edited wrong side, repaired by the invariant, shell idle | 2 | 2 | 2.53 s |
| a far-side drop, with the override — **whole gesture** | 2 | 1 | 2.28 s |

The last row is the point, and the column that carries it is the write count,
not the CPU. Two writes: the cheap members-only change and the layout move. The
repair write is absent — and the repair is demonstrably a write of its own,
because given a hand-edited config with a member on the wrong side, exactly one
further write appears and the member ends up against the pocket. One layout
write is one rebuild.

The CPU figure in that row is not comparable with the three above it and is
listed only for completeness: those are single writes with the shell otherwise
idle, while this one covers the whole gesture — the drag itself, the ghost
window the bar renders under the pointer, the drop, and the pocket folding the
new member away on three monitors. Its own components account for 1.28 s of it
(1.21 + 0.07); the rest is the gesture. Read as a CPU comparison the row would
suggest a 10% saving, which is why it is labelled rather than left to be
misread. What the change removes is the second row's worth of work — one
rebuild, 1.2 to 1.5 s — and the `left` section still pays it.

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
