// Unit tests for Model.js and for the one property of manifest.json that the
// shell punishes silently: a settings key named type, exec or source.
//
// Run through tests/run.sh, which is the command the /implement commit gate
// accepts for this repository.

const fs = require("fs")
const path = require("path")
const Model = require("../Model.js")

const ROOT = path.join(__dirname, "..")

let assertions = 0
let failures = 0

function check(label, actual, expected) {
  assertions++
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a !== e) {
    failures++
    console.error(`FAIL: ${label}\n  expected: ${e}\n  actual:   ${a}`)
  }
}

function contains(label, haystack, needle) {
  assertions++
  if (String(haystack).indexOf(needle) === -1) {
    failures++
    console.error(`FAIL: ${label}\n  expected to contain: ${needle}\n  actual: ${haystack}`)
  }
}

// ------------------------------------------------------------- id shape

check("real omarchy id", Model.isWidgetId("omarchy.audio"), true)
check("dashed id", Model.isWidgetId("omarchy-overview"), true)
check("bare id", Model.isWidgetId("omaplug"), true)
check("empty id", Model.isWidgetId(""), false)
check("path traversal is not an id", Model.isWidgetId("../evil"), false)
check("slash is not an id", Model.isWidgetId("a/b"), false)
check("leading dot is not an id", Model.isWidgetId(".hidden"), false)
check("non-string is not an id", Model.isWidgetId(null), false)

// ------------------------------------------------------ member parsing

const SELF = "jrmmhm.pocket"

check("array of strings",
  Model.parseMembers(["omarchy.audio", "omaplug"], SELF), ["omarchy.audio", "omaplug"])
check("comma separated string",
  Model.parseMembers("omarchy.audio, omaplug", SELF), ["omarchy.audio", "omaplug"])
check("whitespace separated string",
  Model.parseMembers("omarchy.audio  omaplug", SELF), ["omarchy.audio", "omaplug"])
check("array of objects",
  Model.parseMembers([{ id: "omarchy.audio" }, { id: "omaplug" }], SELF), ["omarchy.audio", "omaplug"])

// What actually arrives from the bar. shell.json is parsed into a QVariantList
// and injected as a QML sequence: it indexes and reports length, but
// Array.isArray() says false. node cannot produce that type, so these fixtures
// stand in for it — an array-like that is provably not an Array. Without them
// the suite was green while the plugin read an array-valued `members` as empty.
const sequence = { length: 2, 0: "mehiel.darky", 1: "omaplug" }
check("the fixture is not a real Array", Array.isArray(sequence), false)
check("array-like sequence, as the bar injects it",
  Model.parseMembers(sequence, SELF), ["mehiel.darky", "omaplug"])
check("array-like sequence of objects",
  Model.parseMembers({ length: 1, 0: { id: "omaplug" } }, SELF), ["omaplug"])
check("empty sequence", Model.parseMembers({ length: 0 }, SELF), [])
check("an object with no length is not a list",
  Model.parseMembers({ id: "omaplug" }, SELF), [])
check("a number is not a list", Model.parseMembers(7, SELF), [])
check("order is the user's",
  Model.parseMembers("omaplug, omarchy.audio", SELF), ["omaplug", "omarchy.audio"])
check("duplicates collapse",
  Model.parseMembers("omaplug, omaplug", SELF), ["omaplug"])
check("the pocket drops itself",
  Model.parseMembers("omaplug, " + SELF, SELF), ["omaplug"])
check("invalid ids are dropped",
  Model.parseMembers("omaplug, ../evil, a/b", SELF), ["omaplug"])
check("empty string yields nothing", Model.parseMembers("", SELF), [])
check("undefined yields nothing", Model.parseMembers(undefined, SELF), [])
check("null yields nothing", Model.parseMembers(null, SELF), [])
check("trailing comma yields nothing extra",
  Model.parseMembers("omaplug,", SELF), ["omaplug"])

check("rejected ids are reported",
  Model.rejectedMembers("omaplug, ../evil, a/b", SELF), ["../evil", "a/b"])
check("nothing rejected when all are valid",
  Model.rejectedMembers("omaplug, omarchy.audio", SELF), [])
check("the pocket's own id is not a rejection",
  Model.rejectedMembers(SELF, SELF), [])

// ------------------------------------------------------- reveal cascade

