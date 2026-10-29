# 25. A reload reads the entry from the file

- Status: accepted, revised the same day after the review of 0.6.1 (last
  section)
- Date: 2026-10-29
- Closes the defect [0023](0023-the-neighbours-slide-with-the-reveal.md)
  found and left open ("a reload forgets inline settings")
- Extends [0019](0019-the-inline-write-starts-from-the-injected-settings.md):
  the inline write still starts from `settings`, and this decides what
  `settings` holds after a reload
- Owns every number below; the README and the CHANGELOG name this file

## Context

A hot reload (`rescanPlugins`, which `omarchy plugin update` and the plugin
file watcher also take) gave the pocket its settings as they were when the
shell last started. A pin set or released, or a member taken in or let go,
after that start was forgotten, and the next write put the old state back into
`shell.json`, because the inline write rebuilds the whole entry from
`settings` (0019).

The cause is the host's, reported as
[omacom/omarchy#7691](https://github.com/omacom/omarchy/issues/7691) with a
fix pending as #7692. `Bar.qml::applySettingsDelta()` patches an inline change
into the host's layout and into the running widget's `settings`, but not into
the slot's `entry`, so the slot's `moduleSettings` stays at the entry the slot
was built with. A reload builds the widget again in the same slot, and
`injectProps()` hands it that frozen copy: in the loader's `onLoaded`, again a
turn later, and once more from the slot's `onActiveItemChanged`.

Omarchy 4.0.6, quickshell 0.3.2, Qt 6.12.0, Hyprland 0.56.2. eDP-1 (1152×720
logical) and HDMI-A-1 (ASUS VG289, 1600×900 logical) beside it.

## Decision

The pocket reads its own entry from `shell.json`, at the path `configPath` in
`BarWidget.qml` names, and replaces `settings` with the file's copy when
`settings` is the slot's `moduleSettings` object itself, or the copy taken from
the file earlier. Anything else came from the host's delta path, which is
newer than both. The two are told apart by identity: the host injects the
slot's own object, and a delta is always a new one, even one equal in value.

The file is read fresh, synchronously, and only at these points:

- A moment after the pocket is born, after the slot's copy is injected again,
  and after the pocket finds its own slot (`reconcileTimer` owns the length).
  The moment is there for the rebuild a drop causes: the shell sets its config
  first and writes the file after, so a pocket the bar rebuilt is born before
  the move is on disk.
- Before a click on the mark, a write, or a drag of the mark is decided, if
  that moment has not come yet. So none of them acts on the frozen copy.

It is not read before the pocket has found its slot, since the frozen copy is
the slot's; a walk can find it late, after a monitor move unmapped the
surface. And it is never read again once the slot's `moduleSettings` changes:
a host whose slots follow their entry, which is what #7692 does, injects no
frozen copy.

The order repair (0018) waits until the file has been asked. It is the one
write the pocket makes on its own from `settings`, and a reorder leaves the
frozen copy's `members` out of layout order, so a turn after the reload it
wrote that copy back.

`Model.ownEntrySettings()` reads the file. It returns the entry minus `id`, in
the file's key order, which is the shape the host injects
(`BarModel.js::entrySettings`), and the shape matters: a copy that differed only
in shape would read as newer. It returns nothing for a config that is not
version 1 or does not hold exactly one entry for the pocket, since with two
pockets the file cannot say which entry is this one.

Considered and rejected:

- **The facade's `layoutConfig`.** The host's delta path does not resync it
  (0019 has the measurement), and the host keeps the same facade across the
  reload (`Bar.qml::pluginBarApiFor`).
- **The shell facade's `barConfig`.** It is always one change late
  (omacom/omarchy#11505, 0019).
- **Reading the file once, at load.** The second and third injections overwrite
  it, and a pocket rebuilt after a drag would read the file before the move is
  written.
- **A watched file and a quiet period.** The first version, shipped in 0.6.1;
  the last section has why it went.
- **Waiting for #7692.** It fixes the cause. Until it ships every reload loses
  state.

## What was measured

The same script against `main` (45fef50) and against each build of this
change, the plugin symlink pointed at each checkout and the shell restarted
first, so the frozen copy was the snapshot's. Each run edited the pocket's
entry in `shell.json` by hand, which takes the host's inline path exactly as
the pocket's own writes and a drag onto the mark do, then ran
`rescanPlugins`. `shell.json` was snapshotted first and restored
byte-identically after every run. Every run was on eDP-1, with HDMI-A-1
attached.

| # | Scenario | `main` | 0.6.1 and the builds before it | Revised |
| :--- | :--- | :--- | :--- | :--- |
| 1 | `omarchy.tailscale` dropped from `members` after the start, reload, a pin click on the eDP-1 mark | **the member came back, 2 of 2** | the member stayed out and the pin was written, 6 of 6 three times | the member stayed out 12 of 12; the pin was written 11 of 12 |
| 2 | The eDP-1 pin set after the start, reload | not run | open, 6 of 6 twice | open, 6 of 6 |
| 3 | Shell started with the eDP-1 pin, the pin dropped after the start, reload | not run | folded, 6 of 6 | folded, 6 of 6 |
| 4 | `tests/live.sh --gesture eDP-1`: a member dragged out and back in | not run | 23 of 24 | 6 of 6 |

Rows 2 and 3 were not run against `main` with this script; 0023 measured the
same two states there by its own procedure, with the pin by click: a pin set
was lost 3 of 3, a pin released came back 2 of 2.

Row 1, revised: in the one run without a pin the member had stayed out, and
the click wrote nothing. The owner had moved the mouse during that run; the
logs held no error, and the next six runs passed.
Row 4, 0.6.1: the one failure was a drag out that left the member in; its
cause is not known, and it did not come back.

Row 4 is there for the rebuild a drop causes: the rebuilt pocket must not take
over the file before the move is on disk. It never did.

`tests/qml/reload.qml` plays the host's three injections against slots with a
frozen `moduleSettings`, four pockets, one per case. Against 0.6.1 it fails five
assertions: the file is never taken over while another entry keeps rewriting
it, and a write before the timer carries the frozen copy. It also fails with
`settings` compared by value, without the write asking the file first, without
the slot's change turning the file off, without the restart when the slot is
found late, and with a file read from cache.

## Accepted limit

A pocket the bar rebuilt after a drop reads the file a moment after it is born.
If the move took longer than that to reach the disk, it would take over the
older file. Never seen: the move is written within the same turn.

The order repair, and so the reorder after a drop, runs that moment later
than before 0.6.1.

## Consequences

The pocket reads one file it does not own, at the path the shell uses for it.
A shell that keeps its config somewhere else gets no file and nothing changes.
All QML cases run with an empty home of their own (`tests/qml/run.sh`), so
none of them reads the user's real `shell.json`.

What this does not cover:

- A reload while a second pocket entry exists. Neither pocket writes then
  anyway (`Model.mayWrite()`).
- Settings the host keeps in memory but has not written, if a write ever
  fails. The pocket would take the older file once, at the next read. Not seen.

## Revised after the review of 0.6.1

Two fresh-context reviews of everything since 0.5.0, one adversarial, one
against the stated goals, found the first version's mechanism wrong in three
ways:

- **A busy file starved it.** It watched the file and restarted its quiet
  period on every load, whoever wrote it. A file rewritten more often than
  that, by another plugin or an editor's autosave, kept the frozen copy in
  place for as long as the writing went on. Reproduced offscreen.
- **A click in the first second wrote the frozen copy.** It was documented as
  accepted, but the pocket knows exactly when it still holds that copy.
- **Value equality.** A host delta equal in value to the frozen copy, a pin
  toggled back, read as the frozen copy and could be overwritten by an older
  file. And the stop once the host was current had no test that failed
  without it.

Revised: the file is read on demand and fresh instead of watched, the frozen
copy is told by identity, a click, write or drag asks the file first, and a
slot whose `moduleSettings` change turns the file off.
