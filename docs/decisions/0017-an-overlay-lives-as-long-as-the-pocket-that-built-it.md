# 17. An overlay lives exactly as long as the pocket that built it

- Status: accepted
- Date: 2026-09-10
- Corrects the overlay lifecycle
  [0015](0015-the-host-answers-by-capability-now.md) introduced; the reasons
  0015 gives for the overlay existing at all are unchanged
- Narrows [0016](0016-the-group-is-the-run-not-the-member-list.md)'s remark
  that `bar.layoutConfig` can lag a hand edit

## Context

On Omarchy 4.0.3 the drag gesture worked exactly once per shell session. The
first drag after a restart wrote `members` correctly; every later one did
nothing — the bar moved the widget, the pocket did not record it. `bash
tests/live.sh --gesture` reproduced it on every attempt: the drag out passed,
the drag back in failed.

The overlay 0015 added — an invisible item above the bar carrying the
`PointHandler` that follows a drag and the `HoverHandler` that answers
`pointerOnBar` — was shared between the pocket instances of one surface: the
first to attach built it, later ones found it by `objectName` and counted
themselves in `users`, and the last one out destroyed it.

**The measurement.** `attachOverlay()`, `detachOverlay()` and both handlers
instrumented in a diagnostic copy, one real drag, Omarchy 4.0.3, quickshell
0.3.1, three surfaces. On the surface the drop happened on:

| Time | Event |
| :--- | :--- |
| 10:33:40.245 | old instance: `surfaceRoot` becomes null; it detaches, `users` 1 → 0, a deferred destroy is scheduled |
| 10:33:40.498 | new instance: finds that overlay by name with `users=0`, adopts it, `users=1` |
| 10:33:41.901 | the deferred destroy runs, sees `users=1`, does nothing |
| 10:33:42.044 | old instance destroyed |
| 10:33:42.060 | the overlay's `Component.onDestruction` fires — while the object lives on |
| 10:33:48.968 | the next rebuild finds the same overlay, same address, alive |

After 10:33:42 no `press` reached the overlay's `PointHandler.onActiveChanged`
for the rest of the session: the second drag logged none at all. `pressed`
never became true, so `localDrop` never answered, `dropIntent` stayed
`"none"`, and nothing was written. The same held on all three surfaces.

**The cause, in one sentence:** the overlay's handlers run in the QML context
of the pocket instance that created it, a rebuild destroys that instance while
the new one holds the overlay, and from that moment every handler body is
silently dead — `overlay destroyed … users=1` sixteen milliseconds after
`[pi52] instance destroyed` is that context going.

Qt's own source says the same thing the log does. An object from
`Component.createObject()` is created in the component's context; when that
context is invalidated, the object is not deleted, but its bindings and signal
handlers stop being evaluated, with no warning (`qqmlcontextdata.cpp`,
`qqmlbinding.cpp`, `qqmlboundsignal.cpp`, Qt 6.9). Pointer delivery does not
look at contexts, so the handler's C++ state goes on updating while the QML
that reads it never runs.

Neither of the two fixes tried before this measurement touched that. Swapping
`Qt.callLater` for zero-interval timers raised the "invalid context" warnings
from 9 to 2814 and left the gesture dead; moving the cleanup timer into the
overlay changed nothing. Both reasoned about timing. The defect was ownership.

## Options

**A — Keep sharing, rebuild when the creator dies.** The overlay's
`Component.onDestruction` is a usable signal that its context is gone. But a
surviving instance would then have to notice, drop the corpse and build again,
in the one window where two instances disagree about who holds what. Rejected:
it keeps the property that caused the defect and adds a recovery path to it.

**B — Move the handler bodies out of the overlay.** Leave the overlay as inert
items and read `PointHandler.active` and the hover state through `Connections`
in whichever instance holds it. Rejected: it relies on a dead-context object
behaving well indefinitely, which is exactly what could not be seen from the
inside last time, and it rewrites the part of 0015 that was measured to work.

**C — One overlay per instance, created and destroyed by that instance.**
Chosen. It is the only arrangement in which an object's handlers cannot
outlive the context they run in, because the object never outlives it either.

Within C, the reparented `HoverHandler` needed a decision of its own, below.

## Decision

**Every pocket instance builds its own overlay in `attachOverlay()` and
destroys it in `detachOverlay()`. No instance ever holds an overlay another
built.** The search by name and the `users` count are gone.

Four things about that were each paid for.

**The hover handler is handed back before the overlay goes.** 0015 puts it on
the surface root rather than on the overlay, because a handler on the overlay
takes hover away from the whole bar. A handler declared inside the overlay and
reparented there takes its ownership along: measured offscreen, it is still
alive after `glass.destroy()`, and `destroy()` refuses it because it was not
created dynamically. With one overlay per instance that is one live handler
left on the surface per rebuild. `retire()` switches it off and parents it to
the overlay again, which takes the ownership back — measured offscreen, gone
with the item. A dynamically created handler worked as well; the hand-back won
because it keeps the declaration 0015 describes and adds two lines instead of a
factory. `tests/qml/facade.qml` fails when the hand-back is removed.

