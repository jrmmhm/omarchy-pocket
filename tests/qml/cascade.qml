import QtQuick
import Quickshell
import "plugin" as Pk

// The fan-out follows the bar, not the member list.
//
// On Omarchy 4.0.3 a member reordered inside the run leaves the running pocket
// holding the list it had BEFORE the reorder: the host applies the rewritten
// `members` and a deferred injectProps() puts the old one back a few
// milliseconds later. The list is then out of step with the bar until the next
// full rebuild, and a cascade counted along the list ran in a direction that
// was not on screen — the moved widget fanned out on its own, at the position
// it had left. docs/decisions/0018 has the measurement.
//
// So this case holds the list deliberately stale — rotated against the layout,
// with no shell to write through, so no repair can put it right — and asserts
// what the user sees: the member against the mark is always at least as far
// along as the one behind it, and strictly ahead somewhere. Rotated rather than
// reversed, because a reversed list is also passed by an implementation that
// merely reverses the list. Then the layout changes under the same stale list,
// which is the measured race itself, and the cascade has to follow the layout.
//
// Needs a window: Model.ownsSlot() refuses every slot to an instance that does
// not know its surface. tests/qml/run.sh runs this case offscreen.
QtObject {
  id: harness

  readonly property string selfId: "jrmmhm.pocket"
  // The run in layout order: omaplug, ianswope.snapshots, mehiel.darky, then
  // the mark. `members` names the same three rotated by one.
  readonly property string staleMembers: "ianswope.snapshots, mehiel.darky, omaplug"

  property var slots: []

  property Component slotComponent: Component {
    QtObject {
      property string moduleName: ""
      property string region: "right"
      property var activeItem: null
      property bool hovered: false
      property bool visible: true
      property real opacity: 1
      property real scale: 1
      property int transformOrigin: 0
      property real x: 0
      property real width: 32
      property real height: 30
    }
  }

  function layoutOf(ids) {
    var right = []
    for (var i = 0; i < ids.length; i++) right.push({ id: ids[i] })
    right[ids.indexOf(harness.selfId)] = { id: harness.selfId, members: harness.staleMembers }
    return { left: [], center: [], right: right }
  }

  property QtObject fakeBar: QtObject {
    id: fakeBar
    property var barDragSource: null
    property var barDragTarget: null
    property var barDragTargetGeometry: null
    property bool barDragAfter: false
    property var moduleSlots: []
    property var layoutConfig: harness.layoutOf(["omarchy.tray", "omaplug", "ianswope.snapshots",
                                                 "mehiel.darky", "jrmmhm.pocket"])
    property string centerAnchor: ""
    property var activePopout: null
    property bool barHovered: false
    property bool vertical: false
    property color urgent: "#d06a7e"
    // No shell: nothing may write, so the stale list stays exactly as stale as
    // the host leaves it.
    property QtObject shell: null
    function canonicalWidgetId(id) { return id }
    function slotWindow(slot) { return harness.win }
    function sameWindow(left, right) { return !!left && !!right && left === right }
    function dropMarkerRect(slot, after) { return null }
  }

  property FloatingWindow win: FloatingWindow {
    id: win
    visible: true
    property Pk.BarWidget pocketItem: Pk.BarWidget {
      parent: win.contentItem
      bar: harness.fakeBar
      settings: ({ members: harness.staleMembers })
    }
  }
  readonly property var pocket: harness.win.pocketItem

  property int failures: 0

  function check(label, actual, expected) {
    if (actual === expected) return
    harness.failures++
    console.warn("FAIL: " + label + "\n  expected: " + expected + "\n  actual:   " + actual)
  }

  function slotFor(id) {
    for (var i = 0; i < harness.slots.length; i++) {
      if (harness.slots[i].moduleName === id) return harness.slots[i]
    }
    return null
  }

  // Samples of the members' opacity while the pocket fans out, nearest to the
  // mark first. Filled by the sampler below.
  property var nearestFirst: []
  property var samples: []

  property Timer sampler: Timer {
    interval: 25
    repeat: true
    onTriggered: {
      var row = []
      for (var i = 0; i < harness.nearestFirst.length; i++)
        row.push(harness.slotFor(harness.nearestFirst[i]).opacity)
      harness.samples.push(row)
    }
  }

  // The cascade, as the user sees it: along the run, nothing further from the
  // mark is ever further along than something nearer, and the stagger is real
  // somewhere — otherwise a pocket that revealed everything at once would pass.
  function assertCascade(label) {
    var ordered = true, staggers = false, worst = ""
    for (var s = 0; s < harness.samples.length; s++) {
      var row = harness.samples[s]
      for (var i = 1; i < row.length; i++) {
        if (row[i - 1] < row[i]) {
          ordered = false
          if (worst === "") worst = JSON.stringify(row)
        }
        if (row[i - 1] > row[i]) staggers = true
      }
    }
    harness.check(label + ": nothing behind overtakes the member nearer the mark"
                  + (worst ? " (first offending sample " + worst + ")" : ""), ordered, true)
    harness.check(label + ": and the stagger actually shows", staggers, true)
  }

  property Timer steps: Timer {
    interval: 0
    running: true
    property int step: 0
    onTriggered: {
      step++
      harness["step" + step]()
    }
  }

  function next(ms) {
    harness.steps.interval = ms
    harness.steps.restart()
  }

  function step1() {
    var ids = ["omarchy.tray", "omaplug", "ianswope.snapshots", "mehiel.darky", "jrmmhm.pocket"]
    var made = []
    for (var i = 0; i < ids.length; i++) made.push(harness.slotComponent.createObject(harness, { moduleName: ids[i] }))
    harness.slots = made
    harness.slotFor(harness.selfId).activeItem = harness.pocket
    harness.fakeBar.moduleSlots = made
    harness.next(50)
  }

  function step2() {
    var p = harness.pocket
    // Preconditions. Without them the stage is empty or not stale, and every
    // assertion below would pass for the wrong reason.
    harness.check("the pocket knows its section", p.ownRegion, "right")
    harness.check("it resolves all three members", p.resolution.slots.length, 3)
    harness.check("the list it holds is the stale one", p.memberIds.join(","),
                  "ianswope.snapshots,mehiel.darky,omaplug")
    harness.check("and it knows the list disagrees with the bar", p.membersMisordered, true)

    harness.nearestFirst = ["mehiel.darky", "ianswope.snapshots", "omaplug"]
    harness.samples = []
    harness.sampler.start()
    // Pinned rather than expanded: the fold timer would close an unpinned
    // pocket on its next tick, with no pointer on this bar.
    p.pinned = true
    p.expanded = true
    harness.next(800)
  }

  function step3() {
    harness.sampler.stop()
    harness.assertCascade("fanning out under a stale list")

    // Close it, and let the fold finish before the layout moves.
    harness.pocket.pinned = false
    harness.pocket.expanded = false
    harness.next(900)
  }

  function step4() {
    // The race itself: the layout changes, the list the pocket holds does not.
    harness.fakeBar.layoutConfig = harness.layoutOf(["omarchy.tray", "mehiel.darky", "omaplug",
                                                     "ianswope.snapshots", "jrmmhm.pocket"])
    harness.check("the list is still the stale one after the layout moved",
                  harness.pocket.memberIds.join(","), "ianswope.snapshots,mehiel.darky,omaplug")

    harness.nearestFirst = ["ianswope.snapshots", "omaplug", "mehiel.darky"]
    harness.samples = []
    harness.sampler.start()
    harness.pocket.pinned = true
    harness.pocket.expanded = true
    harness.next(800)
  }

  function step5() {
    harness.sampler.stop()
    harness.assertCascade("fanning out after the layout moved")

    console.warn(harness.failures === 0 ? "QML OK" : "QML FAILURES " + harness.failures)
    Qt.exit(harness.failures === 0 ? 0 : 1)
  }
}
