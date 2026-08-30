# 12. The audit of the published plugin

- Status: accepted
- Date: 2026-08-30
- Corrects the renumbering paragraph of
  [0007](0007-the-two-host-limits-measured.md), which reasoned where it should
  have measured
- Amends [0011](0011-the-tooltip-escapes-because-it-does-not-own-its-sink.md),
  whose bound holds and whose walk did not

## Context

`0.3.1` had been on the marketplace for a day. This is a full read of the
plugin against the host it runs in — security, edge cases, compatibility — and
of every claim the README and `manifest.json` make against what the code does.

Everything below was measured on this machine: Omarchy 4.0.1 as installed,
Quickshell 0.3.1, Qt 6.11.2, node 26.2, two outputs (eDP-1 at x=0, scale 1.667;
HDMI-A-1 at x=1152, scale 2.4). Where a number appears it was taken here and it
lives here; the README and the CHANGELOG name this file rather than restating
it.

### What was checked and found sound

No subprocess, no network, no `eval`, no `Qt.createQmlObject`, no path
handling: `grep` over both source files is empty for all of them. The one real
egress was the tooltip, and [0011](0011-the-tooltip-escapes-because-it-does-not-own-its-sink.md)
closed it at the source a day earlier — re-read against the installed host and
still correct: `Bar.qml`'s tooltip `Text` sets neither `textFormat` nor
`wrapMode`. Config writes go only through `bar.shell.mutateShellConfig`, touch
only this plugin's own `members` key, and move only one member entry. That this
is not a privilege boundary — anyone who can write `members` can write `exec`
on the same entry — is stated correctly in the CHANGELOG and needs no revision.

Fifteen host reads, counted: `bar.layout` and `bar.moduleWidgets` appear only in
comments, so the README's number is right. `bar.urgent` really is the only one
of them the host documents. `U+F01D8` really is `md-dots_horizontal` in the
installed JetBrains Mono NF. `centerAnchor` really does default to
`omarchy.clock`, the anchored centre slot really does carry a `visible` binding
of the host's own, and every centre widget really is built twice with the hidden
copy first. `onCanceled` really does clear the drag without moving anything, so
the cancelled-drag caveat stands. `allowMultiple` is declared in manifests and
read nowhere in `bin/` or `shell/`, so this plugin's own duplicate detection is
in fact the only thing enforcing it.

## What was wrong

### One defect, seen at three depths: the pocket held less than it was told to

**A member with a name every object already has.** `parseMembers()` kept its
duplicate table on a bare object, and `"toString" in {}` is true before anything
is put there. `toString`, `constructor`, `valueOf`, `hasOwnProperty`,
`isPrototypeOf`, `propertyIsEnumerable` and `toLocaleString` all satisfy
`ID_PATTERN`, and every one of them was skipped as a duplicate it had never
been. Skipped inside `parseMembers()`, which runs before `rejectedMembers()`, so
the tooltip had nothing to say either.

**The same shape in `orderMembers()`, and worse.** The guard that keeps the
first index of a repeated layout id, `!(key in rank)`, answers true for a name
nothing put there, so such an id never got a rank and the comparator subtracted
a function. The two engines this file runs in disagree about NaN, and this is
where the audit's own method nearly failed:

| fixture | node (V8) | Qt V4 |
| --- | --- | --- |
| `orderMembers(["a","toString","b"], ["b","toString","a"])` | `["a","toString","b"]` | `["b","toString","a"]` |
| `membersInLayoutOrder(…)` on that result | **`true`** | **`false`** |

In V4 the five-element fixture had no fixpoint at all — measured as a period-2
cycle between `["b","a","valueOf","c","toString"]` and
`["c","toString","valueOf","b","a"]`, with `membersInLayoutOrder()` answering
false at every step. `membersMisordered` is guarded by
`rejectedIds.length === 0`, and these names pass the allowlist, so the guard
never fired: `Component.onCompleted → scheduleReorder → repairMemberOrder`
wrote a different wrong order into the user's `shell.json` on every bar rebuild,
for ever. This was not a display defect. The comment claiming "ordering by the
layout is idempotent" was false in the engine that matters.

**An entry the parser could not read at all.** `toList()` drops anything that is
neither a string nor an object with a string `id`, and it runs upstream of
`rejectedMembers()`, so those entries were gone before anything could name them.
Measured: `members: [{"id": 5}, 42, null, {"name": "omaplug"}]` produced
`Pocket is empty — drag a widget onto it` for a user who had configured four.

### `bar.moduleSlots` was the one host read taken on trust

`bar ? bar.moduleSlots : []` guards a null bar, not a renamed property. Measured
against a bar publishing all fourteen other symbols and not this one: five
TypeErrors per evaluation — `resolution` and `ownSlot` directly, then
`memberHovered`, `apply()` and `tooltipText` through them — and the tooltip left
unassigned. The surface whose whole job is to explain a pocket that cannot work
was the one that went dark. `slotBeforeSelf` never threw, because `ownRegion` is
`""` once `ownSlot` is gone and its loop never runs.

`bar.urgent` was the second, and degrades quietly instead: an undefined assigned
to a `color` leaves the button painting what it painted last and warns once per
evaluation. The README's promise — "a renamed one makes a feature stop applying
rather than misbehave" — was true for thirteen of fifteen.

### Four sentences the code contradicted

- `manifest.json`, which is the marketplace listing: "Tuck a run of bar widgets
  **into one slot**", one sentence before "The widgets never leave the bar
  layout". The first denies the second, and the second is the whole argument
  against every competing grouping widget.
- "The mark lights up while a release would change what the pocket holds":
  `active` begins with `root.pinned`, so it is also lit with no drag in
  progress.
