# How the figures were made

The README's two recordings are of a real bar on a real machine, not a mockup.
That makes them honest and it makes them perishable: every number below is a
property of *that* session, and a capture taken on a different output, scale or
theme will not line up with the ones in the repository. This file is what makes
a re-shoot possible without guessing.

## The session

| | |
| :--- | :--- |
| Omarchy | 4.0.0.alpha (bar byte-identical to upstream `v4.0.1`) |
| Quickshell / Qt | 0.3.1 / 6.11.2 |
| Hyprland | 0.56.2 |
| Output | `eDP-1`, 1920×1200 device px at `scale = 1.6666666` → 1152×720 logical |
| Bar | `position = top`, `size-horizontal = 26` logical px, `[font] base-size = 12` |
| Bar font | JetBrainsMono Nerd Font — the mark is `U+F01D8`, `md-dots_horizontal` |
| Theme | `solace-sunset`: `accent #eb5864`, `foreground #f2e0c8`, `background #1c1d36` |

The theme matters more than it looks. `bar.active` is generated from the theme's
red and `Color.accent` from its accent, and in this one both are `#eb5864` — so
the two drop states light the same colour, which is what the README says and
what the drag recording shows.

## Finding the mark

Do not write the mark's coordinate down. The right section is right-anchored and
reflows whenever any widget appears or disappears — an icon that hides itself
when it has nothing to say (the battery on mains, the agents widget, a tray
item) moves everything on its left. A coordinate measured five minutes earlier
aims at the neighbour.

Measure it instead, from a capture, immediately before the take. The mark has a
signature no other icon on the bar has: three blobs of near-equal tiny width at
even spacing, where every other glyph is one blob or two of unequal size. Walk
outward from it while the pitch stays under about 40 logical px and you have the
whole section, left to right.

## Capturing

At the time of writing the bar's right section spanned logical x ≈ 800…1152 with
the pocket open, so both regions below start at 750 and run to the screen edge.
Regions are in the compositor's logical coordinate space, the same space `slurp`
returns.

```bash
# hover demo
gpu-screen-recorder -w region -region 402x64+750+0 \
  -f 30 -k h264 -fm cfr -cursor yes -q very_high -o /tmp/pocket-raw.mp4

# drag demo
gpu-screen-recorder -w region -region 400x64+752+0 \
  -f 30 -k h264 -fm cfr -cursor yes -q very_high -o /tmp/drag-human.mp4
```

`omarchy screenrecord` (bound to `ALT+PRINT`) wraps the same recorder and picks
its region with `slurp`; it is the easier path if you do not need the region to
match a previous take.

Both files come out 128 device px tall whatever height the region asks for. The
bar's top edge lands at y = 11 and the bar is 43 px tall — find those two numbers
by walking rows from the top until one is no longer black, rather than trusting
these. **Crop before publishing:** below the bar is whatever was on the desktop,
and on the drag take that was a chat window with a name in it.

## Converting

```bash
# hover demo: bar plus a strip of wallpaper, so the tooltip is in frame
ffmpeg -ss 0.25 -t 6.2 -i /tmp/pocket-raw.mp4 -vf \
  "crop=670:100:0:11,fps=15,split[a][b];[a]palettegen=max_colors=128:stats_mode=full[p];\
[b][p]paletteuse=dither=none:diff_mode=rectangle" -loop 0 -y docs/pocket-demo.gif

# drag demo: bar only
ffmpeg -ss 1.0 -t 12.3 -i /tmp/drag-human.mp4 -vf \
  "crop=666:43:0:11,fps=15,split[a][b];[a]palettegen=max_colors=128:stats_mode=full[p];\
[b][p]paletteuse=dither=none:diff_mode=rectangle" -loop 0 -y docs/pocket-drag.gif
```

`dither=none` and `diff_mode=rectangle` are the two settings that matter. Bar
chrome has far fewer than 256 colours, so dithering adds noise that only defeats
the compression; and the background does not move, so writing back the smallest
changed rectangle per frame is exactly the right mechanism. Together they turn a
twelve-second capture into under 200 KB. GIF is the format because it is the
only animated one GitHub gives a play/pause control and honours
`prefers-reduced-motion` for, and because a file in the repository still works
in a clone, a fork and a tarball.

`docs/bar-states.png` is two frames of the hover recording cropped identically
and stacked, so the two states are the same pixels of the same bar rather than
two photographs that nearly line up. `preview.png` is those two strips on a flat
ground; the community directory generates its card from a root `preview.png` if
one is there.

## Driving the pointer

The hover recording is machine-driven — a warp per frame through Hyprland's
cursor dispatcher, eased, so the movement reads as a hand rather than a jump.
Relative motion through `uinput` would be run through libinput's pointer
acceleration and land somewhere different every take.

**The drag recording is not, and cannot be.** A synthetic press through a
virtual `uinput` pointer combined with compositor cursor warps does start a bar
drag and does complete a drop — but the grab does not survive the pointer coming
to rest, so what it records is the *cancelled* drag Pocket documents rather than
the drop. It is visible in the capture: across 111 frames of one such take the
mark never lit once, while a human take lit it for 2.2 s going in and 2.0 s
coming out. If you re-shoot the drag, do it by hand.
