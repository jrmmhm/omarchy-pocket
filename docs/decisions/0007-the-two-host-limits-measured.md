# 7. The two host limits, measured

- Status: accepted
- Date: 2026-08-27
- Corrects the `moduleClickTargetAt` paragraph of [0005](0005-a-pocket-drives-only-its-own-screens-slots.md)

## Context

0005 closed with two neighbouring defects found in the host while looking at
something else, and deliberately left alone: the fold-up timer waits on a bar
hover flag that is one counter for the whole shell, and `Bar.qml`'s
`moduleClickTargetAt` hit-tests a click against the click targets of every
monitor without asking which surface they belong to.

Both were written from reading source. Both have now been measured. One is what
it was said to be. The other is a real defect with a trigger that the reading
got wrong, and the reading's wrongness had already been copied into the README
and the changelog.

Everything below was measured on this machine: Omarchy 4.0.0.alpha, Quickshell
0.3.1, Qt 6.11.2, Hyprland 0.56.2, with three outputs in logical coordinates —
eDP-1 at x=0 (1152×720), HDMI-A-1 at x=1152 (1600×900), DP-2 at x=2752
(1280×720). The installed `Bar.qml` is byte-identical to upstream tag `v4.0.1`,
and to the `quattro` branch as it stood on this date, so none of this is a local
artefact. The tag is the durable half of that claim; the branch has moved on.

The harnesses live outside this repository, under the session scratchpad as
`harness/e1` … `harness/e9`. Each loads the host's own functions verbatim —
copied out of a read-only scratch copy of `/usr/share/omarchy/shell`, never
retyped — and feeds them fake targets. The installed shell was not modified;
`pacman -Qkk omarchy` reports 1654 files, 0 altered.

### The click routing: right about the defect, wrong about the cause

0005 said the round trip through global coordinates goes through coordinates
"which Wayland does not give a client, so both bar surfaces report their origin
as the screen corner and are tested as though stacked on top of each other."

The provenance in that paragraph is correct and survives. The cross-window
branch of `QQuickItem::mapToItem` did arrive in Qt 6.8.0 (`qtdeclarative`
commit `06ace3e226b2`), and it was guarded against a null window in 6.8.1
(QTBUG-129500). Before 6.8 the two scenes were composed as if they shared an
origin.

The conclusion does not survive. `QWaylandWindow::fixedToplevelPositions` is
`true`, and `QWaylandWindow::setGeometry` therefore moves every non-popup
toplevel to `screen()->geometry().topLeft()`. A Wayland client is not told
where its window is, so Qt tells it: the origin of the output it is on. Those
origins are real and distinct.

- **e2** — three real `PanelWindow`s, one per output, each holding a mark at
  local x=100. `mark.mapToGlobal(0, 0)` returned 100, 1252 and 2852: the
  screen's origin plus the local offset, every time. Cross-window `mapToItem`
  between two marks returned the true inter-output distance — 1152, 1600, 2752 —
  and never 0.
- **e3** — the host's verbatim `moduleClickTargetAt`, `moduleTargetClickable`,
  `targetWindow` and `targetBelongsToWindow`, driven against three bar-shaped
  layer surfaces carrying the running shell's real right-section geometry. A
  click at the centre of every widget on every surface: **27 clicks, 27
  same-screen hits, 0 cross-screen hits.** Adding the window filter changed
  nothing — 27 and 0 before, 27 and 0 after.

So on the layout that reported the original symptom, this defect does not fire
at all, and the fix for it is a no-op.

It fires when two surfaces share an origin:

- **e5** — the same verbatim function, two bar surfaces on one screen, identical
  layouts, which is what two mirrored outputs produce. **18 clicks, 9 of them
  cross-surface** — every single click on the losing surface, not
  intermittently. With the window filter: 18 same-surface, 0 cross.
- **e4** — the same, with mismatched layouts: 4 of 18 cross, and the widget that
  answered was not the counterpart of the one clicked but whichever widget
  covered the same point.