- "while one of those is present it does not touch the order at all":
  `membersMisordered` is guarded by `rejectedIds`, `commitDrop()` is not. A drop
  reorders the whole list — measured: `"omarchy.tailscale, ../evil, omaplug"`
  came back `"omaplug, omarchy.tailscale, ../evil, mehiel.darky"`.
- The two renumbering bullets, which 0007's own note above now carries.

## Decision

**Delete the lookup tables rather than harden them.** `Object.create(null)` was
measured working in V4 — `in` false for prototype names, assignment sticking,
`__proto__` becoming an ordinary own key where a bare object *throws* in V4 and
shrugs in node — and it was still the wrong answer. The list `parseMembers()` is
building already answers the duplicate question, and `indexOf()` already answers
the rank question. Two structures that can disagree became none, and the fix
needs no claim about either engine.

Differential evidence, both engines: 400 000 random `(list, layout)` pairs over
ids with no prototype name in them, **0 differences** from the shipped
behaviour, and 4 000 more in V4; 200 000 pairs *including* every prototype name
and `__proto__`, on which the two candidate fixes agree everywhere, so the
choice was style and not behaviour; 200 000 pairs on which the chosen one's
ordering is idempotent, **0 exceptions**, which is the property the config write
depends on.

**Bound the tooltip's walk, not only its line.** 0011 established escape-then-cut
because cutting first bounds nothing for the input the bound exists for. That
bounds the result and leaves the walk over whatever `shell.json` holds: one
megabyte in a single entry cost **111 ms** per call, against 4.3 ms for
`toList()` and 0.1 ms for `parseMembers()` on the same value — so the escape
loop was the term, not the parsing around it. Only the first `MAX_LABEL + 1`
units can reach the kept output, because every input unit produces at least one
output unit. 20 735 differential cases here and 300 285 in an independent
review, surrogate pairs laid on every index from 150 to 175 included: no
difference, and 111 ms became 0.03.

The precondition is the whole argument and nothing asserted it, so
`tests/model-test.js` now does, once per range in the table and once for
ordinary characters. A future edit that maps a character to `""` instead of
escaping it would otherwise take the precondition away in silence.

**Guard the property, not the object.** `barSlots` is read through one property
rather than three copies of a condition, which is the shape this file already
uses for `layoutConfig`, and it stays reactive for the same reason.

**Run the membership fixtures in both engines.** This is the finding that
changes how this repository tests, not only what it tests. Two of the new
assertions are green on the broken code in node — measured, not supposed — so a
suite that ran only there would have reported the fix as unnecessary.
`tests/qml/model.qml` carries the same block, and the two convergence
assertions fail there and only there.

**Assert values, and refuse throws separately.** `tests/qml/noslots.qml` loads
the real widget against a bar missing `moduleSlots` and `urgent` and asserts
what it answers. That is not enough on its own: a thrown binding is not a failed
assertion — Qt leaves the property at its last value — so `tests/qml/run.sh`
additionally refuses any run whose output carries a TypeError from `@plugin/`.
Both were watched failing on the base commit: six value assertions red, and the
five TypeErrors caught by the runner gate.

## What was reported and refused

**A panel opening on a slot the pocket has hidden.** The reading is correct:
`findPanelWidget()` applies no visibility filter, and `pickDrawnSlot()` falls
back to the first candidate when none is drawn. The conclusion does not follow,
and the measurement says why. `memberPanelOpen` watches `bar.activePopout`, so
the moment a member's own panel becomes active the pocket fans out and the slot
is drawn before the panel is anchored to it. Measured live: with
`omarchy.tailscale` tucked away, `omarchy-shell shell toggle omarchy.tailscale`
left it at `visible=true, width=27` on the focused output with the panel
correctly under the bar, and both folded back afterwards. The plugin already
answered this; the layer surfaces and the bar geometry were recorded on both
outputs before, during and after, and `shell.json` came back byte-identical.

**`revealFraction()` can return NaN.** Only with an explicit `NaN` as its fourth
argument. `applyReveal()` is the only caller and passes three, so the default
`0.15` applies — measured, `revealFraction(0.5, 0, 4)` is `0.909`. Guarding an
input no caller can produce is the error handling the project's own rules
forbid.

**`rejectedMembers()` does not deduplicate.** Deliberate, and left alone.
`parseMembers()` deduplicates because two identical ids are one member;
`rejectedMembers()` shows what was typed, occurrence by occurrence, and the line
exists to be found again in `shell.json`.

**Shipping the prose separately from the code.** Refused. The README has to
describe what the code does, and a README correcting itself for a fix that is
not out yet is simply the next false claim.

## Consequences

**A member whose id collides with a JavaScript builtin now works,** and a
`members` list the parser cannot read is named instead of silently reducing to
an empty pocket. Both were the same defect: the pocket held less than it was
told to and said nothing.

**`repairMemberOrder()` has a fixpoint.** The write to `shell.json` terminates
for every input measured, which it did not before.

**The README's guard promise is true for all fifteen host reads** rather than
for thirteen of them.

**The renumbering caveat lost a mechanism and gained a condition,** in the
README and in 0007 alike. The number of members that change the numbering at all
is smaller than either file claimed: only those with a panel of their own.

**Measured live and not repeatable in CI.** The panel routing, the renumbering
and the fold-back need a compositor, two outputs and a running shell. They are
recorded here in the shape 0007 uses for `e2`–`e9`: what was done, what came
back, and no harness kept. A test that copied `panelNavigationSlots()` into this
repository would go on passing after the host changed its mind, which is exactly
what 0007 refuses.

**The rule this file leaves behind.** A lookup keyed by user input is a
namespace, and a bare object is not an empty one. Both defects here are the same
sentence — `"toString" in {}` — and neither would have been found by testing
what the functions are *for*. What found them was asking what an id is allowed
to be and then trying those ids.
