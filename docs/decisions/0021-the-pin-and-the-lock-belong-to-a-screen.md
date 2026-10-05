# 21. The pin and the lock belong to a screen

- Status: accepted
- Date: 2026-10-05
- Supersedes the part of [0020](0020-a-right-click-locks-the-pocket-shut.md)
  that says where the lock lives and that it holds on every screen. What the
  clicks do, the fold and the tooltip's shape stay 0020's
- Writes through the path [0019](0019-the-inline-write-starts-from-the-injected-settings.md)
  fixed, and answers the stale list of [0018](0018-the-fan-out-follows-the-bar-not-the-list.md)
  for the two new keys

## Context

0020 shipped the lock as one boolean on Pocket's entry, held on every screen,
and kept the pin as a flag on each bar instance that no rebuild survived. On a
two-monitor desk that is inconsistent: a lock set on the laptop also shuts the
pocket on the external monitor, and a pin set on either one is gone after the
next drop or restart. The owner asked for both to belong to the screen they
were set on, and to survive a restart and a reboot. Membership, and moving
icons in and out, stay shared by every screen.

**How a screen can be named.** The owner's own monitor tool keys the laptop
panel by its connector and every other screen by its EDID description (make,
model, serial). It keys the panel by connector because the panel's description
changed under that machine once already (a disk swap). Measured on this machine
(Omarchy 4.0.4, quickshell 0.3.1, Hyprland 0.56.2) with an invisible `qs` probe:

| Source | eDP-1 | HDMI-A-1 |
| :--- | :--- | :--- |
| `ShellScreen.name` | `eDP-1` | `HDMI-A-1` |
| `ShellScreen.model` | `0x9EA9` | `ASUS VG289` |
| `ShellScreen.serialNumber` | empty | empty |
| `HyprlandMonitor.description` | empty | empty |
| `hyprctl -j monitors` `.serial` | empty | `R5LMTF096143` |

`Quickshell.Hyprland`'s monitors came back with an empty description, width 0
and an empty `lastIpcObject`, also after `Hyprland.refreshMonitors()`. The
socket itself answers `j/monitors` correctly, so the parse fails on the
quickshell side. That is a host matter and not Pocket's. What a plugin can reach
in-process is the connector and the model.

In the offscreen test platform a window's `ShellScreen` has no name at all
(measured: `QScreen` name `""`).

## Options

**What names a screen.**

*A — The connector for a laptop panel, the model and serial for any other
screen.* Chosen. It is the owner's monitor tool's split, as far as Quickshell
carries it. A monitor keeps its state on another port, and a different monitor
on the same port starts fresh. Identical twins share one name while the serial
is empty. A suffix with the connector was the first plan and was rejected in
review: it renamed a monitor the moment its twin was plugged in, and a dock
renumbers connectors anyway.

*B — The connector alone.* Rejected. The owner's desk and living room put
different monitors on the same HDMI port, and the second would inherit the
first one's state.

*C — The EDID description through `hyprctl` or `Quickshell.Hyprland`.*
Rejected. The first needs a subprocess from the plugin, and the second is
empty on this stack (measured above).

**Where the state lives.**

*A — Two lists on Pocket's own entry in `shell.json`, `pinned` and `locked`.*
Chosen.
- For: it is the write path Pocket already has, with its whole-file tests. It
  is editable in the settings form and with `omarchy bar set`. It is one file
  for everything Pocket keeps.
- Against: every pin click is a `shell.json` write, and on 4.0.3 and later
  every such write reloads plugin panels. Locks and drops already cost the
  same.

*B — A state file of Pocket's own.* Rejected. It needs a second write path
with its own atomic-write and whole-file tests. It is invisible to the
settings form and splits Pocket's state across two files.

**The boolean `locked` 0020 introduced.** It was never released: it lives on
the author's machine only, because the PR that added it was still open.

*A — Read it as locked nowhere; the next right click replaces it.* Chosen. No
migration code is written for one machine.

*B — Read `true` as locked on every connected screen and convert it on the
first write.* Rejected. It is code with one user, kept forever.

*C — New key names.* Rejected. It leaves a dead key behind, and `locked` is the
right name.

## Decision

