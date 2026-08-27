import QtQuick
import Quickshell
import "plugin" as Pk

// The same stage as steer.qml, with one difference: this host refuses the
// second of the two writes.
//
// Both marker values are applied or neither. A host that turned only the
// geometry readonly would otherwise be left placing the widget against the
// pocket while still drawing its insertion line on the far side — the one
// outcome the override must never produce, and the promise the README makes
// about the mark and the bar's own line agreeing. The steering rolls the first
// write back instead. See docs/decisions/0006.
QtObject {
  id: harness

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

  property QtObject fakeBar: QtObject {
    id: fakeBar
    property var barDragSource: null
    property var barDragTarget: null
    // The refusal under test. Assigning it throws, exactly as a host property
    // turned readonly would.
    readonly property var barDragTargetGeometry: ({ x: 100, y: 0, width: 4, height: 30 })
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

  // Driven from a timer for the reasons steer.qml records.
  property Timer starter: Timer {
    interval: 0
    running: true
    onTriggered: harness.runCase()
  }

  function runCase() {
    harness.pocketSlot.activeItem = harness.pocket
    harness.fakeBar.moduleSlots = [harness.otherSlot, harness.pocketSlot]
    check("the pocket finds its own slot", harness.pocket.ownSlot === harness.pocketSlot, true)

    harness.fakeBar.barDragSource = harness.otherSlot
    harness.fakeBar.barDragTarget = harness.pocketSlot
    harness.fakeBar.barDragAfter = true

    // The marker the bar drew is still on the far side, because the write that
    // would have moved it was refused. The side the widget would land on has to
    // match it, which means the steering's own first write has to be undone.
    check("a refused geometry leaves the marker where the bar drew it",
          harness.fakeBar.barDragTargetGeometry.x, 100)
    check("and the placement is rolled back to match it, rather than left half applied",
          harness.fakeBar.barDragAfter, true)

    console.warn(harness.failures === 0 ? "QML OK" : "QML FAILURES " + harness.failures)
    Qt.exit(harness.failures === 0 ? 0 : 1)
  }
}
