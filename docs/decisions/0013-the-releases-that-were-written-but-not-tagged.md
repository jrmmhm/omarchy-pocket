# 13. The releases that were written but not tagged

- Status: accepted
- Date: 2026-08-30
- Records `v0.3.1` and `v0.3.2`, the refs the releases of
  [0011](0011-the-tooltip-escapes-because-it-does-not-own-its-sink.md) and
  [0012](0012-the-audit-of-the-published-plugin.md) went out without
- Names what the marketplace listing still says, which no ref in this
  repository can change

## Context

`CHANGELOG.md` names five versions and links each of them. Three of those
links answered 404:

```
$ curl -s -o /dev/null -w "%{http_code}" -L <url>
releases/tag/v0.1.0  200      releases/tag/v0.3.1     404
releases/tag/v0.2.0  200      releases/tag/v0.3.2     404
releases/tag/v0.3.0  200      compare/v0.3.2...HEAD   404
```

Five versions, six references. `git ls-remote --tags origin` knew `v0.1.0`,
`v0.2.0` and `v0.3.0` and nothing else. The releases themselves happened:
`manifest.json` carries `0.3.1` from `1f051de` and `0.3.2` from `f2b8e89`,
the marketplace listed the plugin on 2026-08-29 against `3ad9860`, and
[0012](0012-the-audit-of-the-published-plugin.md) opens by saying `0.3.1`
had been on the marketplace for a day. What was missing was the ref, not
the release.

## What was measured

**Which commit is which release.** Not the commit that raised the version
number: `1f051de` was followed inside the same pull request by `16ab519`
(cut the value after escaping it, not before), and `f2b8e89` by `b47716e`,
whose fix the `0.3.2` section already describes. The merge commits are the
only first-parent commits that ever carried those trees —
`3ad9860^{tree} == b63bd6d^{tree} == 15a2598…` and
`f6a9405^{tree} == 533c03f^{tree} == c62269e…` — so they are the only
states a reader or a validator ever saw as `0.3.1` and `0.3.2`. Both carry
the matching `manifest.json` version, and at both of them `[Unreleased]`
is empty, which is the file saying the same thing.

**What this repository already does.** All three existing tags are
unsigned annotated tags reading `Pocket <version> — <summary>`, on
first-parent commits of `main`. They were not cut at the moment of
release: `v0.1.0` and `v0.2.0` share the tagger timestamp
`2026-08-27 12:34:08` — one sitting — while `v0.1.0`'s target is from the
previous night and `v0.2.0`'s target is 56 seconds old and six commits
past its own `chore(pocket): release 0.2.0`. Tag dates in this repository
are creation dates, not release dates, and a tag written afterwards is
the practice rather than a departure from it.

**Who receives a tag.** Nobody who has the plugin installed.
`omarchy-plugin-update` runs `git fetch --quiet origin HEAD` and
`git merge --ff-only FETCH_HEAD`; an explicit refspec follows no tags at
all. `omarchy-plugin-add` runs `git clone -- "$url"`, so a fresh install
gets whatever tags exist at clone time and never another one. No tag is
read by `BarWidget.qml`, by `Model.js` or by `omarchy-plugin-validate`,
which checks `manifest.json` fields only. Tagging therefore cannot change
the behaviour of an installed pocket, and this is a property of the host
tooling rather than a claim about the change.

## Options

**Retract the two versions into `[Unreleased]`.** This is the other way to
make a dead link honest, and it is the dishonest one here. The code is
out: `manifest.json` shipped `0.3.1` at `3ad9860` and `0.3.2` at
`f6a9405`, every existing install has fast-forwarded onto them, and the
marketplace still advertises `"version": "0.3.1"` to every visitor. A
retraction would replace a missing ref with a false sentence.

