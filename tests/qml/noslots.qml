import QtQuick
import Quickshell
import qs.Commons
import "plugin" as Pk

// The real BarWidget.qml against a bar that is missing two of the symbols it
// reads. This is the case the README makes a promise about — "a renamed one
// makes a feature stop applying rather than misbehave" — and the only one of
// the fifteen host reads that promise was ever false for.
//
// Measured before the guard: a bar publishing all fourteen other symbols but not
// `moduleSlots` produced five TypeErrors per evaluation, at `resolution` and
// `ownSlot` directly and at `memberHovered`, `apply()` and `tooltipText` through
// them, and the tooltip was left unassigned. `slotBeforeSelf` never threw — it
// walks `layoutIds(ownRegion)`, which is empty once `ownSlot` is gone — so this
// file asserts values rather than counting throws.
//
// Two mechanisms, and both are needed. A thrown binding does not fail an
// assertion: it leaves the property at its last value and aborts whatever was
// reading it. So every probe below is wrapped, and tests/qml/run.sh separately
// refuses any run whose output carries a TypeError from this plugin — without
// that, a regression that threw and left a stale but plausible value would pass
// every line here.
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

  // Reading the property is the assertion. A binding that threw leaves its
  // property undefined and the read that follows throws in turn, so the wrap is
  // what turns "the widget is broken" into a named failure instead of a silent
  // abort halfway down the list.
  function probe(label, fn, expected) {
    var value
    try {
      value = fn()
    } catch (e) {
      harness.failures++
      console.warn("FAIL: " + label + "\n  threw: " + e)
      return
    }
    harness.check(label, value, expected)
  }

  // A bar with everything the pocket reads except `moduleSlots` and `urgent`.
  // Both are absent rather than null, which is what a rename looks like from
  // in here.
  property QtObject blindBar: QtObject {
    property var barDragSource: null
    property var barDragTarget: null
    property var barDragTargetGeometry: null
    property bool barDragAfter: false
    property var layoutConfig: ({ left: [], center: [],
                                  right: [{ id: "jrmmhm.pocket" }] })
    property string centerAnchor: ""
    property var activePopout: null
    property bool barHovered: false
    property bool vertical: false
    property string fontFamily: "monospace"
    property color barForeground: "#ffffff"
    property int barSize: 26
    property QtObject shell: null
    function canonicalWidgetId(id) { return id }
    function slotWindow(slot) { return null }
    function sameWindow(left, right) { return false }
    function dropMarkerRect(slot, after) { return null }
    function showTooltip(target, text) { }
    function hideTooltip(target) { }
    function registerClickTarget(target) { }
    function unregisterClickTarget(target) { }
  }

  property FloatingWindow win: FloatingWindow {
    id: win
    visible: true
    property Pk.BarWidget pocketItem: Pk.BarWidget {
      parent: win.contentItem
      bar: harness.blindBar
      settings: ({ members: "omarchy.audio, omarchy.network" })
    }
  }

  // Driven from a timer for the same reason model.qml is: Qt.exit() does
  // nothing until the event loop runs.
  property Timer starter: Timer {
    interval: 0
    running: true
    onTriggered: harness.runCase()
  }

  function runCase() {
    var p = win.pocketItem

    // The settings still parse. Nothing about the host reaches this half, and
    // asserting it is what separates "degraded" from "broken".
    probe("the members are still read", function () { return p.memberIds.length }, 2)

    // The resolution answers emptily instead of not answering. Every one of
    // these threw before the guard.
    probe("resolution answers", function () { return p.resolution.slots.length }, 0)
    probe("and reports both members as not found",
          function () { return p.resolution.missing.length }, 2)
    probe("own slot is absent, not undefined", function () { return p.ownSlot }, null)
    probe("own region is empty", function () { return p.ownRegion }, "")
    probe("the slot before self is absent", function () { return p.slotBeforeSelf }, null)
    probe("no member is hovered", function () { return p.memberHovered }, false)

    // Refusing to write is the correct degradation, not a second defect: with
    // no region of its own the pocket cannot say where its entry lives.
    probe("it refuses to write", function () { return p.mayWriteMembers }, false)
    probe("it plans no placement repair", function () { return p.misplacedMember }, "")
    probe("it plans no order repair", function () { return p.membersMisordered }, false)
    probe("no drop means anything", function () { return p.dropIntent }, "none")

    // The surface that exists to explain a pocket that cannot work is the one
    // that went dark. It has to survive, and it has to say the true thing.
    probe("the tooltip is still built",
          function () { return p.children[0].tooltipText.indexOf("Not on this bar") !== -1 }, true)
    probe("and it names both members",
          function () { return p.children[0].tooltipText.indexOf("omarchy.audio, omarchy.network") !== -1 },
          true)

    // The other unguarded read. With `urgent` absent the button must fall back
    // to the theme's own colour rather than be handed an undefined.
    probe("the mark keeps a real colour",
          function () { return p.children[0].activeColor.toString() },
          Color.urgent.toString())

    console.warn(harness.failures === 0 ? "QML OK" : "QML FAILURES " + harness.failures)
    Qt.exit(harness.failures === 0 ? 0 : 1)
  }
}
