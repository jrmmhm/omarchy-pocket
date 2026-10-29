# 25. A reload reads the entry from the file

- Status: accepted
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

The pocket reads its own entry from `$HOME/.config/omarchy/shell.json` with a
watched `FileView`, and replaces `settings` with the file's copy when both of
these hold:

- `settings` is the slot's `moduleSettings`, or the copy taken from the file
  earlier. Anything else came from the host's delta path, which is newer than
  both; from then on the file is no longer read.
- The file has been quiet for one second. The file lags the host: the shell
  sets its config first and writes the file after, and a pocket the bar
  rebuilt after a drag is born before the move is on disk. The timer restarts
  on every load of the file and on every change of `settings`, so a late
  injection of the frozen copy is answered again.

The file is asked only once the pocket has found its own slot, since the
frozen copy is the slot's; a walk can find it late, after a monitor move
unmapped the surface, and finding it starts the quiet period again.

The order repair (0018) waits until the file has been asked about the
`settings` the pocket holds. It is the one write the pocket makes on its own
from `settings`, and a reorder leaves the frozen copy's `members` out of layout
order, so a turn after the reload it wrote that copy back, and the host's
answer to that write then read as current. The fresh-context review of this
change found it, and a second review found the same write for a slot found
late; `tests/qml/reload.qml` reproduces both.

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
- **Waiting for #7692.** It fixes the cause, and once it ships `moduleSettings`
  and the file agree, so this code changes nothing there. Until then every
  reload loses state.

## What was measured

The same script against `main` (45fef50) and against this change, the plugin
symlink pointed at each checkout and the shell restarted first, so the frozen
copy was the snapshot's. Each run edited the pocket's entry in `shell.json` by
hand, which takes the host's inline path exactly as the pocket's own writes and
a drag onto the mark do, then ran `rescanPlugins`. `shell.json` was snapshotted
first and restored byte-identically after every run.

| # | Scenario | `main` | This change |
| :--- | :--- | :--- | :--- |
| 1 | `omarchy.tailscale` dropped from `members` after the start, reload, a pin click on the eDP-1 mark | **the member came back, 2 of 2** | the member stayed out, the pin was written, 6 of 6 |
| 2 | The eDP-1 pin set after the start, reload | not run | open, 6 of 6 |
| 3 | Shell started with the eDP-1 pin, the pin dropped after the start, reload | not run | folded, 6 of 6 |
| 4 | `tests/live.sh --gesture eDP-1`: a member dragged out and back in | not run | passed, 6 of 6; with the order repair waiting, 17 of 18 |

Rows 1 and 2 were run again once the order repair waited, 6 of 6 each, and
row 1 once more on the final build, which also waits for the slot, 6 of 6;
row 3 was not. The one failure in row 4 was a drag out that left the member in; it
did not come back in the twelve runs after it, six of them at the same pace,
and its cause is not known.

Rows 2 and 3 were not run against `main` with this script; 0023 measured the
same two states there by its own procedure, with the pin by click: a pin set
was lost 3 of 3, a pin released came back 2 of 2.

Row 4 is there for the rebuild a drop causes: the rebuilt pocket must not take
over the file before the move is on disk. It never did.

`tests/qml/reload.qml` plays the host's three injections against a slot with a
frozen `moduleSettings`. Against `main` (with the `configPath` it sets on one
pocket removed) it fails: the order repair wrote the frozen copy a turn after
the reload, and the next write carried no lock where the file held one. It
also fails without the timer restart on a change
of `settings`, without the stop once the host is current, with no quiet
period, and with the order repair not waiting.

## Accepted limit: the first second after a reload

Until the file has been quiet for a second, the pocket runs on the frozen copy.
Nothing writes `settings` back on its own in that second; a pin click or a
drop by hand does, and writes the frozen copy back, as before this change. A hand is slower than
that after a reload, and the reload itself is rare. The order repair, and so
the reorder after a drop, now runs a second later than before.

## Consequences

The pocket reads one file it does not own, at the path the shell uses for it.
A shell that keeps its config somewhere else gets no file and nothing changes.
All QML cases now run with an empty home of their own (`tests/qml/run.sh`), so
none of them reads the user's real `shell.json`.

What this does not cover:

- A reload while a second pocket entry exists. Neither pocket writes then
  anyway (`Model.mayWrite()`).
- Settings the host keeps in memory but has not written, if a write ever
  fails. The pocket would take the older file. Not seen.
