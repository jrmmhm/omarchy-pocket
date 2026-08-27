import QtQuick
import Quickshell
import "plugin" as Pk

// The real BarWidget.qml, loaded by Quickshell against a bar that is not one.
//
// This is the half of the plugin `tests/model-test.js` cannot reach and
// `qmlformat` does not look at: the drop steering's wiring to the two marker
// properties of the host. That wiring has exactly one observable failure mode
// short of running a shell — it stops steering — and two ways to reach it, both
// silent. Reacting to those values through a property of our own loops (Qt
// prints "Binding loop detected" and skips the re-evaluation); and a misspelt
// signal name is swallowed whole by `ignoreUnknownSignals`, which is there so a
// custom bar without these properties gets silence. Neither leaves anything
// behind that a reader would notice. See docs/decisions/0006.
//
// Run through tests/qml/run.sh, which builds the import tree this needs.
QtObject {
  id: harness

  // Enough of a ModuleSlot for `resolution`, `ownSlot` and `ownRegion`.
  property QtObject pocketSlot: QtObject {
    property string moduleName: "jrmmhm.pocket"
    property string region: "right"
    property var activeItem: null
    property bool hovered: false
    property bool visible: true
    property real opacity: 1
    property real scale: 1
    property int transformOrigin: 0
  }

  property QtObject otherSlot: QtObject {
    property string moduleName: "omarchy.power"
    property string region: "right"
    property var activeItem: null
    property bool hovered: false
    property bool visible: true
  }

  // Enough of Bar.qml to be steered. The far side the bar starts from is
  // x: 100; the near side the pocket must steer to is x: 50.
  property QtObject fakeBar: QtObject {
    id: fakeBar
    property var barDragSource: null
    property var barDragTarget: null
    property var barDragTargetGeometry: null
    property bool barDragAfter: false
    property var moduleSlots: []
    property var layoutConfig: ({
      left: [],
      center: [],
      right: [{ id: "omarchy.power" }, { id: "jrmmhm.pocket" }]
    })
    property string centerAnchor: ""
    property var activePopout: null
    property bool barHovered: false
    property bool vertical: false
    property var shell: null
    function canonicalWidgetId(id) { return id }
    function slotWindow(slot) { return null }
    function sameWindow(left, right) { return false }
    function dropMarkerRect(slot, after) {
      return { x: after ? 100 : 50, y: 0, width: 4, height: 30 }
    }
  }

  property Pk.BarWidget pocket: Pk.BarWidget {
    bar: harness.fakeBar
    settings: ({ members: "omarchy.audio" })
  }

  property int failures: 0

  function check(label, actual, expected) {
    if (actual === expected) return
    harness.failures++
    console.warn("FAIL: " + label + "\n  expected: " + expected + "\n  actual:   " + actual)
  }

  // Driven from a timer rather than from Component.onCompleted, for two
  // reasons that both end the run: the pocket's own onCompleted has to have
  // gone first, and Qt.exit() does nothing until the event loop is running --
  // from onCompleted the process simply hangs until the runner's timeout kills
  // it, which looks like a pass because the assertions have already printed.
  property Timer starter: Timer {
    interval: 0
    running: true
    onTriggered: harness.runCase()
  }

  function runCase() {
    harness.pocketSlot.activeItem = harness.pocket
    harness.fakeBar.moduleSlots = [harness.otherSlot, harness.pocketSlot]

    // Without these the steering refuses for reasons that have nothing to do
    // with what is under test, and the assertions below would pass an empty
    // stage rather than a steered one.
    check("the pocket finds its own slot", harness.pocket.ownSlot === harness.pocketSlot, true)
    check("and reads its own section off it", harness.pocket.ownRegion, "right")
    check("and is allowed to write", harness.pocket.mayWriteMembers, true)

    // One pointer move of a drag arriving from the far side, in the order
    // Bar.qml writes its three values on every move.
    harness.fakeBar.barDragSource = harness.otherSlot
    harness.fakeBar.barDragTarget = harness.pocketSlot
    harness.fakeBar.barDragAfter = true
    harness.fakeBar.barDragTargetGeometry = { x: 100, y: 0, width: 4, height: 30 }

    check("a far-side arrival is steered to the near side", harness.fakeBar.barDragAfter, false)
    check("and the marker is moved with it, so the two cannot disagree",
          harness.fakeBar.barDragTargetGeometry.x, 50)

    // A second move that flips only the side, leaving the geometry object it
    // already holds. One assertion per subscription is the whole point of this
    // one: with both writes in play the geometry handler covers for a dead
    // `after` handler, and a misspelt name there is invisible -- which is the
    // failure ignoreUnknownSignals is quiet about. Bar.qml can write this pair
    // in either order, so neither handler may be the only one that works.
    harness.fakeBar.barDragAfter = true

    check("a side flipped on its own is steered back", harness.fakeBar.barDragAfter, false)

    console.warn(harness.failures === 0 ? "QML OK" : "QML FAILURES " + harness.failures)
    Qt.exit(harness.failures === 0 ? 0 : 1)
  }
}
