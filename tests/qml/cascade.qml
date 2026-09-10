import QtQuick
import Quickshell
import qs.Ui
import "plugin" as Pk

// The fan-out follows the bar, not the member list.
//
// The list a running pocket holds can lag the bar after a reorder, and a
// cascade counted along it ran in a direction that was not on screen — the
// moved widget fanned out on its own. docs/decisions/0018 has the measurement.
//
// So this case holds the list deliberately stale — rotated against the layout,
// with no shell to write through, so no repair can put it right — and asserts
// what the user sees: the member against the mark is always at least as far
// along as the one behind it, and strictly ahead somewhere. Rotated rather than
// reversed, because a reversed list is also passed by an implementation that
// merely reverses the list. Then the layout changes under the same stale list,
// and the cascade has to follow the layout.
//
// Two pockets, one per host shape, driven at the same time. `pocket` reads a
// bar that publishes `moduleSlots`, as Omarchy did before 4.0.3; `facadePocket`
// is handed the host's own Ui/PluginBarApi.qml and finds its slots by walking
// this window, which is the path the stale list was measured on.
//
// Needs a window: Model.ownsSlot() refuses every slot to an instance that does
// not know its surface. tests/qml/run.sh runs this case offscreen.
QtObject {
  id: harness

  readonly property string selfId: "jrmmhm.pocket"
  // The run in layout order: omaplug, ianswope.snapshots, mehiel.darky, then
  // the mark. `members` names the same three rotated by one.
  readonly property string staleMembers: "ianswope.snapshots, mehiel.darky, omaplug"
  readonly property var firstLayout: ["omarchy.tray", "omaplug", "ianswope.snapshots",
                                      "mehiel.darky", "jrmmhm.pocket"]
  readonly property var movedLayout: ["omarchy.tray", "mehiel.darky", "omaplug",
                                      "ianswope.snapshots", "jrmmhm.pocket"]

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
    property var layoutConfig: harness.layoutOf(harness.firstLayout)
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

  // The host's own facade, with no shell for the same reason as above.
  property PluginBarApi facade: PluginBarApi {
    pluginId: "jrmmhm.pocket"
    moduleName: "jrmmhm.pocket"
    layoutConfig: harness.layoutOf(harness.firstLayout)
  }

  // Module slots the walk recognises: the three properties it asks for, in
  // this window's item tree. The facade pocket lives inside its own, the way
  // the host's registryLoader mounts a widget, so `ownSlot` resolves.
  component WalkedSlot: Item {
    property string moduleName: ""
    property string region: "right"
    property var activeItem: null
    property bool hovered: false
    width: 32
    height: 30
  }

  property FloatingWindow win: FloatingWindow {
    id: win
    visible: true
    property Pk.BarWidget pocketItem: Pk.BarWidget {
      parent: win.contentItem
      bar: harness.fakeBar
      settings: ({ members: harness.staleMembers })
    }

    WalkedSlot { id: walkedTray; moduleName: "omarchy.tray" }
    WalkedSlot { id: walkedOmaplug; moduleName: "omaplug" }
    WalkedSlot { id: walkedSnapshots; moduleName: "ianswope.snapshots" }
    WalkedSlot { id: walkedDarky; moduleName: "mehiel.darky" }
    WalkedSlot {
      id: walkedPocketSlot
      moduleName: "jrmmhm.pocket"
      activeItem: facadePocketItem
      Pk.BarWidget {
        id: facadePocketItem
        bar: harness.facade
        settings: ({ members: harness.staleMembers })
      }
    }
    property Pk.BarWidget facadePocket: facadePocketItem
    property var walked: ({ "omaplug": walkedOmaplug, "ianswope.snapshots": walkedSnapshots,
                            "mehiel.darky": walkedDarky })
  }
  readonly property var pocket: harness.win.pocketItem
  readonly property var facadePocket: harness.win.facadePocket

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

  // Samples of the members' opacity while both pockets fan out, nearest to the
  // mark first. Filled by the sampler below.
  property var nearestFirst: []
  property var samples: []
  property var walkedSamples: []

  property Timer sampler: Timer {
    interval: 25
    repeat: true
    onTriggered: {
      var row = [], walkedRow = []
      for (var i = 0; i < harness.nearestFirst.length; i++) {
        row.push(harness.slotFor(harness.nearestFirst[i]).opacity)
        walkedRow.push(harness.win.walked[harness.nearestFirst[i]].opacity)
      }
      harness.samples.push(row)
      harness.walkedSamples.push(walkedRow)
    }
  }

  // The cascade, as the user sees it: along the run, nothing further from the
  // mark is ever further along than something nearer, and the stagger is real
  // somewhere — otherwise a pocket that revealed everything at once would pass.
  function assertCascade(label, samples) {
    var ordered = true, staggers = false, worst = ""
    for (var s = 0; s < samples.length; s++) {
      var row = samples[s]
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

  function setOpen(open) {
    // Pinned rather than expanded alone: the fold timer would close an unpinned
    // pocket on its next tick, with no pointer on this bar.
    var both = [harness.pocket, harness.facadePocket]
    for (var i = 0; i < both.length; i++) {
      both[i].pinned = open
      both[i].expanded = open
    }
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
    var made = []
    for (var i = 0; i < harness.firstLayout.length; i++)
      made.push(harness.slotComponent.createObject(harness, { moduleName: harness.firstLayout[i] }))
    harness.slots = made
    harness.slotFor(harness.selfId).activeItem = harness.pocket
    harness.fakeBar.moduleSlots = made
    // Past the facade pocket's settling pass, which is when its walk has seen
    // every slot in this window.
    harness.next(400)
  }

  function step2() {
    // Preconditions. Without them the stage is empty or not stale, and every
    // assertion below would pass for the wrong reason.
    var both = [["moduleSlots host", harness.pocket], ["facade host", harness.facadePocket]]
    for (var i = 0; i < both.length; i++) {
      var name = both[i][0], p = both[i][1]
      harness.check(name + ": the pocket knows its section", p.ownRegion, "right")
      harness.check(name + ": it resolves all three members", p.resolution.slots.length, 3)
      harness.check(name + ": the list it holds is the stale one", p.memberIds.join(","),
                    "ianswope.snapshots,mehiel.darky,omaplug")
      harness.check(name + ": and it knows the list disagrees with the bar", p.membersMisordered, true)
    }
    harness.check("facade host: it found its slots by walking, not in a registry",
                  harness.facadePocket.hostPublishesSlots, false)

    harness.nearestFirst = ["mehiel.darky", "ianswope.snapshots", "omaplug"]
    harness.samples = []
    harness.walkedSamples = []
    harness.sampler.start()
    harness.setOpen(true)
    harness.next(800)
  }

  function step3() {
    harness.sampler.stop()
    harness.assertCascade("moduleSlots host, fanning out under a stale list", harness.samples)
    harness.assertCascade("facade host, fanning out under a stale list", harness.walkedSamples)

    // Close them, and let the fold finish before the layout moves.
    harness.setOpen(false)
    harness.next(900)
  }

  function step4() {
    // The layout changes, the list the pockets hold does not.
    harness.fakeBar.layoutConfig = harness.layoutOf(harness.movedLayout)
    harness.facade.layoutConfig = harness.layoutOf(harness.movedLayout)
    harness.check("the list is still the stale one after the layout moved",
                  harness.pocket.memberIds.join(",") + "|" + harness.facadePocket.memberIds.join(","),
                  "ianswope.snapshots,mehiel.darky,omaplug|ianswope.snapshots,mehiel.darky,omaplug")

    harness.nearestFirst = ["ianswope.snapshots", "omaplug", "mehiel.darky"]
    harness.samples = []
    harness.walkedSamples = []
    harness.sampler.start()
    harness.setOpen(true)
    harness.next(800)
  }

  function step5() {
    harness.sampler.stop()
    harness.assertCascade("moduleSlots host, fanning out after the layout moved", harness.samples)
    harness.assertCascade("facade host, fanning out after the layout moved", harness.walkedSamples)

    console.warn(harness.failures === 0 ? "QML OK" : "QML FAILURES " + harness.failures)
    Qt.exit(harness.failures === 0 ? 0 : 1)
  }
}
