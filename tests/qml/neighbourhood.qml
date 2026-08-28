import QtQuick
import Quickshell
import qs.Commons
import "plugin" as Pk
import "host/BarModel.js" as Host

// The whole neighbourhood of the mark, swept rather than argued about.
//
// The bar's drop marker is the pocket's only input, and where that marker
// lands is a question of geometry the plugin cannot answer for itself: module
// slots sit flush against one another, so every gap is at exactly the same
// distance from the two slots against it, and `nearestDropTarget()` breaks the
// tie by keeping the first candidate it walked. This file therefore drives the
// HOST's own `nearestDropTarget()` over a stand-in geometry and feeds its
// answer to the real widget, which is the only way to see the two together
// without a running bar and a hand on the mouse.
//
// The stand-in geometry is laid out from what the pocket has actually hidden,
// so opening and closing it moves the slots the way the bar's `Row` does. Two
// things this cannot see: a host that puts spacing between its slots, which
// would end the ties this whole construction rests on, and the second copy the
// bar builds of every centre widget with `centerAnchor` set, whose
// registration order is its own. Both are named in docs/decisions/0008.
//
// Needs a window: `Model.ownsSlot()` refuses every slot to an instance that
// does not know which surface it is on, so a `QtObject` harness resolves
// nothing and would assert an empty stage. tests/qml/run.sh runs this case
// offscreen for that reason, and only this one.
QtObject {
  id: harness

  // The pocket's own section as a bar really carries it: something wide on the
  // far side of the run, four members, the mark, and two widgets behind it, so
  // that "two slots past the mark" exists to be swept.
  readonly property var ids: ["omarchy.tray", "omaplug", "ianswope.snapshots", "mehiel.darky",
                              "omarchy.tailscale", "jrmmhm.pocket", "jerome.claude-attention",
                              "jerome.focus"]
  readonly property var widths: ({ "omarchy.tray": 64 })
  readonly property string members: "omaplug, ianswope.snapshots, mehiel.darky, omarchy.tailscale"

  property var slots: []
  property var otherWindow: null

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
      // Whether this slot answers as belonging to another bar surface. One
      // slot can be moved to a second window that way, which is what the
      // per-surface half of the mark's light has to be shown refusing.
      property bool foreignSurface: false
    }
  }

  property QtObject fakeBar: QtObject {
    id: fakeBar
    property var barDragSource: null
    property var barDragTarget: null
    property var barDragTargetGeometry: null
    property bool barDragAfter: false
    property var moduleSlots: []
    property var layoutConfig: ({ left: [], center: [], right: [] })
    property string centerAnchor: ""
    property var activePopout: null
    property bool barHovered: false
    property bool vertical: false
    property color urgent: "#d06a7e"
    property QtObject shell: null
    function canonicalWidgetId(id) { return id }
    function slotWindow(slot) { return slot && slot.foreignSurface ? harness.otherWindow : harness.win }
    function sameWindow(left, right) { return !!left && !!right && left === right }
    function dropMarkerRect(slot, after) {
      return { x: after ? 900 : 800, y: 0, width: 4, height: 30 }
    }
  }

  property FloatingWindow win: FloatingWindow {
    id: win
    visible: true
    property Pk.BarWidget pocketItem: Pk.BarWidget {
      parent: win.contentItem
      bar: harness.fakeBar
      settings: ({ members: harness.members })
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

  // The mark's own button, found by the property it carries rather than by its
  // index among the children, which is not something to depend on.
  function markButton() {
    var kids = harness.pocket.children
    for (var i = 0; i < kids.length; i++) {
      if (kids[i] && "activeColor" in kids[i]) return kids[i]
    }
    return null
  }

  // Lay the drawn slots out end to end, exactly as `Row { spacing: 0 }` does,
  // skipping what the pocket has hidden. Reading the pocket's own writes here
  // is the point: the collapsed run really is zero wide, and that is what puts
  // the outer neighbour's edge flush against the mark's.
  function layout() {
    var x = 0
    for (var i = 0; i < harness.slots.length; i++) {
      var slot = harness.slots[i]
      slot.x = x
      if (slot.visible) x += slot.width
    }
  }

  // What the bar would draw for a pointer at `px`, from the host's own
  // function and the host's own candidate filter.
  function marker(px, source) {
    var rows = []
    for (var i = 0; i < harness.slots.length; i++) {
      var slot = harness.slots[i]
      if (slot === source || !slot.visible || slot.width <= 0) continue
      rows.push({ slot: slot, x: slot.x, y: 0, width: slot.width, height: slot.height })
    }
    return Host.nearestDropTarget(rows, { x: px, y: 0 }, false)
  }

  // One position of one drag: put the bar's own answer where the bar puts it,
  // then read what the pocket makes of it.
  //
  // All three values, in the order `Bar.qml` assigns them on every pointer
  // move, and the geometry last. It is not decoration: the geometry is a fresh
  // object every time, so its change signal is the one that reaches the pocket
  // on a move that leaves the side alone — write only the side and two
  // consecutive positions on the same side notify nothing at all.
  function ask(px, sourceId) {
    var source = harness.slotFor(sourceId)
    var drop = harness.marker(px, source)
    harness.fakeBar.barDragSource = source
    harness.fakeBar.barDragTarget = drop ? drop.slot : null
    harness.fakeBar.barDragAfter = drop ? drop.after : false
    harness.fakeBar.barDragTargetGeometry = drop
      ? harness.fakeBar.dropMarkerRect(drop.slot, drop.after) : null
    return harness.pocket.dropIntent
  }

  function endDrag() {
    harness.fakeBar.barDragSource = null
    harness.fakeBar.barDragTarget = null
    harness.fakeBar.barDragTargetGeometry = null
    harness.fakeBar.barDragAfter = false
  }

  property int step: 0

  // Driven from a repeating timer for the reason steer.qml records, and in
  // several steps because the pocket opens and folds over animations that no
  // amount of assertion can hurry.
  property Timer driver: Timer {
    interval: 300
    repeat: true
    running: true
    onTriggered: harness.next()
  }

  function next() {
    harness.step++
    if (harness.step === 1) return harness.build()
    if (harness.step === 2) return harness.sweepCollapsed()
    if (harness.step === 3) return harness.checkSteering()
    if (harness.step === 4) return harness.openPocket()
    if (harness.step === 5) return harness.sweepOpen()
    if (harness.step === 6) return harness.checkMembershipLatch()
    if (harness.step === 7) return harness.checkRepeatedIds()
    if (harness.step === 8) return harness.checkRefusedLight()
    if (harness.step === 9) return harness.finish()
  }

  // The pocket's own write comes back in the middle of the gesture, and the
  // gesture must not change its mind about it.
  //
  // A members-only change is an inline settings delta, so the host assigns the
  // new list to every instance's `settings` — while, on a bar with more than one
  // surface, another instance's falling edge is still running inside the single
  // `barDragSource = null` that started all of this. Assigning `settings` here
  // is that event, to the byte. Before the snapshot the stripped membership
  // turned the source into a stranger, `dropDecision()` answered "add", and the
  // widget that had just come out went straight back in. docs/decisions/0009
  // owns the recordings and the timings.
  //
  // Three positions, because two reads take the membership and one case cannot
  // see both. The first two are watched red on the missing snapshot itself. The
  // third is green either way today and is here for the other read: leave
  // `dropGapTouchesMember` on the live list and it answers "remove", because
  // neither slot against that gap is a member any more.
  function checkMembershipLatch() {
    harness.layout()
    var mark = harness.slotFor("jrmmhm.pocket")
    var stripped = "ianswope.snapshots, mehiel.darky, omarchy.tailscale"

    harness.check("a member past the middle of the dots is on its way out",
      harness.ask(mark.x + mark.width - 1, "omaplug"), "remove")
    harness.pocket.settings = { members: stripped }
    harness.check("and the pocket's own removal, patched back mid-gesture, does not turn it around",
      harness.pocket.dropIntent, "remove")
    harness.check("nor reaches the sample the drop is committed from",
      harness.pocket.pendingIntent, "remove")
    harness.endDrag()
    harness.pocket.settings = { members: harness.members }

    // Against the dots the bar names the last member with the marker on its far
    // side, which is the mark's near edge under its other name — so `aimsAtSelf`
    // holds here, and a stripped membership answered "add" at the one position
    // the README promises is a reorder.
    harness.check("against the dots a member is only reordered",
      harness.ask(mark.x + 1, "omaplug"), "none")
    harness.pocket.settings = { members: stripped }
    harness.check("and it stays a reorder when the removal is patched in",
      harness.pocket.dropIntent, "none")
    harness.endDrag()
    harness.pocket.settings = { members: harness.members }

    harness.check("at the outer edge of the run it is a reorder too",
      harness.ask(70, "omaplug"), "none")
    harness.pocket.settings = { members: stripped }
    harness.check("and that gap keeps reading as inside the group",
      harness.pocket.dropIntent, "none")
    harness.endDrag()
    harness.pocket.settings = { members: harness.members }

    harness.check("the snapshot does not outlive the drag",
      harness.pocket.dragMembers.length, 0)
    // And the decision falls back to the live list outside a gesture, which is
    // what an instance built while a drag is already running depends on: it saw
    // no rising edge, so it has no snapshot, and serving it the empty one would
    // make every widget on the bar read as a stranger.
    harness.check("and outside a drag the decision is back on the live list",
      harness.pocket.gestureMembers.length, 4)
  }

  // A section that carries the same widget twice — the host allows it for a
  // spacer and for the indicators — must still name the pocket's own
  // neighbour. Taking the first slot with the right id for every entry answers
  // with the earlier copy twice: the near edge stays unfixed and a gap two
  // slots further out arms the pocket instead. Both were measured before the
  // walk started consuming the slots it had used.
  function checkRepeatedIds() {
    var ids = ["omarchy.spacer", "omarchy.tray", "omarchy.spacer", "jrmmhm.pocket", "jerome.focus"]
    var made = [], entries = []
    for (var i = 0; i < ids.length; i++) {
      made.push(harness.slotComponent.createObject(harness, { moduleName: ids[i] }))
      entries.push({ id: ids[i] })
    }
    harness.slots = made
    harness.slotFor("jrmmhm.pocket").activeItem = harness.pocket
    harness.pocket.settings = { members: "" }
    harness.fakeBar.layoutConfig = { left: [], center: [], right: entries }
    harness.fakeBar.moduleSlots = made
    harness.layout()

    var mark = harness.slotFor("jrmmhm.pocket")
    harness.check("the mark's neighbour is the second copy of the repeated id, not the first",
      harness.pocket.slotBeforeSelf, made[2])
    harness.check("an empty pocket still takes a widget in at its near edge",
      harness.ask(mark.x - 1, "jerome.focus"), "add")
    harness.check("and the far half of the copy two slots out is left alone",
      harness.ask(made[0].x + made[0].width - 1, "jerome.focus"), "none")
    harness.endDrag()
  }

  function build() {
    var made = [], entries = []
    for (var i = 0; i < harness.ids.length; i++) {
      var id = harness.ids[i]
      made.push(harness.slotComponent.createObject(harness, {
        moduleName: id, width: harness.widths[id] !== undefined ? harness.widths[id] : 32
      }))
      entries.push({ id: id })
    }
    harness.slots = made
    harness.slotFor("jrmmhm.pocket").activeItem = harness.pocket
    harness.fakeBar.layoutConfig = { left: [], center: [], right: entries }
    harness.fakeBar.moduleSlots = made

    // Without these the sweep would assert an empty stage rather than a
    // resolved one, and every answer below would be right for the wrong reason.
    harness.check("the pocket finds its own slot",
      harness.pocket.ownSlot === harness.slotFor("jrmmhm.pocket"), true)
    harness.check("and it drives its four members",
      harness.pocket.driven.length, 4)
    harness.check("which it has hidden, because nothing is hovering it",
      harness.slotFor("omaplug").visible, false)
  }

  // A widget that is not a member, arriving while the pocket is closed. The
  // hidden run is zero wide, so the widget outside it stands flush against the
  // mark and the bar names their shared gap by that widget — the near half of
  // the mark, which used to answer "none".
  function sweepCollapsed() {
    harness.layout()
    var mark = harness.slotFor("jrmmhm.pocket")
    harness.check("the collapsed run leaves the mark against its outer neighbour",
      mark.x, 64)

    harness.check("the mark's near edge takes a widget in",
      harness.ask(mark.x + 1, "jerome.focus"), "add")
    harness.check("and so does the far half of the neighbour drawn before it",
      harness.ask(mark.x - 1, "jerome.focus"), "add")
    harness.check("the mark's far half takes it in, as it always did",
      harness.ask(mark.x + mark.width - 1, "jerome.focus"), "add")
    harness.check("and so does the near half of the widget behind it",
      harness.ask(mark.x + mark.width + 1, "jerome.focus"), "add")

    // The zone ends where the next gap begins, which is the middle of the
    // neighbours on either side. Both of these were "none" before and after.
    harness.check("the outer neighbour's own near half is left alone",
      harness.ask(1, "jerome.focus"), "none")
    harness.check("and so is the far half of the widget behind the mark",
      harness.ask(mark.x + mark.width + 31, "jerome.focus"), "none")

    harness.check("the mark lights while a release would collect the widget",
      harness.pocket.dropArmed, false)
    harness.ask(mark.x + 1, "jerome.focus")
    harness.check("the mark is lit on the near edge too",
      harness.pocket.dropArmed, true)
    harness.check("in the colour the bar gives an active widget",
      harness.markButton().activeColor, harness.fakeBar.urgent)
    harness.endDrag()
  }

  // Steering is the one thing that may NOT follow the widened question: the
  // marker rect is computed from this pocket's own slot, and the bar places the
  // widget from `barDragTarget`, which on the near edge is the neighbour.
  function checkSteering() {
    var mark = harness.slotFor("jrmmhm.pocket")

    harness.check("a near-edge arrival still arms the pocket",
      harness.ask(mark.x + 1, "jerome.focus"), "add")
    harness.check("but the bar's marker side is left where the bar put it",
      harness.fakeBar.barDragAfter, true)
    harness.check("and its geometry too, rather than moved to this pocket",
      harness.fakeBar.barDragTargetGeometry.x, 900)

    // The same stage one pixel further in, where the bar does name the pocket:
    // there the steering applies, so the refusal above is a refusal and not a
    // steering that never worked.
    harness.check("aimed at the mark itself it arms as well",
      harness.ask(mark.x + mark.width - 1, "jerome.focus"), "add")
    harness.check("and there the pocket does steer the side",
      harness.fakeBar.barDragAfter, false)
    harness.check("and moves the marker with it",
      harness.fakeBar.barDragTargetGeometry.x, 800)
    harness.endDrag()
  }

  function openPocket() {
    harness.slotFor("omaplug").hovered = true
    harness.check("hovering a member opens the pocket", harness.pocket.expanded, true)
  }

  // A member on its way out, with the run fanned out under the pointer. The
  // answer flips at the middle of the mark, which is where the gap behind it
  // begins — the collision the README's two promises meet on, measured rather
  // than argued.
  function sweepOpen() {
    harness.layout()
    var mark = harness.slotFor("jrmmhm.pocket")
    harness.check("the open run puts the mark behind its four members",
      mark.x, 192)

    harness.check("dropped inside the run, a member is only reordered",
      harness.ask(140, "omaplug"), "none")
    harness.check("against the dots, it is still only reordered",
      harness.ask(mark.x + 1, "omaplug"), "none")
    harness.check("past the middle of the dots, it leaves",
      harness.ask(mark.x + mark.width - 1, "omaplug"), "remove")
    harness.check("one slot past the mark it leaves",
      harness.ask(mark.x + mark.width + 20, "omaplug"), "remove")
    harness.check("two slots past the mark it leaves",
      harness.ask(mark.x + mark.width + 40, "omaplug"), "remove")

    harness.ask(mark.x + mark.width - 1, "omaplug")
    harness.check("the mark answers the way out as well",
      harness.pocket.dropReleases, true)
    harness.check("in the colour the bar draws its own insertion line in",
      harness.markButton().activeColor, Color.accent)
    harness.check("and it is lit, not merely intending to be",
      harness.markButton().active, true)

    // The way out is decided from ids alone, so every screen's pocket reaches
    // it at once. Only the surface the drag is on may light up.
    harness.slotFor("omaplug").foreignSurface = true
    harness.check("a member being dragged on another surface still means remove",
      harness.ask(mark.x + mark.width - 1, "omaplug"), "remove")
    harness.check("but this pocket's mark stays dark for it",
      harness.pocket.dropReleases, false)
    harness.slotFor("omaplug").foreignSurface = false
    harness.endDrag()
  }

  // A second pocket entry means neither pocket writes anything at all, which
  // the mark did not use to know: it lit, the drop was refused, and nothing
  // said so. The decision itself is unchanged — only what the mark claims.
  function checkRefusedLight() {
    var entries = harness.fakeBar.layoutConfig.right.slice()
    entries.push({ id: "jrmmhm.pocket" })
    harness.fakeBar.layoutConfig = { left: [], center: [], right: entries }
    harness.check("a second entry takes the write permission away",
      harness.pocket.mayWriteMembers, false)

    var mark = harness.slotFor("jrmmhm.pocket")
    harness.check("the drop still decides the same way",
      harness.ask(mark.x + 1, "jerome.focus"), "add")
    harness.check("but the mark no longer promises what the drop would refuse",
      harness.pocket.dropArmed, false)
    harness.endDrag()
  }

  function finish() {
    console.warn(harness.failures === 0 ? "QML OK" : "QML FAILURES " + harness.failures)
    Qt.exit(harness.failures === 0 ? 0 : 1)
  }
}
