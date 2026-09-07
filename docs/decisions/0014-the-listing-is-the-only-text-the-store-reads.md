# 14. The listing is the only text the store reads

- Status: accepted
- Date: 2026-09-08
- Corrects the `plugins[]` universality claimed by the README since 0.1.0 and
  drawn in `docs/pocket-layout.svg`, which
  [0010](0010-the-publication-review-changes-documentation-not-code.md) rewrote
  without questioning the word *every*
- Records three deliberate non-fixes and the one action that lives outside this
  repository

## Context

`0.3.2` had been on the marketplace for nine days, verified, current, and
effectively invisible. This file records what the store actually reads, what
that measures out to, and what the description was changed to as a result. No
QML and no JS changed; `Model.js` and `BarWidget.qml` are byte-identical.

Everything below was measured on 2026-09-07 against the live catalogue
(`https://plugins.omarchy.org/catalog.json`, `generatedAt`
`2026-09-07T11:24:36Z`, 2599 entries) and the shipped site scripts at
`?v=20260831-01`.

## What was measured

### The store reads six fields and one image

`scripts/build-catalog.mjs` takes `id`, `name`, `description`, `author`,
`version` and `license` from `manifest.json`, and a root `preview.png` from
which it generates a 720 px card and a 1600 px detail image. It reads the
`barWidget` block for exactly one thing, `defaultSection`, and validates it.
`barWidget.description`, `barWidget.category` and `barWidget.aliases` reach no
store surface. `category` and `tags` on the card are not manifest fields at
all: they come from the submission issue and live in the marketplace's own
`registry.json`.

`site/assets/js/plugin.js` renders the detail page from `description`,
`previewImage`, `tags` and the install command. **It does not render the
README.** This repository's 21 KB of prose, thirteen decision records, changelog
and two test suites appear nowhere in the store.

### Browsing does not reach this plugin and cannot be made to

The catalogue holds 2563 community plugins, of which 2252 are bar widgets, and
it grew by 97.5 listings a day over the fourteen days to 2026-09-07. The browse
page paginates at 9 (`app.js`, `pluginsPerPage`) and defaults to *Recently
added*. Pocket's position, nine days after listing:

| sort | position |
| --- | --- |
| Recently added (default) | 896 of 2563 — page 100 |
| Recent activity | 1052 |
| Most starred | 437 |
| A–Z | 1782 |
| Appearance filter, by stars | 40 of 189 |

There are no featured or curated slots. A listing's own recency is spent within
hours of publication and cannot be bought back except by pushing, which is not
a reason to push.

### Search matches a substring, and the old description contained none

`search.js::matchesDirectSearch` folds `name`, `description`, `author`, the
GitHub owner login, `id`, `category`, `kind` and `tags` into one string; a token
longer than three characters is a plain `includes` against it. There is no
stemming, so `collapse` does not match `collapsing`. Tokens of three characters
or fewer additionally get a prefix pass over `primaryText` — `name`, `id`,
`tags`.

A replica of that function was run over the live catalogue against 26 queries a
user with a crowded bar would type. The shipped description answered **one**,
`hover`, and that only because the word happened to be in it. The rewritten
one answers **17**:

| query | results in catalogue | Pocket's rank by stars |
| --- | --- | --- |
| `declutter` | 1 | **1** — the only result in the catalogue |
| `hide icons` | 3 | 1 |
| `overflow` | 5 | 2 |
| `collapse` | 9 | 2 |
| `drawer` | 11 | 3 |
| `hide` | 30 | 4 |

`pocket` and `tuck` still match, so nothing that found this plugin before stops
finding it.

### The card shows one clipped line

`style.css` gives the browse card's description
`white-space: nowrap; max-height: 21px; overflow: hidden` under a fade mask —
one line, about 53 characters at the rendered card width. Of the shipped 270
characters, roughly 217 were never seen while browsing, and the visible part —
*"Tuck a run of bar widgets behind one mark and fan the"* — named no benefit and
contained no searchable verb.

### Simplicity is decided in one line and one image

The question this file was opened to answer had three parts, and the third is
how quickly a stranger can tell whether they want this. The store gives them
exactly two surfaces to decide on: the clipped card line above, and the card
image. Nothing else — the detail page adds the full description and the preview
at 1600 px, and that is the end of it.