const rf = Model.revealFraction

check("nothing revealed at rest", rf(0, 0, 4), 0)
check("fully revealed at the end", rf(1, 0, 4), 1)
check("the last member is also fully revealed at the end", rf(1, 3, 4), 1)
check("the last member has not started at the halfway point", rf(0.4, 3, 4), 0)
check("a lone member tracks the scalar exactly", rf(0.37, 0, 1), 0.37)
check("count 0 is treated as one member", rf(0.37, 0, 0), 0.37)

// The point of the cascade: the near member is always at least as far along as
// the far one, and strictly ahead somewhere in the middle.
assertions++
{
  let ordered = true, strictSomewhere = false
  for (let p = 0; p <= 1.0001; p += 0.05) {
    for (let i = 1; i < 4; i++) {
      if (rf(p, i - 1, 4) < rf(p, i, 4)) ordered = false
      if (rf(p, i - 1, 4) > rf(p, i, 4)) strictSomewhere = true
    }
  }
  if (!ordered || !strictSomewhere) {
    failures++
    console.error(`FAIL: the cascade is ordered and actually staggers (ordered=${ordered}, staggers=${strictSomewhere})`)
  }
}

// Every member must still complete, however many there are — a stagger that
// did not shrink with the count would leave the last one no run at all.
for (const n of [1, 2, 4, 8, 20]) {
  check(`every one of ${n} members completes`,
    Array.from({ length: n }, (_, i) => rf(1, i, n)).every(v => v === 1), true)
  check(`none of ${n} members starts early`,
    Array.from({ length: n }, (_, i) => rf(0, i, n)).every(v => v === 0), true)
}

check("progress above one is clamped", rf(5, 2, 4), 1)
check("progress below zero is clamped", rf(-5, 0, 4), 0)
check("garbage progress reads as rest", rf("nonsense", 0, 4), 0)
check("an index past the end is the last member", rf(1, 99, 4), rf(1, 3, 4))

// -------------------------------------------------------------- tooltip

// Pinned verbatim, not by substring. This line is the only thing an empty
// pocket ever says, and it once went on explaining a drop rule that had
// already been replaced -- a substring check for "set `members`" was green
// throughout.
check("the empty pocket's line, verbatim",
  Model.describe({ members: [] }),
  "Pocket is empty — drag a widget onto it, or set `members` on its bar entry")
contains("collapsed pocket names its size",
  Model.describe({ members: ["a", "b"] }), "holding 2 widgets")
check("one member is singular",
  Model.describe({ members: ["a"] }).split("\n")[0], "Pocket holding 1 widget")

// The first line must describe what is held, not what was configured. A tooltip
// claiming three widgets directly above three lines saying none of them works
// is worse than no tooltip, and this one is the only place those problems ever
// appear.
check("unusable members are not counted as held",
  Model.describe({ members: ["a", "b", "c"], missing: ["a"] }).split("\n")[0],
  "Pocket holding 2 widgets")
check("a refused anchor is not counted as held",
  Model.describe({ members: ["a", "b"], anchored: ["b"] }).split("\n")[0],
  "Pocket holding 1 widget")
check("nothing usable is said outright, not counted",
  Model.describe({ members: ["a", "b", "c"], missing: ["a", "b"], anchored: ["c"] }).split("\n")[0],
  "Pocket holding nothing — none of the widgets it names can be used")
check("a configured but unusable pocket does not claim to be open",
  Model.describe({ members: ["a"], missing: ["a"], expanded: true }).split("\n")[0],
  "Pocket holding nothing — none of the widgets it names can be used")
check("a member in another section still counts as held",
  Model.describe({ members: ["a", "b"], foreign: ["b"] }).split("\n")[0],
  "Pocket holding 2 widgets")
contains("open pocket offers the pin",
  Model.describe({ members: ["a"], expanded: true }), "click to keep it open")
contains("pinned pocket offers the release",
  Model.describe({ members: ["a"], pinned: true }), "click to release")
contains("missing members are named",
  Model.describe({ members: ["a"], missing: ["a"] }), "Not on this bar: a")
contains("the center anchor refusal is named",
  Model.describe({ members: ["a"], anchored: ["a"] }), "center anchor")
contains("a member in another section is named",
  Model.describe({ members: ["a"], foreign: ["a"] }), "another section")
