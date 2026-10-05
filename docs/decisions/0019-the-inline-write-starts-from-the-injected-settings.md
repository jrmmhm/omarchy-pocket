# 19. The inline write starts from the injected settings

- Status: accepted
- Date: 2026-10-05
- Closes [#16](https://github.com/jrmmhm/omarchy-pocket/issues/16)
- Replaces the base of the merge
  [0015](0015-the-host-answers-by-capability-now.md) describes; the reason the
  merge exists at all is unchanged
- Leans on [0018](0018-the-fan-out-follows-the-bar-not-the-list.md) for the one
  known way the injected `settings` lag, and answers the write-side half of it

## Context

On Omarchy 4.0.3 and later an installed plugin has one write left: the host's
inline writer, `shell.qml::updateEntryInline`, which rebuilds the plugin's entry
as `{id}` plus exactly what it is handed. Whatever Pocket leaves out of that
object is deleted from the user's `shell.json`, and whatever order it hands the
keys in is the order they land in.

Up to 0.4.1, `Model.mergedEntrySettings()` built that object from two copies of
the entry: the facade's `layoutConfig` snapshot as the base, with the injected
`settings` laid over it. #16 described from source why that fails after a hand
edit to Pocket's own entry, and this decision measured it.

**The measurement.** Omarchy 4.0.4-1 (its shell is byte-identical to 4.0.3's),
quickshell 0.3.1, Qt 6.11.2, Pocket at `ec3f769`. A script snapshotted
`shell.json`, rewrote Pocket's entry by hand in one write — `showCount` deleted,
a key `probe16` inserted between `id` and `members`, the first two members
swapped so that `repairMemberOrder()` writes on its own — waited three seconds,
read the file and restored the snapshot.

| | Pocket's entry in `shell.json` |
| :--- | :--- |
| hand edit | `{id, probe16, members: [swapped]}` |
| after Pocket's repair, at `ec3f769` | `{id, members: [ordered], showCount: true, probe16}` |
| after Pocket's repair, with this decision | `{id, probe16, members: [ordered]}` |

At `ec3f769` the deleted key came back and the inserted one moved to the end,
both exactly as #16 predicted. With this decision the repair changes `members`
and nothing else.

**Why the snapshot is stale.** A `shell.json` change that touches only inline
settings takes the bar's delta path, `Bar.qml::applySettingsDelta`, which
patches the host's layout array in place and reassigns each affected widget's
`settings`. `layoutConfig` is never reassigned, so `onLayoutConfigChanged` does
not fire and the facade's copy is not re-synced.

## Options

**A — The injected `settings` alone.** Chosen. The host builds them as the whole
entry minus `id`, in the file's key order (`BarModel.js::entrySettings`), both
when it injects a widget and when the delta path patches one. That is precisely
what the inline writer needs.

**B — The shell facade's `barConfig`.** It is re-synced on every `shell.json`
change, which made it look like the current copy. It is not: `syncPluginApis()`
runs from inside `onShellConfigChanged` and copies the `barConfig` binding
before that binding has re-evaluated, so every plugin receives the config from
before the latest change. Reported upstream as omacom/omarchy#11505, with fixes
open in #11661 and #11888 and none merged on 2026-10-05. Rejected: after a hand
edit it holds the state before the edit, which is #16 again.

**C — Keep the snapshot as base, but drop keys `settings` does not hold.**
Rejected. It fixes the deleted key and leaves the order wrong. The snapshot then
contributes nothing that `settings` does not.

The snapshot was also defended as the copy a plugin in the same scene cannot
write to. That defence held nothing. Another plugin can reach Pocket's
`bar.shell.updateEntryInline` and call it directly, and the facade's
`layoutConfig` is a plain `property var` as well. What actually protects the
entry is that Pocket refuses `id` and the keys that disarm an entry, on its own
writes. That refusal is unchanged.

## Decision

**The inline write is built from the injected `settings` alone.** The written
key keeps its own place, every other key keeps its value and its position, and
a key `settings` does not hold is not written. `Model.mergedEntrySettings(live,
key, value)` owns the rule. `Model.layoutEntryFor()` lost its only caller and is
deleted.

**What `settings` gets wrong, and the answer to it.** 0018 measured one way the
injected `settings` lag: after a reorder, the host can hand a running pocket its
old `members` back, and the instance keeps that old list until the next full
rebuild. A `members` write overwrites that value anyway. A write of any OTHER key
would carry the old list back into the file, and the order repair would not
notice, because the value it compares does not change. So
`BarWidget.qml::writeSetting()` sends `members` in layout order whenever
`membersMisordered` is true. That is the value `repairMemberOrder()` would
write, under the same guard, and the layout is the copy 0018 found current.

## Consequences

#16's two symptoms are gone, and the measurement above is the evidence.
`tests/model-test.js` and `tests/qml/model.qml` replace the comment that named
the gap with four whole-file cases after a hand edit: a changed value, an added
key, a deleted key, and a key inserted mid-entry. The last two failed in both
engines against the old merge before the fix. `tests/qml/facade.qml` drives the
stale `members` case through the real facade.

A host that injects no `settings` at all writes `{id}` plus the written key, and
drops anything else on the entry. No Omarchy host does that: the base widget
declares `settings`, and `injectProps()` assigns it. Pocket could not read its
members on such a host either.
