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
//
// The list it is building is also what it asks about duplicates. A lookup
// object was the obvious tool and the wrong one: an id is a name, and on a bare
// object some names answer before anything has been put there -- `"toString" in
// {}` is true, and so are `constructor`, `valueOf` and four more, every one of
// which ID_PATTERN accepts. Each was refused as a duplicate it had never seen,
// and refused HERE, upstream of rejectedMembers(), so the tooltip named nothing
// and the member simply was not on the bar. Asking the output list costs a
// linear scan over a run that is four widgets long in every real config, and
// there is no second structure left to disagree with it.
function parseMembers(value, selfId) {
  var raw = toList(value)
  var self = typeof selfId === "string" ? selfId : ""
  var out = []
  for (var i = 0; i < raw.length; i++) {
    var id = String(raw[i]).trim()
    if (id === "" || id === self) continue
    if (!isWidgetId(id)) continue
    if (out.indexOf(id) !== -1) continue
    out.push(id)
  }
  return out
}

// The entries toList() could not read at all -- neither a string nor an object
// carrying a string `id` -- named by their position in the list, 1-based
// because that is how a person counts a JSON array.
//
// A position rather than a value, because the whole reason such an entry was
// dropped is that it carries nothing quotable: `{"name": "omaplug"}` and `42`
// have no id to print back at the user. The position is what finds it again in
// shell.json, which is the same job rejectedMembers() does for a value it can
// still show.
//
// It exists because toList() runs BEFORE rejectedMembers(), so these entries
// were gone before anything could name them: a `members` list made entirely of
// them left the tooltip saying "Pocket is empty" to a user who had written
// four. A `members` value that is not a list at all is the same mistake with
// one entry, and answers as that entry -- which is the place to look.
function unreadableEntries(value) {
  if (value === null || value === undefined) return []
  if (typeof value === "string") return []
  if (typeof value.length !== "number") return [1]

  var out = []
  for (var i = 0; i < value.length; i++) {
    var entry = value[i]
    if (typeof entry === "string") continue
    if (entry && typeof entry.id === "string") continue
    out.push(i + 1)
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

// --------------------------------------------------------------- surface

// Whether a bar slot belongs to the surface this pocket lives on.
//
// `Bar.qml` is one object with a window per screen, and every surface's slots
// land in one shared array, so this comparison is the only thing keeping one
// screen's pocket off another screen's widgets. The host owns the comparison
// itself; what belongs here is what to do when its answer is not available.
//
// An instance that does not know its own window matches NOTHING. It used to
// match everything — the comparison was skipped whenever the window was null —
// and null is reachable twice over: a dying instance loses its window while its
// bindings are still live, and a live surface loses its window for as long as a
// monitor move unmaps it. Either way the instance adopted another screen's
// slots, and handed them back visible on the way out. The host's own
// sameWindow() already answers this way; only the caller disagreed.
// docs/decisions/0005 has both paths, their sources, and what each costs.
//
// A host that cannot tell its surfaces apart at all is the separate, older
// case: there is one answer to give and the pocket gives it, which is the
// single-surface degradation a custom bar has always been offered. It is asked
// second on purpose, so that a caller which forgot to say what it knows gets
// the refusal rather than the old answer.
function ownsSlot(state) {
  var s = state || {}
  if (s.surfaceKnown !== true) return false
  if (s.hostComparesWindows !== true) return true
  return s.sameWindow === true
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
  // The layout's own ids, normalised once. A rank is a position in this list,
  // and indexOf() answers with the FIRST one, which is the rule a repeated
  // layout id needs.
  //
  // This used to be a lookup object, and it failed the way parseMembers() did,
  // one step further along. The guard that kept the first index of a repeated
  // id, `!(key in rank)`, answers true for a name nothing put there, so an id
  // called `toString` or `valueOf` never got a rank and the comparator
  // subtracted a function: NaN. What NaN does to a sort is the engine's
  // business, and the two engines this file runs in disagree -- V8 leaves the
  // order alone, Qt's V4 does not, and in V4 the result had no fixpoint at all.
  // membersInLayoutOrder() then answered false for ever and repairMemberOrder()
  // wrote a different wrong order into the user's shell.json on every bar
  // rebuild. tests/qml/model.qml runs the fixtures in the engine that showed it.
  var ids = layoutIds || []
  var known = []
  for (var i = 0; i < ids.length; i++) known.push(String(ids[i]).trim())

  // One rank past the last known position, so every unknown id shares a rank
  // and falls through to its original index. A sentinel that had to be
  // special-cased in the comparator instead produced a comparator that could
  // report a < b and b < a at once; a four-element array still came out right
  // by luck, which is exactly the kind of green that means nothing.
  var unknown = known.length
  var decorated = []
  var source = list || []
  for (var j = 0; j < source.length; j++) {
    var id = String(source[j]).trim()
    // An empty id is unknown rather than looked up: the layout can hold an
    // empty entry too, and matching those to each other would rank a member on
    // a slot that names nothing.
    var at = id === "" ? -1 : known.indexOf(id)
    decorated.push({ value: source[j], rank: at === -1 ? unknown : at, at: j })
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

// Whether the member list already sits in the order the widgets physically do.
// Deliberately asked as "would orderMembers() change anything", so that the
// check and the repair can never disagree about what "in order" means.
//
// It has to be checked on sight rather than folded into a gesture: reordering
// a member inside the run moves widgets without this pocket writing anything
// at all, and the cascade in applyReveal() counts from the member nearest the
// pocket outwards — a list that disagrees with the layout animates in a
// direction that does not exist on screen.
function membersInLayoutOrder(rawList, layoutIds) {
  var source = rawList || []
  var ordered = orderMembers(source, layoutIds)
  for (var i = 0; i < source.length; i++) {
    if (String(ordered[i]).trim() !== String(source[i]).trim()) return false
  }
  return true
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
// wrong end of the list. Its new position is not a guess either: a widget
// aimed at the pocket ends up against the pocket, which is the near end of the
// run by definition — whether the drop steering placed it there directly or
// the placement invariant pulled it back afterwards, the end of the run it
// belongs to is the same one. So order the survivors by the layout and append
// the newcomer to the end that faces the pocket.
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

// Whether the gap the bar is drawing its insertion line in has one of this
// pocket's members against it, on either side.
//
// The user aims at a gap, and a gap has two slots against it. Asking which of
// the two the bar picked is what made the membership rule wrong twice over.
//
// BarModel.nearestDropTarget resolves to the candidate with the nearest edge,
// and adjacent slots share a gap — so the gap at the outer end of the run came
// back as the neighbour outside it or as the first member inside it, on a
// sub-pixel tie, and those two answers meant opposite things. And the answer
// was drawn from the pocket's resolved member slots, which every instance
// filters to its own window: on a multi-monitor bar the instance the drag was
// not on saw every member as a stranger and concluded the member was leaving.
//
// Ids out of the layout have neither problem. They are the same on every
// screen, and they describe both sides of the gap rather than one of them.
// See docs/decisions/0004.
function gapTouchesMember(layoutIds, memberIds, targetId, after) {
  var ids = layoutIds || []
  var want = String(targetId || "").trim()
  if (want === "") return false

  var at = -1
  for (var i = 0; i < ids.length; i++) {
    if (String(ids[i]).trim() === want) { at = i; break }
  }
  if (at === -1) return false
  if (after) at += 1

  // The two range guards are on the engine's terms, not the test suite's. In
  // node an out-of-range index is undefined and falls out harmlessly; the
  // layout reaching this from QML is a sequence type, which is not obliged to
  // be so forgiving. node cannot show the difference, so no test can either —
  // the same reason the tiebreak in orderMembers() carries a comment instead
  // of a fixture.
  var before = at > 0 ? String(ids[at - 1]).trim() : ""
  var behind = at < ids.length ? String(ids[at]).trim() : ""

  var members = memberIds || []
  for (var m = 0; m < members.length; m++) {
    var id = String(members[m]).trim()
    if (id === "") continue
    if (id === before || id === behind) return true
  }
  return false
}

// What a finished drag means for membership. Deliberately expressed in terms
// of the bar's own drop marker rather than pointer coordinates: barDragTarget
// and barDragAfter are the two values Bar.qml already uses to draw the line,
// so the pocket's answer and the line the user is looking at can never
// disagree.
//
// The rule in two sentences: aiming at the pocket takes a widget in, from
// either side; and a member stays in for as long as the line is drawn against
// the group.
//
// Only `targetIsSelf` is an object identity test, and only the `add` branch
// consults it. That is what keeps it safe on a bar built once per monitor: the
// instance that is not being aimed at falls through to doing nothing, rather
// than to acting on a conclusion the other instances did not reach. Everything
// the membership branch reads is an id, identical on every screen.
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

  // Onto the pocket means in, from either side. Splitting the icon so that its
  // two halves meant opposite things was measured on a real bar and felt wrong
  // for the obvious reason: half of the thing you are aiming at did the
  // opposite of what aiming at it looks like.
  if (!isMember) return s.targetIsSelf === true ? "add" : "none"

  // Leaving needs somewhere to land. A drag released off the bar produces no
  // target at all, the bar moves nothing, and neither does the pocket.
  if (s.hasTarget !== true) return "none"

  // Past the pocket, beyond the outer end of the run, or anywhere else on the
  // bar — in each of those the line is drawn in a gap with no member against
  // it, which is what leaving a group looks like. Everywhere inside the run,
  // including its outermost edge, it is a reorder.
  return s.gapTouchesMember === true ? "none" : "remove"
}

// --------------------------------------------------------- drop steering

// Which side of the pocket the bar should be told to place an arriving widget
// on, as { after: <bool> }, or null when the pocket must not touch the bar's
// drop marker at all. See docs/decisions/0003.
//
// Only `after === false` is ever returned, and that is a property of the host
// rather than a simplification. Bar.qml's dropBarModuleAtTarget() resolves
// `after === true` through nextVisibleModuleName(), which walks past every
// module that is not drawn — and a collapsed pocket's members are exactly
// that — so a widget steered that way lands at the far end of the run instead
// of against the pocket. `after === false` names the target slot itself and is
// exact. That is the side the members occupy wherever they lead from the end
// of the list, which is every section but `left`.
//
// The write permission is the same one that decides whether `members` may be
// written at all. Steering without writing would move a widget the user did
// not aim there and then not record it as a member.
//
// `aimedAtOwnSlot` is the bar naming this pocket's own slot as the drop target,
// and it is not implied by the intent: a widget aimed at the mark's near edge
// arms the pocket while `barDragTarget` still points at the widget drawn before
// it. Steering that would write a marker rect computed from THIS slot against a
// target that is the neighbour, and `dropBarModuleAtTarget()` resolves the
// placement from the target — the widget would land beside the neighbour while
// the bar drew its line at the mark. That is a single monitor's defect; on
// several it is also what keeps a drag on one screen from dragging the line
// onto another screen's pocket. See docs/decisions/0008.
function steerDropAfter(state) {
  var s = state || {}
  if (s.intent !== "add") return null
  if (s.aimedAtOwnSlot !== true) return null
  if (s.mayWrite !== true) return null
  if (s.nearestAtEnd !== true) return null
  return { after: false }
}

// The bar's drop marker as Bar.qml computes it: a plain {x, y, width, height}.
// Compared field by field because dropMarkerRect() returns a fresh object on
// every call, so reference equality is always false and the pocket would
// rewrite the marker on every pointer move forever.
function sameMarkerRect(a, b) {
  if (!a || !b) return false
  return a.x === b.x && a.y === b.y && a.width === b.width && a.height === b.height
}

// ------------------------------------------------------------- config write

// The entries of one layout section as the user's file actually holds them, or
// null. Deliberately NOT Bar.qml's rawLayoutSection(), which creates whatever
// is missing: the host may scaffold its own config, a plugin may not. If the
// section this pocket claims to live in is absent, the honest conclusion is
// that there is nothing here to edit — not that the file needs a new section.
function rawSection(config, region) {
  if (!isPlainObject(config)) return null
  if (!isPlainObject(config.bar)) return null
  if (!isPlainObject(config.bar.layout)) return null
  var entries = config.bar.layout[region]
  return Array.isArray(entries) ? entries : null
}

// Set `members` on this plugin's own entry inside a raw shell.json. The config
// reaching a mutator is whatever the user's file holds, so entries may be bare
// id strings. Every other key on the entry is left exactly as it was, and
// nothing outside the entry is touched. Reports whether it was found at all.
function setMembersOnEntry(config, region, id, value) {
  var want = String(id || "").trim()
  if (want === "") return false

  var entries = rawSection(config, region)
  if (entries === null) return false

  for (var i = 0; i < entries.length; i++) {
    if (entryIdOf(entries[i]) !== want) continue
    if (!isPlainObject(entries[i])) entries[i] = { id: want }
    entries[i].members = value
    return true
  }
  return false
}

// The first member sitting on the wrong side of the pocket, or "" if the run
// is intact. Members belong on one side — the side the pocket fans them out
// towards — and a member that is not there fans out alone on the wrong side of
// the icon while the rest of the group is on the other. steerDropAfter() keeps
// a far-side arrival from landing there wherever it applies; this is what
// guarantees the result when it does not.
//
// Ids the region does not hold are skipped rather than reported: a member in
// another section is a different mistake, and the tooltip already names it.
function firstMisplacedMember(layoutIds, selfId, memberIds, nearestAtEnd) {
  var ids = layoutIds || []
  var self = String(selfId || "").trim()
  if (self === "") return ""

  var selfAt = -1
  for (var i = 0; i < ids.length; i++) {
    if (String(ids[i]).trim() === self) { selfAt = i; break }
  }
  if (selfAt === -1) return ""

  var members = memberIds || []
  for (var m = 0; m < members.length; m++) {
    var want = String(members[m]).trim()
    if (want === "" || want === self) continue
    for (var j = 0; j < ids.length; j++) {
      if (String(ids[j]).trim() !== want) continue
      if (nearestAtEnd ? j > selfAt : j < selfAt) return want
      break
    }
  }
  return ""
}

// Move one entry so it sits directly against the pocket, on the side the
// members fan out towards. Reports whether it moved: a member already on the
// correct side is left exactly where the user put it, which is what keeps
// this from fighting the ordering inside the run.
function placeMemberBesideSelf(config, region, id, selfId, nearestAtEnd) {
  var want = String(id || "").trim()
  var self = String(selfId || "").trim()
  if (want === "" || self === "" || want === self) return false

  var entries = rawSection(config, region)
  if (entries === null) return false

  var from = -1
  var selfAt = -1
  for (var i = 0; i < entries.length; i++) {
    var eid = entryIdOf(entries[i])
    if (eid === want && from === -1) from = i
    if (eid === self && selfAt === -1) selfAt = i
  }
  if (from === -1 || selfAt === -1) return false
  if (nearestAtEnd ? from < selfAt : from > selfAt) return false

  var moved = entries.splice(from, 1)[0]
  var at = from < selfAt ? selfAt - 1 : selfAt
  entries.splice(nearestAtEnd ? at : at + 1, 0, moved)
  return true
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

// Whether this pocket is allowed to write at all. Two pockets sharing a member
// would fight over it, and the loser's write would land on the winner's entry
// — so neither writes. The README carries this as a promise, which is why it
// is a function with a test rather than a condition inside a handler.
function mayWrite(layout, selfId) {
  return countEntries(layout, selfId) <= 1
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

// ---------------------------------------------------------- tooltip text

// The plugin's text boundary. Everything a value contributes to the tooltip
// goes through here first, because the widget does not own the item that
// renders it: the string travels through Bar.qml's showTooltip() into a `Text`
// with no `textFormat`, which is `Text.AutoText`. Qt answers that with
// Qt::mightBeRichText(), and a positive answer means StyledText — which parses
// `<img src=…>` and loads it, over the network included. Qt's own documentation
// names two ways out, explicit `Text.PlainText` at the sink or stripping the
// content, and only the second one is a plugin's to take.
//
// Escaping to `&lt;` would be the wrong half of that advice. It is the answer
// for a sink known to be rich; against AutoText it is also a way IN, because
// mightBeRichText() returns true on an `&lt;` before the first line break. The
// `&` has to go, not just the `<` it introduces.
//
// Escapes rather than one replacement glyph, because the only reason this line
// exists is to let the user find the entry again in shell.json. A `<`, an `&`
// and a tab that all render as the same box are three mistakes nobody can tell
// apart. Backslash is escaped along with them, so every backslash in the output
// belongs to an escape this function wrote and no output can be read two ways.
// The cut is the one lossy step, and it says so with its own marker — it can
// land inside an escape, and what is left of one is ASCII letters and digits
// with an ellipsis behind them. See docs/decisions/0011.

// Written as code point ranges rather than as a character class, for two
// reasons that are both about being read. A regex literal full of escapes is a
// line nobody proof-reads, and half of these characters are invisible — spelling
// them out is the only way the set can be checked against what it claims. It
// also keeps this file free of regex escape semantics, which is one engine
// difference fewer between node and Qt's V4.
var TOOLTIP_UNSAFE_RANGES = [
  [0x26, 0x26],     // & — the entity introducer, and on its own enough to turn
                    // Qt's AutoText heuristic to rich by way of &lt;
  [0x3c, 0x3c],     // <
  [0x3e, 0x3e],     // >
  [0x5c, 0x5c],     // backslash, so the escaping below can never be read two ways
  [0x00, 0x1f],     // the C0 controls, newline and tab among them
  [0x7f, 0x9f],     // delete and the C1 controls
  [0xad, 0xad],     // soft hyphen
  [0x61c, 0x61c],   // arabic letter mark, a bidi control like the ones below
  [0x200b, 0x200f], // zero width space through right-to-left mark
  [0x2028, 0x202e], // line and paragraph separator, bidi embedding and override
  [0x2060, 0x206f], // word joiner and the deprecated format characters
  [0xfeff, 0xfeff], // zero width no-break space
  [0xfff9, 0xfffb]  // the interlinear annotation marks
]

// Only U+000A and U+2028 actually forge a line in the host's `Text`; the rest
// of this set is deliberate excess. A tab or a right-to-left override inside a
// widget id is a mistake worth seeing spelled out, and the bidi controls are
// the one group that can rewrite the line's meaning without changing a single
// metric — including the `Not a widget id: ` this file wrote itself.
//
// It is not every invisible character, and does not claim to be: the ordinary
// space separators pass through, and a range test over UTF-16 units cannot
// reach an astral format character at all. What it covers is what can change
// what the line MEANS. See docs/decisions/0011.
function tooltipUnsafe(code) {
  for (var i = 0; i < TOOLTIP_UNSAFE_RANGES.length; i++) {
    if (code >= TOOLTIP_UNSAFE_RANGES[i][0] && code <= TOOLTIP_UNSAFE_RANGES[i][1]) return true
  }
  return false
}

// Two caps, because one oversized value and very many small ones are different
// failures and neither bounds the other. The host's `Text` does not wrap and
// Bar.qml sizes the popup window from it, so an unbounded line is an unbounded
// window; docs/decisions/0011 carries what each measured.
//
// 160 for the value, chosen above ID_PATTERN's own 128-character ceiling so
// that every id the allowlist would have ACCEPTED passes through unchanged —
// this line carries ids that were merely not found, too.
var MAX_LABEL = 160
var MAX_LINE = 160

function tooltipEscape(code) {
  var hex = code.toString(16)
  while (hex.length < 4) hex = "0" + hex
  return "\\u" + hex
}

// One value, rendered so that it means the same thing under every textFormat a
// host may resolve, and occupies exactly one line.
function tooltipSafe(value) {
  if (value === null || value === undefined) return ""

  // Escape first, cut afterwards. The other order is the obvious one and it
  // does not bound anything: one escape turns one character into six, so a
  // value cut to 160 first came back out at 960, and the cap that was supposed
  // to keep the line short only ever held for values that had nothing to
  // escape. The whole point is a bound that holds for hostile input, and
  // hostile input is exactly the input that escapes.
  //
  // That bounds the RESULT and not the walk, and the walk is over whatever
  // shell.json holds: one megabyte in a single entry cost 111 ms per call in
  // node, on a binding the tooltip re-evaluates every time the pointer arrives.
  // Only the first MAX_LABEL + 1 units can reach the kept output, because every
  // input unit produces at least one output unit -- an escape produces six, an
  // ordinary character one, and nothing produces none. So the loop stops there
  // and the result is the same string. Measured against the unsliced function
  // over 20735 differential cases, surrogate pairs laid on every index around
  // the cut included: no difference, and 111 ms became 0.03. The "at least one
  // unit" precondition is asserted in tests/model-test.js, because it is the
  // only thing holding this up and a future edit could take it away silently.
  var text = String(value).slice(0, MAX_LABEL + 1)

  var out = ""
  for (var i = 0; i < text.length; i++) {
    var code = text.charCodeAt(i)
    out += tooltipUnsafe(code) ? tooltipEscape(code) : text.charAt(i)
  }

  if (out.length > MAX_LABEL) {
    out = out.slice(0, MAX_LABEL)
    // Astral characters are not escaped — they carry no markup meaning — so the
    // cut can still fall between the halves of a surrogate pair and leave a
    // string that is no longer well formed. Drop the orphan rather than pass it
    // on. A cut through an escape sequence needs no such care: what is left of
    // it is ASCII letters and digits, which mean nothing anywhere.
    var last = out.charCodeAt(out.length - 1)
    if (last >= 0xd800 && last <= 0xdbff) out = out.slice(0, out.length - 1)
    out += "…"
  }

  return out
}

// One tooltip line's worth of values. What does not fit is counted rather than
// left out in silence — the line names a configuration mistake, and a mistake
// the tooltip silently stops mentioning is one the user goes on looking for.
function tooltipList(values) {
  var source = values || []
  var out = []
  var length = 0

  for (var i = 0; i < source.length; i++) {
    var item = tooltipSafe(source[i])
    // The first value is always taken. A single oversized entry is still worth
    // naming, and reporting it only as a count would name nothing at all.
    if (out.length > 0 && length + item.length + 2 > MAX_LINE) break
    length += item.length + (out.length > 0 ? 2 : 0)
    out.push(item)
  }

  var line = out.join(", ")
  var rest = source.length - out.length
  return rest > 0 ? line + ", +" + rest + " more" : line
}

// One tooltip line per condition, most actionable first. The pocket is the only
// place these problems surface: a member that never appears produces no error
// anywhere else in the shell.
//
// Every value it interpolates goes through tooltipList(), including the three
// lists that can only hold ids the allowlist already accepted. That those are
// safe is an argument about where they came from, and an argument about
// provenance is exactly what made this tooltip's safety accidental in the first
// place. Here it is a property of the function, and it costs an accepted id
// nothing.
function describe(state) {
  var s = state || {}
  var members = s.members || []
  var rejected = s.rejected || []
  var unreadable = s.unreadable || []
  var missing = s.missing || []
  var anchored = s.anchored || []
  var foreign = s.foreign || []

  // An instance that does not know which bar surface it is on resolved nothing,
  // and every member came back unfound — but it never looked, so saying "not on
  // this bar" would be a claim about widgets that are in fact right there. It
  // gets its own line, and the lines drawn from the resolution are suppressed.
  //
  // Normally a state no one can see, because an instance without a window is on
  // a surface that is not being drawn. It is permanent, and then this line is
  // the only account of it, if the widget ever stops resolving its window at
  // all — losing the `Quickshell` import is the way that happens, and the
  // header of BarWidget.qml is where it is warned about. Kept in step with
  // ownsSlot(): the same condition that makes the pocket own no slot is the one
  // that puts this line up, so the tooltip cannot describe a different pocket
  // than the one on screen.
  var unknown = s.surfaceUnknown === true

  // What the pocket actually holds, not what it was asked to hold. Counting the
  // configuration would let the first line say "holding 3 widgets" directly
  // above three lines explaining that none of them could be used — and this
  // tooltip is the only place any of that surfaces.
  var held = unknown ? 0 : Math.max(0, members.length - missing.length - anchored.length)
  var lines = []

  if (unknown) {
    lines.push("Pocket cannot tell which screen it is on — it is hiding nothing")
  } else if (members.length === 0 && rejected.length === 0 && unreadable.length === 0) {
    lines.push("Pocket is empty — drag a widget onto it, or set `members` on its bar entry")
  } else if (members.length === 0) {
    // Empty, but not for want of being told. Saying "set `members`" here is
    // instructing the user to do the thing they have already done, and the
    // lines below are about to explain why it did not take -- which is the
    // whole reason unreadableEntries() exists.
    lines.push("Pocket holding nothing — nothing in `members` could be used")
  } else if (held === 0) {
    lines.push("Pocket holding nothing — none of the widgets it names can be used")
  } else if (s.expanded) {
    lines.push("Pocket open — click to keep it open")
  } else {
    lines.push("Pocket holding " + held + " widget" + (held === 1 ? "" : "s"))
  }

  if (s.pinned) lines.push("Pinned — click to release")
  // Ahead of the rejected line, because it is the earlier failure: these
  // entries never became an id at all, so nothing downstream had anything to
  // refuse. Positions rather than values, for the reason unreadableEntries()
  // gives.
  if (unreadable.length > 0) lines.push("Not a member entry: " + tooltipList(unreadable))
  if (rejected.length > 0) lines.push("Not a widget id: " + tooltipList(rejected))
  if (!unknown && missing.length > 0) lines.push("Not on this bar: " + tooltipList(missing))
  if (!unknown && anchored.length > 0) lines.push("Refused, it is the center anchor: " + tooltipList(anchored))
  if (!unknown && foreign.length > 0) lines.push("In another section, so hiding it looks arbitrary: " + tooltipList(foreign))
  if (s.duplicateInstances) lines.push("A second Pocket entry exists — they will fight over shared members")

  return lines.join("\n")
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { isWidgetId: isWidgetId, toList: toList, parseMembers: parseMembers,
                     rejectedMembers: rejectedMembers, unreadableEntries: unreadableEntries,
                     revealFraction: revealFraction,
                     tooltipSafe: tooltipSafe, tooltipList: tooltipList,
                     describe: describe, entryIdOf: entryIdOf, orderMembers: orderMembers,
                     withoutMember: withoutMember, nextMembers: nextMembers,
                     membersValue: membersValue, dropDecision: dropDecision,
                     setMembersOnEntry: setMembersOnEntry, countEntries: countEntries,
                     mayWrite: mayWrite, firstMisplacedMember: firstMisplacedMember,
                     placeMemberBesideSelf: placeMemberBesideSelf,
                     steerDropAfter: steerDropAfter, sameMarkerRect: sameMarkerRect,
                     gapTouchesMember: gapTouchesMember, ownsSlot: ownsSlot,
                     membersInLayoutOrder: membersInLayoutOrder }
}
