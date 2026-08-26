// Pure logic for the Pocket bar widget. Everything here is decidable without a
// running shell, which is what makes it testable — the QML side keeps only the
// parts that need live objects.
//
// Loaded from BarWidget.qml as `import "Model.js" as Model` and from
// tests/model-test.js as a CommonJS module.

// Widget ids as the shell writes them: omarchy.audio, jerome.focus, omaplug,
// omarchy-overview. Anchored on both ends, because a half-matching id would
// resolve to nothing and look like a typo the user cannot see.
var ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/

function isWidgetId(value) {
  return typeof value === "string" && ID_PATTERN.test(value)
}

// The `members` setting is written by hand in shell.json or through Omarchy's
// settings form. The form can only produce a string, so both shapes have to
// work: ["omarchy.audio", "omaplug"] and "omarchy.audio, omaplug".
//
// Deliberately not Array.isArray(). The bar parses shell.json into a
// QVariantList and injects it, and what arrives in QML is a sequence type that
// indexes and reports `length` like an array while failing Array.isArray().
// Measured on 2026-08-26: an array-valued `members` parsed as nothing at all,
// silently, and the pocket rendered an empty count over a bar it never touched.
// Duck-typing is the fix; the string case is tested first because a string
// carries `length` too.
function toList(value) {
  if (value === null || value === undefined) return []
  if (typeof value === "string") return value.split(/[,\s]+/)
  if (typeof value.length !== "number") return []

  var out = []
  for (var i = 0; i < value.length; i++) {
    var entry = value[i]
    if (typeof entry === "string") out.push(entry)
    else if (entry && typeof entry.id === "string") out.push(entry.id)
  }
  return out
}

// Order is the user's; duplicates and the pocket's own id are dropped. Naming
// itself would make the pocket hide the slot it lives in, and there would then
// be nothing left to hover.
function parseMembers(value, selfId) {
  var raw = toList(value)
  var self = typeof selfId === "string" ? selfId : ""
  var seen = {}
  var out = []
  for (var i = 0; i < raw.length; i++) {
    var id = String(raw[i]).trim()
    if (id === "" || id === self) continue
    if (!isWidgetId(id)) continue
    if (seen[id]) continue
    seen[id] = true
    out.push(id)
  }
  return out
}

// Ids the user wrote that this function refused, so the tooltip can name them
// instead of leaving the user with a pocket that quietly holds less than asked.
function rejectedMembers(value, selfId) {
  var raw = toList(value)
  var self = typeof selfId === "string" ? selfId : ""
  var out = []
  for (var i = 0; i < raw.length; i++) {
    var id = String(raw[i]).trim()
    if (id === "" || id === self) continue
    if (isWidgetId(id)) continue
    out.push(id)
  }
  return out
}

// Each member's own share of the reveal, so they cascade out of the pocket
// instead of all arriving at once. `index` counts from the member nearest the
// pocket, which is the one that should lead.
//
// The stagger shrinks as the pocket fills: four members at 0.15 each still
// leave every one of them 55% of the run to travel, while a dozen at 0.15
// would leave the last one no time at all. Falling progress reverses the
// cascade for free — the nearest member is the last one to fade.
function revealFraction(progress, index, count, maxStagger) {
  var p = Number(progress)
  if (!isFinite(p)) p = 0
  p = Math.max(0, Math.min(1, p))

  var n = Math.max(1, Math.floor(Number(count)) || 1)
  var i = Math.max(0, Math.min(n - 1, Math.floor(Number(index)) || 0))
  var limit = maxStagger === undefined ? 0.15 : Number(maxStagger)
  var stagger = n > 1 ? Math.min(limit, 0.6 / (n - 1)) : 0
  var span = 1 - stagger * (n - 1)
  if (span <= 0) return p

  return Math.max(0, Math.min(1, (p - stagger * i) / span))
}

// One tooltip line per condition, most actionable first. The pocket is the only
// place these problems surface: a member that never appears produces no error
// anywhere else in the shell.
function describe(state) {
  var s = state || {}
  var members = s.members || []
  var lines = []

  if (members.length === 0) {
    lines.push("Pocket is empty — set `members` on its bar entry")
  } else if (s.expanded) {
    lines.push("Pocket open — click to keep it open")
  } else {
    lines.push("Pocket holding " + members.length + " widget" + (members.length === 1 ? "" : "s"))
  }

  if (s.pinned) lines.push("Pinned — click to release")
  if ((s.rejected || []).length > 0) lines.push("Not a widget id: " + s.rejected.join(", "))
  if ((s.missing || []).length > 0) lines.push("Not on this bar: " + s.missing.join(", "))
  if ((s.anchored || []).length > 0) lines.push("Refused, it is the center anchor: " + s.anchored.join(", "))
  if ((s.foreign || []).length > 0) lines.push("In another section, so hiding it looks arbitrary: " + s.foreign.join(", "))
  if (s.duplicateInstances) lines.push("A second Pocket entry exists — they will fight over shared members")

  return lines.join("\n")
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { isWidgetId: isWidgetId, toList: toList, parseMembers: parseMembers,
                     rejectedMembers: rejectedMembers, revealFraction: revealFraction,
                     describe: describe }
}
