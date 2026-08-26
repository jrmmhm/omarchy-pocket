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

contains("empty pocket asks for members",
  Model.describe({ members: [] }), "set `members`")
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
