# 9. A drag decides against the membership it started with

- Status: accepted
- Date: 2026-08-28
- Closes the open case of [0008](0008-the-mark-answers-on-both-of-its-edges.md),
  and corrects the second half of what it claimed to have seen
- Amends [0004](0004-membership-is-decided-from-the-gap-not-the-slot.md)'s
  guard on per-instance input

## Context

0008 recorded, and could not explain, that a member released in the gap behind
the mark stays a member: the mark lights the way-out colour, the bar rebuilds,
and the widget is still hidden. It named the instrument to build next — a
recording of every write to `shell.json` across one such gesture — and said that
two writes were expected and the question was which one carried the id back.

**The recording.** `inotifywait` on `~/.config/omarchy/shell.json`, one snapshot
per atomic replace, on the reporter's three-monitor session, Omarchy 4.x with
Quickshell 0.3.1, 2026-08-28. Two gestures, each dragging one member out of the
open pocket and releasing it in the gap just past the mark. The starting list is
`omaplug, ianswope.snapshots, mehiel.darky, omarchy.tailscale` both times.

| | dragged `omarchy.tailscale` (last in the list) | dragged `omaplug` (first in the list) |
| :--- | :--- | :--- |
| write 1, +0 ms | `omaplug, snapshots, darky` | `snapshots, darky, tailscale` |
| write 2, +15/16 ms | `omaplug, snapshots, darky, tailscale` | `snapshots, darky, tailscale, `**`omaplug`** |
| write 3, +749/740 ms | the bar's own layout move | the bar's own layout move |
| write 4, +1652 ms | — | the placement invariant |

Three writes, not two, and the middle one is the answer. It is not a stale
version being flushed a second time: in the right-hand gesture it puts the id at
the **end** of a list it started at the front of, which is what
`Model.nextMembers()` does for `intent: "add"` and for nothing else. So the
removal is written correctly and the same gesture adds the widget straight back,
sixteen milliseconds later.

**The race, read out of the host rather than guessed at.** A members-only change
is an inline settings delta: `BarModel.inlineSettingsDelta()` finds one entry
changed, and `Bar.qml::applySettingsDelta()` assigns the new `settings` to every
slot carrying that id, with no window filter — every instance, synchronously,
inside the mutator call. `shell.qml::persistShellConfig()` assigns `shellConfig`
before it touches the file, so that cascade runs from inside `commitDrop()`.

