# How the figures were made

The README's two recordings are of a real bar on a real machine, not a mockup.
That makes them honest and it makes them perishable: every number below is a
property of *that* session, and a capture taken on a different output, scale or
theme will not line up with the ones in the repository. This file is what makes
a re-shoot possible without guessing.

They have been re-shot once already, for 0.6.0: the first set predated the
slide of [decision 0023](decisions/0023-the-neighbours-slide-with-the-reveal.md),
so the tray jumped where it now slides. The set in the repository is the second
one and shows the slide on open and on fold.

## The session

| | |
| :--- | :--- |
| Omarchy | `4.0.6-1` — what `omarchy version` and `pacman -Q omarchy` report, and what owns `plugins/bar/Bar.qml`. The in-tree marker `/usr/share/omarchy/version` still reads `4.0.0.alpha` and is the older of the two; where anything in this repository names a host version, this row is the one it means. |
| Quickshell / Qt | 0.3.2 (`0.3.2.r7.g2b4501a-1`) / 6.12.0 |
| Hyprland | 0.56.2 |
| Output | `eDP-1`, 1920×1200 device px at `scale = 1.6666666` → 1152×720 logical. A second monitor, `HDMI-A-1` (3840×2160 at scale 2.4, logical x = 1152), was attached; nothing of it is in frame. |
| Bar | `position = top`, `size-horizontal = 26` logical px (the default), `[font] base-size = 12` |
| Bar font | JetBrainsMono Nerd Font — the mark is `U+F01D8`, `md-dots_horizontal` |
| Theme | `solace-sunset`: `accent #eb5864`, `foreground #f2e0c8`, `background #1c1d36` — set for the takes and reverted afterwards |
| Pocket | 0.6.0, in `right`, six members on the bar and one that is not (the fourth tooltip line) |

The theme matters more than it looks. `bar.active` is generated from the theme's
red and `Color.accent` from its accent, and in this one both are `#eb5864` — so
the two drop states light the same colour, which is what the README says and
what the drag recording shows. The desktop's own theme at the time, Solace Neon,
would not have: its red and its accent differ (its `colors.toml`).

## Finding the mark

Do not write the mark's coordinate down. The right section is right-anchored and
reflows whenever any widget appears or disappears — an icon that hides itself
when it has nothing to say (the battery on mains, the agents widget, a tray
item) moves everything on its left. A coordinate measured five minutes earlier
aims at the neighbour.

Measure it instead, immediately before the take. `omarchy-shell shell
debugBarGeometry` gives every slot, but in surface-local coordinates and with no
monitor field, so with a second monitor attached a slot is only known to be on
the screen you are recording once hovering it opens that screen's pocket —
`open_pocket()` in `tests/pointer.py` does exactly that. From a capture the mark
has a signature no other icon on the bar has: three blobs of near-equal tiny
width at even spacing, where every other glyph is one blob or two of unequal
size.

## Capturing

With the pocket open the bar's right section spanned logical x ≈ 698…1152, tray
chevron to power button, and the centre section ended at 686. Both regions start
at 650 and run to the screen edge; the crop below removes the centre's last icon.
Regions are in the compositor's logical coordinate space, the same space `slurp`
returns.

```bash
# hover demo: 180 logical px tall, because the tooltip is four lines
gpu-screen-recorder -w region -region 502x180+650+0 \
  -f 30 -k h264 -fm cfr -cursor yes -q very_high -o /tmp/hover-raw.mp4

# drag demo
gpu-screen-recorder -w region -region 502x40+650+0 \
  -f 30 -k h264 -fm cfr -cursor yes -q very_high -o /tmp/drag-raw.mp4
```

**Shoot on an empty workspace.** The hover take keeps a strip below the bar for
the tooltip, and that strip is whatever the desktop shows there. Both takes were
made on an empty workspace of `eDP-1`, so it is wallpaper.

**Let the pointer leave the bar the moment you release.** Dropping a widget into
the pocket hides it, which narrows the section, which slides every widget left
of the drop point sideways — under a pointer that stayed where it was. A take for
the first set was spoiled that way: the pointer came to rest on the mark, the
tray chevron arrived underneath it, and its drawer unfolded into frame for half a
second. Nothing about it is a defect; it is the same reflow the README describes
for a widget dropped beside a collapsed pocket, seen from the pointer's side.

`omarchy screenrecord` (bound to `ALT+PRINT`) wraps the same recorder and picks
its region with `slurp`; it is the easier path if you do not need the region to
match a previous take.

The recorder writes the region at device scale and pads anything shorter than
128 device px to 128 with black rows. The hover take came out 836×300 with the
bar's top edge at y = 0; the drag take came out 836×128 with the bar at y = 31.
The bar is 43 px tall. Find those numbers by walking rows from the top until one
is no longer black, rather than trusting these. **Crop before publishing:** below
the bar is whatever was on the desktop, and on a drag take for the first set
that was a chat window with a name in it.

