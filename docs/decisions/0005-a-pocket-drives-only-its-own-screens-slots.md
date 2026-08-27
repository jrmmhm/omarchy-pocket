# 5. A pocket drives only its own screen's slots

- Status: accepted
- Date: 2026-08-27

## Context

`Bar.qml` is one object with a window per screen, and every surface's module
slots land in the same `bar.moduleSlots` array. A pocket therefore has to
filter that array to its own window, or it takes over another screen's widgets.
The filter has been there since the beginning, and so has the hole in it:

```qml
if (mine && bar && typeof bar.slotWindow === "function" && typeof bar.sameWindow === "function"
    && !bar.sameWindow(bar.slotWindow(slot), mine)) continue
```

`mine` is `root.QsWindow.window`. When it is null the comparison is skipped
entirely, so the instance that does not know which screen it is on matches
**everything** instead of nothing — and takes the first slot in the array that
carries the right id, whichever screen it belongs to.

That state is reachable, and two independent measurements say when.

**A dying instance loses its window while its bindings are still live.** In Qt
6.11 `QQmlDelegateModelItem::destroyObjectLater()` clears only the delegate's
own context and is not recursive, then defers the delete. A `ModuleSlot` is
such a delegate; the pocket lives one level deeper, inside the slot's
`registryLoader`, so its context is *not* cleared. `QQuickRepeater::itemsRemoved`
calls `setParentItem(nullptr)` on the slot, `derefWindow()` recurses into every
child, and the pocket's `resolution` binding is re-evaluated with `mine` null —
after which `Component.onDestruction: releaseAll()` runs a later event-loop turn
and hands whatever is in `driven` back as `visible: true`. Measured on Qt 6.11.2.

**A live surface loses its window whenever a monitor moves.** Quickshell's
`WlrLayershell::deleteOnInvisible()` returns `true`, so a Wayland `PanelWindow`
set `visible: false` really destroys its backing window and detaches its content
item; `QsWindow.window` is null until it is recreated. `Ui/ScreenMoveRemap.qml`
pulses exactly that for ~50 ms on every screen whose origin moves, which is
every monitor-profile switch and every hotplug.

The reported symptom is the first of those. Dragging a widget into the pocket,
out of it, or reordering inside it writes the layout, and the write rebuilds
every widget on every monitor. Among the dying instances, one loses its window
late enough that the surviving old slots are gone and the first id match is a
**new** slot on another screen. It adopts it, and on the way out releases it.
The pocket that really owns that slot has already finished its own `apply()`
and has no reason to run again, so the widgets stay out until something makes
it re-apply — which is what hovering it does.

Note what is *not* happening: the victim pocket's `expanded` stays false. The
tooltip that reads "Pocket open" is read by hovering, and hovering is what sets
it. The observation is contaminated by the act of observing, and the same hover
is why the stack folds afterwards.

Two neighbouring defects were found while looking and are deliberately **not**
fixed here; see Consequences.

## Options

**A — Freeze while the window is unknown.** Resolve nothing and make `apply()`
return early, changing neither `driven` nor any slot. Rejected: it introduces a
state that can strand. It also drops `memberPanelOpen` and `memberHovered` for
the duration, so a monitor moving while a member's panel is open folds the
pocket up underneath that panel — strictly worse than today.

**B — Latch the window.** Keep `ownWindow` as a plain property written only
when `QsWindow.window` is non-null, so a transient null neither widens nor
narrows the filter. Rejected: it does not buy what it looks like it buys. A
remap pulse takes the *slots'* windows away too, so their `slotWindow()` is
null and they fail the comparison whether or not this instance latched its own.
The cycle it was meant to avoid happens anyway, and the latch is state that has
to be reasoned about for nothing.

**C — Compare unconditionally.** Chosen.

## Decision

**`driven` contains only slots of this instance's own bar surface. Nothing
else, at any point in its life, including the moment it ends.**

The comparison is no longer conditional on the answer being available. An
instance that does not know its own window matches no slot at all, which is
what the host's own `sameWindow()` already says — it opens with
`if (!left || !right) return false`. The rule moves into `Model.ownsSlot()` so
it has one owner and one test:

- the host cannot tell surfaces apart (no `slotWindow`/`sameWindow`): every slot
  is ours, which is the single-surface degradation this plugin has always
  offered a custom bar;
- we do not know our own window: **no** slot is ours;
- otherwise: the host's answer.

Only the middle line is new, and it is the whole fix. Everything downstream
follows from it without changing: `apply()` releases what left `wanted` and
takes what entered it, `hideDriven()` and `releaseAll()` walk `driven`, and none
of them can now reach a screen this instance does not own.

The tooltip gains a line for the case, because a pocket that has resolved
nothing must not report the same thing as a pocket that is merely empty, and
must not claim its members are "not on this bar" — it never looked. `describe()`
takes `surfaceUnknown` and leads with it.

