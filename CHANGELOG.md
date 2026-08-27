# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

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

[Unreleased]: https://github.com/jrmmhm/omarchy-pocket/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/jrmmhm/omarchy-pocket/releases/tag/v0.2.0
[0.1.0]: https://github.com/jrmmhm/omarchy-pocket/releases/tag/v0.1.0
