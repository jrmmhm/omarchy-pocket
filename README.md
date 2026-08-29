<div align="center">

# Pocket

**Tuck a run of Omarchy bar widgets behind one mark. Point at it, they come back.**

[![tests](https://img.shields.io/github/actions/workflow/status/jrmmhm/omarchy-pocket/ci.yml?branch=main&style=flat&label=tests&logo=github&logoColor=white)](https://github.com/jrmmhm/omarchy-pocket/actions/workflows/ci.yml)
[![Omarchy 4.x](https://img.shields.io/badge/Omarchy-4.x-1f6feb?style=flat)](https://omarchy.org)
[![bar widget](https://img.shields.io/badge/kind-bar--widget-8957e5?style=flat)](https://github.com/basecamp/omarchy)
[![MIT](https://img.shields.io/badge/license-MIT-3fb950?style=flat)](LICENSE)

</div>

![The pocket opening as the pointer arrives, and folding up again when it leaves](docs/pocket-demo.gif)

## What this is

Across the top of an Omarchy desktop runs a thin strip with small icons on it —
the clock, the volume, the battery, the network. It is called the bar, and it
fills up. Every tool you install puts another icon there, and somewhere past a
dozen you stop reading it and start hunting through it.

Pocket takes the icons you rarely need and hides them behind a single mark.
Point at the mark and they slide back out. Move away and they tuck themselves
back in.

They are not stand-ins. They are the same icons, still fully working while they
are out — and, the part that turns out to matter most, they never leave the bar
as far as the rest of the system is concerned. Nothing else on your desktop can
tell that they are hidden.

![The same bar twice: collapsed behind one mark, and fanned back out with the pointer on it](docs/bar-states.png)

<sup>The same bar a moment apart. Four widgets sit behind the three dots; the
pointer is what brings them back. Everything to the right of the mark stays
exactly where it was.</sup>

## Requirements

Omarchy 4.x with the Quickshell bar, and a Nerd Font set as the bar's font —
the mark is a Nerd Font glyph, and a bar without one draws an empty box where
it should be. No network access, no subprocesses.

Bar size and screen scaling are not things Pocket has an opinion about. It
hardcodes no pixel value anywhere, and the mark takes its slot from the same
`Style` token every other bar icon uses, so a larger bar font, a different
`size-horizontal`, or a fractional output scale move it exactly as they move
its neighbours. Checked across three outputs at scales 1.5, 1.667 and 2.4.

<details>
<summary>What it leans on inside the shell, for anyone deciding whether to trust it across updates</summary>

Pocket reaches for fifteen properties and functions on the bar object, plus
`shell.mutateShellConfig` on the shell that bar exposes. Exactly one of them,
`bar.urgent`, is documented as available to plugins; the rest are engine
internals, and it also imports the shell's own `qs.Commons` and `qs.Ui`
modules.

Every *property* it reads is guarded, so a renamed one makes a feature stop
applying rather than misbehave — the drop steering simply stops steering, and
the standing invariant still produces the correct layout. A renamed *module* is
the exception: that is a hard load failure with no graceful half.

Between Omarchy `4.0.0-beta3` and `4.0.1` the bar's API surface did not change
by a single symbol. That is the basis for the version claim above — a
measurement, not a promise from upstream, because upstream makes none.

</details>

## Install

```bash
omarchy plugin add https://github.com/jrmmhm/omarchy-pocket.git --enable
```

It will show you Omarchy's own warning that plugins run as unsandboxed code
inside your shell, ask you to confirm, and ask which section of the bar to put
it in. Add `--yes` to skip both prompts in a script. Then drag the widgets you
want it to hold onto it. That is the whole setup.

## Putting things in, taking them out

![Dragging a widget onto the mark puts it away; dragging it back out past the mark returns it](docs/pocket-drag.gif)

**Drop a widget on the mark and it goes in.** From either side, and from a
little beyond: what the pocket reads is the insertion line the bar is already
drawing, and that line belongs to the mark from the middle of one neighbour to
the middle of the other.

**Drag a member past the middle of the mark and it comes out.** Dropping it
anywhere outside the group takes it out as well. Move it around *inside* the
group and it just gets reordered. That boundary runs through the middle of the
mark: its two halves are the last gap inside the run and the first gap outside
it.

To reach a member you have to open the pocket first — a hidden widget is not on
the bar to be grabbed. Point at the mark, then drag.

The mark lights up while a release would change what the pocket holds, so you
get the answer before you let go rather than an explanation after. It lights in
the bar's alert colour while a widget is about to go *in*, and in the colour the
bar draws its own insertion line in while a member is about to come *out* —
opposite answers, different roles.

Whether you actually see two colours is up to your theme. The first is the
theme's alert colour, the second its accent, and a theme that gives both roles
the same value gives you one colour for both answers. That is the case in the
recording above. On the shipped **kanagawa** theme the accent equals the bar's
text colour, so the "coming out" state reads as not lit at all. Nothing a plugin
can fix from the inside — it is two theme roles, and the theme decides whether
they differ.

## Where to put it on the bar

**Put the pocket on the side of its members that faces the section's anchor.**
In the `right` section that means the members come *first* and the pocket last;
in `left`, the pocket first. Fanning out changes the section's width, and this
ordering is what keeps the mark itself from sliding out from under your pointer.

Pocket keeps that arrangement for you. While you drag a widget onto it, it tells
the bar which side the widget belongs on, so it lands there directly; and a
member that ends up on the wrong side anyway is put back against the pocket. A
widget already on the correct side is never moved.

The `members` list is kept in the order the widgets physically sit in, and
rewritten when the two disagree — that order is what the fan-out follows, so a
list that disagrees with the bar animates in a direction that is not there. If
you write `members` by hand in a different order, expect it back in layout
order. Ids Pocket could not parse are left exactly where you wrote them, and
while one of those is present it does not touch the order at all.

## Settings

Everything is written to this plugin's own entry in
`~/.config/omarchy/shell.json`, so it survives a restart, and you can still edit
it by hand:

```json
{ "id": "jrmmhm.pocket", "members": "omaplug, omarchy.tailscale, ianswope.snapshots" }
```

| Setting | Type | Default | What it does |
| :--- | :--- | :--- | :--- |
| `members` | string or array | `""` | Ids of the bar widgets to tuck away |

`members` also accepts a JSON array, which is the nicer shape by hand. Pocket
writes back whichever shape it finds, and never touches anything else on the
entry. The manifest declares the setting as a string because Omarchy's settings
form can only produce one; both shapes work when you edit the file yourself. The
file hot-reloads, so there is no restart after an edit.

The order you drag survives more than a restart. The run's physical order lives
in `bar.layout` and `members` mirrors it, both in that one file, written by the
host atomically — so a reboot is just a restart, and `omarchy plugin update`
pulls a new version and rebuilds the widgets without touching the file at all. A
member whose widget fails to load after an update keeps its place, because the
place is read from the file rather than from what is running.

## Why this one keeps your setup honest

![Other grouping widgets move the entry into plugins[], which keeps it reported as enabled while taking it off the bar. Pocket leaves it in bar.layout.](docs/pocket-layout.svg)

Every other way of grouping bar widgets moves them out of `bar.layout` — into
the top-level `plugins[]` array — and mounts them again somewhere else. Omarchy
decides a plugin is *enabled* by whether its id appears anywhere in
`shell.json`, a bar entry **or** a `plugins[]` entry, so the widget keeps
reporting as enabled. What it no longer is, is *on the bar*, and that split is
where things come apart:

- `omarchy-shell shell toggle <id>` and its keybinding stop working. The shell
  checks "is it enabled", passes, then asks the bar for the widget's slot — and
  there is none, because the bar never placed it. The failure is a line in a
  log, not an error you see.
- **Switching it off and on again builds it twice.** Toggling off deletes the
  `plugins[]` entry; toggling on puts it back as a `bar.layout` entry, and the
  grouping plugin still names it. Now it is mounted from both.
- Its settings leave `shell.json` for the grouping plugin's own file, which no
  Omarchy tool reads or writes.
- You maintain the same widget in two places, and the two can disagree.

**Pocket moves nothing out.** The widgets stay in `bar.layout`, in their own
module slots, built by the bar itself. Pocket flips `visible` on those slots,
and a Qt `Row` does not lay out an invisible child — so the space closes up and
nothing else in the shell notices. Every tool keeps telling the truth.

## The mark

A row of dots that turns upright as the pocket opens, over the same 600 ms
`OutCubic` the stock tray drawer uses, with the members fading out of it in a
cascade. Deliberately not a chevron: the tray sits in the same section doing a
visually similar thing, and two identical glyphs beside each other are two
things nobody can tell apart.

**Click the mark to pin it open**, click again to release. That is the way out
of the cases where no leave event is ever coming — a workspace switch that
teleports the cursor, an application grabbing the pointer.

The pin holds until you click it again or until the bar is rebuilt, and any
change to the layout rebuilds it: a drop, a member being put back on the right
side, enabling any plugin at all. It is never written to disk either, because
`shell.json` is shared by every bar surface and persisting it would make one
screen's transient state everyone's. Treat it as a pointer aid for the next few
seconds, not as a mode.

## Good to know

Three things change your first hour with it:

- **Keep members in the pocket's own section.** A member in `center` never
  hides. With `centerAnchor` set — which is the default — the bar builds every
  centre widget twice, once drawn and once as a hidden placeholder, and the
  placeholder is created first, so Pocket binds that one every time. A member in
  a different section than the pocket *is* hidden, but it fans out over there on
  its own, which looks like a bug rather than a choice. The tooltip names both
  cases. (Separately, a member may not be the `centerAnchor` itself — that is a
  different mechanism and Pocket refuses it outright.)
- **Dragging a widget next to a collapsed pocket puts it in the pocket.** The
  hidden group takes up no room, so the widget beside it stands against the mark
  and the bar draws its line there — which is the gesture for putting something
  away, whether or not you meant it that way. One drag back out undoes it. With
  the pocket *open* the members are back on the bar, so only the gap against the
  mark itself puts a widget in.
- **`SUPER+CTRL+1…9` renumbers.** Those bindings open "the Nth panel in the
  right section" and count only what is *drawn*, so a collapsed pocket shifts
  the numbering.

<details>
<summary><b>On more than one monitor</b></summary>

- **A pocket on another screen folds up late.** Omarchy counts bar hover once
  for the whole shell rather than once per screen, so while your pointer is on
  *any* monitor's bar, no pocket on any monitor folds. It only delays a fold —
  nothing opens by itself, and everything closes as soon as the pointer leaves
  the bar. The shared state is the host's own and predates any plugin: hover one
  screen's centre section and the inactive indicators appear on every screen.
  Reading it per screen is not available to a plugin.
- **On overlapping outputs, a left click on one screen's bar can land on another
  screen's pocket.** The bar hit-tests a click against the click targets of
  every monitor without asking which screen they belong to. That only reaches
  you where two outputs overlap in the compositor's layout — mirrored, or
  positioned by hand so their rectangles intersect — and where they do, it is
  every contested click rather than an occasional one. On monitors side by side
  it was measured not to happen at all. What was measured, and the one condition
  that triggers it, are in
  [decision 0007](docs/decisions/0007-the-two-host-limits-measured.md).
- **Switching monitor profiles makes the members flash.** A surface that is
  being moved loses its window for about 50 ms, and a pocket that cannot tell
  which screen it is on drives no slots at all — so it hands them back visible
  and takes them again when the window returns. It happens on a surface that is
  unmapped, so what is left is at most a single frame as it comes back.
- **`SUPER+CTRL+1…9` additionally depends on where your pointer is.** The count
  is taken from whichever bar surface answers first, which assumes every monitor
  draws the same widgets, and a pocket is what breaks that. Counting only what
  is drawn is deliberate and documented upstream; this half is not. See
  [decision 0007](docs/decisions/0007-the-two-host-limits-measured.md).

</details>

<details>
<summary><b>While dragging</b></summary>

- **A drag cancelled from outside cannot be told from a drop.** Qt emits
  `canceled` *instead of* `released` with nothing to distinguish them, so if
  something steals the pointer while the mark is lit, the widget joins the
  pocket without you having dropped it. If it was on the far side of the mark
  when that happened, the placement rule then moves it across to join the run;
  if it was already on the members' side, it stays where it is. One drag undoes
  either.
- **In the `left` section, dropping a widget in from the far side takes about
  twice as long.** Any widget reorder makes Omarchy rebuild every widget on
  every monitor, and putting a far-side arrival back where it belongs costs a
  second rebuild. Everywhere else one rebuild is all it costs. The measurements
  are in
  [decision 0002](docs/decisions/0002-members-belong-on-one-side.md), the reason
  `left` is the exception in
  [decision 0003](docs/decisions/0003-steering-the-bar-s-own-drop-marker.md).
- **Dragging the pocket itself** does not take its members along; they stay
  where they were.

</details>

<details>
<summary><b>Limits worth knowing before you fill it up</b></summary>

- **A pocket full of widgets can reach the clock.** The bar's three sections are
  anchored independently and nothing clips them, so a run of ten fanning out to
  the left will draw over the centre section on a narrow screen rather than push
  it aside. How many fit is your screen's business; Pocket does not change it,
  it only decides when they are asked for.
- **`omarchy.tray` is a poor member.** Omarchy pins it to its section's inner
  edge on every config load, and its own drawer assumes it sits there.
- **A disable/enable round-trip loses placement.** Re-enabling a bar widget
  rewrites its entry as a bare `{ "id": ... }` at the widget's default spot.
  Done to a *member* it takes that widget's place in the run, and Pocket then
  records it at the end of the list where the bar left it. Done to the pocket it
  takes `members` with it, for the reason [Remove](#remove) explains.
- **A member cannot be the `centerAnchor`.** That one slot carries a `visible`
  binding of the bar's own, and writing it would destroy the binding for the
  rest of the session. Pocket refuses it — the mark will not light up for it.
- **One pocket per bar.** A second entry added by hand is detected and reported
  in the tooltip; while one exists, Pocket refuses to write anything at all.
- **An unusable id is shown escaped.** The tooltip is rendered by the bar, not
  by Pocket, in an item that decides for itself whether to read the text as
  markup — so anything Pocket did not write is passed through with `<`, `>`, `&`
  and every invisible character spelled out as `\uXXXX`, kept to one line, and
  shortened past 160 characters. A long list of them is named as far as it fits
  and counted after that. What you typed is still what is stored; only the
  display is escaped.
- **The tooltip is a snapshot.** The bar reads a widget's tooltip once, when the
  pointer arrives, and does not update it while the pointer stays. So the lines
  that describe a state your pointer just caused — "Pocket open", "Pinned" —
  appear the *next* time you point at the mark, not the moment they become true.

</details>

<details>
<summary><b>On a vertical bar</b></summary>

Pocket works on a bar docked to the left or right edge, with two rough edges it
does not smooth over:

- The mark's dots start upright and turn flat as the pocket opens — the reverse
  of a horizontal bar, because the glyph is rotated to run along the bar in the
  first place.
- The members grow out of their left or right edge rather than the edge facing
  the mark, so the fan-out reads sideways instead of along the run. It is
  cosmetic; nothing moves anywhere it should not.
- `left` and `right` in the settings mean *top* and *bottom* on a vertical bar.
  The rule in [Where to put it](#where-to-put-it-on-the-bar) still holds, read
  that way.

</details>

The tooltip is where all of this surfaces at runtime — it names every member it
could not find, could not use, or would not touch.

## Remove

```bash
omarchy plugin remove jrmmhm.pocket
```

Every hidden widget comes back. The hidden state is never written anywhere, so
removing Pocket, disabling it, hot-reloading it or killing the shell all have
the same effect: the slots are rebuilt visible and nothing stays lost.

What does not come back is the `members` list. Removing a plugin disables it
first, and disabling a bar widget deletes its layout entry — and `members` lives
on that entry. Copy the line out of `~/.config/omarchy/shell.json` first if you
plan to come back.

## Development

```bash
bash tests/run.sh                    # ALL TESTS PASSED (N assertions, 0 failures)
qmlformat BarWidget.qml > /dev/null  # parses, or exits 1
```

`Model.js` holds everything decidable without a running shell and is unit-tested
with `node`; `BarWidget.qml` keeps only what needs live objects. Most of that
second half needs a real bar and is covered by using it, but two pieces of it
are not: `tests/qml/` loads `BarWidget.qml` in Quickshell against an object that
is not a bar, and pins the drop steering — which fails silently in both
directions it can fail — and the membership a drag is decided against. It runs
as part of `tests/run.sh` and skips itself where Quickshell or an Omarchy shell
is absent, which is every CI runner.

Note that the shell's plugin file-watcher does not follow symlinks, so if you
develop against a symlinked checkout, apply changes with `omarchy restart shell`.

Design decisions live in [`docs/decisions/`](docs/decisions/). How the figures
and recordings in this README were made, and on what, is in
[`docs/media.md`](docs/media.md).

## License

[MIT](LICENSE)
