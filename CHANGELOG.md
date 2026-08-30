# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.2] — 2026-08-30

A full audit of the published plugin against the shell it runs in, and of every
claim its README and marketplace entry make against what the code does. All of
it is in
[decision 0012](docs/decisions/0012-the-audit-of-the-published-plugin.md), which
owns the measurements.

### Fixed

- **A member could be missing from the bar with nothing to say so.** A widget id
  is a name, and a few names — `toString`, `constructor`, `valueOf` and four
  more — are answered by any JavaScript object before anything is put in it.
  Pocket kept its duplicate check on such an object, so a member with one of
  those ids was dropped as a duplicate it had never been, and dropped early
  enough that the tooltip did not mention it either.
- **The same cause rewrote your `shell.json` and never settled.** With such an
  id present, the member list could not be put into layout order at all: the
  comparison it rests on produced no answer, and in Qt's engine — the one the
  bar runs — the result had no stable form. Pocket concluded the list was out of
  order for ever and rewrote it into a different wrong order on every bar
  rebuild. The two engines this code runs in disagree here, which is why the
  test suite now runs these cases in both; two of them are green on the broken
  code in the test engine alone.
- **A `members` entry Pocket could not read at all vanished before anything
  could name it.** A list of four such entries left the tooltip reporting an
  empty pocket. They are now named by their position, which is what finds them
  again in the file.
- **A renamed `bar.moduleSlots` broke the widget instead of stopping it.** That
  was the one property of the fifteen it reads that was guarded against a
  missing bar and not against a missing property, and the tooltip — the surface
  that exists to explain a pocket that cannot work — was among the things that
  stopped working. `bar.urgent` had the same gap and is guarded too, so the
  README's promise now holds for all fifteen.

### Performance

- **The tooltip no longer escapes what it is about to throw away.** The line has
  always been capped; the work behind it was not, and one oversized entry in
  `members` cost 111 ms every time the pointer arrived. It now stops at the cap
  and produces the identical string.

### Documentation

- **The marketplace description contradicted itself.** It said Pocket tucks the
  widgets "into one slot" one sentence before saying they never leave the bar
  layout — and keeping their own slots is the entire argument for this plugin
  over the alternatives.
- **`SUPER+CTRL+1…9` does not renumber for every member.** The count skips
  anything without a panel of its own, so tucking away the tray, the workspaces,
  the indicators or the keyboard layout changes it by nothing. Both the README
  and decision 0007 claimed otherwise, and 0007 also carried a mechanism for the
  multi-monitor half that measurement disproves: a widget counts while *any*
  screen still draws it.
- Two further sentences the code contradicted: the mark is lit while the pocket
  is pinned as well as during a drag, and a drag reorders `members` even while
  an unparseable id is present.

## [0.3.1] — 2026-08-29

### Fixed

- **A mistyped `members` entry could forge a tooltip line.** A value carrying a
  line break grew a line of its own, and the line it grew could read exactly
  like one of Pocket's own warnings — `A second Pocket entry exists` appeared on
  a bar that has only one. Every value the tooltip names is now escaped, so it
  occupies the one line it was given.
- **A mistyped `members` entry could make the tooltip wider than the screen.**
  The bar's tooltip label does not wrap and the popup window is sized from it,
  so a long enough list of unusable entries asked for a surface wider than any
  display. The line now names what fits and counts the rest; the measurements
  are in decision 0011.
- **The tooltip did not guarantee how it would be rendered.** It is handed to a
  `Text` the host owns, which sets no `textFormat` and therefore decides per
  string whether to parse it as markup — and a positive answer there parses
  `<img src=…>` and fetches it. On 0.3.0 the answer was always plain, because
  Qt's heuristic stops at the first line break and the first line is always
  Pocket's own; that was an accident of two properties nothing asserted, and it
  is now a property of the code with tests to match. This closes the finding the
  Omarchy marketplace review raised against 0.3.0. It is not a privilege
  boundary: anyone who can edit this plugin's layout entry can already run
  arbitrary QML from the same entry, and the CHANGELOG does not claim otherwise.
  See [decision 0011](docs/decisions/0011-the-tooltip-escapes-because-it-does-not-own-its-sink.md).