contains("rejected ids are named",
  Model.describe({ members: [], rejected: ["../evil"] }), "Not a widget id: ../evil")
contains("a second pocket is called out",
  Model.describe({ members: ["a"], duplicateInstances: true }), "second Pocket entry")

// ------------------------------------------------------- entry identity

check("a bare string entry is its own id", Model.entryIdOf("omaplug"), "omaplug")
check("an object entry answers with id", Model.entryIdOf({ id: "omaplug", members: "x" }), "omaplug")
check("whitespace around an id is not part of it", Model.entryIdOf(" omaplug "), "omaplug")
check("an entry without an id has none", Model.entryIdOf({ members: "x" }), "")
check("null is not an entry", Model.entryIdOf(null), "")

// ------------------------------------------------------- member ordering

const LAYOUT_RIGHT = ["omarchy.tray", "mehiel.darky", "omaplug", "omarchy.tailscale", SELF, "jerome.focus"]

check("members follow the layout, not the order they were added",
  Model.orderMembers(["omarchy.tailscale", "mehiel.darky", "omaplug"], LAYOUT_RIGHT),
  ["mehiel.darky", "omaplug", "omarchy.tailscale"])
check("an already ordered list is left alone",
  Model.orderMembers(["mehiel.darky", "omaplug"], LAYOUT_RIGHT), ["mehiel.darky", "omaplug"])
// The point of the -1 sentinel: an id the layout does not know must not be
// dropped, and two of them must not be reordered against each other either.
check("ids the layout does not know collect at the end, in their own order",
  Model.orderMembers(["../evil", "omaplug", "nope", "mehiel.darky"], LAYOUT_RIGHT),
  ["mehiel.darky", "omaplug", "../evil", "nope"])
// Long enough that an inconsistent comparator cannot come out right by luck:
// V8 insertion-sorts short arrays and will hide a contradictory comparator.
check("many unknowns still land behind every known id, in their own order",
  Model.orderMembers(["z1", "omarchy.tailscale", "z2", "omarchy.tray", "z3",
                      "omaplug", "z4", "mehiel.darky", "z5", "jerome.focus", "z6"], LAYOUT_RIGHT),
  ["omarchy.tray", "mehiel.darky", "omaplug", "omarchy.tailscale", "jerome.focus",
   "z1", "z2", "z3", "z4", "z5", "z6"])
check("an empty layout leaves everything where it was",
  Model.orderMembers(["b", "a"], []), ["b", "a"])
check("ordering nothing yields nothing", Model.orderMembers([], LAYOUT_RIGHT), [])
check("a missing list yields nothing", Model.orderMembers(undefined, LAYOUT_RIGHT), [])

// -------------------------------------------------- adding and removing

// Works on the RAW list. A round trip through parseMembers would delete the
// ids the tooltip is at that moment asking the user to fix, and that is their
// config, not ours.
check("a member is removed", Model.withoutMember(["a", "b"], "a"), ["b"])
check("removing what is not there changes nothing", Model.withoutMember(["a"], "b"), ["a"])
check("a rejected id survives an unrelated removal",
  Model.withoutMember(["../evil", "a", "b"], "a"), ["../evil", "b"])
check("removing the last member empties the list", Model.withoutMember(["a"], "a"), [])

// ------------------------------------------------------- the next list

// The pocket writes before the bar moves anything, so at this moment the
// dragged widget is still recorded where it came FROM. Ranking it there is
// what would go wrong, and these two fixtures are the proof: the newcomer
// must land against the pocket regardless of where it started.
check("a widget dragged in from the far end still lands nearest the pocket",
  Model.nextMembers(["mehiel.darky", "omaplug"], LAYOUT_RIGHT, "omarchy.tray", "add", true),
  ["mehiel.darky", "omaplug", "omarchy.tray"])
check("a widget dragged in from beyond the pocket lands there too",
  Model.nextMembers(["mehiel.darky", "omaplug"], LAYOUT_RIGHT, "jerome.focus", "add", true),
  ["mehiel.darky", "omaplug", "jerome.focus"])
// In the left section the members sit after the pocket, so the near end is
// the front of the list and the cascade runs the other way.
check("in a left section the newcomer lands at the front",
  Model.nextMembers(["mehiel.darky", "omaplug"], LAYOUT_RIGHT, "omarchy.tray", "add", false),
  ["omarchy.tray", "mehiel.darky", "omaplug"])