And `commitDrop()` runs from the falling edge of `barDragSource`, which
`Bar.qml::clearBarDrag()` produces in its **first** statement. Everything above
therefore happens inside that one assignment, while the remaining twelve
statements of `clearBarDrag()` have not run: `barDragTarget` still names the slot
the drag was aimed at. What differs between instances is only how far the engine
has got in notifying them, and Qt is explicit that
[the evaluation order of bindings is not something to rely on](https://doc.qt.io/qt-6/qtqml-syntax-propertybinding.html).
So the instance the drag is aimed at — whose `dragSource` mirror the engine has
not reached yet — re-evaluates `dropIntent` with the member already stripped and
its own slot still the target, `Model.dropDecision()` takes the `!isMember`
branch, `targetIsSelf` is true, and the answer is `"add"`.
`onDropIntentChanged` records it, and that instance's own falling edge commits
it.

**It takes two instances.** On a single monitor the instance that writes is the
instance that would be fooled, and by then its own `dragSource` is null and both
the binding and the handler refuse on it. This is why the plugin's own harness,
which drives one instance, never saw it, and why 0008 reproduced the symptom
only on the live bar.

**What 0008 got wrong, and this file owns.** It reported that the placement
invariant "should then have pulled that stranded member back … and had not done
so either", and treated that as the second half of one puzzle. The recording
shows the invariant working: the right-hand gesture's write 4 is exactly it. The
left-hand gesture has no such write although its final layout does put the member
behind the pocket, so `Model.firstMisplacedMember()` had something to return —
that one is unreproduced and stays open below. There was never a second half to
the membership puzzle; there is a separate, rarer one.

## Options

**A — Leave it and write the README down to the code.** Not available. There is
no sentence that describes "the widget comes out and goes back in" as a feature.

**B — Ask the host whether a drag is still live before recording a sample**, in
`onDropIntentChanged`, reading `bar.barDragSource` directly instead of this
widget's mirror of it. It works, and the reason to reject it is not the one that
suggests itself: the wrong intent it lets through is invisible, because
everything the mark draws is gone by then. The reason is that the guard is only
correct while `clearBarDrag()` nulls `barDragSource` **first**. Reorder those
twelve statements upstream and the guard silently stops guarding, and nothing in
this repository would notice — the very host detail this plugin is not entitled
to depend on.

**C — Remember on the rising edge that the source began as a member, and refuse
to add it in `commitDrop()`.** One boolean, no new binding. Rejected on two
counts. It is measurably wrong at the run's outer edge: with the membership
stripped, `Model.gapTouchesMember()` finds neither slot against that gap in the
list and answers `"remove"` for what must be a reorder, so the decision still
needs the whole list and not one bit of it. And it repairs the writer while
leaving `dropIntent`, `pendingIntent` and `dropArmed` wrong — the split 0008
closed with "the same predicate decides the write".

**D — Take the membership the gesture is decided against when the gesture
begins.** Chosen.

## Decision

**A drag is decided against the member list as it stood when the drag began.**
`dragMembers` is latched on the rising edge of `dragSource`, beside the
`dragSeen` flag that already marks a gesture as started, copied rather than
referenced so the snapshot does not rest on `Model.parseMembers()` happening to
return a fresh array; `gestureMembers` serves it while a drag is live and the
live list otherwise.

**Both reads go through it, or neither is safe.** `dropGapTouchesMember` and the
`members` field of `Model.dropDecision()` are the only two places that take
membership for the drop decision, and no single release position separates them
— past the middle of the mark exercises one, the run's outer edge the other.
Each is watched red on its own mutation in `tests/qml/neighbourhood.qml`.

**Everything that describes what the pocket holds now stays on the live list:**
`resolution`, the tooltip, `misplacedMember`, `membersMisordered`. Freezing those
would make the tooltip contradict the widgets next to it, and would stop the two
standing invariants from seeing the state they exist to repair. The one-line
string `members: root.memberIds,` occurs twice in `BarWidget.qml`, in the drop
decision and in the tooltip, and only the first of them changed.

**`Model.js` is untouched, and so is the rule.** `dropDecision()` and
`gapTouchesMember()` still read what they read; what changed is which list is
handed to them. 0004's rule — a member stays in while the insertion line is drawn
against the group — is unchanged at every position.

**It is independent of the order the engine notifies anything in**, which is the
property option B does not have. Whether the aimed instance is told first, last
or in between, the list it decides against is the one it began the gesture with.

## Consequences

**The number of writes is not the measure; their content is** — and it could not
be the measure even if one wanted it to be. `commitDrop()` still reads
`setting("members", "")` live, so an instance reaching its falling edge after a
peer has written re-writes the same value; whether that reaches the file at all
is not observable with this instrument. `FileView.setText()` with unchanged
content does not replace the file: measured on Quickshell 0.3.1 by calling
`setText` three times with the text the file already held and once with different
text, under `inotifywait`, which saw **one** atomic replace and not four. Every
write this recording can see therefore carries a change, and the criterion for
this decision is that none of them ever carries the id back.

Measured after the change, same session, same gesture, same instrument: **two
visible writes.** The removal at +0 ms, the bar's own layout move at +581 ms,
and nothing else — no re-add and no placement repair, because with the membership
correct there is nothing misplaced left to repair. The layout write puts the
widget two entries past the mark rather than one, because
`Bar.qml::nextVisibleModuleName()` walks past every module that is not drawn and
`jerome.claude-attention` was hidden at the time. It is drawn directly beside the
dots, which is where it was released; the same host rule is already recorded for
the opposite direction in `Model.js::steerDropAfter()`.

**0004's byte-identical write is corrected here.** It reports that "four of five
real drag gestures produced three writes rather than two, the last two
byte-identical", and derives from it that every instance writes and the repeats
cost nothing. The measurement above refuses the reading: two byte-identical
writes are one file event, so whatever those recordings saw, it was not that.
The count of three is exactly what the recordings in this file show, and the
third write in them is the defect this file names — offered as the candidate,
because 0004's session was not re-run. What survives of 0004 unharmed is its
conclusion, that agreement between instances is worth its cost; what does not is
the shape of the cost.

**0004's guard paragraph is narrower than it reads.** It says the membership rule
takes no per-instance input, and that everything it reads is an id out of the
layout, identical on every screen. Both sentences still hold for the *content*:
every instance latches the same list, because every instance sees the same rising
edge of one shared property and the same config. What is now per-instance is
*when* the list stops being read — an instance that has committed is back on the
live list while its peers are still on their snapshot. The only outcome that can
be constructed from that difference is the byte-identical write above. The
paragraph is amended there rather than here, so that the guard and the code sit
in the same file.

**One thing the harness still cannot reach.** It drives a single instance, so it
cannot produce the interleaving itself. What it reproduces exactly is the event
that interleaving delivers — `applySettingsDelta` assigning a new `settings` to a
live widget mid-gesture — which is the input the fix answers. The interleaving
itself is covered by the live recording above and by nothing else, which is the
same bargain 0006 struck for the drop steering.

**Still open: a stranded member that the placement invariant does not collect.**
In one of the two recorded gestures the widget ended up behind the pocket while
`members` still named it, and no repair write followed within six minutes of
recording; in the other, structurally identical, the repair came 912 ms after the
layout move. Nothing here changes `firstMisplacedMember()`, `scheduleRepair()` or
`repairPlacement()`, and this gesture can no longer reach that state — a member
released past the mark is no longer a member, so there is nothing to misplace.
What remains is a hand-edited config, or a path not yet found. The instrument for
it is the one this file used, kept running long enough to prove an absence rather
than a delay.
