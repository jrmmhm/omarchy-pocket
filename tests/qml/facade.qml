import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "plugin" as Pk

// The real BarWidget.qml against the real facade — `Ui/PluginBarApi.qml` out of
// the installed shell, not a hand-written stand-in.
//
// A stand-in is what this case exists to avoid. The break this whole version
// answers was invisible to a suite whose fake bars all published every symbol
// the plugin reads, and a mock written from the same understanding
// would have repeated the same assumption. The facade is the host's own file:
// when Omarchy narrows it again, this case changes with it.
//
// It pins three things the live bar found and no other case can reach:
//   1. what the capability layer concludes about a facade;
//   2. that the overlay is built even though `bar` arrives AFTER
//      Component.onCompleted, which is how the host injects it — attaching from
//      onCompleted alone left hiding working and the gesture silently dead;
//   3. that every pocket builds and owns its own overlay, and that the one a
//      surface keeps is still armed after the pocket that built first is
//      destroyed — the order every bar rebuild destroys them in. A shared
//      overlay stopped working there, because its handlers ran in the QML
//      context of the pocket that created it. The symptom itself needs a real
//      press, which is what `tests/live.sh --gesture` drives; this pins the
//      ownership that prevents it. See docs/decisions/0017.
//
// Needs a window: the overlay hangs on QsWindow.contentItem, and Model.ownsSlot
// refuses every slot to an instance that does not know its surface. Run through
// tests/qml/run.sh, which builds the import tree and runs this offscreen.
QtObject {
  id: harness

  property int failures: 0

  function check(label, actual, expected) {
    if (actual === expected) return
    harness.failures++
    console.warn("FAIL: " + label + "\n  expected: " + expected + "\n  actual:   " + actual)
  }

  function probe(label, fn, expected) {
    var value
    try {
      value = fn()
    } catch (e) {
      harness.failures++
      console.warn("FAIL: " + label + "\n  threw: " + e)
      return
    }
    harness.check(label, value, expected)
  }

  // The shell the facade hands over. Only the two things this plugin reads on
  // it: the detached bar config, which is where the centre anchor lives once
  // `bar.centerAnchor` is gone, and the inline writer.
  property QtObject fakeShell: QtObject {
    property var barConfig: ({ centerAnchor: "omarchy.clock",
                               layout: { left: [], center: [],
                                         right: [{ id: "jrmmhm.pocket" }] } })
    property int inlineWrites: 0
    property var lastSettings: null
    // Off for the first steps, which predate it. When on, a write is handed back
    // to the surviving pocket the way the host's delta path does it
    // (Bar.qml::applySettingsDelta assigns the widget's `settings`), so the lock
    // can be watched arriving rather than assumed.
    property bool modelDelta: false
    // A refusing writer, for the case where the click has to change nothing.
    property bool refuse: false
    function updateEntryInline(id, settings) {
      if (refuse) return false
      inlineWrites++
      lastSettings = settings
      if (modelDelta) win.secondPocket.settings = JSON.parse(JSON.stringify(settings))
      return true
    }
    // Present and refusing, exactly as the facade's is for a plugin that does
    // not declare kind "bar". The plugin must not read the return value.
    //
    // Given a config, it runs the mutator over it instead, the way the trusted
    // bar's mutator does on Omarchy 4.0.2 and earlier -- and returns undefined,
    // as that one does.
    property var mutatorConfig: null
    function mutateShellConfig(mutator) {
      if (mutatorConfig === null) return false
      mutator(mutatorConfig)
      return undefined
    }
  }

  // The host's own facade, constructed the way Bar.qml constructs it.
  property PluginBarApi facade: PluginBarApi {
    pluginId: "jrmmhm.pocket"
    moduleName: "jrmmhm.pocket"
    shell: harness.fakeShell
    layoutConfig: ({ left: [], center: [], right: [{ id: "jrmmhm.pocket" }] })
  }

  // Two stand-in module slots, carrying the three properties the walk
  // recognises and nothing else. The pocket lives inside one exactly as the
  // host's registryLoader puts it inside a ModuleSlot, so `ownSlot` resolves and
  // `ownRegion` is a real section — without which the widget correctly refuses
  // to write anything at all.
  property FloatingWindow win: FloatingWindow {
    id: win
    visible: true

    Item {
      id: slotA
      property string moduleName: "jrmmhm.pocket"
      property string region: "right"
      property var activeItem: loaderA.item
      property bool hovered: false
      property bool dragSource: false
      width: 27
      height: 26

      // Loaded, the way the host's registryLoader loads every widget, so that
      // step3 can destroy it the way a bar rebuild does.
      //
      // Deliberately created with NO bar. The host injects it from a callLater
      // after the loader completes, so at Component.onCompleted it is null and
      // every question asked of it answers as if there were no host at all.
      Loader {
        id: loaderA
        sourceComponent: Component {
          Pk.BarWidget {
            settings: ({ members: "omarchy.audio" })
          }
        }
      }
    }

    Item {
      id: slotB
      property string moduleName: "jrmmhm.pocket"
      property string region: "right"
      property var activeItem: pocketB
      property bool hovered: false
      property bool dragSource: false
      width: 27
      height: 26

      Pk.BarWidget {
        id: pocketB
        settings: ({ members: "omarchy.audio" })
      }
    }

    // A member, for the lock: the pointer resting on it is what `memberHovered`
    // reads, and its widget is what a panel opened by keybinding hangs from.
    Item {
      id: memberSlot
      property string moduleName: "omarchy.audio"
      property string region: "right"
      property var activeItem: memberItem
      property bool hovered: false
      property bool dragSource: false
      width: 27
      height: 26

      Item { id: memberItem; anchors.fill: parent }
    }

    property var pocketItem: loaderA.item
    property Pk.BarWidget secondPocket: pocketB
  }

  property Timer starter: Timer {
    interval: 0
    running: true
    onTriggered: harness.step1()
  }

  // destroy() is deferred to the event loop, so a step that asks what is left
  // after one has to come back later rather than on the next callLater.
  property var pending: null
  property Timer later: Timer {
    interval: 100
    onTriggered: harness.pending()
  }

  function after(step) {
    harness.pending = step
    later.interval = 100
    later.restart()
  }

  // Long enough for the fold timer (120 ms a tick) to have had its say.
  function afterFold(step) {
    harness.pending = step
    later.interval = 400
    later.restart()
  }

  function surfaceRoot() {
    return win.contentItem
  }

  function overlayCount() {
    var root = harness.surfaceRoot()
    if (!root || !root.children) return -1
    var n = 0
    for (var i = 0; i < root.children.length; i++) {
      var kid = root.children[i]
      if (kid && kid.objectName === "jrmmhm.pocket.overlay") n++
    }
    return n
  }

  function step1() {
    var p = win.pocketItem

    // Before the host has injected anything, the widget must not have decided
    // it wants an overlay: `bar` is null, and a null host is not a host that
    // dropped the drag API.
    probe("with no bar at all, no overlay is wanted", function () { return p.overlayWanted }, false)
    probe("and none was built", function () { return harness.overlayCount() }, 0)

    // Now inject, the way the host does: late.
    p.bar = harness.facade
    p.moduleName = "jrmmhm.pocket"

    Qt.callLater(harness.step2)
  }

  function step2() {
    var p = win.pocketItem

    // What the capability layer concludes about the real facade.
    probe("the facade publishes no slot registry",
          function () { return p.hostPublishesSlots }, false)
    probe("and no drag", function () { return p.hostPublishesDrag }, false)
    probe("so the pocket walks for its slots instead",
          function () { return p.barSlots === p.walkedSlots }, true)
    probe("and wants an overlay", function () { return p.overlayWanted }, true)

    // The regression this case exists for. Attaching from Component.onCompleted
    // alone produced exactly zero overlays here, and on the live bar it left
    // the mark unlit and every drop meaningless while hiding went on working.
    probe("the overlay is built once bar arrives, not at construction",
          function () { return harness.overlayCount() }, 1)
    probe("and the widget holds it", function () { return p.overlay !== null }, true)

    // The centre anchor is gone from the facade and comes back off the shell's
    // detached bar config.
    probe("the anchor is recovered from the shell's bar config",
          function () { return p.anchorId }, "omarchy.clock")

    win.secondPocket.bar = harness.facade
    win.secondPocket.moduleName = "jrmmhm.pocket"

    Qt.callLater(harness.step3)
  }

  property var survivor: null
  property var departedHover: null

  function step3() {
    // Every pocket builds its own. Finding one by name and sharing it is what
    // the previous version did, and it is exactly what this case exists to
    // refuse: the second pocket then held an overlay whose handlers belonged to
    // the first.
    probe("a second pocket on the same surface builds an overlay of its own",
          function () { return harness.overlayCount() }, 2)
    probe("and each pocket holds the one it built",
          function () { return win.pocketItem.overlay !== win.secondPocket.overlay }, true)

    // The write path: the facade's mutator is present and refuses, so the
    // plugin has to fall through to the inline writer and must not be fooled by
    // a return value.
    probe("a members write falls through to the inline writer",
          function () { return win.pocketItem.writeMembers("omarchy.audio, omarchy.network") },
          true)
    probe("and it went to the inline writer exactly once",
          function () { return harness.fakeShell.inlineWrites }, 1)
    probe("carrying the new value",
          function () { return harness.fakeShell.lastSettings.members },
          "omarchy.audio, omarchy.network")

    // A bar rebuild completes the new instances and only then destroys the old
    // ones, so the pocket that built first is the one that goes while the other
    // lives on. That is the order that killed the shared overlay.
    harness.survivor = win.secondPocket.overlay
    harness.departedHover = win.pocketItem.overlay.hoverHandler

    // Off the surface in the same breath, not whenever the deferred delete gets
    // round to it: an overlay still in the window would go on taking presses,
    // and its destructor would reach into the window. Asked before the event
    // loop runs, because afterwards the delete would pass this on its own.
    win.pocketItem.detachOverlay()
    probe("a retired overlay leaves the surface at once, before it is deleted",
          function () { return harness.overlayCount() }, 1)

    loaderA.active = false

    harness.after(harness.step4)
  }

  function step4() {
    probe("the departed pocket took its own overlay with it",
          function () { return harness.overlayCount() }, 1)
    probe("and its hover handler, which sits on the surface root",
          function () { return String(harness.departedHover) }, "null")
    probe("the survivor still holds its own overlay",
          function () { return win.secondPocket.overlay === harness.survivor }, true)
    probe("whose hover handler is still armed",
          function () { return harness.survivor.hoverHandler.enabled }, true)

    Qt.callLater(harness.step5)
  }

  // ------------------------------------------------------------- the lock
  //
  // Driven through the widget's REAL button: triggerPress() is the host's own
  // WidgetButton function, the one its MouseArea and the bar's click forwarding
  // both call with the button that was pressed. What it reaches is the plugin's
  // onPressed, and from there the write, over the real facade, to the inline
  // writer — the whole path a right click takes on 4.0.3 and later, short of
  // the pointer itself. See docs/decisions/0020.

  function pocket() { return win.secondPocket }
  function button() { return win.secondPocket.children[0] }
  function tip() { return harness.button().tooltipText }

  function step5() {
    var p = harness.pocket()
    harness.fakeShell.modelDelta = true
    harness.fakeShell.inlineWrites = 0
    p.settings = ({ members: "omarchy.audio" })

    // Offscreen, the overlay's surface HoverHandler reports the pointer as on
    // the bar, and the fold timer waits for it to leave for as long as it says
    // so. Every fold below is about the lock, not about that, so the pointer is
    // taken off the bar here and the pocket starts closed.
    p.overlay.hovered = false
    p.expanded = false
    probe("the pointer is off the bar for these steps",
          function () { return p.pointerOnBar }, false)

    probe("the pocket holds its member", function () { return p.resolution.slots.length }, 1)
    probe("its button is the host's, with the press the host calls",
          function () { return typeof harness.button().triggerPress }, "function")
    probe("the tooltip explains both clicks under the first line",
          function () { return harness.tip().split("\n").slice(0, 3).join("|") },
          "Pocket holding 1 widget|Left click: pin it open|Right click: lock it shut")

    memberSlot.hovered = true
    probe("unlocked, the pointer on a member opens it", function () { return p.expanded }, true)

    // The pointer is still on the member when the right click lands -- that is
    // where it is on a real bar -- and the fold must not wait for it to leave.
    harness.button().triggerPress(Qt.RightButton)
    probe("a right click writes the lock once", function () { return harness.fakeShell.inlineWrites }, 1)
    probe("as true", function () { return harness.fakeShell.lastSettings.locked }, true)
    probe("carrying members unchanged",
          function () { return harness.fakeShell.lastSettings.members }, "omarchy.audio")
    probe("and the pocket reads it back locked", function () { return p.locked }, true)
    probe("locking folds at once, pointer or not", function () { return p.expanded }, false)
    probe("the locked mark is dimmed", function () { return harness.button().dimmed }, true)
    probe("the tooltip says it is locked and offers the unlock",
          function () { return harness.tip().split("\n").slice(0, 3).join("|") },
          "Pocket locked shut — holding 1 widget|Left click: pin it open|Right click: unlock")

    memberSlot.hovered = false
    memberSlot.hovered = true
    probe("locked, the pointer arriving on a member does not open it",
          function () { return p.expanded }, false)

    harness.afterFold(harness.step6)
  }

  function step6() {
    var p = harness.pocket()
    probe("and it stays shut while the pointer rests there", function () { return p.expanded }, false)

    // The left click pins, exactly as before, and leaves the lock alone.
    harness.button().triggerPress(Qt.LeftButton)
    probe("a left click on a locked pocket pins it open", function () { return p.expanded }, true)
    probe("and writes nothing", function () { return harness.fakeShell.inlineWrites }, 1)
    probe("so it is still locked", function () { return p.locked }, true)
    probe("a pinned mark is not dimmed", function () { return harness.button().dimmed }, false)
    probe("the first line follows the pin, the right click still unlocks",
          function () { return harness.tip().split("\n").slice(0, 3).join("|") },
          "Pocket pinned open|Left click: release the pin|Right click: unlock")

    harness.button().triggerPress(Qt.MiddleButton)
    probe("a middle click is the left click, as it always was", function () { return p.pinned }, false)

    // Unlocking with the pointer on a member opens the pocket under it.
    harness.button().triggerPress(Qt.RightButton)
    probe("a second right click writes the unlock",
          function () { return harness.fakeShell.lastSettings.locked }, false)
    probe("the pocket reads it back unlocked", function () { return p.locked }, false)
    probe("and the pointer already on a member opens it", function () { return p.expanded }, true)

    // A pinned pocket that is locked from this screen drops its pin and folds.
    memberSlot.hovered = false
    p.pinned = true
    harness.button().triggerPress(Qt.RightButton)
    probe("locking a pinned pocket drops the pin", function () { return p.pinned }, false)
    probe("and folds it", function () { return p.expanded }, false)

    // A panel opened from a member holds it open through the lock.
    harness.button().triggerPress(Qt.RightButton)
    probe("unlocked again", function () { return p.locked }, false)
    harness.facade.activePopout = memberItem
    probe("a member's panel opens the pocket", function () { return p.expanded }, true)
    harness.button().triggerPress(Qt.RightButton)
    probe("locking under a member's open panel locks", function () { return p.locked }, true)
    probe("but does not fold away the widget the panel hangs from",
          function () { return p.expanded }, true)
    // The offscreen hover answers again whenever a slot changes visibility, so
    // the pointer is taken off the bar once more before the fold is asked for.
    p.overlay.hovered = false
    harness.facade.activePopout = null

    harness.afterFold(harness.step7)
  }

  function step7() {
    var p = harness.pocket()
    probe("once the panel closes, the locked pocket folds", function () { return p.expanded }, false)

    // A refused write changes nothing at all: the pin the click dropped comes
    // back, and the lock stays where it was.
    harness.button().triggerPress(Qt.RightButton)
    probe("unlocked for the refusal case", function () { return p.locked }, false)
    p.pinned = true
    harness.fakeShell.refuse = true
    harness.button().triggerPress(Qt.RightButton)
    probe("a refused lock leaves the pocket unlocked", function () { return p.locked }, false)
    probe("and gives the pin back", function () { return p.pinned }, true)
    harness.fakeShell.refuse = false
    p.pinned = false

    // The stale list decision 0018 measured: shell.json holds the new order and
    // the running pocket the old one, because the host hands it back. Modelled
    // by not handing writes back, so the order repair's own write never reaches
    // `settings`. A lock written now must not carry the old order into the file.
    harness.fakeShell.modelDelta = false
    // The snapshot's own copy of the entry still carries a key the user has
    // since deleted by hand -- the state #16 was about. The write must be built
    // from `settings`, which no longer has it, and not from this.
    harness.facade.layoutConfig = ({ left: [], center: [], right: [
      { id: "omarchy.network" }, { id: "omarchy.audio" },
      { id: "jrmmhm.pocket", deletedByHand: true, members: "omarchy.audio, omarchy.network" }] })
    p.settings = ({ members: "omarchy.audio, omarchy.network" })

    harness.after(harness.step8)
  }

  function step8() {
    var p = harness.pocket()
    probe("the running pocket still holds the old order",
          function () { return p.membersMisordered }, true)
    harness.button().triggerPress(Qt.RightButton)
    probe("a lock written over a stale list is a lock",
          function () { return harness.fakeShell.lastSettings.locked }, true)
    probe("and carries members in the bar's order, not the stale one",
          function () { return harness.fakeShell.lastSettings.members },
          "omarchy.network, omarchy.audio")
    probe("and is built from settings, not from the snapshot's stale entry (#16)",
          function () { return "deletedByHand" in harness.fakeShell.lastSettings }, false)

    // The other write path. On a host whose config mutator runs, the lock goes
    // through it and changes the one key on the entry, nothing else -- and the
    // inline writer is never asked.
    var writes = harness.fakeShell.inlineWrites
    harness.fakeShell.mutatorConfig = ({ bar: { layout: { left: [], center: [], right: [
      { id: "omarchy.network" },
      { id: "jrmmhm.pocket", members: "omarchy.network, omarchy.audio", note: "x" }] } } })
    p.settings = ({ members: "omarchy.network, omarchy.audio", note: "x" })
    harness.button().triggerPress(Qt.RightButton)
    probe("on a host whose mutator runs, the lock is written through it",
          function () { return JSON.stringify(harness.fakeShell.mutatorConfig.bar.layout.right) },
          JSON.stringify([{ id: "omarchy.network" },
                          { id: "jrmmhm.pocket", members: "omarchy.network, omarchy.audio",
                            note: "x", locked: true }]))
    probe("and the inline writer is not asked as well",
          function () { return harness.fakeShell.inlineWrites }, writes)
    harness.fakeShell.mutatorConfig = null

    Qt.callLater(harness.finish)
  }

  function finish() {
    console.warn(harness.failures === 0 ? "QML OK" : "QML FAILURES " + harness.failures)
    Qt.exit(harness.failures === 0 ? 0 : 1)
  }
}