check("adding a widget that is already a member only re-seats it",
  Model.nextMembers(["mehiel.darky", "omaplug"], LAYOUT_RIGHT, "mehiel.darky", "add", true),
  ["omaplug", "mehiel.darky"])
check("the survivors are put back into layout order",
  Model.nextMembers(["omarchy.tailscale", "mehiel.darky"], LAYOUT_RIGHT, "omaplug", "add", true),
  ["mehiel.darky", "omarchy.tailscale", "omaplug"])
check("removing leaves the rest in layout order",
  Model.nextMembers(["omarchy.tailscale", "omaplug", "mehiel.darky"], LAYOUT_RIGHT, "omaplug", "remove", true),
  ["mehiel.darky", "omarchy.tailscale"])
check("a rejected id survives either way",
  Model.nextMembers(["../evil", "omaplug"], LAYOUT_RIGHT, "mehiel.darky", "add", true),
  ["omaplug", "../evil", "mehiel.darky"])
check("adding nothing adds nothing",
  Model.nextMembers(["omaplug"], LAYOUT_RIGHT, "", "add", true), ["omaplug"])

// -------------------------------------------------------- serialisation

check("a comma string stays a comma string",
  Model.membersValue(["a", "b"], "a, b"), "a, b")
check("an array stays an array",
  Model.membersValue(["a", "b"], ["a"]), ["a", "b"])
// What the bar actually injects is a sequence type, not an Array — the same
// fixture the parser is pinned against.
check("an array-like sequence is recognised as an array",
  Model.membersValue(["a", "b"], { length: 1, 0: "a" }), ["a", "b"])
// manifest.json declares members as a string with "" for a default, so a
// pocket that never had the key must not suddenly grow an array.
check("nothing to preserve writes the shape the manifest declares",
  Model.membersValue(["a"], undefined), "a")
check("an empty string is still a string", Model.membersValue(["a"], ""), "a")
check("an emptied array stays an array", Model.membersValue([], ["a"]), [])
check("an emptied string stays a string", Model.membersValue([], "a"), "")

// ----------------------------------------------------------- drop rules

function drop(overrides) {
  return Model.dropDecision(Object.assign({
    sourceId: "omarchy.bluetooth", selfId: SELF, anchorId: "omarchy.clock",
    members: ["mehiel.darky", "omaplug"],
    targetIsSelf: false, targetIsMember: false, hasTarget: true, innerEdge: false
  }, overrides))
}

// Aiming at the pocket takes a widget in from either side. An earlier rule
// gave the icon's two halves opposite meanings; on a real bar that meant half
// the thing you aim at does the opposite of what aiming at it looks like.
check("the inner edge takes a widget in",
  drop({ targetIsSelf: true, innerEdge: true }), "add")
check("the outer edge takes it in too",
  drop({ targetIsSelf: true, innerEdge: false }), "add")
check("a neighbour is not the pocket", drop({ targetIsSelf: false }), "none")
check("a member dropped on the near side is only reordered",
  drop({ sourceId: "omaplug", targetIsSelf: true, innerEdge: true }), "none")
check("a member dragged past the pocket leaves",
  drop({ sourceId: "omaplug", targetIsSelf: true, innerEdge: false }), "remove")
check("a member dropped elsewhere on the bar leaves",
  drop({ sourceId: "omaplug" }), "remove")
check("a member dropped onto another member is only reordered",
  drop({ sourceId: "omaplug", targetIsMember: true }), "none")
// Released off the bar there is no drop target, the bar moves nothing, and
// neither may the pocket — otherwise the most common failed gesture on the
// bar would silently empty the pocket.
check("a member released off the bar stays",
  drop({ sourceId: "omaplug", hasTarget: false }), "none")

// One negative fixture per refusal, so each guard is seen refusing rather
// than assumed to.
check("the pocket refuses to hold itself",
  drop({ sourceId: SELF, targetIsSelf: true, innerEdge: true }), "none")
check("and refuses itself from the other side too",
  drop({ sourceId: SELF, targetIsSelf: true, innerEdge: false }), "none")
check("the pocket refuses the center anchor",
  drop({ sourceId: "omarchy.clock", targetIsSelf: true, innerEdge: true }), "none")
