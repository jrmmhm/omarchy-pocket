# Pocket

**Tuck a run of bar widgets into one slot and fan them back out on hover.**

A bar that has grown to a dozen widgets is a bar you stop reading. Pocket takes
the ones you rarely need, hides them behind a single mark, and brings them back
the moment you point at it. They stay fully usable while they are out — the same
widgets, not stand-ins.

The mark is a row of dots that turns upright as the pocket opens, over the same
600 ms `OutCubic` the stock tray drawer uses, and the members fade with it.
Deliberately not a chevron: the tray sits in the same section doing a visually
similar thing, and two identical glyphs beside each other are two things nobody
can tell apart.

## Why this one keeps your setup honest

Every other way of grouping bar widgets moves them out of `bar.layout` — into
the top-level `plugins[]` array — and mounts them again somewhere else. That
works on screen and breaks everything around it, because Omarchy decides a bar
widget is *enabled* by whether its id sits in `bar.layout`. Move it out and:

- `omarchy plugin list` and plugin managers report a running widget as **off**
- the obvious fix makes it worse: the manager's toggle can double-mount it
- `omarchy-shell shell toggle <id>` and its keybinding stop finding it
- its settings lose their only valid home

**Pocket moves nothing.** The widgets stay in `bar.layout`, in their own module
slots, built by the bar itself. Pocket only flips `visible` on those slots, and
a Qt `Row` does not lay out an invisible child — so the space closes up and
nothing else in the shell notices. Every tool keeps telling the truth.

## Install

```bash
omarchy plugin add https://github.com/jrmmhm/omarchy-pocket.git --enable
```

Then name the widgets it should hold, on its own entry in
`~/.config/omarchy/shell.json`:

```json
{ "id": "jrmmhm.pocket", "members": "omaplug, omarchy.tailscale, ianswope.snapshots" }
```

`members` also accepts a JSON array — `["omaplug", "omarchy.tailscale"]` — which
is the nicer shape if you edit the file by hand. The comma-separated string
exists because Omarchy's settings form can produce a string and not an array.

| Setting | Type | Default | What it does |
| :--- | :--- | :--- | :--- |
| `members` | string or array | `""` | Ids of the bar widgets to tuck away |

The file hot-reloads: no restart needed after an edit.

## Where to put it

**Put the pocket on the side of its members that faces the section's anchor.**
In the `right` section that means the members come *first* and the pocket last;
in `left`, the pocket first. Fanning out changes the section's width, and this
ordering is what keeps the mark itself from sliding out from under your
pointer.

`omarchy.tray` is a poor member: Omarchy pins it to its section's inner edge on
every config load, and its own drawer assumes it sits there.

## How it decides to open and close

It opens while the pointer is on the mark or on any widget it holds, and
while one of those widgets has its panel open — a bar panel covers the screen
with an input mask, so hover stops arriving entirely, and without that last
condition the pocket would fold up underneath the panel you just opened.

It closes within a tick of all of that stopping **and** the pointer having left
the bar — a repeating check rather than a countdown, because a countdown that a
guard refuses once has nothing left to re-arm it.
Waiting for the bar rather than the pocket is deliberate: folding up narrows the
section, which can slide a neighbour under a stationary pointer, and a pocket
that reacted to that would oscillate. Omarchy's own hover reveal uses the same
rule.

**Click the mark to pin it open**, click again to release. That is the way
out of the cases where no leave event is ever coming — a workspace switch that
teleports the cursor, an application grabbing the pointer. The pin is
session-only and deliberately not written to `shell.json`: a half-written
`shell.json` drops the bar to Omarchy's defaults and deregisters every
third-party widget on it for as long as that lasts.

## Things you should know before installing

- **`SUPER+CTRL+1…9` renumbers.** Those bindings open "the Nth panel in the
  right section" and count only what is *drawn*, so a collapsed pocket shifts
  the numbering — and with a pocket it additionally depends on where your
  pointer is. This is host behaviour, not something a plugin can fix; it already
  happens today whenever a widget hides itself (no battery, no Bluetooth
  adapter). Tracked upstream in
  [omarchy#6355](https://github.com/basecamp/omarchy/issues/6355).
- **Dragging a widget next to a collapsed pocket** drops it *behind* the hidden
  group, because the bar's drop targeting skips invisible slots.
- **Dragging the pocket itself** does not take its members along; they stay
  where they were.
- **A plugin manager's disable/enable round-trip can lose `members`**, because
  re-enabling a bar widget rewrites its entry as a bare `{ "id": ... }`. Keep a
  copy of the line if you toggle the pocket off and on.
- **A member cannot be the `centerAnchor`.** That one slot carries a `visible`
  binding of the bar's own, and writing it would destroy the binding for the
  rest of the session. Pocket refuses it and says so in its tooltip.
- **One pocket per bar.** A second entry added by hand is detected and reported
  in the tooltip; two pockets sharing a member will fight over it.

The tooltip is where all of this surfaces at runtime — it names every member it
could not find, could not use, or would not touch.

## Development

```bash
bash tests/run.sh      # ALL TESTS PASSED (N assertions, 0 failures)
```

`Model.js` holds everything decidable without a running shell and is unit-tested
with `node`; `BarWidget.qml` keeps only what needs live objects. Note that the
shell's plugin file-watcher does not follow symlinks, so if you develop against
a symlinked checkout, apply changes with `omarchy restart shell`.

## Requirements

Omarchy 4.x with the Quickshell bar. No network access, no subprocesses, no
files written — Pocket reads the bar's own state and nothing else.

## License

[MIT](LICENSE)
