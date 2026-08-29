# 11. The tooltip escapes, because it does not own its sink

- Status: accepted
- Date: 2026-08-29
- Amends [0010](0010-the-publication-review-changes-documentation-not-code.md),
  whose review reached `Ui/WidgetButton.qml` and `Bar.qml` and concluded
  "**No QML or JS changed.**" — this one changes JS
- Prompted by the Omarchy marketplace security review of `0a01e26`

## Context

The marketplace review of the release commit reported one release-blocking text
boundary:

> `Model.rejectedMembers()` deliberately preserves malformed values from the
> user-controlled `members` setting, `Model.describe()` concatenates them into
> the tooltip, and `BarWidget.qml` assigns that result to `tooltipText` without
> forcing plain-text rendering. Values rejected by the widget-id allowlist can
> therefore contain rich-text markup or embedded resource references and reach
> the long-lived shell's AutoText tooltip parser.

The path is real and is exactly as described. `rejectedMembers()` preserves what
the user wrote on purpose — the tooltip is the only place a mistyped member
surfaces at all, and a value the tooltip has rewritten is one the user cannot
find again in `shell.json`. From there `describe()` joins it into
`Not a widget id: …`, `BarWidget.qml` assigns the result to `tooltipText`, the
host's `WidgetButton` hands it to `Bar.qml::showTooltip()`, and it lands in a
`Text` that sets no `textFormat`. That is `Text.AutoText`.

`Text.AutoText` asks `Qt::mightBeRichText()` per string. In QML a positive
answer does not mean `RichText` — `QQuickTextPrivate` sets `styledText` for it —
and `StyledText` parses `<img src=…>` and loads it through `QQuickPixmap`,
network included. Qt's own documentation names the two ways out: set
`Text.PlainText` at the sink, or strip the content of unwanted tags.

## What was measured, before deciding anything

On Qt 6.11.2, comparing `contentWidth`/`contentHeight` of the same string in an
`AutoText`, a `PlainText` and a `StyledText` item:

| string | resolves as |
| --- | --- |
| `Not a widget id: <b>x</b>` | rich |
| `Pocket holding 2 widgets\nNot a widget id: <img src=x>` | **plain** |
| `&lt;b&gt; holding\n<b>x</b>` | rich |
| `\n<b>x</b>` | rich |

`mightBeRichText()` stops scanning at the first line break, and `describe()`
pushes a literal first line in every one of its five branches. So on `0a01e26`
the reported parse **does not happen**: the tooltip resolves to plain text, and
no image is fetched. Fed through a rebuilt copy of the host's tooltip label, the
hostile string measured `537.0 x 57.0` under `AutoText` and the identical
`537.0 x 57.0` under `PlainText`.

That is not a reason to leave it alone. The safety rests on two properties that
nothing asserts — that the first line stays free of `<` and `&lt;`, and that the
join stays `\n` — and on a heuristic in a host the plugin does not ship. It is
accidental, and an accident is not a boundary.

Two defects on the same path are not accidental at all, and both are reachable
from the settings form:

- A value carrying a line break forges a whole tooltip line. Measured with
  `["a\nA second Pocket entry exists"]`: the tooltip grew a third line reading
  `A second Pocket entry exists`, which is Pocket's own duplicate-entry warning,
  raised by a configuration that has no second entry.
- `"members": "!,!,!,…"` with 4000 entries produces one line of 12015
  characters. The host's `Text` does not wrap and `Bar.qml` sizes the popup
  window from it, so it asked for a surface **100833 px** wide.

## Decision

`Model.describe()` sends every value it interpolates through `tooltipSafe()`,
which escapes the three markup characters, the backslash, and the control and
format characters that can forge or reorder a line; and through
`tooltipList()`, which bounds the line and counts what it drops. After the
change the same two measurements read `906.2 x 38.0` under both formats — two
lines instead of three — and **1606 px** instead of 100833.

