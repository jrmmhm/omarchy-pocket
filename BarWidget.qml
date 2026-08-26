import QtQuick
// Quickshell, not just its submodules: the QsWindow attached property used to
// tell this bar surface from the one on the other monitor lives in the base
// module, and without it the lookup silently yields null — at which point one
// screen's pocket would drive the other screen's widgets.
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// A bar widget that tucks its neighbours away.
//
// It never moves a widget. The members stay exactly where the user put them in
// `bar.layout`, in their own module slots, built by the bar itself — the pocket
// only flips `visible` on those slots, and a Row does not lay out an invisible
// child. That is the whole mechanism, and it is the reason every Omarchy tool
// keeps telling the truth about a tucked-away widget: `inBar` still finds it,
// `findPanelWidget` still finds it, its settings still live on its own entry.
//
// The alternative — mounting other widgets' components inside this one — is
// what ianswope.stack does, and it forces the members out of `bar.layout`,
// which is where all four of its defects come from.
BarWidget {
  id: root
  moduleName: "jrmmhm.pocket"

  // ------------------------------------------------------------- settings

  readonly property var memberIds: Model.parseMembers(setting("members", ""), root.moduleName)
  readonly property var rejectedIds: Model.rejectedMembers(setting("members", ""), root.moduleName)
  readonly property bool showCount: setting("showCount", true) === true

  // ------------------------------------------------------------- identity

  // The bar exists once per monitor and every surface's slots land in the same
  // `bar.moduleSlots` array, so a pocket has to filter to its own window or it
  // would hide the other screen's widgets too.
  readonly property var ownWindow: root.QsWindow ? root.QsWindow.window : null

  function canonical(id) {
    return bar && typeof bar.canonicalWidgetId === "function"
      ? bar.canonicalWidgetId(String(id || ""))
      : String(id || "")
  }

  // A custom bar may not carry centerAnchor at all; treat that as "no anchor".
  readonly property string anchorId: bar && ("centerAnchor" in bar) ? canonical(bar.centerAnchor) : ""

  // ----------------------------------------------------------- resolution

  // Reading `bar.moduleSlots` and `bar.centerAnchor` inside the binding is what
  // makes this reactive: the array is replaced on every register/unregister, so
  // a layout rebuild — which destroys and recreates every slot — re-runs this
  // and lets apply() re-assert the tucked state the rebuild reset.
  readonly property var resolution: {
    var slots = bar ? bar.moduleSlots : []
    var ids = root.memberIds
    var anchor = root.anchorId
    var mine = root.ownWindow

    var found = [], missing = [], anchored = [], foreign = []

    for (var i = 0; i < ids.length; i++) {
      var want = root.canonical(ids[i])
      var hit = null

      for (var j = 0; j < slots.length; j++) {
        var slot = slots[j]
        if (!slot || root.canonical(slot.moduleName) !== want) continue
        if (mine && bar && typeof bar.slotWindow === "function" && typeof bar.sameWindow === "function"
            && !bar.sameWindow(bar.slotWindow(slot), mine)) continue
        hit = slot
        break
      }

      if (hit === null) { missing.push(ids[i]); continue }

      // The anchored center slot is the one place in Bar.qml where a module
      // slot's `visible` carries a binding of the host's own. Writing it would
      // destroy that binding for the rest of the session, and nothing would
      // report it. Refuse instead, and say so in the tooltip.
      if (anchor !== "" && hit.region === "center" && want === anchor) {
        anchored.push(ids[i])
        continue
      }

      if (hit.region !== root.ownRegion && root.ownRegion !== "") foreign.push(ids[i])
      found.push(hit)
    }

    return { slots: found, missing: missing, anchored: anchored, foreign: foreign }
  }

  // Which section this pocket itself sits in, read off its own slot so a member
  // in a different section can be called out as the layout mistake it is.
  readonly property string ownRegion: {
    var slots = bar ? bar.moduleSlots : []
    var mine = root.ownWindow
    for (var i = 0; i < slots.length; i++) {
      var slot = slots[i]
      if (!slot || slot.activeItem !== root) continue
      if (mine && bar && typeof bar.slotWindow === "function" && typeof bar.sameWindow === "function"
          && !bar.sameWindow(bar.slotWindow(slot), mine)) continue
      return String(slot.region || "")
    }
    return ""
  }

  // ---------------------------------------------------------------- state

  property bool expanded: false
  property bool pinned: false
  property int drawnCount: 0

  // Every slot this pocket has currently set to invisible. Kept as its own list
  // rather than derived from `resolution`, because the restore has to reach
  // slots that have *left* the member list — and, on destruction, slots the
  // binding can no longer be evaluated for.
  property var driven: []

  readonly property bool selfHovered: pocketHover.hovered

  readonly property bool memberHovered: {
    var list = root.resolution.slots
    for (var i = 0; i < list.length; i++) if (list[i] && list[i].hovered) return true
    return false
  }

  // A bar panel covers the whole screen with an input mask while it is open, so
  // no hover reaches the bar at all during that time. Without this the pocket
  // would fold up underneath the panel the user just opened from it.
  readonly property bool memberPanelOpen: {
    var active = bar ? bar.activePopout : null
    if (!active) return false
    var list = root.resolution.slots
    for (var i = 0; i < list.length; i++) if (list[i] && list[i].activeItem === active) return true
    return false
  }

  readonly property bool holdOpen: pinned || selfHovered || memberHovered || memberPanelOpen

  readonly property bool duplicateInstances: {
    if (!bar || typeof bar.moduleWidgets !== "function") return false
    return bar.moduleWidgets(root.moduleName).length > 1
  }

  // --------------------------------------------------------------- effect

  function slotIsDrawn(slot) {
    return !!slot && !!slot.activeItem && slot.activeItem.visible === true && slot.width > 0
  }

  function measure() {
    var list = root.resolution.slots
    var n = 0
    for (var i = 0; i < list.length; i++) if (root.slotIsDrawn(list[i])) n++
    root.drawnCount = n
  }

  function setSlotVisible(slot, value) {
    // Slots die with the bar surface, and a rebuild can hand us one mid-teardown.
    try { if (slot) slot.visible = value } catch (e) { }
  }

  function apply() {
    var wanted = root.resolution.slots

    // Anything we previously hid and no longer own goes back first — a member
    // removed from the setting, or refused as the center anchor, must not stay
    // invisible just because it left the list.
    for (var i = 0; i < root.driven.length; i++) {
      var old = root.driven[i]
      if (wanted.indexOf(old) === -1) root.setSlotVisible(old, true)
    }

    // Counting has to happen while the members are still drawn: once they are
    // invisible, Qt's effective-visibility cascade makes "hidden by us" and
    // "hid itself" read exactly the same, and the count would decay to zero.
    if (!root.expanded) root.measure()

    for (var j = 0; j < wanted.length; j++) root.setSlotVisible(wanted[j], root.expanded)

    root.driven = root.expanded ? [] : wanted.slice()

    // Geometry does not settle in the tick that writes `visible`, so a count
    // taken right here would read the previous frame.
    if (root.expanded) Qt.callLater(root.measure)
  }

  function revealAll() {
    for (var i = 0; i < root.driven.length; i++) root.setSlotVisible(root.driven[i], true)
    root.driven = []
  }

  onResolutionChanged: apply()
  onExpandedChanged: apply()

  // A rebuild can hand the pocket back with the pointer already resting on it,
  // and holdOpen would then never *change* — it was already true when this
  // instance was born.
  Component.onCompleted: {
    if (holdOpen) expanded = true
    apply()
  }

  // Without this, disabling or hot-reloading the plugin leaves someone else's
  // widgets invisible with no way back short of restarting the shell.
  Component.onDestruction: revealAll()

  onHoldOpenChanged: if (holdOpen) expanded = true

  // A repeating tick rather than a one-shot restarted on hover-end. Omarchy's
  // own bar polls hover the same way for its tooltip, for the same reason: a
  // leave event is not something to build a state machine on. A one-shot can be
  // spent by a hover-end that the guard below then refuses, after which nothing
  // re-arms it and the pocket stays open forever.
  Timer {
    interval: 120
    repeat: true
    running: root.expanded && !root.pinned
    onTriggered: {
      if (root.holdOpen) return
      // Folding up widens nothing but narrows the section, which slides the
      // pocket itself out from under a stationary pointer — and the pointer
      // landing on a neighbour would fold it, moving it back, and so on. Hold
      // until the pointer has left the bar entirely, which is the same rule
      // Bar.qml applies to its own hover reveal.
      if (root.bar && root.bar.barHovered) return
      root.expanded = false
    }
  }

  // ----------------------------------------------------------------- view

  readonly property string countText: Model.countText(root.drawnCount, root.showCount && !root.expanded)

  // Chevron pointing the way the members lie: closed it points at them, open it
  // points back at the pocket. Written as code points because the glyphs are
  // unreadable in an editor and in a diff.
  readonly property string glyph: root.expanded
    ? String.fromCodePoint(0xf054)
    : String.fromCodePoint(0xf053)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  HoverHandler { id: pocketHover }

  TextMetrics {
    id: countMetrics
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.bar.iconFont
    text: root.countText
  }

  BarIconButton {
    id: button
    bar: root.bar
    slotSize: Style.bar.iconSlot + (root.countText !== "" ? countMetrics.width + Style.space(3) : 0)
    tooltipText: Model.describe({
      members: root.memberIds, expanded: root.expanded, pinned: root.pinned,
      rejected: root.rejectedIds, missing: root.resolution.missing,
      anchored: root.resolution.anchored, foreign: root.resolution.foreign,
      duplicateInstances: root.duplicateInstances
    })
    active: root.pinned

    iconComponent: Component {
      Item {
        Row {
          anchors.centerIn: parent
          spacing: Style.space(3)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.glyph
            textFormat: Text.PlainText
            color: button.foreground
            font.family: button.fontFamily
            font.pixelSize: Style.bar.iconFont
            renderType: Text.NativeRendering
            rotation: root.vertical ? 90 : 0
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.countText !== ""
            text: root.countText
            textFormat: Text.PlainText
            color: button.foreground
            font.family: button.fontFamily
            font.pixelSize: Style.bar.iconFont
            renderType: Text.NativeRendering
          }
        }
      }
    }

    // The pointer is the primary gesture; the click is the way out of the cases
    // where no leave event is coming — a panel grabbing input, a workspace
    // switch teleporting the cursor. Session-only on purpose: persisting it
    // would mean writing shell.json, and a half-written shell.json drops the
    // bar back to Omarchy's defaults, deregistering every third-party widget
    // on it for as long as that lasts.
    onPressed: function(code) {
      root.pinned = !root.pinned
      if (root.pinned) root.expanded = true
    }
  }
}
