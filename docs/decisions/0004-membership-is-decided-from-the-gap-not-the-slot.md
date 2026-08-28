# 4. Membership is decided from the gap, not from the slot

- Status: accepted, complemented by [0005](0005-a-pocket-drives-only-its-own-screens-slots.md),
  guard narrowed by [0009](0009-a-drag-decides-against-the-membership-it-started-with.md)
- Date: 2026-08-27
- Amends: [0001](0001-pocket-writes-its-own-members.md)

## Context

0001 decided that a finished drag is read from the bar's own drop marker, so
that what the pocket does and what the user is looking at cannot disagree. It
expressed the rule in terms of the two values `Bar.qml` publishes: which slot
the drop would land on, and which side of that slot the marker sits on.

Reading the *slot* turned out to be the wrong half of that marker. The user
aims at a **gap**, and a gap has two slots against it. Two consequences, both
reproduced:

**On a multi-monitor bar, every reorder inside the pocket ejects the member.**
`Bar.qml` is one object with a window per screen, so `barDragTarget` is shared
by every surface, while each pocket filters its member slots to its own window
(`resolution`). The pocket on the screen the drag is *not* on therefore sees
the target as "not one of my members", concludes the member is leaving, and
writes that — and it is allowed to, because `mayWrite` counts layout entries
and there is only one. Measured over the user's own layout: all ten reachable
positions inside the run disagree between the two instances.

**On a single monitor, one position is still wrong.**
`BarModel.nearestDropTarget` picks the candidate with the nearest edge, and
adjacent slots share a gap. The gap at the run's outer edge resolves either to
the neighbour outside the run with the marker on its far side, or to the first
member with the marker on its near side, depending on a sub-pixel tie. Those
two denote the same insertion point and the old rule answered them differently
— "leaves" against "reorder". The same gesture did different things on
different attempts.

In both cases the member is dropped from `members` while the bar leaves it
sitting among the remaining members: neither in the pocket nor out of it. If
the user drops it exactly where it already was, `moveModuleInConfig` declines
to move anything at all and nothing on screen even changes.

## Options

**A — Filter the drop target per window before comparing.** Fixes the
multi-monitor half and nothing else, and keeps a per-instance input in a rule
that must be the same on every screen.

**B — Special-case the run's outer edge.** Fixes the single-monitor half and
nothing else.

**C — Ask what the marker is drawn against, not which slot won.** Chosen.

## Decision

A member stays a member while the bar's insertion line is drawn against the
group — that is, while the gap it marks has one of this pocket's members on
either side of it. It leaves when the gap has none: past the pocket, beyond the
outer end of the run, or anywhere else on the bar.

`Model.gapTouchesMember()` answers exactly that, from the region's layout ids,
the member ids, the target's id and the marker's side. `dropDecision()` loses
both `targetIsMember` and `innerEdge`, and the rule collapses to two sentences:
aiming at the pocket takes a non-member in, and a member stays in while the
marker touches the group.

**The rule takes no per-instance input, and that is the property to preserve.**
Everything it reads is an id out of the layout, identical on every screen, so
every pocket instance reaches the same conclusion. `targetIsSelf` stays an
object identity test and stays safe, because it only ever gates the `add`
branch and its fallthrough is "do nothing" — the instance that is not being
aimed at declines rather than acting. Reintroducing `resolution.slots` into the
membership branch, for any reason, restores the multi-monitor defect. A test
states that intent — a member's fate must not depend on which instance is
asking — but it can only vary the inputs the rule has, so it would not catch a
new per-instance input being added. This paragraph is the guard; the test is
the reminder.

[0009](0009-a-drag-decides-against-the-membership-it-started-with.md) narrows
what "no per-instance input" covers, and the distinction is worth having here
rather than only there. The list the rule reads is now taken when the drag
begins, and the *content* is still identical on every screen — one shared
property's rising edge, one config. What became per-instance is *when* an
instance stops reading the live list: one that has already committed is back on
it while its peers are still on their snapshot. That difference is reachable
only in the moments after a peer's write, and the only outcome constructible
from it is a repeat write of the value that peer already wrote. Reintroducing
`resolution.slots` remains forbidden for the reason above; a snapshot of ids is
not that.

