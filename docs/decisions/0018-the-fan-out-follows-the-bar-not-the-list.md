# 18. The fan-out follows the bar, not the member list

- Status: accepted
- Date: 2026-09-10
- Narrows the reason [0001](0001-pocket-writes-its-own-members.md) and
  [0004](0004-membership-is-decided-from-the-gap-not-the-slot.md) give for
  keeping `members` in layout order: the cascade no longer rests on it. The
  order repair itself is unchanged
- Another case of the stale injected `settings` that
  [#16](https://github.com/jrmmhm/omarchy-pocket/issues/16) describes from the
  write side

## Context

Reported on the author's bar: drag the member at the far end of the run to the
end against the mark, and the next fan-out is wrong. The untouched members
cascade outwards from the mark as they should; the widget that has just moved
arrives on its own, late, at the place it has left.

The cascade in `applyReveal()` counts along `driven`, which `resolution` builds
in `members` order. `members` is kept in layout order — the order repair writes
it back after every reorder — so the two were meant to agree. On Omarchy 4.0.3
they do not.

**The measurement.** Omarchy 4.0.3-1, quickshell 0.3.1, Qt 6.11.2, three
outputs. A throwaway bar-widget plugin in the same scene watched the pocket on
one surface while a virtual pointer reordered a member, and a second process
polled `shell.json` every 5 ms. One run, representative of three. Both clocks
are wall time; the file column is when the poller saw the write, so it trails
the event by up to one poll:

| t (ms) | Event |
| :--- | :--- |
| 0 | the poller sees the host's own move: new layout, `members` still in the old order; the bar has rebuilt |
| +115 | the new pocket instance's `settings.members` becomes the new order — stack: `persistShellConfig` → `onBarConfigChanged` → `applyBarConfig` → `applySettingsDelta` (Bar.qml:611), i.e. its own `repairMemberOrder()` write coming back |
| +118 | its `settings.members` goes back to the old order — stack: `injectProps` (Bar.qml:2005), called from the event loop |
| +126 | the poller sees `members` in the new order in `shell.json` |

`injectProps()` hands a widget `moduleSettings`, which comes from the slot's
`entry`. The delta path replaces the element in the host's layout array and
patches the running widget's `settings`, but the slot keeps the entry its
Repeater gave it, and a deferred `injectProps()` queued when the slot loaded then
restores the old settings from it. From then on `shell.json` holds the new order
and the running pocket the old one, until the next full rebuild. Its
`membersMisordered` stays true, and the repair finds nothing to write, because
the file is already right: in every measured run the poller saw exactly one
`members` write per reorder over a window of 30 to 45 s.

What stays current is the layout. An order change is never a delta:
`BarModel.inlineSettingsDelta()` returns null as soon as an entry id differs at
an index, so the host reassigns `layoutConfig`, and `onLayoutConfigChanged`
re-syncs every facade's copy. The probe evaluated
`Model.orderMembers(memberIds, layoutIds(ownRegion))` on the running pocket at
every sample, and in each measured run it was the bar's physical order from the
first sample on, while `settings` was stale.

Two screen recordings of the fan-out after a reorder match the stale list
exactly, member by member.

## Options

**A — Rank the cascade along the layout.** Chosen.

**B — Read `members` from the facade's layout snapshot instead of `settings`.**
Rejected. The snapshot goes stale in the opposite case — an inline-only change
patches the host's layout without re-syncing the facade, which is #16 — so
this swaps one stale copy for another, and it would move the write path, which
has nothing to do with the symptom.

**C — Order `resolution` by the layout.** The first plan. Rejected in review:
`resolution` feeds `apply()`, so every facade re-sync — each popout and each
click-target change hands out a fresh `layoutConfig` — would have re-run the
whole resolve-and-apply pass for an order only the animation uses. It would also
have reordered the tooltip's lists, and it ranked raw member ids against
canonical layout ids.

**D — Rank by slot geometry, or by position in `barSlots`.** Rejected. `apply()`
moves slots by writing `visible`, so geometry inside that chain is the loop 0002
refused. And `barSlots` is registration order, which for the second copy of a
centre widget under `centerAnchor` is not layout order (0008).

## Decision

**Each driven slot's place in the cascade is its position along the layout,
nearest the mark first.** `Model.cascadeRanks()` owns the rule, and
`revealRanks` in `BarWidget.qml` feeds it to `applyReveal()`. It compares the
slots' own canonical names against `layoutIds()`, which are canonical too.

Two things about it were each paid for.

**An id the section does not hold goes to the far end.** Counting along the list
put such a member — one sitting in another section — at the leading end in the
`right` section. It was the one physically furthest away, and it led the cascade.

**No layout means the old cascade.** Before a pocket has resolved its own
section `layoutIds()` is empty, and so it is on a host without `layoutConfig`.
Every id is then unknown and keeps the relative place the list gave it, which is
exactly the cascade this plugin has always drawn.

## Consequences

The fan-out runs from the mark outwards whatever the list a pocket holds says.
`tests/qml/cascade.qml` samples every member's opacity while a pocket fans out
under a list rotated against the layout, and again after the layout moves under
the same list — once against a bar that publishes `moduleSlots`, once against the
host's own facade with the slots found by walking. Against the unfixed widget
every half failed, with the member furthest from the mark ahead of the one
against it.

Five mutants of the new code were each killed by the suite: unknown ids not
reversed, the layout direction ignored, unknown ids leading, the last
occurrence of a repeated id instead of the first, and `applyReveal()` put back
on the list-counted formula — the first four by `tests/model-test.js`, the last
by `tests/qml/cascade.qml`. On the live bar after the fix, with the pocket's
`settings` still stale, the recording shows the member against the mark leading.

The stale list itself is not fixed here. It is the host's race, and it has no
other visible effect found so far: membership changes made by a drag are written
before the host's own move and therefore reach the rebuild. `membersMisordered`
reads true in an affected instance and the order repair writes nothing. #16
names the write-side risk of the same stale `settings`.
