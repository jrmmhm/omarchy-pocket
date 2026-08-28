# 10. The publication review changes documentation, not code

- Status: accepted
- Date: 2026-08-28
- Corrects the `plugins[]` consequences claimed by the README since 0.1.0
- Records three deliberate non-fixes, so that none of them is a silent one

## Context

Before publishing, the plugin was reviewed end to end against the host it runs
on — `Bar.qml`, `shell.qml`, `services/PluginRegistry.qml`, `Ui/WidgetButton.qml`
and `Commons/Color.qml` of the Omarchy package named in
[`media.md`](../media.md) — and against a live three-monitor session at three
different output scales (1.5, 1.667, 2.4).

Everything the review found was either a documentation defect or a behaviour the
owner chose to leave alone. **No QML or JS changed.** That is the decision this
file records, because three of those choices are the kind that read as bugs to
the next person who finds them, and a non-fix that nobody wrote down is
indistinguishable from an oversight.

## What was wrong, and is now corrected in the README

**The central claim about `plugins[]` was false.** The README stated that moving
a widget into the top-level `plugins[]` array makes `omarchy plugin list` and
plugin managers report it as **off**. `PluginRegistry.isEnabled()` resolves
through `findEntryLocation()`, which searches `bar.layout` *and* `plugins[]`, so
such a widget reports **enabled**. Measured on the reporter's own machine:
`omarchy-overview` sits in `plugins[]` and `omarchy plugin list` prints
`enabled`. `ianswope.stack`'s own README documents the same rule and relies on
it deliberately.

The conclusion the paragraph was drawing survives, and is stronger stated
truthfully — the widget is reported enabled while not being on the bar, and that
split is the defect:

- `shell.qml::summon()` passes the enabled check and then asks
  `Bar.qml::findPanelWidget()` for a slot that was never created, so
  `omarchy-shell shell toggle <id>` fails into a log line.
- `setEnabled()` deletes a `plugins[]` entry when switching off and inserts a
  `bar.layout` entry when switching on, so an off/on round trip leaves the
  widget mounted from both places. The README's old "the manager's toggle can
  double-mount it" was right, and this is the path.
- The widget's settings move to the grouping plugin's own file, which
  `updateEntryInline()` and the settings form never look at. Read out of
  `ianswope/omarchy-stack` at its published `0.1.0`: its `Panel.qml` mounts each
  held widget itself and injects `entry.settings` from `~/.config/omarchy/
  stacks.json`, and its README instructs the reader to move the folded widgets
  into `plugins[]` — the same mechanism this file describes, documented by the
  plugin that uses it.

**The two drop colours can be one colour.** `activeColor` picks `Color.accent`
for a member leaving and `bar.urgent` for a widget arriving. `bar.urgent` is
`Color.bar.active`, generated from the theme's red by
`default/themed/shell.toml.tpl`; `Color.accent` is the theme's accent. On
`solace-sunset` both are `#eb5864` — measured off a capture of a real drag, both
gestures lighting the same colour. On the shipped `kanagawa` theme
`accent == foreground`, so the leaving state is indistinguishable from unlit.
The CHANGELOG's "two opposite answers cannot be mistaken for each other" was a
claim about the code that the themes do not honour, and the README now says so.

**A member in `center` fails deterministically, not occasionally.** With
`centerAnchor` set — the shipped default is `omarchy.clock` — `CenterModules`
declares the hidden placeholder `ModuleList` *before* the three drawn ones.
Slots register in creation order and `resolution` breaks at its first match, so
the placeholder is always the one bound. The README said "may bind the
placeholder"; it does, every time.

## The three non-fixes

**A vertical bar keeps its rough edges.** `growthOrigin` returns
`Item.Right`/`Item.Left` unconditionally, while `Bar.qml` lays a vertical
section out as a `Column` — so the members grow sideways instead of along the
run. `textRotation` adds the bar's own 90° before the reveal's, so the mark's
dots start upright and turn flat, the reverse of a horizontal bar. Both are
cosmetic and both are one line away from a fix. The owner's call was to leave
the code alone; the answer is therefore a README section that says exactly what
a side-docked bar looks like, because a documented rough edge is a choice and an
undocumented one is a bug report on day one.

**The tooltip stays a snapshot.** `Ui/WidgetButton.qml` calls `bar.showTooltip`
only from `onEntered`, and `triggerPress()` hides the tooltip before it emits
`pressed` — so `Model.describe()`'s "Pocket open" and "Pinned" lines never
appear on the hover or the click that causes them. They are not dead: the next
`onEntered` reads the new state. Fixing it means calling `bar.showTooltip` again
whenever the text changes, which is a plugin re-driving a host mechanism it does
not own, for two lines that are one pointer movement away from correct. Recorded
instead, in the README's own list of limits.

**`bar.shell.mutateShellConfig` stays.** Omarchy's bar-widget contract test
(`test/shell.d/bar-widget-contract-test.sh`) mocks `updateEntryInline` and not
`mutateShellConfig`, which makes `updateEntryInline` the sanctioned way for a
widget to write its own settings back. It is still the wrong tool here, for two
independent reasons. It rebuilds the entry as `{ id }` plus whatever it is
handed and drops every other key, which breaks 0001's promise that Pocket never
touches anything else on its entry; and it edits entries in place with no way to
express a move, which is exactly what the placement repair does. `Bar.qml`
itself reaches for `mutateShellConfig` in three places for the same purpose.
0001 stands.

## Consequences

**The README grew a "Good to know" section, and shrank.** Three entries sit in
the running text because they change the first hour — a member in `center`, a
widget dragged in beside a collapsed pocket, and `SUPER+CTRL+1…9` — and the rest
fold into four themed `<details>` blocks. Honesty was never the thing to trade
away; the wall was. The README owns how many there are; no other file states a
count, because a count in two places is a count that drifts.

**Two drawings were retired in favour of two recordings.** `pocket-states.svg`
and `pocket-drag.svg` both described things a capture shows better, and both had
drawn the mark's dots the wrong way round since they were made: `U+F01D8` is
`md-dots_horizontal` and `textRotation` adds 90° as the pocket opens, so
collapsed is `•••` and open is `⋮`, and the figures had it inverted. A drawing
of a live surface invents that class of error; a capture cannot.
`pocket-layout.svg` stays, because a configuration file is the one thing here
that cannot be photographed.

**One edge condition came back clean, and is written down for that reason.** A
changed bar size or output scale moves nothing that Pocket decides: there is no
pixel literal anywhere in `BarWidget.qml`, the mark's slot comes from
`Style.bar.iconSlot` like every other bar icon's, and the mark was seen
rendering identically on outputs at scales 1.5, 1.667 and 2.4. A check that
found nothing is indistinguishable from a check that was never made unless its
result is recorded, so the README states it.

**The recordings are perishable and say so.** `docs/media.md` records the
output, scale, theme, bar size, font, region and encoder settings they were made
with, because none of it is recoverable from the files afterwards.

**One thing the review could not automate.** A drag driven by a virtual `uinput`
button plus compositor cursor warps starts a real bar drag and completes a real
drop, but the grab does not survive the pointer coming to rest — so it records
the cancelled drag this plugin documents rather than the drop it was aiming for.
Across 111 frames of such a take the mark never lit; a human take lit it for
2.2 s going in and 2.0 s coming out. The drag recording in the README is a human
gesture, and `shell.json` was byte-identical before and after it.