**Escaping to `&lt;` would have been the wrong half of Qt's advice.** Entity
escaping is the answer for a sink known to be rich. Against `AutoText` it is
also a way *in*: `mightBeRichText()` returns true on an `&lt;` before the first
line break, so escaping a value that reached line one would flip the very
decision it was meant to survive. And in the plain case that actually occurs
today, the user would read `&lt;b&gt;` where they wrote `<b>`. The `&` has to
go, not just the `<` it introduces.

**Escapes rather than one replacement glyph.** The line exists so the user can
find the entry again in `shell.json`. A `<`, an `&` and a tab that all render as
the same box are three different mistakes nobody can tell apart. A `\uXXXX`
escape is ugly and reversible, which is the correct trade for a line whose whole
job is to be acted on.

**Both caps, because neither bounds the other.** One value of 20000 characters
and 4000 values of one character are different failures. The per-value cap is
160, chosen above `ID_PATTERN`'s own 128-character ceiling so that every id the
allowlist would have *accepted* passes through untouched — the same line also
carries ids that were merely not found.

**The value is escaped first and cut afterwards, and the other order is a
trap.** Cutting first is the obvious order and it bounds nothing: one escape
turns one character into six, so a value cut to 160 came back out at 960. The
first version of this change had it that way, and the review that caught it
measured what the cap was actually worth — 978 and 989 characters for the two
hostile shapes against 178 for the harmless one, so the cap held only where it
was not needed. Both shapes now measure under 200. The bound has to hold for
hostile input, and hostile input is exactly the input that escapes.

**All four lists, not only `rejected`.** `missing`, `anchored` and `foreign` can
only hold ids that already passed the allowlist, so the escaping is provably a
no-op for them. That proof is an argument about where the values came from, and
an argument about provenance is what made this tooltip's safety accidental in
the first place. It is now a property of the function, and it costs an accepted
id nothing — `tooltipSafe(x) === x` for every `x` the allowlist accepts, asserted
up to the 128-character boundary.

**Not in `rejectedMembers()`.** Every gesture that writes reads the raw setting
through `toList()`, and `membersMisordered` refuses to reorder while any value
is rejected. Escaping at the source would have sent the escaped form towards
`shell.json` — the repair would have damaged the configuration it explains.

## What this is not

**It is not a privilege boundary, and the changelog does not say it is.**
`BarModel.customModuleType()` infers a command module from an entry's `exec` key
and a bare QML module from its `source` key. Anyone who can write `members` on
this plugin's layout entry can write either of those on the same object, which
is arbitrary code in the same shell — `tests/model-test.js` already guards the
manifest against reserved keys for that reason. An image fetch is strictly less
than what the same file already grants. What is fixed here is robustness against
a configuration mistake, and that is the word the CHANGELOG uses.

## Consequences

- The tooltip may now show a `\uXXXX` escape where the user wrote the character
  itself. The README's limits list says so, and owns that statement alone.
- A pocket naming very many unusable ids reports the first few and a count.
- `tests/qml/model.qml` runs the boundary in Qt's V4 engine, which is where the
  plugin's copy of `Model.js` actually executes.
- A test asserting that `AutoText` and `PlainText` render `describe()` output
  identically was written and thrown away: it is green on `0a01e26`, so it would
  have asserted a property that was already true and caught nothing.
- The hostile fixtures name `example.invalid`, which RFC 2606 reserves and which
  resolves nowhere. A fixture that ever did reach a rich text parser would fetch
  its `src`, and a suite that quietly makes network requests is worse than the
  defect it is testing for. The same reasoning kept a deliberately rich `<img>`
  out of the positive control: it would have been flaky, because `QQuickPixmap`
  loads asynchronously and the assertion would race the placeholder.
- The escaped set is not every invisible character and the README does not claim
  it is. The ordinary space separators pass through, and a range test over
  UTF-16 code units cannot reach an astral format character at all — U+E0020's
  tag characters go through as surrogate pairs. What is covered is what can
  change what the line *means*: markup, line forging, and the bidi controls.
