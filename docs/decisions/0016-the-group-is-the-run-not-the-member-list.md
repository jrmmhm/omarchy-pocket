# 16. The group a drop is judged against is the run, not the member list

- Status: accepted
- Date: 2026-09-09
- Narrows [0004](0004-membership-is-decided-from-the-gap-not-the-slot.md)'s
  gap rule, which asked about `members` and not about the run
- Completes what [0015](0015-the-host-answers-by-capability-now.md) left
  standing: it named the far side as the place a member could be stranded, and
  did not notice that a stranded member could no longer be taken out either
- Shares its side test with [0002](0002-members-belong-on-one-side.md)'s
  placement invariant, which had defined that side already

## Context

0004 decided that a finished drag is judged from the gap the bar draws its line
in: if one of the two slots against that gap is a member, the drop is a reorder
inside the group; otherwise the widget is leaving. The predicate asked one
question — "is either edge of this gap in `members`" — and that question is
wrong for any member that is not part of the run.

**The measurement.** The author's own bar had `omarchy.bluetooth` in `members`
while the widget sat past the mark, on the far side, where 0015 says a 4.0.3
host can no longer move it back from. Driven with a synthetic pointer on the
running bar, twice: press on the member, glide 89px away, glide back into the
gap on its own inner side, release. `members` unchanged, `bar.layout` unchanged,
nothing written. The same gesture in the gap on its outer side, the same result.
The member could only be released by dropping it at least two slots away from
itself, and nothing on the bar said so — the mark does not light for a gap that
far away, because the mark is not what the drop is aimed at.

The cause is not the far side. It is that a member counts as "the group" from
wherever it stands, **including from the gap it is standing in itself**: both
gaps around such a member have a member against them, so both read as inside the
run. A member cut off from the run by a widget that is not a member is the same
case without the mark being involved at all.

## Options

**A — Exclude the widget being dragged from the member set.** The obvious
reading of the measurement, and wrong. The gap at the outer end of the run then
loses its only member edge, so dropping the outermost member back where it
already is — a drag of five pixels past the host's four-pixel threshold — would
eject it. A single-member pocket loses its member on any drop at all. README
promises the opposite ("Move it around *inside* the group and it just gets
reordered"), and `tests/model-test.js` holds it in "the gap against the pocket
from inside the run", "the only member, from its outer side" and "the only
member, from its inner side".

**B — Ask whether the gap touches the run.** Chosen.

**C — Repair the placement instead.** 0002's invariant did exactly that until
4.0.3 refused the write, and 0015 recorded the loss. Nothing here can bring it
back: moving another widget's entry is the one write an installed plugin no
longer has. Reporting it in the tooltip, which is what 0015 left in its place,
tells the user about a state they still cannot leave.

## Decision

**A gap is inside the group when one of the two entries against it is a member
sitting on the pocket's own side of the mark. Nowhere else.**

Three things about that sentence were each paid for.

**The side is not a second definition.** `firstMisplacedMember()` already
decided which side a member belongs on, and a rule that decided it again would
be the two-copies-of-one-rule failure 0004 warns about — one of them would
eventually answer "this member is misplaced" while the other answered "this
member is part of the run". Both now ask `onPocketSide()`, and neither owns it.

**Both edges are answered by position, not by id.** A hand-written layout may
name the same widget twice; resolving a member's id to its first occurrence
would side-test the wrong copy, so the gap beside the second copy would inherit
the first copy's verdict. `tests/model-test.js` pins both copies of one id.

**A layout without the pocket in it answers "inside the group".** The old
predicate never asked where the pocket was and so could not fail to find it.
This one can: `bar.layoutConfig` is a snapshot refreshed on registry events and
can lag a hand edit, `canonicalWidgetId` may not resolve, and a surface that has
not resolved its own slot has no region to read. Answering "outside" there would
eject a member on the strength of a layout whose sides cannot be told apart, so
the fail-safe answers the other way and nothing is written. It is a fixture
rather than an argument, because its whole point is the case nobody watches.

## Consequences

A member that is not part of the run comes out with any drop beside it, which is
the defect this record exists for. Everything inside the run behaves exactly as
0004 and 0008 describe, down to the outermost edge, and every fixture written
for them passes unchanged.

One arrangement changes: a hand-edited `members` holding widgets on both sides of
the mark. A drop between two of those far-side widgets now ends the membership of
the one being dragged, where it previously did nothing. That is the fix seen from
its other end, and the CHANGELOG says so under Changed rather than only under
Fixed.

Five fixtures in `tests/model-test.js` had to gain the pocket's own id in their
layouts. Each of them exists to hold a guard on a malformed or unknown id, and
each was written for a predicate that needed no pocket — under the new rule they
would have passed through the fail-safe instead, which is to say they would have
passed with their guards deleted. That is the class of green `tests/run.sh`
warns about in its own header, and the reason this paragraph is here rather than
in a commit message.

The gesture is asserted in Qt's V4 engine as well as in node, and not for
symmetry: the layout reaching the rule from QML is a sequence type, and the two
edge reads are out of range by construction whenever the gap sits at either end
of a section. node answers `undefined` and falls through; a sequence type is not
obliged to.