## Consequences

The gesture that was reported broken — drag a widget into the pocket, out of
it, or around inside it — no longer leaves a stack fanned out on a screen
nobody was working on. So does the case nobody reported: a pocket on a monitor
being unplugged can no longer release the widgets of a monitor that is staying.

**A monitor move now costs one release-and-re-hide cycle per pocket.** During
the remap pulse the surface has no window, so its own slots fail the comparison
too — `bar.slotWindow()` reads the same attached property — and `apply()` hands
them back visible before the pulse ends and takes them again. It happens on a
surface that is unmapped, so there is nothing to see; the risk is a single frame
at the moment the surface comes back. This is the price of having no state: the
alternative was to latch the window, which does not avoid the cycle at all,
because the slots lose their window whether or not this instance latched its
own. Option B says the rest.

**A member's panel can lose its hold for the length of that pulse.**
`memberPanelOpen` reads the resolution, which is empty while the window is
unknown, and the fold-up timer's other guard is the host's bar-hover flag, which
an open panel's input mask already forces false. A monitor moving in the ~50 ms
window while a member's panel is open can therefore fold the pocket underneath
it. It re-opens on its own as soon as the resolution returns. Recorded rather
than fixed: covering it means holding state through a blackout, which is the
option this decision rejected, and the pocket is invisible for the part of it
that could be seen.

**Two neighbouring defects were found and deliberately left alone.** Both are
the same mistake in the host that this decision is about in the plugin — state
that exists once for the shell being read as though it were per screen.

The fold-up timer waits on `bar.barHovered`, and `barHoverCount` is one counter
fed by every surface, so while the pointer is on any monitor's bar no pocket on
any monitor folds. It was tempting to replace it with "is the pointer on one of
*my* slots", and that is wrong: the host's hover handler fills the whole bar
surface including the empty runs between the sections, a hidden slot is
zero-width and cannot be hovered at all, and the guard exists precisely to hold
the fold while the pointer rests somewhere the fold would move something under
it. Narrowing it reopens the oscillation the timer's own comment describes and
breaks the parity with Omarchy's centre-section reveal that the README claims.
It only ever delays a fold and never opens anything, so it is a README note.

`Bar.qml::moduleClickTargetAt` hit-tests a click against `clickTargets` from
every monitor, and `mapToItem` between two windows goes through global
coordinates that Wayland does not give a client — both bar surfaces report the
screen corner, so they are tested stacked on top of each other. Two pockets at
the same distance from their bar's left edge can therefore take each other's
clicks, which pins the wrong screen's pocket. Refusing a press that arrives
without a hover was the obvious guard and is wrong twice: `KeyboardPanel`
forwards bar clicks through `triggerPress` while a panel's input mask makes
hover impossible, which is exactly the case the README offers the pin for; and
the host resolves one target and does not try a second, so the guard would turn
a wrong action into a dead click without ever delivering the press to the pocket
that was aimed at. `KeyboardPanel::pressTargetAt` already filters by window —
the fix is the same filter in `moduleClickTargetAt`, and it belongs upstream.

**An instance that owns no slot still writes.** It runs `steerDrop()` and
`commitDrop()` as before, because 0004 requires every instance to reach the same
membership answer from ids alone, and none of that reads the resolution. What
changed is only what it may touch on screen.

**What this does not fix.** With `centerAnchor` set, the bar builds every centre
widget twice in the *same* window; no window comparison separates the drawn one
from the placeholder, and the README's caveat about a centre member stands
untouched. And `sameWindow()` falls back to comparing screen names, so "our own
surface" is as precise as the host's own answer and no more.

**The rule cannot be defended by a test.** The defect lived in object lifetime,
not in logic: `ownsSlot()` is pure and its tests state the refusal from both
sides, but nothing in the suite can notice a future caller reintroducing "if we
cannot tell, take it". This paragraph is the guard; the tests are the reminder —
the same division 0004 records for the same reason.

Checked on the three-monitor session that reported it (eDP-1, HDMI-A-1, DP-2 on
USB-C), after a shell restart on the fixed build: a widget dragged into the
pocket, one dragged out of it, and one reordered inside it — each performed on
the middle screen, each followed by looking at the other two — left no stack
fanned out anywhere. A monitor-profile switch and back returned every pocket to
hiding its own members. Before the change the same three gestures produced the
defect intermittently.

This is an observation of the screens by the person who reported it, not an
instrument reading; what the machine contributes is the negative half. The
shell's log carries no `TypeError` from the plugin across the restart and the
gestures, which is what a `resolution` binding that could not evaluate would
produce on every `moduleSlots` change — so the new comparison did run, on all
three surfaces, for every rebuild the test drove.
