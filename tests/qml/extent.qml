import QtQuick
import Quickshell
import qs.Ui
import "plugin" as Pk

// The neighbours slide, they do not jump.
//
// The bar lays its slots out in a Row (a Column on a vertical bar), and a slot
// moves its neighbours by its extent alone: opacity and scale move nothing. So
// the members' width — their height on a vertical bar — has to ride the reveal,
// out and back, or everything beside the run jumps by the run's whole length in
// one frame, at the start of opening and at the end of closing.
//
// Two pockets on two bars, one horizontal and one vertical, driven at the same
// time, each with one member whose slot sizes itself the way the host's
// ModuleSlot does: `width: implicitWidth`, `height: implicitHeight`. Asserted
// per bar: the extent along the bar passes through values strictly between
// nothing and full while opening and while closing; it only grows on the way
// out and only shrinks on the way back; the other extent is left alone; and
// once fully out, the host's own sizing is back, so a member whose label grows
// while the pocket is open grows with it.
//
// Then a third pocket, collapsed, is unloaded the way the host unloads a plugin
// on a hot reload: its slots outlive it. The member it gave back must still
// follow its own size afterwards. A size handed back as a binding made inside
// the pocket stops with the pocket, and froze there (docs/decisions/0023).
//
// Needs a window: Model.ownsSlot() refuses every slot to an instance that does
// not know its surface. tests/qml/run.sh runs this case offscreen.
QtObject {
  id: harness

  readonly property string selfId: "jrmmhm.pocket"
  readonly property string memberId: "omaplug"
  readonly property var layoutIds: ["omarchy.tray", "omaplug", "jrmmhm.pocket"]

  property Component slotComponent: Component {
    Item {
      property string moduleName: ""
      property string region: "right"
      property var activeItem: null
      property bool hovered: false
      implicitWidth: 40
      implicitHeight: 24
      width: implicitWidth
      height: implicitHeight
    }
  }

  function layout() {
    return { left: [], center: [], right: [{ id: "omarchy.tray" },
      { id: harness.memberId }, { id: harness.selfId, members: harness.memberId }] }
  }

  component FakeBar: QtObject {
    property var barDragSource: null
    property var barDragTarget: null
    property var barDragTargetGeometry: null
    property bool barDragAfter: false
    property var moduleSlots: []
    property var layoutConfig: harness.layout()
    property string centerAnchor: ""
    property var activePopout: null
    property bool barHovered: false
    property bool vertical: false
    property color urgent: "#d06a7e"
    // No shell: nothing may write, so the members stay as the layout names them.
    property QtObject shell: null
    function canonicalWidgetId(id) { return id }
    function slotWindow(slot) { return harness.win }
    function sameWindow(left, right) { return !!left && !!right && left === right }
    function dropMarkerRect(slot, after) { return null }
  }

  property FakeBar rowBar: FakeBar { vertical: false }
  property FakeBar columnBar: FakeBar { vertical: true }
  property FakeBar unloadedBar: FakeBar { vertical: false }
  property var unloadedMember: null

  property FloatingWindow win: FloatingWindow {
    id: win
    visible: true
    property Pk.BarWidget rowPocket: Pk.BarWidget {
      parent: win.contentItem
      bar: harness.rowBar
      settings: ({ members: harness.memberId })
    }
    property Pk.BarWidget columnPocket: Pk.BarWidget {
      parent: win.contentItem
      bar: harness.columnBar
      settings: ({ members: harness.memberId })
    }
    property Loader unloadable: Loader {
      parent: win.contentItem
      active: false
      sourceComponent: Component {
        Pk.BarWidget {
          bar: harness.unloadedBar
          settings: ({ members: harness.memberId })
        }
      }
    }
  }

  // [label, bar, pocket, extent along the bar, extent across it]
  readonly property var cases: [
    ["horizontal bar", harness.rowBar, harness.win.rowPocket, "width", "height"],
    ["vertical bar", harness.columnBar, harness.win.columnPocket, "height", "width"]
  ]

  property var members: ({})
  property var samples: ({})

  property int failures: 0

  function check(label, actual, expected) {
    if (actual === expected) return
    harness.failures++
    console.warn("FAIL: " + label + "\n  expected: " + expected + "\n  actual:   " + actual)
  }

  property Timer sampler: Timer {
    interval: 20
    repeat: true
    onTriggered: {
      for (var i = 0; i < harness.cases.length; i++) {
        var c = harness.cases[i], slot = harness.members[c[0]]
        harness.samples[c[0]].push({ along: slot[c[3]], across: slot[c[4]] })
      }
    }
  }

  function startSampling() {
    var fresh = {}
    for (var i = 0; i < harness.cases.length; i++) fresh[harness.cases[i][0]] = []
    harness.samples = fresh
    harness.sampler.start()
  }

  // `growing`: the run is opening, so the extent may only rise; else only fall.
  function assertSlides(phase, growing) {
    for (var i = 0; i < harness.cases.length; i++) {
      var c = harness.cases[i], label = c[0] + ", " + phase
      var full = harness.members[c[0]]["implicit" + (c[3] === "width" ? "Width" : "Height")]
      var across = harness.members[c[0]]["implicit" + (c[4] === "width" ? "Width" : "Height")]
      var rows = harness.samples[c[0]]
      var between = false, monotonic = true, crossStill = true, worst = ""
      for (var s = 0; s < rows.length; s++) {
        if (rows[s].along > 0 && rows[s].along < full) between = true
        if (rows[s].across !== across) crossStill = false
        if (s > 0 && (growing ? rows[s].along < rows[s - 1].along : rows[s].along > rows[s - 1].along)) {
          monotonic = false
          if (worst === "") worst = rows[s - 1].along + " -> " + rows[s].along
        }
      }
      harness.check(label + ": the " + c[3] + " passes through the values in between", between, true)
      harness.check(label + ": and only ever moves one way"
                    + (worst ? " (first offending step " + worst + ")" : ""), monotonic, true)
      harness.check(label + ": the " + c[4] + " is left alone", crossStill, true)
    }
  }

  function setOpen(open) {
    // Pinned rather than expanded alone: the fold timer would close an unpinned
    // pocket on its next tick, with no pointer on this bar.
    for (var i = 0; i < harness.cases.length; i++) {
      harness.cases[i][2].sessionPinned = open
      harness.cases[i][2].expanded = open
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
    var members = {}
    for (var i = 0; i < harness.cases.length; i++) {
      var c = harness.cases[i], made = []
      for (var j = 0; j < harness.layoutIds.length; j++)
        made.push(harness.slotComponent.createObject(win.contentItem, { moduleName: harness.layoutIds[j] }))
      made[2].activeItem = c[2]
      c[1].moduleSlots = made
      members[c[0]] = made[1]
    }
    harness.members = members
    harness.next(400)
  }

  function step2() {
    for (var i = 0; i < harness.cases.length; i++) {
      var c = harness.cases[i]
      // Precondition: without it nothing below is about this pocket's member.
      harness.check(c[0] + ": the pocket resolves its member", c[2].resolution.slots.length, 1)
      harness.check(c[0] + ": the member starts tucked away", harness.members[c[0]].visible, false)
    }
    harness.startSampling()
    harness.setOpen(true)
    harness.next(800)
  }

  function step3() {
    harness.sampler.stop()
    harness.assertSlides("opening", true)

    // Fully out: the host's sizing is back, so a member that grows is followed.
    for (var i = 0; i < harness.cases.length; i++) {
      var c = harness.cases[i], slot = harness.members[c[0]]
      var key = c[3] === "width" ? "implicitWidth" : "implicitHeight"
      slot[key] = slot[key] + 10
      harness.check(c[0] + ": fully out, the member follows its own size", slot[c[3]], slot[key])
    }

    harness.startSampling()
    harness.setOpen(false)
    harness.next(900)
  }

  function step4() {
    harness.sampler.stop()
    harness.assertSlides("closing", false)

    for (var i = 0; i < harness.cases.length; i++) {
      var c = harness.cases[i]
      harness.check(c[0] + ": closed, the member is tucked away again", harness.members[c[0]].visible, false)
    }

    var made = []
    for (var j = 0; j < harness.layoutIds.length; j++)
      made.push(harness.slotComponent.createObject(win.contentItem, { moduleName: harness.layoutIds[j] }))
    harness.unloadedBar.moduleSlots = made
    harness.unloadedMember = made[1]
    win.unloadable.active = true
    made[2].activeItem = win.unloadable.item
    harness.next(400)
  }

  function step5() {
    // Precondition: the pocket is holding the member, or unloading it proves nothing.
    harness.check("unloaded pocket: the member starts tucked away", harness.unloadedMember.visible, false)
    win.unloadable.active = false
    harness.next(100)
  }

  function step6() {
    var slot = harness.unloadedMember
    harness.check("unloaded pocket: the member is given back", slot.visible, true)
    slot.implicitWidth = slot.implicitWidth + 10
    harness.check("unloaded pocket: the member still follows its own size", slot.width, slot.implicitWidth)

    console.warn(harness.failures === 0 ? "QML OK" : "QML FAILURES " + harness.failures)
    Qt.exit(harness.failures === 0 ? 0 : 1)
  }
}
