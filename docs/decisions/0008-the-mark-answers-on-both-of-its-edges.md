# 8. The mark answers on both of its edges

- Status: accepted
- Date: 2026-08-27
- Delivers what [0002](0002-members-belong-on-one-side.md) decided and did not get
- Narrows the steering of [0003](0003-steering-the-bar-s-own-drop-marker.md) /
  [0006](0006-the-drop-steering-listens-it-does-not-sample.md)
- Leaves [0004](0004-membership-is-decided-from-the-gap-not-the-slot.md)'s rule
  exactly as it is

## Context

Two things were reported about the neighbourhood of the mark: that a widget
aimed at it does not always go in, and that a member dragged out of it does not
always come out. Neither was reproduced by reading the code, and this file
exists because the reading would have been wrong.

**How the neighbourhood was measured.** `tests/qml/neighbourhood.qml` drives
`BarModel.nearestDropTarget()` — the host's own function, linked and not copied —
over a stand-in geometry, and feeds its answer to the real widget. The geometry
is laid out the way `Bar.qml` lays out a section, `Row { spacing: 0 }`, from
whatever the pocket has actually hidden at that moment. The section is the one
this pocket lives in: something wide on the far side of the run (64), four
members and the mark and two widgets behind it (32 each).

The pointer positions below are that stand-in's, not a real bar's. What is not
arbitrary is where the answers change, and that is what the table is for.

**Dragging a member, pocket fanned out.** The mark sits at [192, 224).

| pointer | bar names | side | the gap it means | touches the group | answer |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 64–80 | outer neighbour | after | neighbour │ member 1 | yes | stay |
| 81–176 | members | after | inside the run | yes | stay |
| 177–208 | last member | after | last member │ **mark** | yes | **stay** |
| 209–240 | **mark** | after | **mark** │ next widget | no | **out** |
| 241–272 | next widget | after | next │ the one after it | no | out |
| 273–300 | two past the mark | after | — | no | out |

The answer flips at 208, which is the middle of the mark. Every gap gives the
same answer under both of its names, which is the property 0004 bought; nothing
here is a defect. What it is instead is a **collision between two promises the
README makes**: *"anywhere from against the dots to the far end of the run — it
just gets reordered"* and *"drag a member past the dots and it comes out"*. The
gap against the dots is the first of those and the gap behind them is the
second, and they meet on the middle of a 32-pixel icon. Dropped on the near
half, a member that already sits against the mark is reordered to where it
already is, `moveModuleInConfig()` declines the null move, and nothing on screen
happens at all — which is what "it does not come out" looks like.

**A widget arriving, pocket collapsed.** The mark sits at [64, 96), and the
hidden run is zero wide, so the widget outside it stands flush against the mark.

| pointer | bar names | side | the gap it means | armed before | armed now |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1–32 | outer neighbour | before | edge │ neighbour | no | no |
| 33–80 | outer neighbour | after | neighbour │ **mark** | **no** | **yes** |
| 81–112 | **mark** | after | **mark** │ next widget | yes | yes |
| 113–144 | next widget | after | next │ the one after it | no | no |

The middle column is the defect. Slots sit flush, so the gap at the mark's near
edge is at *exactly* the same distance from the mark as from the widget before
it, and `nearestDropTarget()` resolves that tie by keeping the candidate it
walked first. `moduleSlots` is appended in slot creation order, which is layout
order, so the pocket loses every tie at its near edge and wins every one at its
far edge. The `add` branch asked "is the bar naming my own slot", so half the
icon answered "no" — 0002 changed the rule to "from either side" and measured
the gesture that made it necessary, but half of it never arrived, and the README
has promised it since.

## Options

**A — Leave it and write the README down to the code.** "Past the middle of the
dots", "the far half takes a widget in". Cheapest, and it makes 0002 a decision
that was taken and not delivered.

**B — Make the whole mark mean "out" for a member**, symmetric with the way in.
Rejected: it takes the gap against the dots away as a reorder target, so the
innermost position in the run becomes the one position a member cannot be
dragged to, and the README promise it breaks is the more useful of the two.

**C — Decide the `add` branch from the layout ids**, the way 0004 decides
membership: does the gap touch the pocket or one of its members. Rejected on
three measurements. The layout gap and the drawn gap are not the same gap — with
a non-member sitting inside the run, `nextVisibleModuleName()` lands the widget
beside *it* rather than against the pocket. An id-based answer is reached by
every instance at once, so every screen's pocket would steer, and the steering
writes a marker rect computed from *its own* slot: the line would jump to
another monitor's pocket. And `gapTouchesMember()` takes the first entry
carrying the target's id, which for a widget the host allows twice — a spacer,
the indicators — can be an entry in a different part of the layout entirely.

**D — Ask the same question about both names of the one gap.** Chosen.

## Decision

