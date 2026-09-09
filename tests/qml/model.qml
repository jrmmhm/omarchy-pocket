import QtQuick
import "plugin/Model.js" as Model

// The tooltip text boundary, re-asserted in the engine it actually runs in.
//
// `tests/model-test.js` covers what the escaping does; this covers where it
// does it. Model.js is written for two engines — node's V8 and Qt's V4 — and
// the boundary is the one function in it whose correctness rests on engine
// details rather than on arithmetic: charCodeAt over a string the host handed
// in, Number.toString(16), and the difference between a JS string and the
// sequence type QML delivers for an array-valued setting. node cannot show any
// of that, which is the same bargain steer.qml already makes for the drop
// steering.
//
// Deliberately not a rebuilt copy of Bar.qml's tooltip `Text`. Asserting that
// AutoText and PlainText render identically is green on the unfixed commit —
// the heuristic stops at the first line break and describe() always writes a
// literal first line — so such a test would assert a property that was already
// true and catch nothing. What is worth running here is the code that changed.
//
// Run through tests/qml/run.sh, which builds the import tree this needs.
QtObject {
  id: harness

  property int failures: 0

  function check(label, actual, expected) {
    if (actual === expected) return
    harness.failures++
    console.warn("FAIL: " + label + "\n  expected: " + expected + "\n  actual:   " + actual)
  }

  // Lists compare by value, not by identity. Every ordering fixture below
  // answers with a fresh array, so `===` would fail all of them alike and prove
  // nothing about any of them.
  function checkList(label, actual, expected) {
    harness.check(label, JSON.stringify(actual), JSON.stringify(expected))
  }

  function from(code) { return String.fromCharCode(code) }

  function longestLine(rejected) {
    var lines = Model.describe({ members: [], rejected: rejected }).split("\n")
    var longest = 0
    for (var i = 0; i < lines.length; i++) longest = Math.max(longest, lines[i].length)
    return longest
  }

  // Driven from a timer for the same reason steer.qml is: Qt.exit() does
  // nothing until the event loop runs, and from Component.onCompleted the
  // process hangs until the runner's timeout kills it — which looks like a pass,
  // because the assertions have already printed by then.
  property Timer starter: Timer {
    interval: 0
    running: true
    onTriggered: harness.runCase()
  }

  function runCase() {
    check("V4 escapes less-than", Model.tooltipSafe("a<b"), "a\\u003cb")
    check("V4 escapes greater-than", Model.tooltipSafe("a>b"), "a\\u003eb")
    check("V4 escapes ampersand", Model.tooltipSafe("a&b"), "a\\u0026b")
    check("V4 escapes backslash", Model.tooltipSafe("a" + harness.from(0x5c) + "b"), "a\\u005cb")
    check("V4 escapes a line break", Model.tooltipSafe("a" + harness.from(0x0a) + "b"), "a\\u000ab")
    check("V4 escapes a line separator", Model.tooltipSafe("a" + harness.from(0x2028) + "b"), "a\\u2028b")
    check("V4 escapes a right-to-left override", Model.tooltipSafe("a" + harness.from(0x202e) + "b"), "a\\u202eb")

    // The counterpart. An id the allowlist would have accepted has to come
    // through untouched, or the line stops naming what the user has to fix.
    check("V4 leaves an accepted id alone", Model.tooltipSafe("omarchy.audio"), "omarchy.audio")
    check("V4 leaves a rejected id with nothing to escape alone",
          Model.tooltipSafe("../evil"), "../evil")

    // The shape the bar actually delivers. A `members` array parsed out of
    // shell.json arrives in QML as a sequence type, which indexes and reports
    // `length` like an array while failing Array.isArray() — the reason
    // toList() duck-types instead. The boundary is downstream of that and must
    // survive the same value.
    var raw = harness.hostileSetting
    var rejected = Model.rejectedMembers(raw, "jrmmhm.pocket")
    check("V4 rejects both hostile entries", rejected.length, 2)

    var tooltip = Model.describe({ members: ["omarchy.audio"], rejected: rejected })
    check("V4 lets no markup character through", /[<>&]/.test(tooltip), false)
    check("V4 lets a value forge no line", tooltip.split("\n").length, 2)

    // Bounded on the other axis too, which the per-value cap does not cover.
    // Twice, because the harmless flood and the hostile one reach the caps by
    // different routes, and the hostile one is the shape that was measured
    // escaping past a cap applied too early. docs/decisions/0011 has the
    // numbers.
    var harmless = []
    var hostile = []
    var wide = ""
    for (var w = 0; w < 160; w++) wide += "<"
    for (var i = 0; i < 4000; i++) { harmless.push("!"); hostile.push(wide) }
    check("V4 keeps a harmless flood bounded", harness.longestLine(harmless) < 200, true)
    check("V4 keeps a hostile flood bounded", harness.longestLine(hostile) < 200, true)

    // ------------------------------------------------- membership and order
    //
    // These are not a second copy of tests/model-test.js for symmetry's sake.
    // The defect they cover reached the comparator with a NaN, and what a sort
    // does with a NaN comparator is the engine's own business: V8 leaves the
    // order alone, V4 does not. Two of the assertions below were GREEN in node
    // against the unfixed code — measured, not supposed — so node could only
    // ever have said the fix was unnecessary. This file is where they mean
    // something.
    checkList("V4 holds a member whose id is a prototype name",
              Model.parseMembers(["toString", "omaplug"], "jrmmhm.pocket"),
              ["toString", "omaplug"])
    checkList("V4 does not report it as a rejection instead",
              Model.rejectedMembers(["toString", "omaplug"], "jrmmhm.pocket"), [])
    checkList("V4 still collapses a real duplicate",
              Model.parseMembers(["toString", "toString", "omaplug"], "jrmmhm.pocket"),
              ["toString", "omaplug"])

    var namedLayout = ["b", "toString", "a"]
    checkList("V4 ranks a layout id that is a prototype name",
              Model.orderMembers(["a", "toString", "b"], namedLayout), namedLayout)
    check("V4 agrees the result is in layout order",
          Model.membersInLayoutOrder(Model.orderMembers(["a", "toString", "b"], namedLayout),
                                     namedLayout), true)

    // The fixture that had no fixpoint. Ordering alternated between two wrong
    // orders for ever while membersInLayoutOrder() answered false, and every
    // pass of that is one repairMemberOrder() write into the user's shell.json.
    // The last two lines are the ones that say the writing stops.
    var cycleLayout = ["c", "b", "valueOf", "toString", "a"]
    var cycleList = ["a", "toString", "valueOf", "b", "c"]
    checkList("V4 lands the cycling fixture in layout order",
              Model.orderMembers(cycleList, cycleLayout), cycleLayout)
    checkList("V4 orders the result again to the same thing",
              Model.orderMembers(Model.orderMembers(cycleList, cycleLayout), cycleLayout),
              cycleLayout)
    check("V4 gives the repair a fixpoint to stop at",
          Model.membersInLayoutOrder(Model.orderMembers(cycleList, cycleLayout), cycleLayout), true)

    checkList("V4 collects an unknown id at the end, __proto__ included",
              Model.orderMembers(["__proto__", "a", "b"], ["b", "a"]), ["b", "a", "__proto__"])
    checkList("V4 leaves ordinary ids in layout order",
              Model.orderMembers(["omarchy.tailscale", "mehiel.darky", "omaplug"],
                                 ["omarchy.tray", "mehiel.darky", "omaplug", "omarchy.tailscale"]),
              ["mehiel.darky", "omaplug", "omarchy.tailscale"])

    // The sequence type again, this time on the entry shapes toList() cannot
    // read. A hand-written array is exactly where these come from.
    checkList("V4 names the entries it cannot read",
              Model.unreadableEntries(harness.unreadableSetting), [1, 2, 3])
    check("V4 says so in the tooltip",
          Model.describe({ members: [],
                           unreadable: Model.unreadableEntries(harness.unreadableSetting) })
            .indexOf("Not a member entry: 1, 2, 3") !== -1, true)

    // ------------------------------------------------------------- the run
    //
    // The narrowing that lets a member on the wrong side of the mark be dragged
    // out lives on a layout the HOST hands over, and that is a sequence type
    // rather than an array — the same difference toList() duck-types around.
    // gapTouchesMember() now indexes that value at `at` and `at - 1`, and one
    // of those two is deliberately out of range whenever the gap is at either
    // end of the section. node answers `undefined` there and falls through
    // harmlessly; a sequence type is not obliged to, and this is the engine
    // where that shows. See docs/decisions/0016.
    var runLayout = harness.splitLayout
    var runMembers = harness.splitMembers
    check("V4 keeps the run against the group",
          Model.gapTouchesMember(runLayout, runMembers, "jrmmhm.pocket", false,
                                 "jrmmhm.pocket", true), true)
    check("V4 lets the far-side member leave",
          Model.gapTouchesMember(runLayout, runMembers, "omarchy.bluetooth", false,
                                 "jrmmhm.pocket", true), false)
    // The gap past the last entry in the section: `at` equals the layout's
    // length, so the second edge read is out of range by construction.
    check("V4 survives the gap past the last entry",
          Model.gapTouchesMember(runLayout, runMembers, "omarchy.network", true,
                                 "jrmmhm.pocket", true), false)
    // And the gap before the first, where `at - 1` is out of range.
    check("V4 survives the gap before the first entry",
          Model.gapTouchesMember(runLayout, runMembers, "omarchy.tray", false,
                                 "jrmmhm.pocket", true), false)
    check("V4 ejects nothing from a layout without the pocket",
          Model.gapTouchesMember(harness.pocketlessLayout, runMembers, "omaplug", true,
                                 "jrmmhm.pocket", true), true)

    console.warn(harness.failures === 0 ? "QML OK" : "QML FAILURES " + harness.failures)
    Qt.exit(harness.failures === 0 ? 0 : 1)
  }

  // Declared as a property so the engine hands runCase() the same kind of value
  // a setting does, rather than a literal built inside the function.
  //
  // `example.invalid` is reserved by RFC 2606 and resolves nowhere. It is used
  // instead of a real host because a fixture that ever DID reach a rich text
  // parser would fetch it, and a suite that quietly makes network requests is
  // worse than the defect it is testing for.
  property var hostileSetting: ["<img src=\"http://example.invalid/p.png\">",
                               "a" + String.fromCharCode(0x0a) + "A second Pocket entry exists"]

  // Declared here for the same reason: the entry shapes toList() refuses have
  // to arrive as the sequence type a hand-written `members` array becomes, not
  // as a literal the function builds for itself.
  property var unreadableSetting: [{ id: 5 }, 42, { name: "omaplug" }, "omaplug"]

  // Declared, not built in the function, for the third time and the same
  // reason: layoutIds() hands gapTouchesMember() a value that came from the
  // host, and the out-of-range reads it makes are only interesting on the type
  // the host actually delivers. `omarchy.bluetooth` is a member sitting past
  // the pocket — the arrangement the author's own bar had.
  property var splitLayout: ["omarchy.tray", "omaplug", "agx.screen-time", "jrmmhm.pocket",
                             "omarchy.agents", "omarchy.bluetooth", "omarchy.network"]
  property var splitMembers: ["omaplug", "agx.screen-time", "omarchy.bluetooth"]
  property var pocketlessLayout: ["omaplug", "agx.screen-time", "omarchy.network"]
}