**Cut GitHub Releases as well as tags.** Refused as more than the minimum.
`gh release list` prints nothing and `/releases/latest` answers 404 for
this repository — it has never had a Release object, and
`releases/tag/v0.3.0` answers 200 anyway, because GitHub synthesises that
page from the bare annotated tag. The repository's landing page will go on
saying *No releases published* while the changelog links to pages titled
*Release v0.3.x*; that is true of `v0.1.0` today and the two new tags
neither cause it nor worsen it.

## Decision

**Tag the two releases where they actually stood.** `v0.3.1` on `3ad9860`,
`v0.3.2` on `f6a9405`, annotated and unsigned, in the message form the
three existing tags use. All five versions then resolve the same way, and
`CHANGELOG.md` needed no edit to any version section or link definition —
the file was never wrong about what it had released.

**Tag before writing this record.** The record moves `main` past
`f6a9405`, and a tag placed afterwards would either miss the tip or fold a
note about the release into the release it names. `[Unreleased]` is what
carries the difference from here on.

**Verify the target before pushing, because a tag is effectively final.**
A clone that already holds a tag does not move it on a plain fetch, so a
tag on the wrong commit cannot be corrected outward. A tag push also runs
no workflow — `ci.yml` fires on `push: branches: [main]` and
`pull_request` — so there is no red run to catch a mistake either. The
check that stands in for it is `git show <sha>:manifest.json` against the
version the tag names, run for both before the push.

## What this does not reach

**The marketplace card keeps saying `v0.3.0`.** Its release comes from
`build-catalog.mjs`, which asks `/releases/latest` and falls back to
`/tags?per_page=1` — but only on an incremental build.
`repositoryReleaseForRefresh` returns the stored value otherwise, and the
scheduled refresh (`refresh-catalog.yml`, `cron: "17 4 * * *"`) has no
approved repository and therefore takes the `incremental: false` plan. The
stored `{"tag": "v0.3.0"}` is re-emitted daily and re-validated for shape
only. Pushing tags does not move it; an approved update does.

**The listing will go to *Update unverified* on its own.**
`catalog-verification.mjs` sets it from
`observedCommit !== verification.commit`. The listing is pinned at
`3ad9860`, and its last upstream observation, `2026-08-30T09:56:21Z`,
predates the merge of pull request #8 at `2026-08-30T12:38:37Z`. The next
refresh sees `f6a9405` and the card drops out of the Verified filter. This
is the marketplace working as documented, not a defect here.

**The corrected description reaches the card through neither route taken
so far.** The card's `description` is `manifest.description` read at the
pinned commit, where it still contains the *into one slot* sentence that
`0.3.2` records as corrected. The repository's own About text was a second
copy of that sentence and has been set to the current
`manifest.json` description; that field is read only by the marketplace's
submission inspection and never published on a card.

**The one open action, named so it is not rediscovered.** The marketplace's
`verify-plugin.yml` issue form, option *Verify and publish a newer
upstream commit*, with the plugin id, the repository root URL and the full
commit `f6a9405d0dc30ee08c7eac1c05574393d8450342`. It is also the only
thing that triggers the incremental build the release field needs.

## Consequences

**All six version references in `CHANGELOG.md` resolve**, and they resolve
the same way for every version the file names rather than only for the
newest.

**An installed pocket is untouched.** No file the runtime reads was
changed, and the two Omarchy commands that reach this repository read only
`origin HEAD`.

**The tags are the record on GitHub and nowhere else.** A checkout made
before today will never receive `v0.3.1` or `v0.3.2`; anyone reconstructing
what a given user is running should read `manifest.json`, not the tag list
of their clone.

**The branch of pull request #8 is gone**, on `origin` and locally, as the
branches of #1–#4 already were. `533c03f` stays reachable as `f6a9405^2`
and through `refs/pull/8/head`.

**The rule this file leaves behind.** A version exists in as many places as
publish it, and they do not update together: a number in a manifest, a
heading in a changelog, a git ref, a card in a directory, a sentence in a
repository's own description. Four of those five said something different
about this plugin on the same afternoon. Cutting a release means naming
all of them, and the ones outside this repository are the ones that need
an action rather than a commit.
