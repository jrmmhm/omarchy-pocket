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
// Membership can be changed by dragging, and that is the one thing the pocket
// writes: its own `members` key, on its own layout entry, through the host's
// own config mutator. The gesture itself belongs to the bar — the pocket only
// reads the drop marker the bar is already drawing. See
// docs/decisions/0001-pocket-writes-its-own-members.md.
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

  // Positions of entries the parser could not read at all. They are dropped
  // inside toList(), which runs before rejectedIds can see anything, so without
  // this a `members` list made only of them left the tooltip reporting an empty
  // pocket to someone who had configured four widgets.
  readonly property var unreadableAt: Model.unreadableEntries(setting("members", ""))

  // ------------------------------------------------------------- identity

  // The bar exists once per monitor and every surface's slots land in the same
  // `bar.moduleSlots` array, so a pocket has to filter to its own window or it
  // would hide the other screen's widgets too.
  //
  // Null is a state, not an impossibility: a dying instance loses its window
  // while its bindings still run, and a live surface loses its window for as
  // long as a monitor move unmaps it. Both are answered in Model.ownsSlot(),
  // which matches nothing rather than everything. See docs/decisions/0005.
  readonly property var ownWindow: root.QsWindow ? root.QsWindow.window : null

  // Whether the host publishes the two helpers that tell one bar surface's
  // slots from another's. A custom bar need not, and then there is nothing to
  // filter with and one answer to give.
  readonly property bool hostComparesWindows: !!bar
    && typeof bar.slotWindow === "function" && typeof bar.sameWindow === "function"

  // This instance does not know which bar surface it is on. Deliberately not
  // conditioned on the host as well: ownsSlot() refuses on an unknown window
  // whatever the host can do, so conditioning the tooltip differently would let
  // it describe a pocket other than the one on screen.
  readonly property bool surfaceUnknown: ownWindow === null

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
        if (!Model.ownsSlot({
              hostComparesWindows: root.hostComparesWindows,
              surfaceKnown: mine !== null,
              sameWindow: root.hostComparesWindows && mine !== null
                ? bar.sameWindow(bar.slotWindow(slot), mine) : false
            })) continue
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

  // This pocket's own module slot. `activeItem === root` is already exact per
  // instance — every bar surface builds its own — so no window filter belongs
  // here. Identity against this object is also what makes the drop rule below
  // correct on a multi-monitor bar without mapping a single coordinate.
  readonly property var ownSlot: {
    var slots = bar ? bar.moduleSlots : []
    for (var i = 0; i < slots.length; i++) {
      if (slots[i] && slots[i].activeItem === root) return slots[i]
    }
    return null
  }

  // Which section this pocket itself sits in, read off its own slot so a member
  // in a different section can be called out as the layout mistake it is.
  readonly property string ownRegion: ownSlot ? String(ownSlot.region || "") : ""

  // The layout as the bar holds it, which is the only honest answer to "how
  // many pockets are there". Guarded because a custom bar need not have it.
  readonly property var barLayout: bar && ("layoutConfig" in bar) ? bar.layoutConfig : null

  function layoutIds(region) {
    var entries = root.barLayout ? root.barLayout[region] : null
    var out = []
    if (!entries || typeof entries.length !== "number") return out
    for (var i = 0; i < entries.length; i++) out.push(root.canonical(Model.entryIdOf(entries[i])))
    return out
  }

  // ---------------------------------------------------------------- state

  property bool expanded: false
  property bool pinned: false

  // Every slot this pocket has currently taken over. Kept as its own list
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

  // Requiring `expanded` means this can only ever keep the pocket open, never
  // open it. It is needed because hover is not something to fall back on
  // during a drag: Qt delivers no hover events at all while another item holds
  // the mouse grab, so every hover flag is frozen at whatever it last was.
  readonly property bool dragHoldsOpen: expanded && dragSource !== null

  readonly property bool holdOpen: pinned || selfHovered || memberHovered || memberPanelOpen || dragHoldsOpen

  // Counted off the layout rather than off live instances. `bar.moduleWidgets`
  // counts what is mounted, and the bar is built once per monitor — plus a
  // second time for every center widget when centerAnchor is set — so it
  // reported a second pocket on every setup with more than one screen.
  readonly property bool duplicateInstances: Model.countEntries(root.barLayout, root.moduleName) > 1

  // Whether this pocket may act on the layout at all — one property rather than
  // the same pair of conditions repeated at each call site, because the drop
  // steering below has to refuse in exactly the cases the writes refuse in. Two
  // copies of that rule drifting apart is what would let the pocket move a
  // widget the user did not aim there and then not record it as a member.
  readonly property bool mayWriteMembers: Model.mayWrite(root.barLayout, root.moduleName)
    && root.ownRegion !== ""

  // ----------------------------------------------------------------- drag

  // The bar already owns widget drag-and-drop, and it publishes the three
  // values it draws its own drop marker from: the slot being dragged, the slot
  // the drop would land on, and which side of that slot the marker sits on.
  // Reading those three is the whole of this feature. The pocket starts no
  // drag, grabs no pointer, and never asks where the cursor is — so what it
  // decides and what the user is looking at cannot disagree.
  //
  // Pointer coordinates were the obvious alternative and are the wrong tool:
  // Qt delivers no hover at all under a mouse grab, scene coordinates are per
  // window, and a bar surface exists per monitor. Object identity has none of
  // those problems.
  readonly property var dragSource: bar ? bar.barDragSource : null
  readonly property var dragTarget: bar ? bar.barDragTarget : null
  readonly property bool dragAfter: bar ? bar.barDragAfter === true : false
  readonly property string dragSourceId: dragSource ? canonical(dragSource.moduleName) : ""
  readonly property string dragTargetId: dragTarget ? canonical(dragTarget.moduleName) : ""

  // What this pocket held when the drag began, and what the whole gesture is
  // decided against.
  //
  // Deliberately not the live list. A members-only write is an inline settings
  // change, so the host patches it into EVERY instance's `settings` — including
  // the instances whose falling edge has not run yet, because `clearBarDrag()`
  // nulls `barDragSource` in one statement and the entire cascade, this
  // pocket's write included, happens inside it. The instance the drag is aimed
  // at then recomputes with the member already stripped while its own slot is
  // still the drop target, and `dropDecision()` reads that as a widget arriving
  // from outside: the gesture that has just taken a widget out puts it straight
  // back, within the same handful of milliseconds. It needs a second instance to
  // happen at all, which is why a single-window harness never saw it. Both write
  // recordings and their timings are in docs/decisions/0009.
  //
  // Copied rather than referenced, so that the snapshot does not rest on
  // Model.parseMembers() returning a fresh array on every evaluation.
  property var dragMembers: []

  // Read by the drop decision and by nothing else. What the pocket holds NOW —
  // `resolution`, the tooltip, `misplacedMember`, `membersMisordered` — stays on
  // the live list: those describe the bar, not the gesture, and freezing them
  // would make the tooltip contradict the widgets beside it.
  readonly property var gestureMembers: root.dragSeen ? root.dragMembers : root.memberIds

  // The gap the bar is drawing its line in, answered from ids rather than from
  // this instance's own resolved slots. `resolution` is filtered to one window,
  // and the bar is built once per monitor — reading it here made the instance
  // the drag was NOT on see every member as a stranger and eject it.
  readonly property bool dropGapTouchesMember: Model.gapTouchesMember(
    root.layoutIds(root.ownRegion), root.gestureMembers, root.dragTargetId, root.dragAfter)

  // The slot the bar names when it draws its line against the mark's NEAR edge.
  //
  // Module slots sit flush against one another — Bar.qml lays them out in a
  // `Row` with `spacing: 0` — so that edge is at exactly the same distance from
  // two candidates, and `BarModel.nearestDropTarget()` breaks the tie by
  // keeping the first one it walked. `moduleSlots` is appended in slot creation
  // order, which is layout order, so the pocket loses the tie at its near edge
  // to whatever is drawn before it and wins the one at its far edge. Measured
  // across the whole neighbourhood in docs/decisions/0008.
  //
  // Walked in layout order rather than in `moduleSlots` order, because the two
  // agree everywhere except for the second copy the bar builds of every centre
  // widget when `centerAnchor` is set, whose registration order is its own.
  //
  // Reading `slot.visible` here is not the loop 0002 refused. That one read it
  // inside the binding that writes it; nothing downstream of this one writes
  // `visible` — it reaches the drop decision, the mark's colour and the
  // steering, and stops there.
  readonly property var slotBeforeSelf: {
    var ids = root.layoutIds(root.ownRegion)
    var slots = bar ? bar.moduleSlots : []
    var mine = root.ownWindow
    var last = null
    // A slot answers for one layout entry and then steps aside. The host lets
    // some widgets be added twice — a spacer, the indicators — and taking the
    // first slot carrying the id every time would answer with the earlier copy
    // for both of them: the mark's real neighbour would go unrecognised while
    // a gap further out armed the pocket instead. Slots are created in layout
    // order, so consuming them in that order pairs the nth entry with the nth
    // slot.
    var used = []

    for (var i = 0; i < ids.length; i++) {
      if (ids[i] === root.moduleName) break

      for (var j = 0; j < slots.length; j++) {
        var slot = slots[j]
        if (!slot || slot.region !== root.ownRegion) continue
        if (root.canonical(slot.moduleName) !== ids[i]) continue
        if (used.indexOf(slot) !== -1) continue
        if (!Model.ownsSlot({
              hostComparesWindows: root.hostComparesWindows,
              surfaceKnown: mine !== null,
              sameWindow: root.hostComparesWindows && mine !== null
                ? bar.sameWindow(bar.slotWindow(slot), mine) : false
            })) continue
        // What is not drawn is not a candidate: moduleDropAtScene() skips a
        // slot that is invisible or has no size, so the bar can never name it —
        // and a collapsed pocket's own members are exactly that.
        if (slot.visible !== true || slot.width <= 0 || slot.height <= 0) continue
        used.push(slot)
        last = slot
        break
      }
    }
    return last
  }

  // Aiming at the mark means aiming at either of its two edges. The far one the
  // bar names by this slot; the near one it names by the widget drawn before
  // it, with the marker on that widget's far side — the same gap under its
  // other name. Without the second term the near half of the mark never armed
  // at all, which is what made the README's "from either side" untrue for half
  // the icon while 0002 believed it had settled the question.
  //
  // Both terms are object identity against slots this instance can see, so the
  // instance that is not being aimed at still falls through to doing nothing.
  // That is the property 0004 asks the `add` branch to keep, and the reason the
  // steering below may still be hung on the narrower of the two.
  readonly property bool aimsAtSelf: !!root.dragTarget
    && (root.dragTarget === root.ownSlot
        || (root.dragAfter && root.dragTarget === root.slotBeforeSelf))

  readonly property string dropIntent: {
    if (!root.dragSource) return "none"
    return Model.dropDecision({
      sourceId: root.dragSourceId,
      selfId: root.moduleName,
      anchorId: root.anchorId,
      members: root.gestureMembers,
      targetIsSelf: root.aimsAtSelf,
      hasTarget: !!root.dragTarget,
      gapTouchesMember: root.dropGapTouchesMember
    })
  }

  // Lit while a release would take a widget in. `mayWriteMembers` is what
  // commitDrop() checks, and until now the light did not: a bar carrying a
  // second pocket entry lit the mark and then wrote nothing, which is the one
  // thing the light is not allowed to do.
  readonly property bool dropArmed: dropIntent === "add" && mayWriteMembers

  // Lit while a release would let a member go. Unlike the add above, this
  // answer is taken from ids alone (0004), so every screen's pocket reaches it
  // in the same instant — the light has to ask separately whether the drag is
  // on this surface. The resolved member slots are already filtered to it, so
  // asking them costs no further reading of the host.
  readonly property bool dropReleases: dropIntent === "remove" && mayWriteMembers
    && root.resolution.slots.indexOf(root.dragSource) !== -1

  // What the drag last meant. The decision has to be taken when the drag ENDS,
  // and Bar.qml clears every drag property in one breath at that moment.
  property string pendingIntent: "none"
  property string pendingId: ""
  property bool dragSeen: false

  onDropIntentChanged: {
    if (!root.dragSource) return
    root.pendingIntent = root.dropIntent
    root.pendingId = root.dragSourceId
  }

  onDragSourceChanged: {
    if (root.dragSource) {
      root.dragSeen = true
      root.dragMembers = root.memberIds.slice()
      return
    }

    // Always cleared on the falling edge. Bar.qml calls clearBarDrag() on every
    // press too, and a sample left from the previous drag must never be able to
    // decide the next one.
    //
    // The intent is read before the snapshot is dropped, because dropping it
    // re-evaluates dropIntent synchronously. Nothing comes of that today — the
    // drag source is already null and the binding refuses on it — but the two
    // lines are in this order on purpose and not by accident.
    var intent = root.dragSeen ? root.pendingIntent : "none"
    var id = root.pendingId
    root.dragSeen = false
    root.dragMembers = []
    root.pendingIntent = "none"
    root.pendingId = ""
    if (intent !== "none") root.commitDrop(intent, id)
  }

  // -------------------------------------------------------- drop steering

  // Left to itself, the bar places a widget where its own drop marker said, so
  // one aimed at the pocket from the far side lands on the far side and the
  // invariant below has to move it back — a second layout write, and therefore
  // a second full rebuild of every widget on every monitor. Told where the
  // widget belongs while the drag is still running, the bar places it correctly
  // the first time and the invariant finds nothing to do.
  //
  // Everything here is optional by construction. A missing property or a
  // renamed dropMarkerRect() makes the override stop applying, and the
  // invariant still produces the correct layout — one rebuild slower. That is
  // why the invariant was not replaced by this. See docs/decisions/0003.

  readonly property var steerAfter: Model.steerDropAfter({
    intent: root.dropIntent,
    aimedAtOwnSlot: !!root.dragTarget && root.dragTarget === root.ownSlot,
    nearestAtEnd: root.membersLeadFromEnd,
    mayWrite: root.mayWriteMembers
  })

  // The re-entrancy guard, and the only thing that stops the recursion:
  // steerDrop() writes the two properties whose change signals called it, and
  // Qt delivers those synchronously.
  property bool steering: false

  // Listened to, rather than sampled into a property of this widget's own. A
  // property that reads these two values with a handler that writes them back
  // is a cycle through that property's own binding: Qt finds its update()
  // re-entered, prints "Binding loop detected" and SKIPS the re-evaluation, so
  // the flag above was never even reached. The near miss is measured too:
  // hanging the handlers on the mirror properties this file already has
  // (`dragAfter`) loops in exactly the same way, because any binding that
  // transitively depends on what its handler writes does. docs/decisions/0006
  // has the engine version and the counts.
  //
  // Both signals call the same function and that function re-asserts BOTH
  // values, so a change to either fixes both. Bar.qml writes them one after the
  // other on every pointer move, and reacting to only one would make the
  // outcome depend on which it writes last: reverse those two assignments and
  // the bar would draw its insertion line on one side of the pocket while
  // placing the widget on the other. A marker that lies is worse than no
  // override at all.
  //
  // ignoreUnknownSignals is what keeps this host access optional like every
  // other one here: a custom bar that publishes neither property gets silence.
  Connections {
    target: root.bar
    ignoreUnknownSignals: true
    function onBarDragAfterChanged() { root.steerDrop() }
    function onBarDragTargetGeometryChanged() { root.steerDrop() }
  }

  function steerDrop() {
    if (root.steering) return
    if (!root.steerAfter) return
    if (!bar || !("barDragAfter" in bar) || !("barDragTargetGeometry" in bar)) return
    if (typeof bar.dropMarkerRect !== "function") return

    var want = root.steerAfter.after
    var rect = bar.dropMarkerRect(root.ownSlot, want)
    if (!rect) return

    // The rect is compared field by field, not by identity: dropMarkerRect()
    // returns a fresh object every call. Comparing only `after` would not do
    // either — in the order Bar.qml writes today the `after` assignment
    // triggers this, and the geometry assignment that follows would then find
    // `after` already correct and stop, leaving the line drawn on the side the
    // widget is not going to.
    if (bar.barDragAfter === want && Model.sameMarkerRect(bar.barDragTargetGeometry, rect)) return

    // Guarded so a host that turned one of these readonly cannot leave the flag
    // latched and the override off for the rest of the session. Both values are
    // applied or neither: the write that decides the placement goes first, so a
    // refusal there applies nothing at all, and a refusal on the geometry is
    // rolled back. Leaving that one half-written is the one outcome this
    // override must never produce — measured against a host with a readonly
    // geometry, it placed the widget against the pocket while the bar kept
    // drawing its line on the far side. The invariant below carries the result
    // either way. `finally` would say this more directly, but Qt 5's qmlformat
    // segfaults on it, and that is the parser named in the README.
    root.steering = true
    var hostAfter = bar.barDragAfter
    try {
      bar.barDragAfter = want
      bar.barDragTargetGeometry = rect
    } catch (e) {
      try { bar.barDragAfter = hostAfter } catch (e2) { }
    }
    root.steering = false
  }

  // ---------------------------------------------------------- persistence

  // The widget just taken in, held visible until the bar's own release handler
  // has returned. Qt cancels a pressed MouseArea the moment its item becomes
  // invisible, and that MouseArea is still mid-release: hiding the slot any
  // earlier revokes its grab, which clears the bar's click suppression and
  // turns the drop into a click on the widget that was dropped. Dropping the
  // power widget into the pocket would open the power menu.
  property string heldVisibleId: ""

  function isHeld(slot) {
    return root.heldVisibleId !== "" && !!slot
      && root.canonical(slot.moduleName) === root.heldVisibleId
  }

  function releaseVisibleHold() {
    if (root.heldVisibleId === "") return
    root.heldVisibleId = ""
    root.apply()
  }

  // Written synchronously, before the bar persists its own move. Deferring it
  // is not an option: the bar's move reassigns the layout, which destroys and
  // rebuilds every widget on every monitor, and a deferred callback would be
  // reaching for an instance that no longer exists. Running first is also
  // harmless — a members-only change is an inline settings change, which the
  // bar patches into the running widgets instead of rebuilding them, and the
  // move that follows reads the config this call already updated.
  function commitDrop(intent, id) {
    if (!root.mayWriteMembers) return
    if (!bar || !bar.shell || typeof bar.shell.mutateShellConfig !== "function") return

    var region = root.ownRegion
    var raw = root.setting("members", "")
    var next = Model.nextMembers(Model.toList(raw), root.layoutIds(region), id, intent,
                                 root.membersLeadFromEnd)
    var value = Model.membersValue(next, raw)
    var selfId = root.moduleName

    root.heldVisibleId = intent === "add" ? String(id) : ""

    var written = false
    bar.shell.mutateShellConfig(function (config) {
      written = Model.setMembersOnEntry(config, region, selfId, value)
    })

    if (written) Qt.callLater(root.releaseVisibleHold)
    else root.releaseVisibleHold()
  }

  // ------------------------------------------------------- placement repair

  // Members belong on the side the pocket fans them out towards. A member that
  // is not there would fan out alone on the wrong side of the icon while the
  // rest of the group is on the other — which reads as the pocket having lost
  // it. The steering above keeps a far-side arrival from landing there in the
  // first place wherever it applies; this is what guarantees the result when it
  // does not, and what repairs a hand-edited config either way.
  //
  // Written as a standing invariant rather than as a step in the drop, because
  // it cannot be a step in the drop: the bar persists its own move AFTER this
  // widget has written, and would overwrite any correction made first. The
  // move also rebuilds every widget, so whatever repairs the placement has to
  // be something the NEW instance does on sight. That it also repairs a
  // hand-edited config is the better half of the bargain.
  //
  // It converges: each pass moves exactly one widget to the correct side, and
  // there is no rule that moves one back.
  readonly property string misplacedMember: Model.firstMisplacedMember(
    root.layoutIds(root.ownRegion), root.moduleName, root.memberIds, root.membersLeadFromEnd)

  // Never written straight from a handler. A bar surface exists per monitor,
  // every one of them reaches this conclusion at the same moment, and the write
  // rebuilds the whole bar — done inline it would land in the middle of the
  // Repeater still creating the delegates that are asking for it. Deferred, the
  // first write wins and the instances the rebuild replaces find nothing left
  // to do; Qt.callLater collapses the repeats per object for free.
  function scheduleRepair() {
    if (root.misplacedMember === "") return
    Qt.callLater(root.repairPlacement)
  }

  function repairPlacement() {
    if (root.misplacedMember === "") return
    if (!root.mayWriteMembers) return
    if (!bar || !bar.shell || typeof bar.shell.mutateShellConfig !== "function") return

    var region = root.ownRegion
    var id = root.misplacedMember
    var selfId = root.moduleName
    var nearestAtEnd = root.membersLeadFromEnd

    bar.shell.mutateShellConfig(function (config) {
      Model.placeMemberBesideSelf(config, region, id, selfId, nearestAtEnd)
    })
  }

  onMisplacedMemberChanged: scheduleRepair()

  // ---------------------------------------------------- member order repair

  // The member list is kept in the order the widgets physically sit in, and
  // reordering a member inside the run is the one way that order changes
  // without this pocket writing anything — the bar moves the widget, and
  // membership does not change, so no gesture of ours runs. The same standing
  // invariant shape as the placement repair above, and separate from it
  // because it is a different mistake and a much cheaper one: `members` is an
  // inline settings change, which the bar patches into the running widgets
  // instead of rebuilding them. See docs/decisions/0002 for what each costs.
  //
  // It converges for the same reason: ordering by the layout is idempotent,
  // and nothing puts the list back out of order.
  //
  // It writes back what toList() produced, so it must not run over a list
  // toList() cannot reproduce. A hand-written entry with spaces in it comes
  // back split, and joined again it is no longer what the user wrote — a typo
  // would be silently rewritten into several ids, one of them possibly a
  // duplicate. An id the parser rejects is exactly that marker, and the
  // tooltip is already asking the user to fix it. Every gesture that writes
  // has the same lossy step, but a gesture is asked for; this is not.
  readonly property bool membersMisordered: root.rejectedIds.length === 0
    && !Model.membersInLayoutOrder(
      Model.toList(root.setting("members", "")), root.layoutIds(root.ownRegion))

  function scheduleReorder() {
    if (!root.membersMisordered) return
    Qt.callLater(root.repairMemberOrder)
  }

  function repairMemberOrder() {
    if (!root.membersMisordered) return
    if (!root.mayWriteMembers) return
    if (!bar || !bar.shell || typeof bar.shell.mutateShellConfig !== "function") return

    var region = root.ownRegion
    var raw = root.setting("members", "")
    var value = Model.membersValue(
      Model.orderMembers(Model.toList(raw), root.layoutIds(region)), raw)
    var selfId = root.moduleName

    bar.shell.mutateShellConfig(function (config) {
      Model.setMembersOnEntry(config, region, selfId, value)
    })
  }

  onMembersMisorderedChanged: scheduleReorder()

  // ------------------------------------------------------------ animation

  // One animated scalar, everything else derived from it — the shape the stock
  // tray drawer uses, with its duration and curve, so the two read as the same
  // gesture. Driving each slot's opacity from a per-slot animation instead
  // would put N competing animations on objects this widget does not own.
  readonly property int animationDuration: 600
  property real revealProgress: expanded ? 1 : 0

  Behavior on revealProgress {
    NumberAnimation { duration: root.animationDuration; easing.type: Easing.OutCubic }
  }

  // Which end of the member list sits against the pocket. In the right section
  // the members precede it, so the last one is its neighbour and should lead
  // the cascade; in the left section the first one does.
  readonly property bool membersLeadFromEnd: ownRegion !== "left"

  // Members grow out of the edge that faces the pocket rather than swelling in
  // place, which reads as coming out of it. Scale is visual only — it moves no
  // layout and touches nothing the bar computes.
  readonly property int growthOrigin: membersLeadFromEnd ? Item.Right : Item.Left

  onRevealProgressChanged: applyReveal()

  function applyReveal() {
    var list = root.driven
    var n = list.length

    for (var i = 0; i < n; i++) {
      if (root.isHeld(list[i])) continue
      var order = root.membersLeadFromEnd ? (n - 1 - i) : i
      var f = Model.revealFraction(root.revealProgress, order, n)
      root.setSlotProperty(list[i], "transformOrigin", root.growthOrigin)
      root.setSlotProperty(list[i], "opacity", f)
      root.setSlotProperty(list[i], "scale", 0.6 + 0.4 * f)
    }

    // Space is only given back once the members have gone, so the neighbours
    // slide in behind them rather than through them.
    if (!root.expanded && root.revealProgress <= 0.001) root.hideDriven()
  }

  // --------------------------------------------------------------- effect

  function setSlotProperty(slot, name, value) {
    // Slots die with the bar surface, and a rebuild can hand us one mid-teardown.
    try { if (slot) slot[name] = value } catch (e) { }
  }

  function setSlotVisible(slot, value) { setSlotProperty(slot, "visible", value) }

  function hideDriven() {
    for (var i = 0; i < root.driven.length; i++) {
      if (root.isHeld(root.driven[i])) continue
      root.setSlotVisible(root.driven[i], false)
    }
  }

  function apply() {
    var wanted = root.resolution.slots

    // Anything we previously took over and no longer own goes back first — a
    // member removed from the setting, or refused as the center anchor, must
    // not stay invisible just because it left the list.
    for (var i = 0; i < root.driven.length; i++) {
      var old = root.driven[i]
      if (wanted.indexOf(old) === -1) root.release(old)
    }

    root.driven = wanted.slice()

    // Room is made up front so the members have somewhere to grow into;
    // taking it back waits for them to finish leaving, in applyReveal().
    if (root.expanded) {
      for (var j = 0; j < wanted.length; j++) root.setSlotVisible(wanted[j], true)
    }

    root.applyReveal()
  }

  function release(slot) {
    root.setSlotProperty(slot, "opacity", 1)
    root.setSlotProperty(slot, "scale", 1)
    root.setSlotProperty(slot, "transformOrigin", Item.Center)
    root.setSlotVisible(slot, true)
  }

  function releaseAll() {
    for (var i = 0; i < root.driven.length; i++) root.release(root.driven[i])
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
    // The instance that could see the misplacement is the one the drop's own
    // rebuild created, and a binding that starts out non-empty never changes,
    // so it would never fire its handler. The same holds for the order.
    scheduleRepair()
    scheduleReorder()
  }

  // Without this, disabling or hot-reloading the plugin leaves someone else's
  // widgets invisible with no way back short of restarting the shell.
  Component.onDestruction: releaseAll()

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
      // Folding up narrows the section, which slides the pocket itself out from
      // under a stationary pointer — and the pointer landing on a neighbour
      // would fold it, moving it back, and so on. Hold until the pointer has
      // left the bar entirely, which is the same rule Bar.qml applies to its
      // own hover reveal.
      if (root.bar && root.bar.barHovered) return
      root.expanded = false
    }
  }

  // ----------------------------------------------------------------- view

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  HoverHandler { id: pocketHover }

  BarIconButton {
    id: button
    bar: root.bar
    // Lit while a release would change what the pocket holds — the answer given
    // before the drop, not explained after it. The same predicates decide the
    // write, so the light cannot promise something the drop then refuses.
    active: root.pinned || root.dropArmed || root.dropReleases
    // Two answers, two colours, because they are opposite answers and the
    // difference is the whole gesture: taking a widget in keeps the colour the
    // bar gives an active widget, letting a member go borrows the colour
    // Bar.qml paints its own insertion line in — the line the user is looking
    // at while the pocket decides. A theme whose accent is its bar text reads
    // that state as unlit, which is the state it replaced.
    activeColor: root.dropReleases ? Color.accent : (root.bar ? root.bar.urgent : Color.urgent)
    // Deliberately not the stock tray's chevron: the tray sits in the same
    // section doing a visually similar thing, and two identical glyphs side by
    // side are two things a user cannot tell apart. Dots read as "there is more
    // here", and turning them upright rides the same scalar as everything else,
    // so it is the drawer's move by construction rather than by a copied number.
    text: String.fromCodePoint(0xf01d8)
    // Derived from the animated scalar, so it must not carry a Behavior of its
    // own — two animations on one value fight and the slower one wins twice.
    textRotation: (root.vertical ? 90 : 0) + root.revealProgress * 90

    // The plugin's only text sink, and the reason Model.describe() escapes what
    // it interpolates. From here the string travels through WidgetButton's
    // onEntered into Bar.qml's showTooltip(), and lands in a `Text` that sets no
    // `textFormat` — so the host, not this file, decides whether it is parsed as
    // markup. Nothing assigned here may depend on that decision.
    tooltipText: Model.describe({
      members: root.memberIds, expanded: root.expanded, pinned: root.pinned,
      rejected: root.rejectedIds, unreadable: root.unreadableAt,
      missing: root.resolution.missing,
      anchored: root.resolution.anchored, foreign: root.resolution.foreign,
      duplicateInstances: root.duplicateInstances, surfaceUnknown: root.surfaceUnknown
    })

    // The pointer is the primary gesture; the click is the way out of the cases
    // where no leave event is coming — a panel grabbing input, a workspace
    // switch teleporting the cursor.
    //
    // Session-only on purpose, though not for the reason this comment used to
    // give. Writing shell.json is safe: the host writes it atomically, and the
    // pocket now writes `members` itself. The pin stays unwritten because it is
    // a pointer aid for the next few seconds and because shell.json is shared
    // by every bar surface — persisting it would make one screen's transient
    // state everyone's.
    onPressed: function(code) {
      root.pinned = !root.pinned
      if (root.pinned) root.expanded = true
    }
  }
}