## [0.3.0] — 2026-08-28

### Documentation

- The README is rewritten for someone who has never heard of a bar widget. It
  opens on a recording of the pocket opening and folding, says what the thing
  is in three paragraphs of plain language, and follows the order every
  neighbouring Omarchy plugin uses. It gained the two sections a published
  plugin needs and did not have: how to remove it, and what it actually
  requires — a Nerd Font among other things, since the mark is a glyph.
- **The README's central claim about competing grouping widgets was wrong.** It
  said that moving a widget into the top-level `plugins[]` array makes Omarchy
  report it as *off*. Omarchy reports it as *on*: `isEnabled()` searches
  `bar.layout` and `plugins[]` alike. The split it really produces is worse and
  is now described accurately — the widget is reported enabled while not being
  on the bar, so its keybinding fails into a log line, an off/on round trip
  mounts it twice, and its settings move to a file no Omarchy tool reads. See
  [decision 0010](docs/decisions/0010-the-publication-review-changes-documentation-not-code.md).
- The two hand-drawn figures of the bar are replaced by recordings of a real
  one, and the third is redrawn. Both drawings had the mark's dots inverted
  since they were made — `U+F01D8` is `md-dots_horizontal` and the glyph turns
  90° as the pocket opens, so collapsed is `•••` and open is `⋮`.
  `pocket-layout.svg` stays, because a config file cannot be photographed; it is
  redrawn with a light-mode variant built in. `docs/media.md` records the
  output, scale, theme, region and encoder settings the captures were made with.
- Eight limits that were real and unwritten are now written: a full pocket can
  draw over the centre clock, the pin does not survive a bar rebuild, a member
  in the `center` section fails every time rather than sometimes, a member in
  another section is hidden as well as warned about, a monitor-profile switch
  makes the members flash, the tooltip is a snapshot taken when the pointer
  arrives, a vertical bar rotates the mark the other way and fans out sideways,
  and a cancelled drag moves the widget only when it was on the far side.
- The whole list of limits would be a wall, so the three that change the first
  hour stay in the running text and the rest fold into themed `<details>`
  blocks.

### Fixed

- A member dragged out of the pocket comes out and stays out. On a bar with more
  than one screen it went straight back in: the removal was written correctly,
  and a few milliseconds later the same gesture added it again. A members-only
  write is an inline settings change, so the host hands the new list to every
  pocket on every screen at once — in the middle of the one assignment that ends
  the drag, and therefore before the pocket the drag was aimed at has finished
  deciding. That pocket then saw a widget that was no longer a member sitting on
  its own mark, which is what asking to be taken *in* looks like. A drag is now
  decided against the member list as it stood when the drag began, so what the
  pocket writes cannot change the answer it is still giving. Both recordings, the
  race read out of the host, and the one thing still open are in
  [decision 0009](docs/decisions/0009-a-drag-decides-against-the-membership-it-started-with.md),
  which closes the case decision 0008 left open.

- The near half of the mark takes a widget in, which it never did. Module slots
  sit flush against one another, so the gap at that edge is exactly as far from
  the pocket as from the widget drawn before it, and the bar resolves the tie in
  favour of whichever it built first — always the neighbour. The pocket asked
  whether the bar had named its own slot, so half the icon answered nothing at
  all, and the README's "from either side" was untrue for it. It now recognises
  both names of that one gap. The drop steering keeps the narrower question and
  refuses where the bar named the neighbour: steering there would have placed
  the widget outside the run while the bar drew its line at the mark — on one
  monitor, not just across several. Measured across the whole neighbourhood in
  [decision 0008](docs/decisions/0008-the-mark-answers-on-both-of-its-edges.md).
