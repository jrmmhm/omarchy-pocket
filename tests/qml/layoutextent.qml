import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Ui
import "plugin" as Pk

// The neighbours slide on a bar whose sections are layouts.
//
// From Omarchy 4.5.0 on, a section is a GridLayout (Bar.qml::ModuleList), and
// a layout does not read a slot's `width`: it sizes the slot from its
// `Layout.preferredWidth`, which the host binds to the slot's full size
// (Bar.qml::ModuleSlot). A pocket that drives `width` there is overruled on
// the next layout pass, and everything beside the run jumps by the run's whole
// length in one frame -- measured on the live bar in docs/decisions/0026.
//
// So the slots here are laid out by GridLayouts and carry the host's two lines,
// `implicitWidth` along the bar and `Layout.preferredWidth: implicitWidth`.
// Asserted per bar, horizontal and vertical: the widget after the member moves
// through the positions in between while the pocket opens and while it folds,
// one way each time; fully out, the member follows its own size again, up and
// down to nothing without leaving a hole; and a pocket unloaded while it holds
// the member, as a hot reload does, leaves it following its own size
// (docs/decisions/0023, 0027).
//
// Then a pocket in the `center` section of a bar that publishes no
// `centerAnchor`, as 4.5.0 does not: its member is a member, not refused as the
// centre anchor. Beside it, the answers of a host older than 4.5.0, which must
// not change: a centre member in a Row is a member, and one hanging beside the
// sections, where the old centre anchor hung, is refused.
//
// Needs a window: Model.ownsSlot() refuses every slot to an instance that does
// not know its surface. tests/qml/run.sh runs this case offscreen.
QtObject {
  id: harness

  readonly property string selfId: "jrmmhm.pocket"
  readonly property string memberId: "omaplug"
  readonly property var layoutIds: ["omarchy.tray", "omaplug", "jrmmhm.pocket"]

  // The host's ModuleSlot, as far as sizing goes.
  property Component slotComponent: Component {
    Item {
      property string moduleName: ""
      property string region: "right"
      property var activeItem: null
      property bool hovered: false
      property bool vertical: false
      property real along: 40
      property real across: 24
      implicitWidth: vertical ? across : along
      implicitHeight: vertical ? along : across
      Layout.preferredWidth: implicitWidth
      Layout.preferredHeight: implicitHeight
      Layout.alignment: Qt.AlignLeft | Qt.AlignTop
    }
  }

  function layout(region) {
    var out = { left: [], center: [], right: [] }
    out[region] = [{ id: "omarchy.tray" }, { id: harness.memberId },
                   { id: harness.selfId, members: harness.memberId }]
    return out
  }

  component FakeBar: QtObject {
    property var barDragSource: null
    property var barDragTarget: null
    property var barDragTargetGeometry: null
    property bool barDragAfter: false
    property var moduleSlots: []
    property var layoutConfig: harness.layout("right")
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

  // As FakeBar, without `centerAnchor`: the host's facade carries none.
  component AnchorlessBar: QtObject {
    property var barDragSource: null
    property var barDragTarget: null
    property var barDragTargetGeometry: null
    property bool barDragAfter: false
    property var moduleSlots: []
    property var layoutConfig: harness.layout("center")
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

  property FakeBar rowBar: FakeBar { vertical: false }
  property FakeBar columnBar: FakeBar { vertical: true }
  property FakeBar unloadedBar: FakeBar { vertical: false }
  property AnchorlessBar centreBar: AnchorlessBar { }
  // The same question on a host older than 4.5.0, which must answer as it
  // always did: a centre slot in a Row is a member, one hanging beside the
  // sections (the old centre anchor's place) is refused.
  property AnchorlessBar rowCentreBar: AnchorlessBar { }
  property AnchorlessBar anchorCentreBar: AnchorlessBar { }
  property var unloadedMember: null
  property var centreMember: null
  property var rowCentreMember: null

  property FloatingWindow win: FloatingWindow {
    id: win
    visible: true
    implicitWidth: 400
    implicitHeight: 300

    property GridLayout rowGrid: GridLayout {
      parent: win.contentItem
      y: 0
      flow: GridLayout.LeftToRight
      rowSpacing: 0
      columnSpacing: 0
    }
    property GridLayout columnGrid: GridLayout {
      parent: win.contentItem
      x: 300
      flow: GridLayout.TopToBottom
      rowSpacing: 0
      columnSpacing: 0
    }
    property GridLayout unloadedGrid: GridLayout {
      parent: win.contentItem
      y: 100
      flow: GridLayout.LeftToRight
      rowSpacing: 0
      columnSpacing: 0
    }
    property GridLayout centreGrid: GridLayout {
      parent: win.contentItem
      y: 200
      flow: GridLayout.LeftToRight
      rowSpacing: 0
      columnSpacing: 0
    }

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
    property Pk.BarWidget centrePocket: Pk.BarWidget {
      parent: win.contentItem
      bar: harness.centreBar
      settings: ({ members: harness.memberId })
    }
    property Row rowCentre: Row { parent: win.contentItem; y: 250 }
    property Item anchorCentre: Item { parent: win.contentItem; y: 280 }
    property Pk.BarWidget rowCentrePocket: Pk.BarWidget {
      parent: win.contentItem
      bar: harness.rowCentreBar
      settings: ({ members: harness.memberId })
    }
    property Pk.BarWidget anchorCentrePocket: Pk.BarWidget {
      parent: win.contentItem
      bar: harness.anchorCentreBar
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

  // [label, bar, pocket, grid, position along the bar, position across it]
  readonly property var cases: [
    ["horizontal layout", harness.rowBar, harness.win.rowPocket, harness.win.rowGrid, "x", "y"],
    ["vertical layout", harness.columnBar, harness.win.columnPocket, harness.win.columnGrid, "y", "x"]
  ]

  property var members: ({})
  property var neighbours: ({})
  property var samples: ({})

  property int failures: 0

  function check(label, actual, expected) {
    if (actual === expected) return
    harness.failures++
    console.warn("FAIL: " + label + "\n  expected: " + expected + "\n  actual:   " + actual)
  }

  function build(grid, bar, region, vertical) {
    var made = []
    for (var j = 0; j < harness.layoutIds.length; j++)
      made.push(harness.slotComponent.createObject(grid, {
        moduleName: harness.layoutIds[j], region: region, vertical: vertical }))
    bar.moduleSlots = made
    return made
  }

  function sample() {
    for (var i = 0; i < harness.cases.length; i++) {
      var c = harness.cases[i], after = harness.neighbours[c[0]]
      harness.samples[c[0]].push({ along: after[c[4]], across: after[c[5]] })
    }
  }

  property Timer sampler: Timer {
    interval: 20
    repeat: true
    onTriggered: harness.sample()
  }

  // The first sample is taken at once, before the pocket is told anything, so
  // a jump in the first frame shows as one.
  function startSampling() {
    var fresh = {}
    for (var i = 0; i < harness.cases.length; i++) fresh[harness.cases[i][0]] = []
    harness.samples = fresh
    harness.sample()
    harness.sampler.start()
  }

  // The widget after the member travels by the member's whole extent between
  // `from` and `to`; it must pass through what lies between, one way.
  function assertSlides(phase, growing) {
    for (var i = 0; i < harness.cases.length; i++) {
      var c = harness.cases[i], label = c[0] + ", " + phase
      var rows = harness.samples[c[0]]
      var first = rows.length ? rows[0].along : NaN, last = rows.length ? rows[rows.length - 1].along : NaN
      var lo = Math.min(first, last), hi = Math.max(first, last)
      var between = 0, monotonic = true, crossStill = true, worst = ""
      for (var s = 0; s < rows.length; s++) {
        if (rows[s].along > lo && rows[s].along < hi) between++
        if (rows[s].across !== rows[0].across) crossStill = false
        if (s > 0 && (growing ? rows[s].along < rows[s - 1].along : rows[s].along > rows[s - 1].along)) {
          monotonic = false
          if (worst === "") worst = rows[s - 1].along + " -> " + rows[s].along
        }
      }
      var trail = []
      for (var t = 0; t < rows.length; t++)
        if (t === 0 || rows[t].along !== rows[t - 1].along) trail.push(rows[t].along)
      harness.check(label + ": the neighbour travels the member's whole extent ("
                    + trail.join(" ") + ")", hi - lo, 40)
      harness.check(label + ": through the positions in between (" + trail.join(" ") + ")",
                    between >= 3, true)
      harness.check(label + ": one way only" + (worst ? " (first offending step " + worst + ")" : ""),
                    monotonic, true)
      harness.check(label + ": and stays put across the bar", crossStill, true)
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

  function extentOf(c, slot) { return c[4] === "x" ? slot.width : slot.height }

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
    var members = {}, neighbours = {}
    for (var i = 0; i < harness.cases.length; i++) {
      var c = harness.cases[i]
      var made = harness.build(c[3], c[1], "right", c[4] === "y")
      made[2].activeItem = c[2]
      members[c[0]] = made[1]
      neighbours[c[0]] = made[2]
    }
    harness.members = members
    harness.neighbours = neighbours
    harness.next(400)
  }

  function step2() {
    for (var i = 0; i < harness.cases.length; i++) {
      var c = harness.cases[i]
      // Preconditions: without them nothing below is about this pocket's member.
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
    for (var i = 0; i < harness.cases.length; i++) harness.members[harness.cases[i][0]].along = 50
    harness.next(50)
  }

  function step4() {
    for (var i = 0; i < harness.cases.length; i++) {
      var c = harness.cases[i], slot = harness.members[c[0]]
      harness.check(c[0] + ": fully out, the member follows its own size up", harness.extentOf(c, slot), 50)
      slot.along = 0
    }
    harness.next(50)
  }

  function step5() {
    for (var i = 0; i < harness.cases.length; i++) {
      var c = harness.cases[i], slot = harness.members[c[0]]
      harness.check(c[0] + ": and down to nothing, leaving no hole", harness.extentOf(c, slot), 0)
      slot.along = 40
    }
    harness.next(50)
  }

  function step6() {
    harness.startSampling()
    harness.setOpen(false)
    harness.next(900)
  }

  function step7() {
    harness.sampler.stop()
    harness.assertSlides("folding", false)

    for (var i = 0; i < harness.cases.length; i++) {
      var c = harness.cases[i]
      harness.check(c[0] + ": folded, the member is tucked away again", harness.members[c[0]].visible, false)
    }

    var made = harness.build(win.unloadedGrid, harness.unloadedBar, "right", false)
    harness.unloadedMember = made[1]
    win.unloadable.active = true
    made[2].activeItem = win.unloadable.item

    var centre = harness.build(win.centreGrid, harness.centreBar, "center", false)
    centre[2].activeItem = win.centrePocket
    harness.centreMember = centre[1]

    var inRow = harness.build(win.rowCentre, harness.rowCentreBar, "center", false)
    inRow[2].activeItem = win.rowCentrePocket
    harness.rowCentreMember = inRow[1]
    var beside = harness.build(win.anchorCentre, harness.anchorCentreBar, "center", false)
    beside[2].activeItem = win.anchorCentrePocket
    harness.next(400)
  }

  function step8() {
    // Precondition: the pocket is holding the member, or unloading it proves nothing.
    harness.check("unloaded pocket: the member starts tucked away", harness.unloadedMember.visible, false)
    // Mid-fold, so the member is handed back while the pocket is driving it.
    win.unloadable.item.expanded = true
    harness.next(150)
  }

  function step9() {
    win.unloadable.active = false

    var p = win.centrePocket
    harness.check("centre: the member is not refused as the centre anchor", p.resolution.anchored.length, 0)
    harness.check("centre: it is resolved as a member", p.resolution.slots.length, 1)
    harness.check("centre: and tucked away", harness.centreMember.visible, false)

    harness.check("centre in a Row: a member, as before 4.5.0",
                  win.rowCentrePocket.resolution.slots.length, 1)
    harness.check("centre in a Row: and tucked away", harness.rowCentreMember.visible, false)
    harness.check("centre beside the sections: still refused as the centre anchor",
                  win.anchorCentrePocket.resolution.anchored.length, 1)
    harness.next(100)
  }

  function step10() {
    var slot = harness.unloadedMember
    harness.check("unloaded pocket: the member is given back", slot.visible, true)
    harness.check("unloaded pocket: at its full size", slot.width, 40)
    slot.along = 55
    harness.next(50)
  }

  function step11() {
    harness.check("unloaded pocket: the member still follows its own size",
                  harness.unloadedMember.width, 55)

    console.warn(harness.failures === 0 ? "QML OK" : "QML FAILURES " + harness.failures)
    Qt.exit(harness.failures === 0 ? 0 : 1)
  }
}
