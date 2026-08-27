# 6. The drop steering listens, it does not sample

- Status: accepted
- Date: 2026-08-27
- Replaces the mechanism, not the decision, of [0003](0003-steering-the-bar-s-own-drop-marker.md)
- Corrects a measurement reported in [0005](0005-a-pocket-drives-only-its-own-screens-slots.md)

## Context

0003 tells the bar where an arriving widget belongs by overriding the two values
it draws its drop marker from. It required that a change to *either* value
re-assert *both*, so that the order in which `Bar.qml` writes them cannot decide
the outcome, and it implemented that by sampling both into one property —
`readonly property var hostDropMarker` — and re-asserting from that property's
change handler.

That shape logs `Binding loop detected for property "hostDropMarker"` on every
steered pointer move, and has since it was written.

**The cause, measured rather than reasoned about.** `Bar.qml` writes
`barDragAfter`; the binding for `hostDropMarker` begins evaluating, assigns,
emits its change signal, and the handler writes both host properties back — into
the same binding whose `update()` is still on the stack. Qt finds its
`updatingFlag` set, prints the warning, and **skips** the re-evaluation. An
instrumented offscreen run on Qt 6.11.2 shows the order directly: binding eval,
changed handler, write, *warning*, write, *warning* — and the line that would
print if the re-entrancy flag had refused never appears.

So the `steering` flag 0003 introduced has never done anything. Qt's own guard
ends the recursion, one warning per write, and the result is correct only
because that guard happens to refuse *after* the write has landed rather than
before. The next host write re-evaluates the binding and the correction
converges anyway.

**The frequency 0005 reports is wrong, and this file owns the corrected one.**
0005 says the loop "writes some eighty warnings per shell start". The count was
right for the session it was read in; the unit was not. Across three shell
sessions in `journalctl --user`, every start produced **zero**, and every
warning fell in bursts minutes later, during drags. The unit is **three warnings
per steered pointer move** — measured against the real widget, not inferred —
which is some tens to some hundreds per dragged widget, depending on how far the
pointer travels before it is released.

## Options

**A — Leave it.** The steering does reach the right answer today, so this is
noise and nothing else. Rejected on two grounds. The correctness is accidental:
it rests on Qt refusing the nested evaluation *after* the write rather than
before, which is an implementation detail of `QQmlBinding::update()` and not a
promise. And the noise has already cost something — 0005 read this very log and
drew the wrong conclusion from it.

**B — Defer the write with `Qt.callLater`.** Removes the re-entrancy entirely
and would work. Rejected: it puts an event-loop turn between the marker the bar
drew and the correction, and the user can end the gesture by releasing the button
inside that turn. The whole point of steering before the drop is that the answer
is never late.

**C — Hang the handlers on the mirror properties this file already has**
(`dragAfter`, plus a new one for the geometry). The obvious smaller change, and
it does not work: measured, it produces `Binding loop detected for property
"dragAfter"`, three per move, exactly as before. Any binding whose handler writes
something the binding transitively depends on reproduces this, `steerAfter`
included. This is recorded because it is the change a later reader will propose
as a simplification.

**D — Listen to the host's two change signals directly.** Chosen.

## Decision

The pocket subscribes to `barDragAfterChanged` and `barDragTargetGeometryChanged`
through a `Connections` on the bar. There is no property of this widget's own
between the host's values and the correction, so there is no binding for Qt to
find re-entered.

0003's requirement survives unchanged and for the same reason it was written:
both handlers call the same function, and that function re-asserts both values,
so a change to either fixes both and the order of `Bar.qml`'s assignments stays
irrelevant. What changes is only where the re-assert is triggered from.

`ignoreUnknownSignals: true` is what keeps this host access optional like every
other one in 0003: a custom bar that publishes neither property gets silence
rather than two warnings. Measured in both directions — with the flag, silence;
without it, Qt names both handlers.

`steering` stops being decorative and becomes the guard it was written as. The
handlers now really are re-entered, synchronously, and the flag really does
refuse. That is also the first time 0003's sentence about a write from inside a
change handler re-entering it is true of this code; see Consequences.

**Both marker values are applied, or neither.** 0003 argued that ordering the
writes with placement first meant "a refusal there applies nothing at all rather
than half of it". That covers only a host that refuses the *first* write.
Measured against a host with a readonly geometry: the first write lands, the
second throws, the `catch` swallows it, and the bar then places the widget
against the pocket while still drawing its line on the far side. The marker
lies, which is the one thing 0003 and the README both promise cannot happen. The
`catch` now rolls the first write back.

## Consequences

`hostDropMarker` is gone and nothing replaced it — one property and one handler
removed, one `Connections` added.

**One trigger edge is lost, deliberately.** The old binding also depended on
`bar` itself, so an instance whose `bar` was injected while a drag was already
running re-asserted immediately; the `Connections` re-arms on the same event but
does not call. In the host this is unreachable on a fresh instance, because
`ModuleSlot`'s `Component.onCompleted → registerModuleSlot` runs *after*
`registryLoader.onLoaded → injectProps`, so `ownSlot` is still null at injection
and the steering has nothing to aim at. What remains is a plugin hot-reload
during a drag, with the pointer then held still until the button is released.
The cost is the one 0003 already names for every other way the override can stop
applying: the bar places the widget on the far side, the invariant from 0002
pulls it back, one extra rebuild, correct final layout. Restoring the edge takes
`onBarChanged: Qt.callLater(root.steerDrop)` — measured to work, and measured
*not* to work without the `callLater`, because the derived bindings are still
stale at that instant. It is not worth the line.

**This is testable, and 0004's and 0005's "the tests are the reminder" does not
apply.** Quickshell can load `BarWidget.qml` itself against an object that is
not a bar, so `tests/qml/` exercises the working tree rather than a model of it.
Two cases, each watched red on its own mutation: the sampling binding (three
binding loops), a missing rollback (`steer-readonly` alone), and a misspelt
signal name — the last being the failure `ignoreUnknownSignals` makes silent,
and the price this decision pays for keeping the access optional.

That last one needs both of its assertions, and the reason is worth writing down
because the obvious harness does not have them. A move that writes the side and
the geometry lets the geometry handler cover for a dead `after` handler: with
only that case, misspelling `onBarDragAfterChanged` leaves the suite green. The
second assertion flips the side on its own, which is a pair `Bar.qml` can write
in either order, so neither subscription may be the only one that works.

They do not run on GitHub's runners, which have no Quickshell package. That is
the same bargain `.github/workflows/ci.yml` already makes for `qmlformat`;
`tests/qml/run.sh` says which condition it skipped on, and the README's
Development section says the coverage is local, rather than either claiming
coverage that is not there.

**Two sentences in 0003 are wrong about the code as it stood, and both are
corrected there rather than left to be found.** The paragraph beginning "Both
values are overridden together" describes the sampling property this decision
removes. The paragraph beginning "A write from inside a change handler re-enters
it" reports a measurement that did not hold for the code it was written about —
Qt skipped the nested evaluation — and becomes true only now.

Measured on the user's session, four drag gestures across two monitors, the same
set before and after a shell restart on each build: **166 warnings before, 0
after**, no `TypeError` from the plugin either side, and the layout ending where
it started. This file owns those numbers.

The reproduction is cheap enough to repeat rather than trust. `tests/qml/run.sh`
is the short way. The long way, which is how the cause was found, is an offscreen
`qml6` file with two properties, a sampling binding over them and a handler that
writes them back, run with `QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen`
— without that first variable Qt routes the warnings to the journal and the
terminal stays empty, which is its own small trap.
