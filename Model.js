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

// ------------------------------------------------------------ membership

// The bar hands entries over as plain objects after a JSON round-trip, but a
// hand-written shell.json may still carry a bare id string. Both shapes have
// to answer "which widget is this".
function entryIdOf(entry) {
  if (typeof entry === "string") return entry.trim()
  if (entry && typeof entry === "object" && typeof entry.id === "string") return entry.id.trim()
  return ""
}

function isPlainObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

// Members are kept in the order their widgets physically sit on the bar, not
// in the order they were added. The cascade in applyReveal() counts from the
// member nearest the pocket outwards; if the list disagreed with the layout,
// the animation would run in a direction that does not exist on screen. The
// bar decides where a dropped widget lands, so the list follows the bar.
//
// Ids the layout does not know — a typo the user has not fixed yet — keep
// their relative order and collect at the end rather than being dropped.
function orderMembers(list, layoutIds) {
  var rank = {}
  var ids = layoutIds || []
  for (var i = 0; i < ids.length; i++) {
    var key = String(ids[i]).trim()
    if (key !== "" && !(key in rank)) rank[key] = i
  }

  // One rank past the last known position, so every unknown id shares a rank
  // and falls through to its original index. A sentinel that had to be
  // special-cased in the comparator instead produced a comparator that could
  // report a < b and b < a at once; a four-element array still came out right
  // by luck, which is exactly the kind of green that means nothing.
  var unknown = ids.length
  var decorated = []
  var source = list || []
  for (var j = 0; j < source.length; j++) {
    var id = String(source[j]).trim()
    decorated.push({ value: source[j], rank: id in rank ? rank[id] : unknown, at: j })
  }

  // The `at` tiebreak is not redundant even though ES2019 requires a stable
  // sort: this file also runs in Qt's V4 engine, which makes no such promise.
  // node cannot show the difference, so no test can either — it is here on the
  // engine's terms, not the test suite's.
  decorated.sort(function (a, b) {
    return a.rank === b.rank ? a.at - b.at : a.rank - b.rank
  })

  var out = []
  for (var k = 0; k < decorated.length; k++) out.push(decorated[k].value)
  return out
}

// Operates on the RAW list — what the user actually wrote — and never on the
// parsed one. Round-tripping through parseMembers would quietly delete the
// very ids the tooltip is at that moment asking the user to fix.
function withoutMember(rawList, id) {
  var drop = String(id || "").trim()
  var out = []
  var source = rawList || []
  for (var i = 0; i < source.length; i++) {
    if (drop !== "" && String(source[i]).trim() === drop) continue
    out.push(source[i])
  }
  return out
}

// The member list a finished drag leaves behind.
//
// The layout is consulted only for the members that did NOT move, because the
// pocket writes before the bar does: at this moment the dragged widget is
// still recorded at its old position, and ranking it there would put it at the
// wrong end of the list. Its new position is not a guess — dropping on the
// inner edge lands it against the pocket, which is the near end of the run by
// definition. So order the survivors by the layout and append the newcomer to
// the end that faces the pocket.
function nextMembers(rawList, layoutIds, id, intent, nearestAtEnd) {
  var ordered = orderMembers(withoutMember(rawList, id), layoutIds)
  if (intent !== "add") return ordered

  var want = String(id || "").trim()
  if (want === "") return ordered
  return nearestAtEnd ? ordered.concat([want]) : [want].concat(ordered)
}

// Write back the shape that was found. A user who wrote a comma string gets a
// comma string; one who wrote an array keeps an array. With nothing to
// preserve the string wins, because that is what manifest.json declares the
// setting to be.
function membersValue(list, previousRaw) {
  var items = []
  var source = list || []
  for (var i = 0; i < source.length; i++) {
    var id = String(source[i]).trim()
    if (id !== "") items.push(id)
  }

  if (previousRaw !== null && previousRaw !== undefined && typeof previousRaw !== "string"
      && typeof previousRaw.length === "number") {
    return items
  }
  return items.join(", ")
}