The image was rendered at the real card size, 340×175, and read. It is legible
and its 2:1 source is very nearly the card's `object-fit: cover` box, so almost
nothing is cropped where the 16:9 screenshots around it lose their top and
bottom. What it spends is space: roughly 45 % of its area is the plugin name and
a tagline that the card prints again as text ten pixels below, and the
difference between its two bar rows — the whole point — is an icon-counting
exercise at that size.

Past the card the decision moves to GitHub, and there the README is the surface.
At 21 KB it is the longest in the comparison set by a factor of two against the
next (9.3 KB) and five against the median (4.3 KB), which is a feature of this
project rather than a defect — but the sentence that decides whether a reader
wants the plugin was the fourth of the opening paragraph, behind an explanation
of what a bar is. It is now the first, and `Requirements` keeps its place ahead
of `Install`, because a bar without a Nerd Font draws an empty box where the
mark should be.

### 350, not 500, is the binding length

`build-catalog.mjs` caps `description` at 500. GitHub's About field, which
carries a verbatim second copy of the same sentence, refuses anything over 350
and answers `422 Validation Failed`. The tighter bound is the one that decides
whether a single sentence can serve both places, and no file in this repository
stated it. `tests/model-test.js` now does.

### The comparison was false, in two directions

The README has claimed since `0.1.0` that *every other* way of grouping bar
widgets moves the entries out of `bar.layout` into `plugins[]`. Three other
plugins were read at the commits named here:

| plugin | commit | what it does |
| --- | --- | --- |
| `io.github.eshayat102.hide-icons` | `f9ba20a` | saves `originalVisible`, sets `slot.visible` on `bar.moduleSlots`, writes settings through `bar.shell.updateEntryInline` — **this plugin's mechanism** |
| `nightdevil00/plugin.hider` | `dcf797a` | `config.bar.layout.right = right.filter(...)` — deletes the entries from the layout, never touching `plugins[]` |
| `salemsayed/omatender` | `6335ea2` | captures each entry's origin, moves it, restores it later |

So *every* is false because of the first, and *into `plugins[]`* is false as a
description of moving because of the second. `ianswope.stack` at `276e95b`, the
one plugin 0010 actually measured, still does what 0010 says it does; the error
was generalising from it. The claim as it stood would have been carried into the
marketplace card by the first draft of the new description, which is how it was
found.

## Options

**Buy visibility with recency.** Rejected. `repositoryUpdatedAt` drives the
*Recent activity* sort, and a push moves the listing to the top of it for a few
hours. Roughly 130 repositories push a day, so the effect decays the same day,
and a commit made to move a sort order is a commit made for the wrong reason.

**Change `category` or `tags`.** Rejected on measurement rather than on
principle. Neither is a manifest field and the update form has no place for
them, so both would need a maintainer request. `Appearance` holds 189 plugins
against `Widgets` at 775, so the current category is already the smaller pond
and moving would enlarge it. Of the thirteen allowed tags only `hyprland` is
unused here, and it answers queries with 447 results. The two tags this listing
carries, `bar` and `quickshell`, are the two most common in the catalogue — 1913
and 1799 uses — and buy no differentiation, but nothing in the closed vocabulary
buys any either.

**Rewrite the description.** Taken. It is the only store surface this repository
owns outright, it costs one field, and it is measurable before it ships.

## Decision

**Lead with the benefit and the verb, and say nothing about other plugins.**
339 characters, first sentence carrying the whole pitch because that sentence is
what the card shows and what the README tagline now repeats verbatim. The
comparison that made the first draft false was removed rather than qualified: a
sentence about 2563 plugins nobody has read is not a sentence this repository
can defend, and the properties it was reaching for — folding, grouping,
collapse, overflow, and the entry not moving — are all statements about Pocket
alone.

**Drop the two claims the code does not carry.** "Every Omarchy tool keeps
reporting them correctly" was in the shipped description and is contradicted by
this project's own `SUPER+CTRL+1…9` finding, recorded in
[0012](0012-the-audit-of-the-published-plugin.md) and in
[0007](0007-the-two-host-limits-measured.md): a member with a panel of its own
leaves the panel numbering while it is hidden. The README's "Nothing else on
your desktop can tell that they are hidden" was the same claim in stronger
words. Both now name the exception and link to it.

