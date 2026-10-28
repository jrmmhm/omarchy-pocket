import QtQuick
import Quickshell
import qs.Ui
import "plugin" as Pk

// The mark stays with its run.
//
// The bar moves only the entry that is dragged. A mark dragged away from its
// members leaves them fanning out apart from it, and a mark dropped between
// them splits the run; from Omarchy 4.0.3 on nothing can repair either. So the
// pocket refuses a drag of its own slot while a member stands against it, by
// disabling that slot for a moment, which takes the bar's pointer grab away
// before anything is dropped. docs/decisions/0024 has the live measurement.
//
// What can be asserted here is the refusal itself: the pocket's slot is
// disabled and enabled again, after the handler that named the drag has
// returned and not inside it. Nothing else is touched, by a drag of a member,
// by a drag that ended before the refusal ran, or by a mark with no member
// against it.
//
// Two pockets, one per host shape, driven by the same steps. `pocket` reads a
// bar that publishes `moduleSlots` and `barDragSource`, as Omarchy did before
// 4.0.3; `facadePocket` is handed the host's own Ui/PluginBarApi.qml, walks
// this window for its slots and reads the dragged one off the slots' own
// `dragSource`, as it does on 4.0.3 and later.
//
// Needs a window: Model.ownsSlot() refuses every slot to an instance that does
// not know its surface. tests/qml/run.sh runs this case offscreen.
QtObject {
  id: harness

  readonly property string selfId: "jrmmhm.pocket"
  readonly property var runLayout: ["omarchy.tray", "omaplug", "mehiel.darky", "jrmmhm.pocket"]
  // darky has stepped out of the run: the mark stands apart from its member.
  readonly property var apartLayout: ["omarchy.tray", "omaplug", "mehiel.darky",
                                      "omarchy.agents", "jrmmhm.pocket"]
  readonly property string members: "omaplug, mehiel.darky"

  function layoutOf(ids) {
    var right = []
    for (var i = 0; i < ids.length; i++) right.push({ id: ids[i] })
    right[ids.indexOf(harness.selfId)] = { id: harness.selfId, members: harness.members }
    return { left: [], center: [], right: right }
  }

  // Items rather than QtObjects, because the refusal is a write to `enabled`.
  // Parented outside the window, so the facade pocket's walk does not find them.
  property Component slotComponent: Component {
    Item {
      property string moduleName: ""
      property string region: "right"
      property var activeItem: null
      property bool hovered: false
      property bool dragSource: false
      property int enabledChanges: 0
      onEnabledChanged: enabledChanges++
      width: 32
      height: 30
    }
  }

  property QtObject fakeBar: QtObject {
    property var barDragSource: null
    property var barDragTarget: null
    property var barDragTargetGeometry: null
    property bool barDragAfter: false
    property var moduleSlots: []
    property var layoutConfig: harness.layoutOf(harness.runLayout)
    property string centerAnchor: ""
    property var activePopout: null
    property bool barHovered: false
    property bool vertical: false
    property color urgent: "#d06a7e"
    property QtObject shell: null
    function canonicalWidgetId(id) { return id }
    function slotWindow(slot) { return harness.win }
    function sameWindow(left, right) { return !!left && !!right && left === right }
    function dropMarkerRect(slot, after) { return null }
  }

  property PluginBarApi facade: PluginBarApi {
    pluginId: "jrmmhm.pocket"
    moduleName: "jrmmhm.pocket"
    layoutConfig: harness.layoutOf(harness.runLayout)
  }

  component WalkedSlot: Item {
    property string moduleName: ""
    property string region: "right"
    property var activeItem: null
    property bool hovered: false
    property bool dragSource: false
    property int enabledChanges: 0
    onEnabledChanged: enabledChanges++
    width: 32
    height: 30
  }

  property FloatingWindow win: FloatingWindow {
    id: win
    visible: true
    property Pk.BarWidget pocketItem: Pk.BarWidget {
      parent: win.contentItem
      bar: harness.fakeBar
      settings: ({ members: harness.members })
    }

    WalkedSlot { id: walkedTray; moduleName: "omarchy.tray" }
    WalkedSlot { id: walkedOmaplug; moduleName: "omaplug" }
    WalkedSlot { id: walkedDarky; moduleName: "mehiel.darky" }
    WalkedSlot { id: walkedAgents; moduleName: "omarchy.agents" }
    WalkedSlot {
      id: walkedPocketSlot
      moduleName: "jrmmhm.pocket"
      activeItem: facadePocketItem
      Pk.BarWidget {
        id: facadePocketItem
        bar: harness.facade
        settings: ({ members: harness.members })
      }
    }
    property Pk.BarWidget facadePocket: facadePocketItem
    property var walked: ({ "omaplug": walkedOmaplug, "mehiel.darky": walkedDarky,
                            "jrmmhm.pocket": walkedPocketSlot })
  }

  property var slots: []

  function slotFor(id) {
    for (var i = 0; i < harness.slots.length; i++) {
      if (harness.slots[i].moduleName === id) return harness.slots[i]
    }
    return null
  }

  // [label, pocket, slot lookup, start a drag of a slot, end it]
  readonly property var hosts: [
    ["moduleSlots host", harness.win.pocketItem,
     function (id) { return harness.slotFor(id) },
     function (slot) { slot.dragSource = true; harness.fakeBar.barDragSource = slot },
     function (slot) { harness.fakeBar.barDragSource = null; slot.dragSource = false }],
    ["facade host", harness.win.facadePocket,
     function (id) { return harness.win.walked[id] },
     function (slot) { slot.dragSource = true },
     function (slot) { slot.dragSource = false }]
  ]

  property int failures: 0

  function check(label, actual, expected) {
    if (actual === expected) return
    harness.failures++
    console.warn("FAIL: " + label + "\n  expected: " + expected + "\n  actual:   " + actual)
  }

  function changes(h, id) { return h[2](id).enabledChanges }

  function setLayout(ids) {
    harness.fakeBar.layoutConfig = harness.layoutOf(ids)
    harness.facade.layoutConfig = harness.layoutOf(ids)
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
    for (var i = 0; i < harness.apartLayout.length; i++)
      made.push(harness.slotComponent.createObject(harness, { moduleName: harness.apartLayout[i] }))
    harness.slots = made
    harness.slotFor(harness.selfId).activeItem = harness.win.pocketItem
    harness.fakeBar.moduleSlots = made
    // Past the facade pocket's settling pass, which is when its walk has seen
    // every slot in this window.
    harness.next(400)
  }

  function step2() {
    for (var i = 0; i < harness.hosts.length; i++) {
      var h = harness.hosts[i]
      // Preconditions: without them nothing below is about this pocket's mark.
      harness.check(h[0] + ": the pocket finds its own slot", h[1].ownSlot === h[2](harness.selfId), true)
      harness.check(h[0] + ": and resolves both members", h[1].resolution.slots.length, 2)

      h[3](h[2](harness.selfId))
      harness.check(h[0] + ": the mark is being dragged", h[1].draggingSelf, true)
      harness.check(h[0] + ": not refused inside the handler that named the drag",
                    harness.changes(h, harness.selfId), 0)
    }
    harness.next(50)
  }

  function step3() {
    for (var i = 0; i < harness.hosts.length; i++) {
      var h = harness.hosts[i]
      var own = h[2](harness.selfId)
      harness.check(h[0] + ": with a member against it, the mark's drag is refused",
                    harness.changes(h, harness.selfId), 2)
      harness.check(h[0] + ": and its slot is enabled again", own.enabled, true)
      harness.check(h[0] + ": no member slot is touched",
                    harness.changes(h, "omaplug") + harness.changes(h, "mehiel.darky"), 0)
      h[4](own)
      // A member's own drag is the gesture, and is never refused.
      h[3](h[2]("mehiel.darky"))
    }
    harness.next(50)
  }

  function step4() {
    for (var i = 0; i < harness.hosts.length; i++) {
      var h = harness.hosts[i]
      harness.check(h[0] + ": a member's drag is left alone",
                    harness.changes(h, "mehiel.darky") + harness.changes(h, harness.selfId), 2)
      h[4](h[2]("mehiel.darky"))
      // A drag that is over before the deferred refusal runs: nothing to refuse.
      var own = h[2](harness.selfId)
      h[3](own)
      h[4](own)
    }
    harness.next(50)
  }

  function step5() {
    for (var i = 0; i < harness.hosts.length; i++) {
      var h = harness.hosts[i]
      harness.check(h[0] + ": a drag over before the refusal ran is left alone",
                    harness.changes(h, harness.selfId), 2)
    }
    // darky steps out of the run; the mark now stands apart from its member.
    harness.setLayout(harness.apartLayout)
    harness.next(50)
  }

  function step6() {
    for (var i = 0; i < harness.hosts.length; i++) {
      var h = harness.hosts[i]
      h[3](h[2](harness.selfId))
    }
    harness.next(50)
  }

  function step7() {
    for (var i = 0; i < harness.hosts.length; i++) {
      var h = harness.hosts[i]
      harness.check(h[0] + ": a mark apart from its members can be dragged back to them",
                    harness.changes(h, harness.selfId), 2)
      h[4](h[2](harness.selfId))
    }

    console.warn(harness.failures === 0 ? "QML OK" : "QML FAILURES " + harness.failures)
    Qt.exit(harness.failures === 0 ? 0 : 1)
  }
}