check("and refuses it from the other side too",
  drop({ sourceId: "omarchy.clock", targetIsSelf: true, innerEdge: false }), "none")
check("a widget that merely shares the anchor's name pattern is fine",
  drop({ sourceId: "omarchy.clockwork", targetIsSelf: true, innerEdge: true }), "add")
check("with no anchor set, nothing is refused for being one",
  Model.dropDecision({ sourceId: "omarchy.clock", selfId: SELF, anchorId: "",
    members: [], targetIsSelf: true, innerEdge: true, hasTarget: true }), "add")
check("a drag with no source decides nothing", drop({ sourceId: "" }), "none")
check("an empty state decides nothing", Model.dropDecision({}), "none")
check("no state at all decides nothing", Model.dropDecision(undefined), "none")

// --------------------------------------------------------- config write

function layoutFixture() {
  return { version: 1, bar: { position: "top", layout: {
    left: [{ id: "omarchy.menu" }],
    right: [{ id: "omarchy.tray" }, { id: SELF, members: ["a"], showCount: true }]
  } } }
}

{
  const config = layoutFixture()
  check("the write reports it found the entry",
    Model.setMembersOnEntry(config, "right", SELF, "a, b"), true)
  check("members is what was written",
    config.bar.layout.right[1].members, "a, b")
  // The user's file is not ours to tidy. Anything else on the entry — a
  // setting from an older version, a key we have never heard of — stays.
  check("every other key on the entry survives",
    config.bar.layout.right[1].showCount, true)
  check("no neighbouring entry is touched",
    config.bar.layout.right[0], { id: "omarchy.tray" })
}

{
  const config = { bar: { layout: { right: ["omarchy.tray", SELF] } } }
  check("a bare string entry is promoted to an object",
    Model.setMembersOnEntry(config, "right", SELF, "a"), true)
  check("the promoted entry keeps its id",
    config.bar.layout.right[1], { id: SELF, members: "a" })
  check("the neighbouring string entry is left as a string",
    config.bar.layout.right[0], "omarchy.tray")
}

// The README promises that the only thing Pocket writes is its own entry. A
// refusal therefore has to leave the file byte-for-byte alone -- scaffolding a
// missing section would be the host's business, not a plugin's, and would make
// that promise false. Each of these checks the return value AND that nothing
// moved.
function untouched(label, config, mutate) {
  const before = JSON.stringify(config)
  check(label, mutate(config), false)
  check(label + " — and the config is untouched", JSON.stringify(config), before)
}

untouched("an entry that is not in the region is reported, not invented",
  layoutFixture(), c => Model.setMembersOnEntry(c, "center", SELF, "a"))
untouched("a region that is not a list is refused",
  { bar: { layout: { right: "not an array" } } },
  c => Model.setMembersOnEntry(c, "right", SELF, "a"))
untouched("a config with no bar at all is refused, not scaffolded",
  {}, c => Model.setMembersOnEntry(c, "right", SELF, "a"))
untouched("a config whose layout is not an object is refused",
  { bar: { layout: 7 } }, c => Model.setMembersOnEntry(c, "right", SELF, "a"))
untouched("an empty id is refused",
  layoutFixture(), c => Model.setMembersOnEntry(c, "right", "", "a"))
untouched("a missing section is refused by the placement repair too",
  {}, c => Model.placeMemberBesideSelf(c, "right", "a", SELF, true))

check("a config that is not an object is refused",
  Model.setMembersOnEntry(null, "right", SELF, "a"), false)

// ---------------------------------------------------- placement repair

const RIGHT_IDS = ["omarchy.tray", "mehiel.darky", "omaplug", SELF, "jerome.focus", "omarchy.bluetooth"]

check("a run entirely on the right side of the pocket is intact",
  Model.firstMisplacedMember(RIGHT_IDS, SELF, ["mehiel.darky", "omaplug"], true), "")
check("a member past the pocket is named",
  Model.firstMisplacedMember(RIGHT_IDS, SELF, ["mehiel.darky", "omarchy.bluetooth"], true),
  "omarchy.bluetooth")
check("the first one is named, not all of them",
  Model.firstMisplacedMember(RIGHT_IDS, SELF, ["jerome.focus", "omarchy.bluetooth"], true),
  "jerome.focus")
