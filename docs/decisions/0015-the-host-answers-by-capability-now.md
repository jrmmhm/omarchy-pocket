# 15. The host is asked by capability, not by assumption

- Status: accepted
- Date: 2026-09-09
- Amends [0002](0002-members-belong-on-one-side.md) on the far side of the mark
- Narrows [0004](0004-membership-is-decided-from-the-gap-not-the-slot.md)'s
  "no per-instance input" the way
  [0009](0009-a-drag-decides-against-the-membership-it-started-with.md) narrowed
  it before
- Extends [0005](0005-a-pocket-drives-only-its-own-screens-slots.md) with the
  fold guard a facade leaves behind
- Its overlay's lifecycle is corrected by
  [0017](0017-an-overlay-lives-as-long-as-the-pocket-that-built-it.md): shared
  between instances, the overlay's handlers died with the one that built it

## Context

Omarchy 4.0.3, released 2026-09-08, stopped injecting the bar into installed
plugins. A third-party bar widget now receives `Ui/PluginBarApi.qml`, a
capability-scoped facade, and `bar.shell` a matching `PluginShellApi`. It is a
security fix from a responsible disclosure (upstream PR #9618, reported by
Roger Piñol), aimed at authentication-service exposure; the bar surface was
narrowed alongside it.

**The measurement.** Of the fifteen host symbols this plugin reads, the facade
carries none: no `moduleSlots`, `slotWindow`, `sameWindow`, `canonicalWidgetId`,
`centerAnchor`, `barHovered`, `barDragSource`, `barDragTarget`, `barDragAfter`,
`barDragTargetGeometry`, `dropMarkerRect`. `bar.shell.mutateShellConfig` is
present and returns `false` without calling its mutator for any plugin that does
not declare `kind: "bar"`.

Every guard this file has held. Nothing threw, nothing warned, and the pocket
loaded cleanly and did nothing: measured on a three-monitor session,
`debugBarGeometry` reported all seven members at `visible=true` while the pocket
was collapsed. The suite was green at 373 assertions throughout, because every
case drove the widget against a fake bar written from the same understanding as
the code. The README's promise — a renamed property stops a feature rather than
breaking one — was kept to the letter and was worth nothing, because all fifteen
went at once.

It is not this plugin's problem alone. Upstream issues #10937, #10929 and #10888
report the same removal from three other plugins, unanswered; the whole
bar-organiser category is down. Of the published answers, one changes `kinds` to
`["bar"]` and replaces the entire bar, and one walks the QML scene. Upstream's
own documentation says the second is available: "The facades are API boundaries,
not same-process QML sandboxes: a visual widget shares the host bar's scene and
can walk its parent hierarchy to ordinary host objects."

## Options

**A — Follow the upstream guidance and declare `kind: "bar"`.** It is the only
supported route to `mutateShellConfig`. Rejected twice over: a plugin declaring
that kind is enabled only while it IS the selected bar, so Pocket would have to
render and maintain the whole bar; and taking the privilege by declaring a kind
this plugin does not implement is precisely the hole PR #9618 closed. The
manifest test that holds this plugin to one kind stays.

**B — Wait for upstream.** Three reports, no maintainer reply, no migration
guide, and a native grouping feature open since July with three unmerged pull
requests. Rejected: it leaves every installation broken for an unbounded time.

**C — Replace each host reading with a fallback.** Chosen.

**D — Replace the host readings outright.** Rejected on the hard requirement:
an older Omarchy still publishes everything, and a user who updates the plugin
before the shell must keep the behaviour they have. Preferring the host also
means a future release that gives the API back is used again without an edit.

## Decision

**Every host reading has a preferred source and a fallback, and which one is
used is decided at runtime from the observed capability. Never from a version
number.**

| Reading | Preferred | Fallback |
| :--- | :--- | :--- |
| slots | `bar.moduleSlots` | walk this surface's item tree |
| centre anchor | `bar.centerAnchor` | `bar.shell.barConfig`, plus a structural test |
| pointer on the bar | `bar.barHovered` | a HoverHandler on the surface root |
| pointer during a drag | `barDragSceneX/Y` (unused before) | a PointHandler holding a passive grab |
| dragged widget | `bar.barDragSource` | the slot whose own `dragSource` is true |
| insertion line | `barDragTarget` / `barDragAfter` | computed from pointer and slot geometry |
| writing `members` | `shell.mutateShellConfig` | `shell.updateEntryInline` on its own entry |
| moving another entry | `shell.mutateShellConfig` | none; the tooltip says so |

Five things about that table are not obvious and were each paid for.

**The walk covers the whole surface, not the pocket's row.** A member in another
section is hidden today, and the centre anchor is mounted beside the section
loaders rather than inside one — a walk over the row alone would silently stop
hiding the first and stop refusing the second. Measured on the live bar: 26
slots across three sections, per surface. Everything it finds is on this surface
by construction, which is why the fallback needs no window filter at all and
reports `hostComparesWindows: false` honestly rather than as the degradation
0005 offers a custom bar.