// What a finished drag means for membership. Deliberately expressed in terms
// of the bar's own drop target rather than pointer coordinates: barDragTarget
// and barDragAfter are the two values Bar.qml already uses to draw its drop
// marker, so the pocket's answer and the line the user is looking at can never
// disagree. Comparing the target against this instance's own slot is an object
// identity test, which is correct per monitor and per center-anchor duplicate
// without mapping a single coordinate.
//
// The rule in one sentence: dropping a widget onto the pocket puts it in, and
// dragging a member past the pocket takes it out.
function dropDecision(state) {
  var s = state || {}
  var source = String(s.sourceId || "").trim()
  if (source === "") return "none"

  // Naming itself would hide the slot it lives in. Naming the center anchor
  // would be refused later anyway — refusing it here keeps a permanent
  // complaint out of the user's config instead of writing one into it.
  if (source === String(s.selfId || "")) return "none"
  if (s.anchorId && source === String(s.anchorId)) return "none"

  var members = s.members || []
  var isMember = false
  for (var i = 0; i < members.length; i++) {
    if (String(members[i]).trim() === source) { isMember = true; break }
  }

  if (s.targetIsSelf === true) {
    // Onto the pocket means in, from either side. Splitting the icon so that
    // its two halves meant opposite things was measured on a real bar and felt
    // wrong for the obvious reason: half of the thing you are aiming at did
    // the opposite of what aiming at it looks like.
    if (!isMember) return "add"

    // For something already inside, the far side is the way out — dragging it
    // past the pocket is how leaving a group looks. The near side is just
    // reordering within the run.
    return s.innerEdge === true ? "none" : "remove"
  }

  // Leaving needs somewhere to land. A drag released off the bar produces no
  // target at all, the bar moves nothing, and neither does the pocket.
  if (isMember && s.hasTarget === true && s.targetIsMember !== true) return "remove"

  return "none"
}

// ------------------------------------------------------------- config write

// Set `members` on this plugin's own entry inside a raw shell.json, mirroring
// Bar.qml's own rawLayoutSection(): the config reaching a mutator is whatever
// the user's file holds, so the region may be missing, may not be an array,
// and its entries may be bare id strings. Every other key on the entry is left
// exactly as it was. Reports whether an entry was found at all.
function setMembersOnEntry(config, region, id, value) {
  if (!isPlainObject(config)) return false
  var want = String(id || "").trim()
  if (want === "") return false

  if (!isPlainObject(config.bar)) config.bar = {}
  if (!isPlainObject(config.bar.layout)) config.bar.layout = {}
  if (!Array.isArray(config.bar.layout[region])) config.bar.layout[region] = []

  var entries = config.bar.layout[region]
  for (var i = 0; i < entries.length; i++) {
    if (entryIdOf(entries[i]) !== want) continue
    if (!isPlainObject(entries[i])) entries[i] = { id: want }
    entries[i].members = value
    return true
  }
  return false
}

// How many entries the layout holds for one widget id. This is the honest
// answer to "is there a second pocket": bar.moduleWidgets() counts live
// instances, and the bar is built once per monitor — plus a second time for
// every center widget when centerAnchor is set — so it reports a duplicate on
// any setup with more than one screen.
function countEntries(layout, id) {
  var want = String(id || "").trim()
  if (want === "") return 0

  var regions = ["left", "center", "right"]
  var total = 0
  for (var r = 0; r < regions.length; r++) {
    var entries = layout ? layout[regions[r]] : null
    if (!entries || typeof entries.length !== "number") continue
    for (var i = 0; i < entries.length; i++) if (entryIdOf(entries[i]) === want) total++
  }
  return total
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
  var rejected = s.rejected || []
  var missing = s.missing || []
  var anchored = s.anchored || []
  var foreign = s.foreign || []

  // What the pocket actually holds, not what it was asked to hold. Counting the
  // configuration would let the first line say "holding 3 widgets" directly
  // above three lines explaining that none of them could be used — and this
  // tooltip is the only place any of that surfaces.
  var held = Math.max(0, members.length - missing.length - anchored.length)
  var lines = []

  if (members.length === 0) {
    lines.push("Pocket is empty — drag a widget onto its inner edge, or set `members` on its bar entry")
  } else if (held === 0) {
    lines.push("Pocket holding nothing — none of the widgets it names can be used")
  } else if (s.expanded) {
    lines.push("Pocket open — click to keep it open")
  } else {
    lines.push("Pocket holding " + held + " widget" + (held === 1 ? "" : "s"))
  }

  if (s.pinned) lines.push("Pinned — click to release")
  if (rejected.length > 0) lines.push("Not a widget id: " + rejected.join(", "))
  if (missing.length > 0) lines.push("Not on this bar: " + missing.join(", "))
  if (anchored.length > 0) lines.push("Refused, it is the center anchor: " + anchored.join(", "))
  if (foreign.length > 0) lines.push("In another section, so hiding it looks arbitrary: " + foreign.join(", "))
  if (s.duplicateInstances) lines.push("A second Pocket entry exists — they will fight over shared members")

  return lines.join("\n")
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { isWidgetId: isWidgetId, toList: toList, parseMembers: parseMembers,
                     rejectedMembers: rejectedMembers, revealFraction: revealFraction,
                     describe: describe, entryIdOf: entryIdOf, orderMembers: orderMembers,
                     withoutMember: withoutMember, nextMembers: nextMembers,
                     membersValue: membersValue, dropDecision: dropDecision,
                     setMembersOnEntry: setMembersOnEntry, countEntries: countEntries }
}