// Mirrored: in a left section the members sit after the pocket, so being
// before it is the mistake.
check("in a left section the sides are mirrored",
  Model.firstMisplacedMember(RIGHT_IDS, SELF, ["jerome.focus"], false), "")
check("and a member before the pocket is the mistake there",
  Model.firstMisplacedMember(RIGHT_IDS, SELF, ["mehiel.darky"], false), "mehiel.darky")
// A member in another section is a different mistake and the tooltip already
// names it; repairing it by moving it here would be an unasked-for edit.
check("a member the region does not hold is skipped",
  Model.firstMisplacedMember(RIGHT_IDS, SELF, ["omarchy.clock"], true), "")
check("a pocket that is not in the region reports nothing",
  Model.firstMisplacedMember(["a", "b"], SELF, ["a"], true), "")
check("no members, nothing misplaced",
  Model.firstMisplacedMember(RIGHT_IDS, SELF, [], true), "")

{
  const config = { bar: { layout: { right: [
    { id: "omarchy.tray" }, { id: "mehiel.darky" }, { id: SELF },
    { id: "jerome.focus" }, { id: "omarchy.bluetooth", quirk: 1 }] } } }
  check("a member past the pocket is moved back against it",
    Model.placeMemberBesideSelf(config, "right", "omarchy.bluetooth", SELF, true), true)
  check("it now sits directly before the pocket",
    config.bar.layout.right.map(Model.entryIdOf),
    ["omarchy.tray", "mehiel.darky", "omarchy.bluetooth", SELF, "jerome.focus"])
  check("and it was moved, not rebuilt",
    config.bar.layout.right[2].quirk, 1)
  // Idempotent, which is what stops the invariant from oscillating.
  check("a second pass moves nothing",
    Model.placeMemberBesideSelf(config, "right", "omarchy.bluetooth", SELF, true), false)
}

{
  const config = { bar: { layout: { left: [
    { id: "b" }, { id: SELF }, { id: "a" }] } } }
  check("a left-section member before the pocket is moved",
    Model.placeMemberBesideSelf(config, "left", "b", SELF, false), true)
  check("and lands directly after it",
    config.bar.layout.left.map(Model.entryIdOf), [SELF, "b", "a"])
}

// ADR 0002 claims the invariant converges. One misplaced member proves
// nothing about that; this drives the real loop -- find one, move it, look
// again -- with three of them scattered among widgets that are not members.
{
  const members = ["a", "b", "c"]
  const config = { bar: { layout: { right: [
    { id: "x" }, { id: "b" }, { id: SELF }, { id: "y" },
    { id: "a" }, { id: "z" }, { id: "c" }] } } }
  let passes = 0
  for (;;) {
    const ids = config.bar.layout.right.map(Model.entryIdOf)
    const stray = Model.firstMisplacedMember(ids, SELF, members, true)
    if (stray === "") break
    if (++passes > 10) break
    Model.placeMemberBesideSelf(config, "right", stray, SELF, true)
  }
  check("three misplaced members converge", passes, 2)
  check("and every member ends up before the pocket, non-members undisturbed",
    config.bar.layout.right.map(Model.entryIdOf),
    ["x", "b", "a", "c", SELF, "y", "z"])
}

check("a member already on the correct side is left alone",
  Model.placeMemberBesideSelf({ bar: { layout: { right: [{ id: "a" }, { id: SELF }] } } },
    "right", "a", SELF, true), false)
check("an entry that is not there is not invented",
  Model.placeMemberBesideSelf({ bar: { layout: { right: [{ id: SELF }] } } },
    "right", "a", SELF, true), false)
check("a pocket that is not there is refused",
  Model.placeMemberBesideSelf({ bar: { layout: { right: [{ id: "a" }] } } },
    "right", "a", SELF, true), false)
check("the pocket refuses to move itself",
  Model.placeMemberBesideSelf({ bar: { layout: { right: [{ id: SELF }] } } },
    "right", SELF, SELF, true), false)
check("a config that is not an object is refused",
  Model.placeMemberBesideSelf(null, "right", "a", SELF, true), false)

// ------------------------------------------------------- entry counting

// The bug this replaces: bar.moduleWidgets() counts live instances, and the
// bar is built once per monitor. On the three-monitor session this was
// measured on, a single pocket entry reported as three and the tooltip
// claimed a second pocket that does not exist.
const LAYOUT = { left: [{ id: "omarchy.menu" }], center: [{ id: "omarchy.clock" }],
                 right: [{ id: "omarchy.tray" }, { id: SELF }] }