**The walk replaces its array only when the set changed.** The host replaced its
own on every register and unregister; a walk that assigns a fresh array on every
call notifies every downstream binding whether or not anything moved, and
`resolution` feeds `apply()`, which re-asserts state that feeds back. Measured
as a binding loop on the tooltip — the one surface that exists to explain a
pocket that cannot work, dark again, for the second time in this project.

**The overlay carries two handlers and neither substitutes for the other.** Qt
delivers hover only while no exclusive grabber exists — the same line in every
release from 6.5 to 6.11, so a design and not a bug — and a `PointHandler`
answers only while a point is pressed, resetting its position to (0,0) on
release, which is inside the bar and would mean the pocket never folded again.
A handler holding a *passive* grab keeps every move and the release regardless
of the foreign exclusive grab; that grab can only be taken at press, by an item
hit before the slot's own MouseArea, which is why the overlay sits above the
bar. Measured live: continuous positions through a drag, the correct source, and
no effect on the host's own gesture.

**The hover handler does not sit on the overlay.**
`QQuickDeliveryAgentPrivate::deliverHoverEventRecursive` breaks out of the
sibling walk as soon as any HoverHandler reports itself hovered; `blocking` only
decides whether the walk stops entirely. An overlay above the bar is visited
first, so a handler there took hover away from the whole bar — the mark stopped
fanning out on pointer and nothing in the plugin could tell, because from the
inside it simply never happened. The same function names the place that works:
"Don't propagate to siblings, only to ancestors". It sits on the surface root,
which is where the host puts its own `barHovered`. It is re-armed after a
rebuild, because Qt's hover bookkeeping does not always survive one: measured
stuck true at a frozen position on the surface a drop happened on, holding the
pocket open for the rest of the session.

**The inline write carries the whole entry.** The host's inline writer rebuilds
the entry as `{id}` plus exactly what it is handed, so every key omitted is
deleted from the user's `shell.json`. The README promises the opposite, and
without the merge that promise would be false the first time anyone put a second
key on the entry — the author's own bar carries one. The merge base is the
host's layout snapshot and never the injected `settings` property: that is a
writable `var` in a scene every plugin shares, and a key another plugin dropped
into it would otherwise be laundered into the config through the one write this
plugin is trusted with. Capability is decided by whether this plugin's own
mutator body RAN, because no return value separates "refused" from "did
nothing".

### What the far side of the mark now does

**Amends 0002.** With no steering and no write to another widget's entry, a
far-side arrival would stay on the far side for good. That splits the run — the
outcome 0002 measured as the reported bug — and it also breaks the way out:
`gapTouchesMember` would read the gap past the mark as inside the group, so
"drag a member past the middle of the mark and it comes out" would stop working
there.

So where the host cannot be steered, a far-side release is refused. This is
0002's option A, which 0002 measured as wrong — but it was wrong in a world
where nothing told the user. The predicate that refuses is the same one that
lights the mark, so the far half simply does not light, and the answer arrives
before the button comes up rather than as a surprise after it. 0002's own
measurement stands and its decision is unchanged wherever steering is available.

### What the drag rule now reads

**Narrows 0004.** Only the surface a drag is on carries a slot with
`dragSource` set, so exactly one pocket instance sees a gesture at all. That is
a per-instance input into the membership rule, which 0004 asked to keep free of
them. It is safe for the reason 0004 itself gives for `targetIsSelf`: the
instance that is not being aimed at falls through to doing nothing, rather than
to acting on a conclusion the others did not reach. It is also strictly better
than what 0004 was defending against — one writer instead of several — and it
removes the race 0009 records, because the instances that are not on the drag
surface never reach the write at all.

## Consequences

On Omarchy 4.0.3 and later, three things are gone and are documented as gone:
the mark's far half no longer takes a widget in; the placement invariant cannot
move a member back and the tooltip names the misplacement instead; and a member
in another section is reported without the section it is in. On earlier
versions every path is the preferred one and behaviour is unchanged, which the
existing QML cases — all written against a bar that publishes everything — now
serve as the regression suite for.

Two new tests exist because neither of the old kinds could have caught this.
`tests/qml/facade.qml` loads the host's own facade rather than a stand-in.
`tests/live.sh` asks the running shell whether the bar is drawing what the
setting says it should, and answers "21 of 21 member slots disagree" against a
pocket that hides nothing.

One limitation surfaced that is older than this change and not caused by it: a
member whose own widget has hidden itself has no drawn slot, the bar starts a
drag only on a drawn slot, and so it cannot be taken out by the gesture that put
it in — on any host. Reported on a real bar, where the bluetooth widget went
into the pocket while its adapter was showing. The tooltip now names it and
points at `members`; nothing else could, because from the outside it looks
exactly like a widget the pocket is holding.

The fallbacks rest on something upstream describes rather than promises. If the
scene stops being walkable, the preferred side is already asked first and the
plugin degrades to what it does today — visibly, and with the tooltip saying so.
That is a worse position than reading a documented API, and it is the position
upstream has left this category of plugin in.