**Aiming at the mark means aiming at either of its two edges.** The far one the
bar names by this pocket's own slot; the near one it names by the widget drawn
before it, with the marker on that widget's far side. `aimsAtSelf` accepts both,
and both terms stay object identity against slots this instance can see — so the
instance that is not being aimed at still falls through to doing nothing, which
is the property 0004 asks of this branch. `Model.dropDecision()` is not touched,
and neither is the membership rule: `gapTouchesMember()` still decides a
member's fate from ids alone, identical on every screen.

**The steering keeps the narrower question.** `steerDropAfter()` gains a fourth
refusal, `aimedAtOwnSlot`, because "the pocket is armed" no longer implies "the
bar named the pocket". This is single-monitor correctness and not a multi-screen
nicety: steering a target that is the neighbour writes `barDragAfter = false`
against a `barDragTarget` that is still the neighbour, and
`dropBarModuleAtTarget()` reads the target — the widget would land *before* the
neighbour, outside the run, while the bar drew its line at the mark. Measured by
removing the refusal: the marker side the decision itself reads is overwritten
in the same breath, so the mark goes dark and the drop is refused rather than
misplaced. Nothing needs steering at the near edge anyway;
`nextVisibleModuleName()` walks past the hidden members and lands the widget
directly against the mark, on the side the members occupy in `right` and
`center`.

**The mark answers both gestures, in two colours.** It lights while a release
would take a widget in, as before, and now also while a release would let a
member go — in `Color.accent`, which is what `Bar.qml` paints its own insertion
line in, so the mark borrows the colour of the line the user is already looking
at. The way out is decided from ids, so every screen's pocket reaches it at
once; the light asks separately whether the drag is on this surface, by looking
for the dragged slot among the members this instance resolved. That question is
per-instance on purpose and stays out of the rule.

**Neither light promises what the write would refuse.** Both are gated on
`mayWriteMembers`, which is what `commitDrop()` checks. A bar carrying a second
pocket entry used to light the mark and then write nothing — the comment above
that binding has claimed "the same predicate decides the write" since 0001, and
it is true for the first time here.

## Consequences

**The armed zone runs from the middle of one neighbour to the middle of the
other.** That is what "the gap beside the mark" means once ties put every
boundary on a slot's midpoint, and the far side has behaved that way since 0002
— the near half of the widget behind the mark has always armed it. The near side
now matches. Where the neighbour is wide, as a tray is, its far half arms the
pocket; a widget released there joins, instead of landing in the same place
without joining. Narrowing it would take a pointer coordinate, which 0001
refused for reasons that have not changed.

**The member direction is unchanged, and the collision stays.** No code answers
it differently than it did; what changed is that the mark now says which side of
the boundary the pointer is on, before the drop rather than after it. Option B
is the change that would remove the collision, and it costs a promise worth more
than the ambiguity it removes.

**`left` still pays two rebuilds for an arrival on the far side of its members,**
which is now reachable from the mark's near half as well. The invariant from
0002 moves the widget back and the README caveat already carries the cost; 0002
owns the number.

**A theme whose accent is its bar text reads the way-out state as unlit.** That
is the state it replaced, so the failure direction is silence rather than a
wrong signal. The palette has no colour that is guaranteed distinct from both
the bar's active colour and its text, and inventing one would ignore the theme.

**Found and not fixed: `gapTouchesMember()` looks up the drag target's id in
this pocket's own section, whoever holds it.** For a widget the host allows more
than once, and for a drag whose target is in another section entirely, the entry
it finds can be the wrong one, and the membership answer is then about a gap
somewhere else. It predates this change and is untouched by it — the `add`
branch no longer reads that function at all, and the `remove` branch reads it
exactly as 0004 left it. Fixing it means giving the rule the target's region,
which is a change to the membership branch and belongs with its own measurement.

**What the sweep cannot see.** It is one section (`right`) on one host version:
a host that put spacing between its module slots would end the ties this whole
construction rests on, and the second copy the bar builds of every centre widget
with `centerAnchor` set registers in an order of its own, so the near edge there
may resolve either way. Neither changes the decision — asking about both names
of the gap is right whichever name the host picks — but the table's middle
column is a statement about `right`.

**The second reported symptom was not reproduced.** Driving `resolution`,
`driven`, `apply()`, `hideDriven()` and `heldVisibleId` through a member leaving
and a widget arriving, with every write to `visible` logged, showed no write
landing on a slot that should not have had one. What the same harness did show
is that a `Repeater` over a plain JS array destroys and recreates every delegate
when the array is replaced, so an externally written `visible: false` does not
survive a layout rebuild — every drag hands the members back visible for the
span between the rebuild and the new instance's `apply()`. That is the bar's
doing and not this plugin's, and without an observation to attach to it, it is
recorded here as a mechanism and not as a cause.