**Bind the description with two assertions rather than a habit.** Nothing
checked this field, which is how the *into one slot* sentence 0012 records
reached the marketplace in the first place. `tests/model-test.js` now holds the
length against the 350 bound and the README tagline against the description's
first sentence. Both were watched failing before they passed — the tagline
against the shipped pair, the length against the 383-character first draft.

## The three non-fixes

**`preview.png` stays as it is.** Its 2:1 source is very nearly the card's own
`object-fit: cover` box, so almost nothing is cropped where the 16:9 screenshots
around it lose their top and bottom, and it was rendered at the real 340×175 and
read. About 45 % of its area is the plugin name and a tagline that the card
prints again as text ten pixels below, and the difference between its two bar
rows is an icon-counting exercise at card size. The owner's call was to leave it
alone. It therefore keeps the older tagline wording, which is still true and no
longer word-for-word the description — a divergence recorded here so it is a
choice rather than an oversight.

**The tagline inside the image is not the tagline under test.** The assertion
binds `manifest.json` to `README.md` and to nothing else, because those are the
two a test can read.

**GitHub topics and the homepage field are not a marketplace measure.**
`build-catalog.mjs` reads neither; `repositoryMetadata()` returns
`stargazers_count` and `pushed_at` and nothing more. They are worth setting for
GitHub's own search and they are honestly labelled as that.

## What this does not reach

**The card still says what the pinned commit said.** `description` is read at
`listingValidatedCommit`, which is `f01fe35`. Until an update is filed and
approved, the store shows the old sentence, and once `main` moves past that
commit the scheduled refresh sets the card to *Update unverified* —
`catalog-verification.mjs` compares the observed commit against the verified
one, and 1698 of 2563 community listings carry the verified badge, so its
absence is conspicuous.

**Three open actions, named so none is rediscovered.** All three live outside
this repository and none of them is a commit.

1. **Cut `v0.3.3` on the merge commit.** `CHANGELOG.md` names the version and
   links it, and until the tag exists both `releases/tag/v0.3.3` and
   `compare/v0.3.3...HEAD` answer 404 — the exact defect 0013 closed and whose
   closing sentence was *all six version references resolve*. 0013's practice is
   the one to follow: annotated, unsigned, on the first-parent commit of `main`
   that carried the tree, which is the merge commit rather than this branch's
   tip, and verified with `git show <sha>:manifest.json` before the push because
   a tag cannot be corrected outward.
2. **Set the repository's About text to the new description.** 0013 established
   About as one of the places this sentence lives, and it currently still reads
   *"…so every Omarchy tool keeps reporting them correctly"* — the sentence this
   file records as disproved. The 350-character bound exists precisely so one
   sentence can stand in both places; until About is updated it does not.
   `tests/model-test.js` cannot see this copy, which is why it is written down
   here instead.
3. **File the marketplace update.** The `verify-plugin.yml` issue form, option
   *Verify and publish a newer upstream commit*, with the plugin id, the
   repository root URL and the forty-character SHA of `main` at the moment of
   filing. 0013 established that the SHA is read then and never copied from a
   file, and that nothing may be pushed between reading it and submitting. What
   0013 did not say, and this file does: the filing belongs immediately after
   the push, because the interval between them is exactly the interval in which
   the listing is both unverified and out of date.

## Consequences

**Seventeen of twenty-six intent queries reach this plugin instead of one**, and
one of them reaches nothing else in the catalogue.

**The README no longer makes a claim about software nobody measured.** What it
says is unchanged for the landing place it describes — `plugins[]`, which of the
four plugins read here and in 0010 is `ianswope.stack` alone. `plugin.hider`
moves entries without ever touching `plugins[]`, so the four consequences listed
under that paragraph are the array's and not moving's, and the README now says
so. What it no longer claims is that there is no other kind.

**The plugins that were read are named here and only here.** The README points
at this file rather than repeating them, because a competitor's mechanism is a
perishable fact and 0013's rule is that such a fact has one owner.

**A second copy of the pitch is now enforced rather than hoped for.** The tagline
cannot drift from the description without a red run, and the description cannot
outgrow the About field without one.

**The rule this file leaves behind.** A store lists what it can read, not what
you wrote. Six fields and one image were the entire surface; everything this
project is proud of — the audits, the two-engine suite, the thirteen decision
records — sat behind a click that the description had to earn first, and for
nine days it did not earn it.