## Converting

```bash
# hover demo: bar plus a strip of wallpaper, so the tooltip is in frame
ffmpeg -ss 2.6 -t 6.4 -i /tmp/hover-raw.mp4 -vf \
  "crop=780:192:56:0,fps=15,split[a][b];[a]palettegen=max_colors=128:stats_mode=full[p];\
[b][p]paletteuse=dither=none:diff_mode=rectangle" -loop 0 -y docs/pocket-demo.gif

# drag demo: bar only
ffmpeg -ss 2.6 -t 16 -i /tmp/drag-raw.mp4 -vf \
  "crop=780:43:56:31,fps=15,split[a][b];[a]palettegen=max_colors=128:stats_mode=full[p];\
[b][p]paletteuse=dither=none:diff_mode=rectangle" -loop 0 -y docs/pocket-drag.gif
```

Both takes are scripted, so each gesture starts about three seconds in and the
`-ss` is the same. A hand-made take is more comfortable as one long recording
with the gesture somewhere inside it: start the recorder, take your time, trim
afterwards. Find the gesture by scanning frames for the lit mark rather than by
watching the clip — it is the only thing in frame that is red.

The slide is short — the tray chevron covers its distance in about half a
second each way — so check it at the frame rate you publish: at 15 fps the GIF
holds seven intermediate positions of the chevron on open and seven on fold.

`dither=none` and `diff_mode=rectangle` are the two settings that matter. Bar
chrome has far fewer than 256 colours, so dithering adds noise that only defeats
the compression; and the background does not move, so writing back the smallest
changed rectangle per frame is exactly the right mechanism. Together they turn
the sixteen-second drag take into about 200 KB. The hover take is larger, about
330 KB, because its strip of wallpaper is a gradient. GIF is the format because
it is the only animated one GitHub gives a play/pause control and honours
`prefers-reduced-motion` for, and because a file in the repository still works
in a clone, a fork and a tarball.

`docs/bar-states.png` is two frames of the raw hover recording — 2.0 s into
`/tmp/hover-raw.mp4`, before the pointer arrives, and 5.0 s into it, with the
pointer on the mark — cropped identically to the bar (`crop=780:42:56:0`: ffmpeg
rounds a crop of these yuv420 frames to an even height, and asking for 43 gave
42, which also keeps out the bar's last row, already blended with the wallpaper)
and stacked with a 6 px gap, so the two states are the same pixels of the same
bar rather than two photographs that nearly line up. `preview.png` is those two
strips at 1000 px wide on a dark 1280×640 ground, under the title in Noto Sans
Bold 70 and the tagline in Noto Sans 24; the community directory generates its
card from a root `preview.png` if one is there.

## Driving the pointer

Both recordings are machine-driven, by two short scripts written for the
session and not kept in the repository; what they did is below, close enough to
rewrite them.

The hover take is a warp per frame through Hyprland's cursor dispatcher
(`hl.dsp.cursor.move`), at 60 Hz and eased in and out, so the movement reads as
a hand rather than a jump: 1.2 s at rest below the frame, 0.9 s to the middle of
the mark, 2.8 s on it, 0.7 s back out, 2.6 s for the fold. Relative motion
through `uinput` would be run through libinput's pointer acceleration and land
somewhere different every take.

The drag take moves the other way round: warps only *before* the press, and real
relative motion for everything while the button is held. It reuses
`tests/pointer.py` — `Pointer`, `open_pocket()` to find the screen's surface,
`nudge_by()` for the 30 px that start the drag — and replaces `glide_to()` with
a slower copy: steps of at most 4 px every 22 ms instead of 8 px every 20 ms,
still corrected against `hyprctl cursorpos` after each one. The target is read
from `debugBarGeometry` during the drag: two px inside the mark's left edge
going in, one px inside the left edge of the widget that had followed it (the
monitor widget) going out. Then 1.0 s at rest on the target before the release.
That records the drop. The mark is lit going in and coming out, and `shell.json`
was byte-identical after the in-and-out pair. The first set could not be shot
this way: there the grab was moved by compositor warps, and it did not survive
the pointer coming to rest, so what it recorded was the *cancelled* drag Pocket
documents rather than the drop ([decision
0010](decisions/0010-the-publication-review-changes-documentation-not-code.md)).
Do not warp while the button is held.

The widget going in is grabbed at its right edge rather than its middle. The
dragged image hangs off the pointer by where it was pressed, so a widget pressed
in the middle covers the mark at the very moment it lights; pressed at its right
edge, the image trails to the left of the pointer and the mark stays in view.

After each drop the bar rebuilds every widget, so the drag recording shows the
section jump and the agents widget blink out for a few frames right after the
release. That is the host's rebuild, not the slide; the slide belongs to opening
and folding.
