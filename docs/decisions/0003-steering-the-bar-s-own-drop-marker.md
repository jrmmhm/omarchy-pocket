# 3. Steering the bar's own drop marker

- Status: accepted
- Date: 2026-08-27
- Resolves the open question in [0002](0002-members-belong-on-one-side.md)

## Context

0002 chose a standing invariant to keep members on one side of the pocket, and
accepted its cost: a widget dropped onto the pocket from the far side is placed
there by the bar and then moved back, which is a second layout write and
therefore a second full bar rebuild. 0002 owns the measurement; it left open
whether to spend host coupling to avoid the second rebuild.

## Options

**A — Leave it.** Costs nothing and stays uncoupled. The gesture is rare, and
the price is a permanent dependency on host internals.

**B — Correct the placement after the drop.** Already rejected in 0002: the
bar persists its move after this plugin has written, and rebuilds every widget
in the process.

**C — Tell the bar where the widget belongs, before it decides.** Chosen.

## Decision

While a drag would take a widget into the pocket, the pocket overrides the two
values `Bar.qml` uses to place a dropped widget — `barDragAfter` and
`barDragTargetGeometry` — so the bar places it against the pocket in the first
place. The invariant from 0002 stays exactly as it is, and remains the thing
that guarantees the result.

Three properties of `Bar.qml` shape the implementation, and all three were
measured rather than assumed.

**Both values are overridden together, from a change to either.** `Bar.qml`
assigns `barDragTarget`, then `barDragAfter`, then `barDragTargetGeometry`, on
every pointer move. Hanging the override on only the last of those would make
the result depend on that order: reversing the two assignments would leave the
`after` override silently overwritten while the geometry override survived, and
the bar would then draw its insertion line on one side of the pocket and place
the widget on the other. A marker that lies is worse than no override at all,
because the pocket's whole drop rule is built on the promise that its answer
and the line the user is looking at cannot disagree. Sampling both values into
one binding and re-asserting both makes the order of those two assignments
irrelevant. It does not cover `barDragTarget`: moved behind the other two, the
intent would still be one pointer move behind when the signal arrives, and the
override would apply late — which costs the fast path, not the result.

**The geometry has to be compared field by field.** `dropMarkerRect()` returns
a fresh object on every call, so reference equality is always false and the
pocket would rewrite the marker forever. Comparing only `barDragAfter` is not
enough either, and for the same ordering reason: in the order `Bar.qml` writes
today, the `after` assignment triggers the correction and the geometry
assignment that follows would then find `after` already correct and stop —
leaving the right side with a wrongly drawn line.

**A write from inside a change handler re-enters it.** Measured on Qt 6: an
equal-valued write to a `bool` property emits nothing, a `var` property holding
a fresh object emits on every write, change signals are synchronous, and a
write from inside the handler re-enters it. The override therefore carries a
re-entrancy flag, and clears it after a `try`/`catch` around the two writes, so
that a host which turned one of them readonly cannot leave the flag latched and
the override off for the rest of the session. `finally` would say that more
directly and is deliberately not used: Qt 5's `qmlformat` segfaults on it, and
that is the parser the README names as this project's syntax check. The write
that decides the placement goes first, so a refusal there applies nothing at
all rather than half of it.

**Only one side is steerable.** `dropBarModuleAtTarget()` resolves
`afterTarget === true` through `nextVisibleModuleName()`, which walks past every
module that is not drawn — and a collapsed pocket's members are exactly that. A
widget steered that way would land at the far end of the run rather than against
the pocket. `afterTarget === false` names the target slot itself and is exact.
That is the side the members occupy in the `right` and `center` sections, so
those get the fast path; in `left` the members sit after the pocket, the side
that would be needed is the unreliable one, and the override refuses to apply.

**The pocket does not steer where it would not write.** A second pocket entry,
or a pocket that cannot find its own layout entry, already refuses to write
`members`. Steering without writing would move a widget the user did not aim
there and not record it as a member, so both now read the same permission.

## Consequences

The `right` and `center` sections pay one bar rebuild for a drop from either
side. `left` still pays two; 0002 keeps the numbers.

Every host access is optional. If a future Omarchy renames the properties or
drops `dropMarkerRect()`, the override stops applying, and the invariant from
0002 still produces the correct layout — one rebuild slower. That is the whole
reason the invariant was not replaced by this.

The cost is real and worth naming: the plugin now writes two undocumented
properties of the running host mid-gesture, which is a coupling direction 0001
did not have. What it buys is one bar rebuild on a gesture a user performs
rarely; [0002](0002-members-belong-on-one-side.md) owns what a rebuild costs.
The case for leaving it alone was argued and is recorded here as option A.

One defect found while reviewing this change is **not** fixed by it, and is
recorded so that closing 0002's open question does not read as closing the
subject. In the `left` section, a widget dropped onto the pocket from the near
side is placed by the bar past the hidden members — or, when the pocket's run
ends the section, not moved at all — while `nextMembers()` records it as the
member nearest the pocket. Layout order and member order then disagree
permanently, and the reveal cascade runs in a direction that does not exist on
screen. It predates this change, `firstMisplacedMember()` cannot see it because
the widget is on the correct side, and fixing it is a separate decision.