**Destroyed inline, not from a `Qt.callLater`.** The deferral existed so a new
instance could adopt the overlay before it went. Nothing adopts one now, and a
`callLater` whose scope object is being deleted is dropped by Qt without a word
(`qqmldelayedcallqueue.cpp`) — from `Component.onDestruction` that would leave
the overlay on the surface for good.

**Taken off the surface first.** `destroy()` is deferred, and in that gap an
item still in the window is hit-tested and its destructor reaches into the
window. The bar's own items leave the window before they are deleted — an old
pocket instance loses `surfaceRoot` well before it is destroyed, 1.8 s in the
table above — and `glass.parent = null` does the same for the overlay. It also
makes a retired overlay stop receiving presses at once rather than seconds
later, which the plan review raised.

**Deletion was counted, not assumed.** Every retired overlay and handler was
kept in a shared `.pragma library` array and tallied from the instances that
came after. On the live bar, after two `--gesture` runs — four drops, twelve
retired overlays across three surfaces — all twelve overlays and all twelve
handlers were gone by the next two-second tick. Reading a retired handler from
the instance that retired it, a few hundred milliseconds later, still finds it
alive; that reading is too early, not a leak, and it misled one round of this
investigation.

## What else was measured

**`bar.layoutConfig` is not frozen.** The session before this one recorded the
facade's layout as refreshed only on registry events, and a fix built on that
brought one pass in four. Measured here: the facade's `right` section changed
within a millisecond of each drop's rebuild, and 52 ms after `shell.json` was
restored from outside with a different order. The host re-syncs the facade on
every `layoutConfig` change (`Bar.qml`, `onLayoutConfigChanged`); what it does
not re-sync is an inline-settings-only edit, which `applySettingsDelta()`
patches in place without a change signal. 0016's fail-safe for a layout without
the pocket in it stands; its remark that the snapshot "can lag a hand edit" is
true only of that kind of edit. The failures that were attributed to a frozen
layout were this defect: every run after the first drop of a session had no
working overlay.

**The two pockets on one surface are argued, not measured with a press.** Two
overlays then stack on that surface, each with a passive-grab `PointHandler`;
Qt continues delivery past a passive grab, and both hover handlers sit on the
same ancestor, so neither shadows the other. No test drives a press into that
arrangement. It is also the arrangement the README already calls a limit — a
second pocket entry makes Pocket refuse every write — so what it could break is
a gesture that writes nothing either way.

## Consequences

The gesture survives every rebuild: `bash tests/live.sh --gesture` passes twice
in one shell session, the pocket folds afterwards (`bash tests/live.sh`), and
`shell.json` is byte-identical to its snapshot. One overlay is built and one
destroyed per pocket instance per rebuild, where the shared one was built once
per surface and session.

`tests/qml/facade.qml` pins the ownership: two pockets build two overlays, the
one that built first can be destroyed without taking the survivor's, and its
hover handler goes with it. It cannot press a button offscreen, so it pins the
cause rather than the symptom; the symptom is `tests/live.sh --gesture`, which
drives a real drag with a virtual pointer and is not part of `tests/run.sh`.

## Open: the quickshell crashes of 2026-09-09 and 2026-09-10

quickshell died with SIGSEGV four times on 2026-09-09 and never before in a
`coredumpctl` history reaching back to July. All four stacks end in
`derefWindow()` inside `~QQuickItem`, from a deferred delete; all four came
while the session was locked, 46–82 s after it locked. A fifth followed on
2026-09-10 at 09:34:09 with the same stack — `derefWindow` ←
`setParentItem` ← `~QQuickItem` ← `deleteChildren` ← `sendPostedEvents` —
on a build that still shared the overlay; lock-screen PAM sessions start 19 s
after it, so the session was most likely locked then too. It came after a
nine-hour locked stretch overnight that had produced none.

The overlay was the prime suspect, as the one item this plugin hangs in a
foreign window and deletes late, and frame `setParentItem` inside
`~QQuickItem` is an item that still had a parent in a window when it was
finally deleted. Against it: the first day brought Omarchy 4.0.2 → 4.0.3,
qt6-base, Hyprland and mesa; the first four fell in hours of constant plugin
edits and shell reloads; quickshell issue #972 describes a segfault when a
process ends during a config reload, and every crash log ends in IpcHandler
deregistrations. Without symbols the stack does not say which item it was.

What this change does to the question: it deletes overlays far more often, and
it deletes each one after taking it out of the window, so none of those
deletes can reach a window from the destructor the crash died in. That lowers
this plugin's exposure to that stack; it does not show the plugin was the
cause.

What would settle it: a crash on a build carrying this change, symbolicated,
with the plugin's last overlay delete placed against it — or, the other way, a
week of normal use with lock cycles and no crash. A soak of rebuilds while
locked (`omarchy bar move` in a loop) on the build before this change and on
this one, comparing `coredumpctl list quickshell`, would separate the two
faster than waiting. No single lock proves anything: one survived and the next
did not.