- **A click changes only its own screen.** A left or middle click switches this
  screen's name in `pinned`, a right click in `locked`. Every other name in the
  list stays where the write path finds it. `Model.screenKey()` names the
  screen. `Model.screenList()`, `onScreen()` and `withScreen()` read and edit
  the lists, in the shape they were found in (`membersValue()`'s rule).
- **Per-screen values are computed inside the write.** `writeSettings()` takes
  a function of the current value (`Model.nextValue()`). On the mutator path
  it is evaluated against the config inside the mutator, which is the file as
  it is now. On the inline path it is evaluated against `settings`. A pocket
  whose `settings` lag therefore cannot drop another screen from the list on
  the mutator path.
- **Locking a pinned screen is one write.** The lock and the dropped pin go out
  together, so neither a refusal nor a rebuild can land between them. The fold
  is asked again once the write has returned (`foldIfLocked()`). Both values
  arrive in the same `settings` assignment, and inside the lock's own change
  handler `pinned` can still answer with the pin from before the write.
- **The screen name is latched.** A monitor move unmaps the surface for a
  moment (0005). A name that went blank then would drop both states and bring
  them back in an order the bindings choose.
- **Where Pocket cannot name its screen or may not write,** the left click pins
  for the session as before. The right click is neither offered nor acted on,
  and a persisted pin is not read, because no click could release it. A lock
  set by hand still holds there.
- **The tooltip says `on this screen`** in both click hints.

## Consequences

**Live, A/B against `eafc3ac` on both monitors.** A real uinput pointer, two
`omarchy-restart-shell` runs per monitor, and `shell.json` restored
byte-identically after every run:

| Behaviour | `eafc3ac` | this decision |
| :--- | :--- | :--- |
| hover opens, leaving folds (each screen) | yes | yes |
| left click pins this screen only | yes | yes |
| the pin after a restart | lost | kept, this screen only |
| right click locks this screen only | no, both | yes |
| the lock after a restart | kept, both | kept, this screen only |
| pinned + right click folds at once, other screen's pin kept | — | yes |
| a name no screen has locks nothing | — | yes |
| drag a member out and back in | passes | passes |
| pin/release, 10 runs per button per screen | 40/40 | 40/40 |

The first base run had one middle-click pin on eDP-1 that took effect on the
second click, and a first 10-run series counted 8/10 for the left click there.
The owner had moved the mouse during that run. The undisturbed rerun above is
40/40.

The names written were `ASUS VG289` and `eDP-1`. Each was read back by the
pocket that the restart had just built.

**Tests.** `tests/model-test.js` and `tests/qml/model.qml` hold the naming and
list rules in both engines, together with whole-file one-change cases for a
per-screen write. `tests/qml/facade.qml` puts a second window beside the
first, as a second monitor, behind the host's real `PluginBarApi`. It drives
the real button through these cases:

- each click stays on its own screen;
- a lock and the dropped pin go out as one write;
- the stale list of 0018;
- a lagging pocket on the mutator path;
- a second entry;
- a never-seen screen.

Sixteen Model.js mutants and sixteen widget mutants were run. All Model.js
mutants died in node and in V4, except one: it removed a guard that
`membersValue()` already made redundant, so that guard was deleted. Every
widget mutant died in `tests/qml`, two of them only after the second-entry
case was added.

**What this does not cover.**
- *The 0018 window on the inline path.* A deferred `injectProps()` restores a
  rebuilt pocket's `settings` from its slot's entry, about 118 ms after the
  rebuild in 0018's measurement. That reverts every key a write in that window
  carried, not only `members`. A pin or lock clicked within that window after a
  drop can be undone in the running pockets. The next write from them then
  carries the old list back into the file. Nothing automatic writes `pinned`
  or `locked`, so it takes a click inside the window. The mutator path is not
  affected.
- *Overlapping outputs.* A left click can land on another screen's pocket
  there (0007). That click now pins the other screen and persists.
- *Identical monitors* share their state, and a serial number that starts
  arriving later renames every external screen once.
- *A rebuild re-runs the fan-out of a pinned pocket.* A rebuild comes on every
  drop and every plugin enable. The new instance gets its `settings` after it
  is built. Before this decision, the rebuild dropped the pin instead.
- *Physically unplugging a monitor* was not done live, because switching an
  output off moves the owner's workspaces. A restart builds the surface anew
  under the same name, which is what a replug does to it. The never-seen case
  is covered live and in `tests/qml`.

**Lesson.** When two values are delivered in one assignment, a change handler
for one of them can read the other before it has been updated, just like a
binding that depends on the changing property. Inside the handler, ask only
what does not depend on that assignment. Ask again after the write that
caused it, where both values are settled. This is the same shape as
omacom/omarchy#11505 and the `holdOpen` rule in 0020, one step further out.