- The mark no longer lights up for a drop it would then refuse. A bar carrying a
  second Pocket entry writes nothing at all, which the light did not know.

- The bar's drop marker is no longer read through a property of Pocket's own,
  which the QML engine reported as a binding loop on every pointer move of a
  drag it was steering. What the steering does is unchanged — a change to either
  of the bar's two marker values still re-asserts both — and it now also undoes
  the first of those two writes when the second is refused, so the side a widget
  lands on and the line the bar draws can no longer come apart. See
  [decision 0006](docs/decisions/0006-the-drop-steering-listens-it-does-not-sample.md),
  which also corrects what decision 0005 said about how often this happened.

- On more than one monitor, dragging a widget into the pocket, out of it, or
  around inside it no longer leaves the pocket on another screen fanned out.
  A pocket filtered the bar's shared slot list to its own window only while it
  knew which window that was — and when it did not, it skipped the comparison
  and matched every screen. It then adopted another screen's widgets and handed
  them back visible as it died, while the pocket that owns them had already
  finished and had no reason to look again. The comparison is now unconditional:
  an instance that does not know its own window owns no slot at all. Both ways
  a window goes missing, and what each costs, are in
  [decision 0005](docs/decisions/0005-a-pocket-drives-only-its-own-screens-slots.md).
- The tooltip no longer reports members as "not on this bar" when the pocket has
  not been able to look at the bar. It says which state it is in instead.

- Reordering a widget *inside* the pocket no longer throws it out. It was
  dropped from `members` while the bar left it sitting among the remaining
  members — neither in the pocket nor out of it — and dropped exactly where it
  already sat, nothing on screen changed at all. On a bar with more than one
  monitor this happened at every position inside the group, because the pocket
  on the screen the drag was not on read every member as a stranger; on a
  single monitor it happened at the group's outer edge, on a sub-pixel tie in
  which of the two adjacent slots the bar reported. Membership is now decided
  from the gap the insertion line is drawn in, which is the same on every
  screen and on both sides. See
  [decision 0004](docs/decisions/0004-membership-is-decided-from-the-gap-not-the-slot.md).
- The member list is kept in the order the widgets physically sit in even when
  the pocket writes nothing itself, so the reveal cascade always runs in the
  direction they are actually in. This also closes the `left`-section case
  [decision 0003](docs/decisions/0003-steering-the-bar-s-own-drop-marker.md)
  recorded as open.

### Changed

- The mark answers both directions of the gesture. It lights while a release
  would take a widget in, as before, and now also while a release would let a
  member go — in the colour the bar draws its own insertion line in. Whether
  that reads as two colours is up to the theme, and this entry originally
  claimed more than the code can deliver: the two states take the bar's alert
  role and the theme's accent, and a theme that gives both the same value gives
  one colour for both answers. Measured off a real drag on `solace-sunset`,
  where they are both `#eb5864`; on the shipped `kanagawa` theme the accent
  equals the bar's text colour, so the leaving state reads as unlit.
  [Decision 0010](docs/decisions/0010-the-publication-review-changes-documentation-not-code.md)
  has both measurements. Where a member leaves and
  where it is merely reordered is unchanged: that boundary runs through the
  middle of the icon, where the last gap inside the run meets the first gap
  outside it, and the mark is now what says which of the two you are on.
  [Decision 0008](docs/decisions/0008-the-mark-answers-on-both-of-its-edges.md)
  has the measurement and the two README promises it sits between.