check("one entry counts once", Model.countEntries(LAYOUT, SELF), 1)
check("an id that is not in the layout counts zero",
  Model.countEntries(LAYOUT, "nope"), 0)
check("a second entry in the same region is counted",
  Model.countEntries({ right: [{ id: SELF }, { id: SELF }] }, SELF), 2)
check("a second entry in another region is counted",
  Model.countEntries({ left: [SELF], right: [{ id: SELF }] }, SELF), 2)
check("bare string entries count too",
  Model.countEntries({ right: [SELF] }, SELF), 1)
check("a region that is not a list is skipped, not crashed on",
  Model.countEntries({ right: "nope", left: [{ id: SELF }] }, SELF), 1)
check("no layout counts zero", Model.countEntries(undefined, SELF), 0)
check("an empty id counts zero", Model.countEntries(LAYOUT, ""), 0)

// The README carries this as a promise -- while a second pocket exists,
// neither writes anything at all -- so it gets a test rather than living as a
// condition inside a handler where nothing can see it.
check("one pocket may write", Model.mayWrite(LAYOUT, SELF), true)
check("two pockets may not",
  Model.mayWrite({ right: [{ id: SELF }, { id: SELF }] }, SELF), false)
check("two pockets in different regions may not either",
  Model.mayWrite({ left: [SELF], right: [{ id: SELF }] }, SELF), false)
// Not yet mounted is not the same as duplicated: a pocket that cannot find
// itself must still be allowed to write, or the very first drag would be
// refused on a bar whose layout has not been handed over yet.
check("a pocket the layout does not hold yet may write",
  Model.mayWrite(LAYOUT, "nope"), true)
check("no layout at all may write", Model.mayWrite(null, SELF), true)

// --------------------------------------------------- manifest integrity

// BarModel.customModuleType() infers a custom module from the entry's own keys:
// `exec` means a command module, `source` means a bare qml file, and `type` is
// taken literally. Any of them on a plugin entry makes Bar.qml skip registry
// resolution, and the slot renders as an empty item with no warning anywhere.
// The bar copies EVERY key of the entry except `id` into `settings`, so a
// reserved key in `defaults` or `schema` reaches the entry and disarms the
// plugin. One assertion per reserved word, and one negative fixture per word so
// the guard is seen failing rather than assumed to work.
const RESERVED = ["type", "exec", "source"]

function settingKeys(manifest) {
  const meta = (manifest && manifest.barWidget) || {}
  const keys = Object.keys(meta.defaults || {})
  for (const entry of meta.schema || []) {
    if (entry && typeof entry.key === "string") keys.push(entry.key)
  }
  return keys
}

function reservedKeysIn(manifest) {
  return settingKeys(manifest).filter(k => RESERVED.indexOf(k) !== -1).sort()
}

const manifest = JSON.parse(fs.readFileSync(path.join(ROOT, "manifest.json"), "utf8"))

check("manifest id", manifest.id, "jrmmhm.pocket")
check("manifest schema version", manifest.schemaVersion, 1)
check("manifest declares one kind", manifest.kinds, ["bar-widget"])
check("manifest entry point", manifest.entryPoints.barWidget, "BarWidget.qml")
check("entry point file exists", fs.existsSync(path.join(ROOT, manifest.entryPoints.barWidget)), true)
check("default section is a real section",
  ["left", "center", "right"].indexOf(manifest.barWidget.defaultSection) !== -1, true)
check("only one pocket per bar", manifest.barWidget.allowMultiple, false)

check("the shipped manifest reserves nothing", reservedKeysIn(manifest), [])

for (const word of RESERVED) {
  check(`a '${word}' key in defaults is caught`,
    reservedKeysIn({ barWidget: { defaults: { [word]: "x" } } }), [word])
  check(`a '${word}' key in schema is caught`,
    reservedKeysIn({ barWidget: { schema: [{ key: word }] } }), [word])
}

// ----------------------------------------------------------------- done

if (failures === 0) {
  console.log(`ALL TESTS PASSED (${assertions} assertions, 0 failures)`)
  process.exit(0)
}
console.log(`TESTS FAILED (${failures} failures out of ${assertions} assertions)`)
process.exit(1)