Deleting `innerEdge` changes nothing. In the `right` and `center` sections the
gap before the pocket touches the innermost member and the gap after it touches
nothing, which is exactly what `innerEdge` said; in `left` it mirrors. Deleting
`targetIsMember` changes exactly one thing on a single monitor — the run's outer
edge, which was the defect.

Two answers the new rule gives are deliberate rather than incidental:

**A member the layout of this section does not hold is not touched by the
gap.** Dragging it therefore ends its membership. That is the right answer: a
member in another section is a mistake the tooltip already names, and the
README already says dropping a member anywhere else on the bar takes it out.

**A member refused as the `centerAnchor` still counts as a member here.** The
rule is id-based on purpose, and `resolution` — which is what refuses it — is
per-instance. Consulting it would be the very coupling this decision removes.

## Consequences

The gesture that was reported broken now behaves the same on one screen and on
three, and at every position within the group.

`isMemberSlot()` in `BarWidget.qml` had no other caller and is deleted with
`onInnerEdge`. The pocket now reads one fewer of the bar's live objects.

The rule is asserted in the coordinate system of `bar.layoutConfig`, which is
normalised and has `omarchy.tray` pinned to its section's inner edge, while the
bar's own move operates on the raw `shell.json` section. When a hand-written
config has the tray somewhere else, the two orders differ by that one entry.
The membership verdicts stay consistent across that difference — a test carries
the displaced-tray fixture — but the position the widget lands in is the bar's
to decide, not this rule's.

A reorder inside the run moves widgets without this pocket writing anything, so
the member list would no longer describe the order they sit in — and the
cascade in `applyReveal()` counts from the member nearest the pocket outwards,
so a list that disagrees animates in a direction that does not exist on screen.
`membersInLayoutOrder()` therefore joins the placement invariant as a second
standing check, repaired the same deferred way and for the same reasons. It is
kept separate because it is a different mistake and a much cheaper one:
`members` is an inline settings change, which the bar patches into the running
widgets instead of rebuilding them — 0002 has what each costs.

Asking it as "would `orderMembers()` change anything" rather than re-deriving
the comparison is deliberate: the check and the repair then cannot drift into
disagreeing about what "in order" means. Ids the layout does not hold keep
their place, so a typo the user has not fixed yet never puts the list into a
rewrite it can never satisfy.

Measured on the user's three-monitor session, with every write counted by
inotify: a member list put out of order by hand is repaired by exactly one
write, 34 ms later, 0.03 s of shell CPU and no rebuild. A layout reorder —
what the bar itself does — costs one layout write, its rebuild, and then that
one repair.

One observation from the live session: four of five real drag gestures produced
three writes rather than two, the last two byte-identical, together 0.02 s of
CPU. Reproducing each path on its own afterwards gave the expected counts
above, so it is not either invariant on its own.

**That reading is refused by a later measurement, and
[0009](0009-a-drag-decides-against-the-membership-it-started-with.md) owns the
correction.** `FileView.setText()` does not replace the file when the content is
unchanged, so two byte-identical writes are one file event and cannot be what
was counted. The candidate below is refuted with it; the third write 0009
recorded is a defect, not the price of agreement.

The candidate — derived from the code, not measured — is this decision working
as intended. The bar's drag properties live on the shared bar root, so every
pocket instance runs the same falling-edge handler, and the membership branch
now reads only instance-independent ids. All of them therefore reach the same
conclusion and all of them call `commitDrop`, which nothing deduplicates: one
write per monitor, byte-identical from the second on. Agreement is the whole
point of the change, and this is its price. It is cheap — identical bytes are
an empty settings delta and no rebuild — and it is written down so a later
measurement has something to compare against rather than a mystery.

Two things this rule now depends on are recorded as known rather than fixed.
`memberIds` is not passed through `bar.canonicalWidgetId` while
`layoutIds()` and the drag target's id are; the host's implementation is the
identity today, so nothing differs, but if it ever stopped being so,
`gapTouchesMember()`, `membersInLayoutOrder()` and `firstMisplacedMember()`
would all fail together. And while a member is stranded on the wrong side of
the pocket, the gap behind the pocket touches it and therefore reads as inside
the group — a drag there does not eject. That is what "outside the group"
means when the group is temporarily the wrong shape, and the placement
invariant restores it.