- Dropping a widget onto the pocket from the far side now costs one bar rebuild
  instead of two. While the drag is running, Pocket tells the bar which side of
  the mark the widget belongs on, so the bar places it there in the first place
  and the placement invariant has nothing to repair. The invariant is unchanged
  and still guarantees the result: every host access is optional, so a future
  Omarchy that renames those properties makes the override stop applying rather
  than misbehave. The `left` section keeps the old cost — the side it would need
  is the one the bar resolves past hidden modules, which a collapsed pocket's
  members are. Measured in
  [decision 0002](docs/decisions/0002-members-belong-on-one-side.md), decided in
  [decision 0003](docs/decisions/0003-steering-the-bar-s-own-drop-marker.md).
- The README now names two host limits that look like Pocket bugs and are not:
  a pocket on another screen folds up late, because Omarchy counts bar hover
  once for the whole shell; and on outputs that overlap in the compositor's
  layout, a left click on one screen's bar can land on another screen's pocket,
  because the bar hit-tests clicks against every monitor's targets without
  asking which screen they belong to. Each says why a plugin cannot filter it
  out from the inside. Both have since been measured, and the second one no
  longer carries the cause it was first given — see
  [decision 0007](docs/decisions/0007-the-two-host-limits-measured.md), which
  also settles that no upstream issue tracks the `SUPER+CTRL+1…9` caveat, and
  that the one the README used to cite never did.
- The README now says what the dragged order survives — a restart, a reboot, an
  `omarchy plugin update`, a member whose widget fails to load — and the known
  way to lose it.
- `bash tests/run.sh` now also loads `BarWidget.qml` in Quickshell against a
  fake bar, which is the only way to cover the drop steering's wiring to the
  host at all. It skips itself where Quickshell or an Omarchy shell is absent,
  so CI is unaffected.

## [0.2.0] — 2026-08-27

### Added

- Membership is a drag gesture. Dropping a widget onto the mark puts it away
  from either side; dragging a member past the mark takes it back out. The mark
  lights up while a release would collect it, so the answer is given before the
  drop rather than explained after it. The decision reads the bar's own drop
  target, so what Pocket does and what the bar's insertion line shows cannot
  disagree.
- Members are kept on the side of the pocket they fan out towards. One that
  ends up on the wrong side — dropped in from the far side, or moved there by
  hand — is put back against the pocket. Members already on the correct side
  are never reordered.
- The member list is kept in layout order, so the reveal cascade always runs in
  the direction the widgets physically sit.

### Fixed

- The tooltip no longer claims a second Pocket entry exists on multi-monitor
  setups. It counted mounted instances, and the bar is built once per monitor —
  plus a second time for every center widget when `centerAnchor` is set.
  Measured on a three-monitor session, where one entry reported as three.

### Changed

- Pocket now writes to `shell.json`: its own entry, its own `members` key, and
  the position of a member that ended up on the wrong side of it. Always
  through the host's own config mutator, which writes atomically. Ids the
  parser rejects are preserved rather than deleted by an unrelated drag, and
  the shape found on disk — comma string or array — is the shape written back.
  See [`docs/decisions/0001`](docs/decisions/0001-pocket-writes-its-own-members.md)
  and [`0002`](docs/decisions/0002-members-belong-on-one-side.md).
- The README's claim that Pocket writes no files was accurate for 0.1.0 and is
  no longer true; the reasoning that called writing `shell.json` unsafe was
  wrong even then, since the host writes it atomically.

## [0.1.0] — 2026-08-26

### Added

- First release. Hides the bar widgets named in `members` behind one mark and
  reveals them on hover, without moving any of them out of `bar.layout`.
- Click the mark to pin it open for the session.
- A tooltip that names every member it could not find, could not use, or would
  not touch.

[Unreleased]: https://github.com/jrmmhm/omarchy-pocket/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/jrmmhm/omarchy-pocket/releases/tag/v0.3.1
[0.3.0]: https://github.com/jrmmhm/omarchy-pocket/releases/tag/v0.3.0
[0.2.0]: https://github.com/jrmmhm/omarchy-pocket/releases/tag/v0.2.0
[0.1.0]: https://github.com/jrmmhm/omarchy-pocket/releases/tag/v0.1.0
