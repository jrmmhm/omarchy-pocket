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

// ------------------------------------------------------------- counting

check("zero hides the count", Model.countText(0, true), "")
check("negative hides the count", Model.countText(-3, true), "")
check("count is shown", Model.countText(4, true), "4")
check("showCount false hides it", Model.countText(4, false), "")
check("garbage counts as zero", Model.countText("nonsense", true), "")

// -------------------------------------------------------------- tooltip

contains("empty pocket asks for members",
  Model.describe({ members: [] }), "set `members`")
contains("collapsed pocket names its size",
  Model.describe({ members: ["a", "b"] }), "holding 2 widgets")
check("one member is singular",
  Model.describe({ members: ["a"] }).split("\n")[0], "Pocket holding 1 widget")
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
