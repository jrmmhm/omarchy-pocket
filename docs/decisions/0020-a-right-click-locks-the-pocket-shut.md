# 20. A right click locks the pocket shut

- Status: accepted; where the lock lives and the pin's staying unwritten are
  superseded by [0021](0021-the-pin-and-the-lock-belong-to-a-screen.md): both
  are per-screen settings now
- Date: 2026-10-05
- Answers [#20](https://github.com/jrmmhm/omarchy-pocket/issues/20)
- Gives the pin's reason for staying unwritten
  ([`BarWidget.qml`, `onPressed`](../../BarWidget.qml)) a counterpart: the lock
  is the one state Pocket persists besides `members`
- Writes through the path [0019](0019-the-inline-write-starts-from-the-injected-settings.md)
  fixed, which is why that one came first

## Context

#20 asked for a right click on the mark to "lock it shut": a pocket that does
not open when the pointer merely passes over it. Until now every button did the
same thing. The host's `WidgetButton` hands its `pressed` signal the button that
was pressed, by both routes a click takes. A left click goes through the bar's
own `modulePointer` and `pressModuleClickTarget()`. A right or middle click goes
to the button's own `MouseArea`, because `modulePointer` accepts the left button
only. Pocket's handler ignored the argument and toggled the pin for every
button. That has been so since Omarchy 4.0.0 and is unchanged in 4.0.4.

The owner added a second request: the tooltip should say what each click does,
because nothing else on the bar does.

## Options

**Where the lock lives.**

*A — A setting on Pocket's own entry (`locked`).* Chosen. A lock is a mode, not
a pointer aid. It should survive a restart and a bar rebuild, and a rebuild
happens on every drop and every plugin enable. The pin's stated reason for
staying unwritten is that `shell.json` is shared by every surface, so persisting
one screen's transient state makes it everyone's. Here that sharing is the
point: a lock that held on one monitor and not the other would read as broken.
It can also be set wherever settings are edited, including `omarchy bar set`.
Which values count as locked is `Model.isLocked()`'s to say.

*B — Session-only, per instance, like the pin.* Rejected. It would silently
unlock on every rebuild, which in practice means after every drop.

**What the left click does to a lock.**

*A — It pins and leaves the lock alone.* Chosen. The pin wins while it holds,
and when it is released the pocket is locked again.

*B — It pins and unlocks.* The first plan, rejected in review. A left click
reaches the pocket through the bar's hit test, which on overlapping outputs can
pick another screen's pocket ([0007](0007-the-two-host-limits-measured.md)). A
click that landed there would then change a setting that every screen shares.
Only the right click writes.

## Decision

- **A right click toggles `locked`.** It is the only click that writes, under
  the same permission as `members`, so a second Pocket entry refuses it. Locking
  drops this screen's pin first. Another screen's pin belongs to that screen and
  stays. If the write is refused, nothing changes and the pin comes back.
- **Locked, the pointer opens nothing.** Exactly the two pointer terms leave
  `holdOpen`. The pin still opens the pocket, and so does a member's panel
  opened by keybinding, because that panel has to hang from a widget that is
  drawn.
- **Locking folds at once.** It does not wait for the pointer to leave the bar
  the way the fold timer does, unless a pin or a member's open panel still holds
  the pocket. The fold handler asks those terms one by one, not `holdOpen`.
  `holdOpen` depends on `locked`, and inside `locked`'s own change handler it
  can still answer for the hover from a moment ago. A mutant that used it was
  caught by `tests/qml/facade.qml`.
- **The mark is dimmed while locked.** It is not dimmed while pinned, and not
  while the drag light is on: the light answers before the button comes up, and
  dimming it would weaken that answer.
- **The tooltip names both clicks, directly under its first line.** Each line
  says what that click would do next, so the text follows the state. The right
  click is left out where Pocket may not write. Neither line appears on an empty
  pocket, unless a pin or a lock is what is holding it. The first line now reads
  `Pocket pinned open` and `Pocket locked shut — holding N widgets` for the two
  states.

## Consequences

A right click no longer pins. That is the one change to existing behaviour, and
the CHANGELOG records it. The middle click still pins.

Every lock and unlock is a `shell.json` write. On 4.0.3 and later it goes
through the inline writer, which the bar's delta path delivers to the running
instances without rebuilding them. 0018 measured that for a `members` write.

`tests/qml/facade.qml` drives the real button's `triggerPress()` for all three
buttons against the host's own facade. It covers the write and its delivery back
through a model of the delta path, the fold with the pointer still on a member,
the hover that no longer opens, the pin over the lock, a member's open panel, a
refused write, and a lock written over the stale `members` 0019 describes.
Fifteen mutants of the new code were run against the suite, and the suite
caught all fifteen.

Not covered by any automated test: a real pointer resting on the mark of a
locked pocket. The harness drives hover through a member's `hovered` flag,
because offscreen there is no pointer to rest anywhere. What the live bar showed
is that a `locked: true` written by hand reaches the running pocket without an
error and leaves it collapsed.
