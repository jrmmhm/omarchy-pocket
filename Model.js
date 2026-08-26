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
function toList(value) {
  if (Array.isArray(value)) {
    var out = []
    for (var i = 0; i < value.length; i++) {
      var entry = value[i]
      if (typeof entry === "string") out.push(entry)
      else if (entry && typeof entry.id === "string") out.push(entry.id)
    }
    return out
  }
  if (typeof value === "string") return value.split(/[,\s]+/)
  return []
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

function countText(count, show) {
  if (show === false) return ""
  var n = Math.max(0, Math.floor(Number(count) || 0))
  return n > 0 ? String(n) : ""
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
                     rejectedMembers: rejectedMembers, countText: countText, describe: describe }
}