Which surface loses is registration order. `registerClickTarget` appends, and
`moduleClickTargetAt` scans backwards and returns the first hit, so the surface
that registered **last** wins every contested click — which e5 shows directly:
surfaceB registered first and every one of the nine cross-surface resolutions
went to surfaceA. `WidgetButton.syncClickRegistration` appends in creation order
across windows, so this is stable within a session and arbitrary between
sessions.

Two measurements pin the condition down further, and both narrow it to the
outputs alone:

- **e8** — shifting a surface 1000 px along its screen left the result identical
  to e5. A margin does not move what Qt believes the window's origin to be.
- **e9** — a surface anchored to the *bottom* of its screen reported its mark at
  global y=0, exactly like a top-anchored one, though its real bottom edge sat
  at y=694. `mapToItem` between a top-anchored and a bottom-anchored surface
  returned (0, 0).

The bar's position, its margins and its anchoring are therefore all irrelevant.
Each surface is tested as though it sat at its output's top-left corner with the
bar's own size. Since a horizontal bar is as wide as its screen, the hit test's
two inequalities reduce to: **the outputs overlap in the compositor's global
layout, and their origins are less than one bar height apart vertically.**
Mirroring is the common way to arrange that; two outputs positioned by hand so
their rectangles intersect is the other. Monitors placed side by side or stacked
clear of each other never satisfy it.

One caveat keeps that from being absolute. The pinning is applied in
`setGeometry`, and a window that has not been configured yet has not been
through it — `QWaylandWindow::initWindow` calls `setGeometry_helper` directly.
0005 records the two ways a bar surface loses and regains its window, including
the ~50 ms pulse `Ui/ScreenMoveRemap.qml` produces on every monitor move. During
such a pulse the stacked-origin reading is momentarily the right one. Nothing
was measured there; it is named because "side by side is safe" is a
steady-state statement, not a permanent one.

Finally, the path is narrower than "a click": `ModuleSlot`'s `modulePointer`
declares `acceptedButtons: Qt.LeftButton`, so right and middle clicks reach the
widget's own `MouseArea` and never pass through `moduleClickTargetAt`.

### The bar hover: as recorded

`barHoverCount` is one integer on the bar root, and every surface's
`HoverHandler` reports into it through `setBarHovered`; `barHovered` is
`barHoverCount > 0`.

- **e7** — three real per-screen layer surfaces running the host's verbatim
  `setBarHovered`, `barHoverCount` and `barHovered`, plus a per-surface tally
  for comparison. With the pointer on HDMI-A-1's surface and nowhere else, the
  shell-wide flag read `barHovered=true` while eDP-1's and DP-2's own surfaces
  both reported not-hovered.

The host shows the same confusion in its own centre section, with no plugin
involved, through a second shell-wide property. `centerSectionRevealHeld` is
also a single root property, and `widgets/Indicators.qml` binds
`revealInactiveIndicators` to it.

- **live, on the running shell** — with the pointer resting on eDP-1's centre
  section, `omarchy-shell shell debugBarGeometry` reported the
  `omarchy.indicators` widget at 126 px on **all three** outputs, against 21 px
  with the pointer off every bar. Hovering one screen's bar reveals the other
  screens' indicators.

The two are separate properties and separate evidence — e7 is the hover counter,
the live reading is the reveal — and they meet only in the collapse timer, whose
condition is `!centerSectionHovered && !barHovered`. That is the whole of the
delayed fold: the reveal cannot be released while any surface reports hover.

Note what the counter is not. Its comment says a pointer crossing from one
monitor's bar to another's must stay counted however the enter and leave
interleave, and a shared bool would be left false by whichever event landed
last. That reasoning is sound and the counter is right. What was never decided
is that everything *derived* from it should be shell-wide too.

## Options

**A — Work around either limit inside Pocket.** Rejected, and the reasons differ.

For the click routing, a widget is handed `triggerPress(button)` and nothing
else: no coordinates, no slot, no window. `Ui/WidgetButton.qml` passes only the
button through, and `Bar.qml` calls it the same way. The window helpers on the
bar — `targetBelongsToWindow`, `slotWindow`, `sameWindow` — all need a target
the receiver does not have. Refusing a press that arrives without a hover is the
obvious guard and is wrong twice: `KeyboardPanel` forwards bar clicks through
`triggerPress` while a panel's input mask makes hover impossible, which is
exactly the case the pin exists for; and the host resolves one target and does
not try a second, so the guard would turn a wrong action into a dead click
without delivering the press to the pocket that was aimed at.

For the hover, no per-screen signal exists to read. The host offers only the
shell-wide `barHovered`. Quickshell's Hyprland module exposes `focusedMonitor`,
`monitors`, `monitorFor` and the event socket — no pointer position, and window
focus is not hover. The only per-surface signal is which module slot the pointer
is on, which does not cover the empty runs between the sections, where the fold
has to keep waiting.

**B — Narrow the fold guard to "the pointer is on one of my own slots".**
Rejected in 0005 and still rejected: it reopens the oscillation the timer's own
comment describes, and breaks the parity with Omarchy's centre-section reveal
that the README claims.

**C — Report both upstream, change nothing here, and say in the README what was
measured.** Chosen.

## Decision

**Both limits stay host limits. Pocket changes nothing, and the README states
the measured condition rather than a mechanism.**

0005 said of the click routing that "the fix is the same filter in
`moduleClickTargetAt`, and it belongs upstream". That recommendation stands and
its justification changes. The filter is not what stops a defect on the layout
that reported the symptom — e3 shows it changing nothing there. It is what stops
a defect on overlapping outputs, where e5 measures it going from 9 wrong clicks
in 9 to none. `Ui/KeyboardPanel.qml::pressTargetAt` already applies exactly that
filter for the same job, so the asymmetry within one file is the argument, and
the one-line fix is unchanged.

The README carries no causal mechanism for either limit any more. It names the
condition, says whether a plugin can filter it out, and points here. A mechanism
in user-facing prose is a claim that the next measurement can falsify, and this
file exists because that already happened once.

All measured numbers live here and nowhere else. The README and the changelog
name this file instead of restating them.

## Consequences

**The README's click caveat gets narrower and truer.** A reader with monitors
side by side is told the case does not reach them, which 27 clicks say and the
old text did not. A reader with mirrored outputs is told it reaches every
contested click rather than "can", which 9 of 9 say.

**The renumbering caveat loses its issue reference and gains a distinction.**
`omarchy#6355` is "Bar widget group / collapsible drawer", a feature request for
a collapsible group; it tracks nothing about the hotkeys. No upstream issue
tracks the renumbering, and none should be opened for the half of it that is
intended: merged PR #6702 and the comment above `panelWidgetIdAt` both say the
count deliberately skips what is not drawn.

The other half is not documented and is not intended. That comment justifies
counting from any surface with "every monitor lays its bar out from the one
layout" — and `panelNavigationSlots(region, null)` is called without a window,
so it walks `moduleSlots` across every surface and takes the first id match it
finds visible. A pocket breaks the assumption: the same widget is drawn on one
screen and hidden on another, so which surface answers decides the number. That
is a consequence of the same mistake this file is about, found while checking
the reference, and it is left where it was found rather than opened as a third
report.

**Two reports go upstream, neither of them yet filed.** Neither limit is
reported in `basecamp/omarchy`, open or closed, and no PR addresses either. The
drafts are held for approval; nothing has been posted.

**What is not settled.** The pre-configure window in which the pinning has not
been applied is named above and was not measured — a monitor move is a live
gesture, and reproducing the transient reliably needs an instrument this
investigation did not build. And the whole condition rests on
`fixedToplevelPositions` staying `true`; it can be turned off with
`QT_WAYLAND_DISABLE_FIXED_POSITIONS`, and with it off the original stacked
reading would be correct after all. It is not set in this session.

**The rule this file leaves behind.** A defect read out of source is a
hypothesis about a mechanism, and a mechanism is the part most likely to be
wrong while the symptom stays right. 0005 reasoned from "Wayland gives no global
coordinates" to a conclusion that a nine-line harness disproves, and the wrong
half was copied into two other files before anyone ran it. The measurement is
cheap; it was simply never taken.
