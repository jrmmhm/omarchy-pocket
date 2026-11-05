import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "plugin" as Pk
import "plugin/Model.js" as Model

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
      // The other screen's pocket, once it is in play: the delta path patches
      // every instance of the entry, on every surface (Bar.qml::applySettingsDelta).
      if (modelDelta && win2.pocket.bar) win2.pocket.settings = JSON.parse(JSON.stringify(settings))
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

      // Keeps the host's panel contract, as Ui/Panel.qml does: a keybinding
      // calls open() on it and `opened` follows.
      Item {
        id: memberItem
        anchors.fill: parent
        property bool opened: false
        function open() { opened = true }
        function close() { opened = false }
      }
    }

    property var pocketItem: loaderA.item
    property Pk.BarWidget secondPocket: pocketB
  }

  // A second bar surface, standing in for the second monitor: its own window,
  // its own pocket and its own copy of the member, as the bar builds one per
  // screen. Both pockets share the one layout entry and the one facade.
  property FloatingWindow win2: FloatingWindow {
    id: win2
    visible: true

    Item {
      property string moduleName: "jrmmhm.pocket"
      property string region: "right"
      property var activeItem: pocketC
      property bool hovered: false
      property bool dragSource: false
      width: 27
      height: 26

      Pk.BarWidget {
        id: pocketC
        settings: ({ members: "omarchy.audio" })
      }
    }

    Item {
      id: memberSlot2
      property string moduleName: "omarchy.audio"
      property string region: "right"
      property var activeItem: memberItem2
      property bool hovered: false
      property bool dragSource: false
      width: 27
      height: 26

      Item {
        id: memberItem2
        anchors.fill: parent
        property bool opened: false
        function open() { opened = true }
        function close() { opened = false }
      }
    }

    property Pk.BarWidget pocket: pocketC
  }

  // A third bar surface, with real geometry, for the gesture itself. Omarchy
  // 4.5.0's bar surface spans its whole screen and paints the bar as a strip
  // along one edge (Bar.qml::BarPanel), so the strip here is the top 26 px of a
  // taller window. Four slots side by side: network, the member, the pocket,
  // power. Its own facade, so the layout the other steps rewrite stays theirs.
  property PluginBarApi facade3: PluginBarApi {
    pluginId: "jrmmhm.pocket"
    moduleName: "jrmmhm.pocket"
    shell: harness.fakeShell
    layoutConfig: ({ left: [], center: [], right: [
      { id: "omarchy.network" }, { id: "omarchy.audio" },
      { id: "jrmmhm.pocket", members: "omarchy.audio" }, { id: "omarchy.power" }] })
  }

  property FloatingWindow win3: FloatingWindow {
    id: win3
    visible: true
    implicitWidth: 300
    implicitHeight: 200

    Item {
      width: 300
      height: 26

      Row {
        id: strip3

        Item {
          id: netSlot3
          property string moduleName: "omarchy.network"
          property string region: "right"
          property var activeItem: netItem3
          property bool hovered: false
          property bool dragSource: false
          // Bar.qml::ModuleSlot: true from the moment a widget is let go of
          // past the removal threshold until its entry leaves the layout.
          property bool removalPending: false
          implicitWidth: 27
          implicitHeight: 26
          Item { id: netItem3 }
        }

        Item {
          id: memberSlot3
          property string moduleName: "omarchy.audio"
          property string region: "right"
          property var activeItem: memberItem3
          property bool hovered: false
          property bool dragSource: false
          property bool removalPending: false
          implicitWidth: 27
          implicitHeight: 26
          Item { id: memberItem3 }
        }

        Item {
          property string moduleName: "jrmmhm.pocket"
          property string region: "right"
          property var activeItem: pocketD
          property bool hovered: false
          property bool dragSource: false
          property bool removalPending: false
          implicitWidth: 27
          implicitHeight: 26

          Pk.BarWidget {
            id: pocketD
            settings: ({ members: "omarchy.audio" })
          }
        }

        Item {
          id: powerSlot3
          property string moduleName: "omarchy.power"
          property string region: "right"
          property var activeItem: powerItem3
          property bool hovered: false
          property bool dragSource: false
          property bool removalPending: false
          implicitWidth: 27
          implicitHeight: 26
          Item { id: powerItem3 }
        }
      }
    }

    property Pk.BarWidget pocket: pocketD
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

  // The name the pocket under test reads off its real window's screen.
  property string key: ""

  function pocket() { return win.secondPocket }
  function button() { return win.secondPocket.children[0] }
  function tip() { return harness.button().tooltipText }

  function step5() {
    var p = harness.pocket()
    harness.fakeShell.modelDelta = true
    harness.fakeShell.inlineWrites = 0
    p.settings = ({ members: "omarchy.audio" })

    // Offscreen, the overlay's surface HoverHandler reports the pointer at the
    // window's corner, which is where these unplaced slots all sit, and the
    // fold timer holds the pocket open for a pointer on its run. Every fold
    // below is about the lock, not about that, so the pointer is taken off the
    // bar here and the pocket starts closed.
    p.overlay.hovered = false
    p.expanded = false

    probe("the pocket holds its member", function () { return p.resolution.slots.length }, 1)

    // The screen name comes from the real window's real ShellScreen, through
    // the same binding the bar runs. Offscreen that screen has no name at all
    // (measured: QScreen name ""), which is the case of a pocket that cannot
    // keep a per-screen state: no lock offered, the pin kept for the session.
    probe("the pocket reads its screen off its real window",
          function () { return p.liveScreenKey === Model.screenKey(win.screen) }, true)
    probe("a screen without a name gives no key", function () { return p.screenKey }, "")
    probe("so nothing per-screen is kept", function () { return p.persistsScreenState }, false)
    probe("and the right click is not offered",
          function () { return harness.tip().indexOf("Right click") }, -1)
    harness.button().triggerPress(Qt.RightButton)
    probe("nor does it write", function () { return harness.fakeShell.inlineWrites }, 0)
    harness.button().triggerPress(Qt.LeftButton)
    probe("the left click pins for the session instead",
          function () { return p.sessionPinned && harness.fakeShell.inlineWrites === 0 }, true)
    harness.button().triggerPress(Qt.LeftButton)
    probe("and releases it", function () { return p.pinned }, false)
    p.expanded = false

    // From here on the pocket is on a named screen. A real bar names it; the
    // live run in docs/decisions/0021 shows which names.
    p.screenKey = "eDP-1"
    harness.key = p.screenKey
    probe("on a named screen it keeps a per-screen state",
          function () { return p.persistsScreenState }, true)
    probe("its button is the host's, with the press the host calls",
          function () { return typeof harness.button().triggerPress }, "function")
    probe("the tooltip explains both clicks under the first line",
          function () { return harness.tip().split("\n").slice(0, 3).join("|") },
          "Pocket holding 1 widget|Left click: pin it open on this screen"
          + "|Right click: lock it shut on this screen")

    memberSlot.hovered = true
    probe("unlocked, the pointer on a member opens it", function () { return p.expanded }, true)

    // The pointer is still on the member when the right click lands -- that is
    // where it is on a real bar -- and the fold must not wait for it to leave.
    harness.button().triggerPress(Qt.RightButton)
    probe("a right click writes the lock once", function () { return harness.fakeShell.inlineWrites }, 1)
    probe("as this screen's name", function () { return harness.fakeShell.lastSettings.locked }, harness.key)
    probe("carrying members unchanged",
          function () { return harness.fakeShell.lastSettings.members }, "omarchy.audio")
    probe("and the pocket reads it back locked", function () { return p.locked }, true)
    probe("locking folds at once, pointer or not", function () { return p.expanded }, false)
    probe("the locked mark is dimmed", function () { return harness.button().dimmed }, true)
    probe("the tooltip says it is locked and offers the unlock",
          function () { return harness.tip().split("\n").slice(0, 3).join("|") },
          "Pocket locked shut — holding 1 widget|Left click: pin it open on this screen|Right click: unlock")

    memberSlot.hovered = false
    memberSlot.hovered = true
    probe("locked, the pointer arriving on a member does not open it",
          function () { return p.expanded }, false)

    harness.afterFold(harness.step6)
  }

  function step6() {
    var p = harness.pocket()
    probe("and it stays shut while the pointer rests there", function () { return p.expanded }, false)

    // The left click pins and leaves the lock alone. The pin is this screen's
    // name in `pinned`, written like the lock.
    harness.button().triggerPress(Qt.LeftButton)
    probe("a left click on a locked pocket pins it open", function () { return p.expanded }, true)
    probe("and writes the pin once", function () { return harness.fakeShell.inlineWrites }, 2)
    probe("as this screen's name", function () { return harness.fakeShell.lastSettings.pinned }, harness.key)
    probe("a persisted pin, not a session one", function () { return p.sessionPinned }, false)
    probe("carrying the lock unchanged",
          function () { return harness.fakeShell.lastSettings.locked }, harness.key)
    probe("so it is still locked", function () { return p.locked }, true)
    probe("a pinned mark is not dimmed", function () { return harness.button().dimmed }, false)
    probe("the first line follows the pin, the right click still unlocks",
          function () { return harness.tip().split("\n").slice(0, 3).join("|") },
          "Pocket pinned open|Left click: release the pin|Right click: unlock")

    harness.button().triggerPress(Qt.MiddleButton)
    probe("a middle click is the left click, as it always was", function () { return p.pinned }, false)
    probe("and writes the release", function () { return harness.fakeShell.lastSettings.pinned }, "")

    // Unlocking with the pointer on a member opens the pocket under it.
    harness.button().triggerPress(Qt.RightButton)
    probe("a second right click writes the unlock",
          function () { return harness.fakeShell.lastSettings.locked }, "")
    probe("the pocket reads it back unlocked", function () { return p.locked }, false)
    probe("and the pointer already on a member opens it", function () { return p.expanded }, true)

    // A pinned pocket that is locked from this screen drops its pin and folds,
    // in ONE write: the lock and the dropped pin land together or not at all.
    memberSlot.hovered = false
    harness.button().triggerPress(Qt.LeftButton)
    probe("pinned again", function () { return p.pinned }, true)
    var before = harness.fakeShell.inlineWrites
    harness.button().triggerPress(Qt.RightButton)
    probe("locking a pinned pocket drops the pin", function () { return p.pinned }, false)
    probe("and folds it", function () { return p.expanded }, false)
    probe("in one write", function () { return harness.fakeShell.inlineWrites - before }, 1)
    probe("which carries both keys",
          function () {
            return JSON.stringify([harness.fakeShell.lastSettings.locked,
                                   harness.fakeShell.lastSettings.pinned])
          }, JSON.stringify([harness.key, ""]))

    // A panel opened from a member holds it open through the lock. Handed over
    // as the object, which is what a host that publishes it does (≤4.0.2) and
    // the facade never does; the facade's marker has its own case in step12.
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
    harness.fakeShell.refuse = true
    // Where nothing can be written, the left click still pins, for the session.
    harness.button().triggerPress(Qt.LeftButton)
    probe("a refused pin falls back to the session pin", function () { return p.sessionPinned }, true)
    harness.button().triggerPress(Qt.RightButton)
    probe("a refused lock leaves the pocket unlocked", function () { return p.locked }, false)
    probe("and gives the pin back", function () { return p.pinned }, true)
    harness.button().triggerPress(Qt.LeftButton)
    probe("the session pin is released without a write", function () { return p.pinned }, false)
    harness.fakeShell.refuse = false

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
          function () { return harness.fakeShell.lastSettings.locked }, harness.key)
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
                            note: "x", locked: harness.key }]))
    probe("and the inline writer is not asked as well",
          function () { return harness.fakeShell.inlineWrites }, writes)
    harness.fakeShell.mutatorConfig = null

    Qt.callLater(harness.step9)
  }

  // ------------------------------------------------------ two screens
  //
  // The pin and the lock are per screen (docs/decisions/0021): one pocket on
  // each of two surfaces, one shared entry, and every write handed back to
  // both, the way the delta path does it. Each click must change its own
  // screen and leave the other's state exactly where it was -- including when
  // the writing pocket holds the stale list 0018 measured, and on the mutator
  // path when its `settings` lag the file.

  function buttonOf(pocket) { return pocket.children[0] }

  function step9() {
    var b = harness.pocket()
    var c = win2.pocket
    c.bar = harness.facade
    c.moduleName = "jrmmhm.pocket"
    b.screenKey = "eDP-1"
    c.screenKey = "ASUS VG289"
    harness.facade.layoutConfig = ({ left: [], center: [], right: [
      { id: "omarchy.audio" }, { id: "jrmmhm.pocket", members: "omarchy.audio" }] })
    harness.fakeShell.modelDelta = true
    b.settings = ({ members: "omarchy.audio" })
    c.settings = ({ members: "omarchy.audio" })
    Qt.callLater(harness.step10)
  }

  function step10() {
    var b = harness.pocket()
    var c = win2.pocket
    // Offscreen, an overlay reports the pointer on the run; every fold below is
    // about the screens, not about that.
    if (c.overlay) c.overlay.hovered = false
    b.overlay.hovered = false
    b.expanded = false
    c.expanded = false

    probe("the second screen's pocket holds its own copy of the member",
          function () { return c.resolution.slots.length === 1 && c.resolution.slots[0] === memberSlot2 }, true)

    harness.buttonOf(b).triggerPress(Qt.RightButton)
    probe("a lock on one screen names that screen",
          function () { return harness.fakeShell.lastSettings.locked }, "eDP-1")
    probe("and locks that screen's pocket", function () { return b.locked }, true)
    probe("and not the other screen's", function () { return c.locked }, false)
    // Asked through holdOpen rather than `expanded`: offscreen the pocket's own
    // HoverHandler can already report a hover, and then nothing changes to
    // open it.
    memberSlot2.hovered = true
    memberSlot.hovered = true
    probe("the other screen's member still holds its pocket open on hover",
          function () { return c.holdOpen }, true)
    probe("while this screen's member no longer does", function () { return b.holdOpen }, false)
    memberSlot2.hovered = false
    memberSlot.hovered = false
    c.expanded = false

    harness.buttonOf(c).triggerPress(Qt.LeftButton)
    probe("a pin on the other screen names that screen",
          function () { return harness.fakeShell.lastSettings.pinned }, "ASUS VG289")
    probe("and carries the first screen's lock unchanged",
          function () { return harness.fakeShell.lastSettings.locked }, "eDP-1")
    probe("the pinned screen is pinned", function () { return c.pinned }, true)
    probe("the first screen is not", function () { return b.pinned }, false)

    harness.buttonOf(c).triggerPress(Qt.RightButton)
    probe("locking the pinned screen adds it to the lock and drops only its pin",
          function () {
            return JSON.stringify([harness.fakeShell.lastSettings.locked,
                                   harness.fakeShell.lastSettings.pinned])
          }, JSON.stringify(["eDP-1, ASUS VG289", ""]))
    probe("both screens are locked now", function () { return b.locked && c.locked }, true)

    harness.buttonOf(b).triggerPress(Qt.RightButton)
    probe("unlocking one screen leaves the other locked",
          function () { return harness.fakeShell.lastSettings.locked }, "ASUS VG289")
    probe("so that one reads unlocked", function () { return b.locked }, false)
    probe("and the other still locked", function () { return c.locked }, true)

    // The stale list of 0018: this screen's pocket holds members in the old
    // order. Its pin still carries the other screen's lock, and the members go
    // out in the bar's order. Writes are not handed back from here, as in
    // step7, or the order repair's own write would end the stale state.
    harness.fakeShell.modelDelta = false
    harness.facade.layoutConfig = ({ left: [], center: [], right: [
      { id: "omarchy.network" }, { id: "omarchy.audio" },
      { id: "jrmmhm.pocket", members: "omarchy.audio, omarchy.network" }] })
    b.settings = ({ members: "omarchy.audio, omarchy.network", locked: "ASUS VG289" })
    Qt.callLater(harness.step11)
  }

  function step11() {
    var b = harness.pocket()
    var c = win2.pocket
    probe("the first screen's pocket holds the stale order", function () { return b.membersMisordered }, true)
    harness.buttonOf(b).triggerPress(Qt.LeftButton)
    probe("its pin carries the other screen's lock under a stale list",
          function () {
            var s = harness.fakeShell.lastSettings
            return JSON.stringify([s.members, s.locked, s.pinned])
          }, JSON.stringify(["omarchy.network, omarchy.audio", "ASUS VG289", "eDP-1"]))
    probe("and the other screen is still locked and unpinned",
          function () { return c.locked && !c.pinned }, true)

    // The mutator path, with this pocket's `settings` behind the file: the file
    // already holds the other screen's lock, the pocket does not know it yet.
    // The list is read inside the mutator, so that lock survives.
    harness.fakeShell.mutatorConfig = ({ bar: { layout: { left: [], center: [], right: [
      { id: "omarchy.network" }, { id: "omarchy.audio" },
      { id: "jrmmhm.pocket", members: "omarchy.network, omarchy.audio",
        locked: "ASUS VG289", pinned: "eDP-1" }] } } })
    b.settings = ({ members: "omarchy.network, omarchy.audio", pinned: "eDP-1" })
    harness.buttonOf(b).triggerPress(Qt.RightButton)
    probe("on the mutator path a lagging pocket's lock keeps the other screen's",
          function () { return JSON.stringify(harness.fakeShell.mutatorConfig.bar.layout.right[2]) },
          JSON.stringify({ id: "jrmmhm.pocket", members: "omarchy.network, omarchy.audio",
                           locked: "ASUS VG289, eDP-1", pinned: "" }))
    harness.fakeShell.mutatorConfig = null

    // A second Pocket entry: Pocket may not write. A persisted pin is not read
    // there, because no click could release it; a lock set by hand is, as it
    // always was, because it is the user's to keep.
    harness.facade.layoutConfig = ({ left: [], center: [], right: [
      { id: "omarchy.audio" }, { id: "jrmmhm.pocket" }, { id: "jrmmhm.pocket" }] })
    b.settings = ({ members: "omarchy.audio", pinned: "eDP-1", locked: "eDP-1" })
    probe("with a second entry the pocket may not write", function () { return b.mayWriteMembers }, false)
    probe("so a persisted pin is not read", function () { return b.pinned }, false)
    probe("but a lock set by hand still holds", function () { return b.locked }, true)

    // A screen the lists have never named starts unpinned and unlocked.
    c.screenKey = "DELL U2720Q"
    c.settings = ({ members: "omarchy.audio", locked: "eDP-1, ASUS VG289", pinned: "eDP-1, ASUS VG289" })
    probe("a never-seen screen starts unlocked", function () { return c.locked }, false)
    probe("and unpinned", function () { return c.pinned }, false)

    Qt.callLater(harness.step12)
  }

  // ------------------------------------------------ a panel by keybinding
  //
  // The facade never hands a member's popout over as the object: every popout
  // Pocket does not own arrives as the facade's own `foreignPopoutMarker`
  // (Bar.qml::syncPluginBarApiObjects). A keybinding opens the focused screen's
  // copy of the member (BarModel.pickPanelSlot), and that copy reports
  // `opened`. Only that screen's pocket may open, and a lock does not stop it
  // (docs/decisions/0020, 0022).

  function settleTwoScreens(bSettings, cSettings) {
    var b = harness.pocket()
    var c = win2.pocket
    harness.facade.activePopout = null
    harness.facade.layoutConfig = ({ left: [], center: [], right: [
      { id: "omarchy.audio" }, { id: "jrmmhm.pocket", members: "omarchy.audio" }] })
    harness.fakeShell.modelDelta = true
    harness.fakeShell.refuse = false
    b.screenKey = "eDP-1"
    c.screenKey = "ASUS VG289"
    b.settings = bSettings
    c.settings = cSettings
    memberSlot.hovered = false
    memberSlot2.hovered = false
    memberItem.opened = false
    memberItem2.opened = false
  }

  // A new layout restarts each pocket's settling pass, which re-arms the
  // overlay's hover 250 ms later — and offscreen that hover answers "on the
  // run". So the pointer is taken off the bar only after that pass has run.
  function quiet() {
    var b = harness.pocket()
    var c = win2.pocket
    b.overlay.hovered = false
    if (c.overlay) c.overlay.hovered = false
    b.expanded = false
    c.expanded = false
  }

  function step12() {
    harness.settleTwoScreens(({ members: "omarchy.audio", locked: "eDP-1" }),
                             ({ members: "omarchy.audio" }))
    harness.afterFold(harness.step12b)
  }

  function step12b() {
    var b = harness.pocket()
    var c = win2.pocket
    harness.quiet()
    probe("the first screen's pocket is locked", function () { return b.locked }, true)

    memberItem.opened = true
    probe("a member reporting `opened` with no popout live opens nothing",
          function () { return b.expanded }, false)
    harness.facade.activePopout = ({ owner: "another widget" })
    probe("a popout handed over as an object is asked by identity alone, as before",
          function () { return b.expanded }, false)
    memberItem.opened = false

    harness.facade.activePopout = harness.facade.foreignPopoutMarker
    probe("a foreign panel alone opens no pocket",
          function () { return b.expanded || c.expanded }, false)

    var noop = function () { }
    var halfPanels = [({ opened: true }), ({ opened: true, open: noop }), ({ opened: true, close: noop })]
    for (var i = 0; i < halfPanels.length; i++) {
      memberSlot.activeItem = halfPanels[i]
      probe("a member with `opened` but not both of open() and close() does not count (" + i + ")",
            function () { return b.expanded }, false)
    }
    memberSlot.activeItem = memberItem

    memberItem.opened = true
    probe("the member's panel summoned on the first screen opens its pocket, locked or not",
          function () { return b.expanded }, true)
    probe("and not the other screen's", function () { return c.expanded }, false)

    memberItem.opened = false
    harness.facade.activePopout = null
    b.overlay.hovered = false
    harness.afterFold(harness.step13)
  }

  function step13() {
    var b = harness.pocket()
    var c = win2.pocket
    probe("once the panel closes, the locked pocket folds", function () { return b.expanded }, false)

    harness.facade.activePopout = harness.facade.foreignPopoutMarker
    memberItem2.opened = true
    probe("the member's panel summoned on the second screen opens that pocket",
          function () { return c.expanded }, true)
    probe("and leaves the first shut", function () { return b.expanded }, false)

    // Another panel opens elsewhere: the host closes the member's panel and the
    // marker stays. A member that does not keep the contract cannot tell its
    // own panel from that one, so the pocket is held for it.
    memberItem2.opened = false
    memberSlot2.activeItem = ({ open: function () { }, close: function () { } })
    if (c.overlay) c.overlay.hovered = false
    harness.afterFold(harness.step13b)
  }

  function step13b() {
    var c = win2.pocket
    probe("a member without the contract holds an open pocket for any foreign panel",
          function () { return c.expanded }, true)
    // The member keeps the contract again, so nothing is left holding.
    memberSlot2.activeItem = memberItem2
    if (c.overlay) c.overlay.hovered = false
    harness.afterFold(harness.step14)
  }

  function step14() {
    var b = harness.pocket()
    var c = win2.pocket
    probe("a panel open elsewhere does not hold a pocket whose members keep the contract",
          function () { return c.expanded }, false)
    harness.facade.activePopout = null

    // ------------------------------------------------- identical twins
    //
    // Two monitors of one model with no serial number reaching Pocket get one
    // name (docs/decisions/0021), and so one pin and one lock.
    harness.settleTwoScreens(({ members: "omarchy.audio" }), ({ members: "omarchy.audio" }))
    harness.afterFold(harness.step14b)
  }

  function step14b() {
    var b = harness.pocket()
    var c = win2.pocket
    harness.quiet()
    b.screenKey = "VS248"
    c.screenKey = "VS248"
    var before = harness.fakeShell.inlineWrites
    harness.buttonOf(b).triggerPress(Qt.LeftButton)
    probe("a pin on one twin writes the shared name once",
          function () { return harness.fakeShell.lastSettings.pinned }, "VS248")
    probe("and pins both twins", function () { return b.pinned && c.pinned }, true)

    harness.buttonOf(c).triggerPress(Qt.RightButton)
    probe("a lock on the other twin is one write",
          function () { return harness.fakeShell.inlineWrites - before }, 2)
    probe("that locks the shared name and drops the shared pin",
          function () {
            return JSON.stringify([harness.fakeShell.lastSettings.locked,
                                   harness.fakeShell.lastSettings.pinned])
          }, JSON.stringify(["VS248", ""]))
    probe("both twins read locked", function () { return b.locked && c.locked }, true)
    b.overlay.hovered = false
    if (c.overlay) c.overlay.hovered = false
    harness.afterFold(harness.step15)
  }

  function step15() {
    var b = harness.pocket()
    var c = win2.pocket
    probe("and both twins fold", function () { return b.expanded || c.expanded }, false)
    harness.buttonOf(b).triggerPress(Qt.RightButton)
    probe("unlocking either twin unlocks both",
          function () { return !b.locked && !c.locked && harness.fakeShell.lastSettings.locked === "" }, true)
    Qt.callLater(harness.stepDrag1)
  }

  // ------------------------------------------------ the drop, on 4.5.0
  //
  // Omarchy 4.5.0 lets a released widget's ghost glide to where it lands, and
  // clears the drag only once it is there (Bar.qml::settleBarDrag). The
  // overlay sees the button come up at the start of that glide, so the drop's
  // target is gone before the drag is. Driven here in every order the two can
  // arrive in, plus a press during the glide, a release below the strip, and a
  // widget going in. Coordinates are win3's: network 0-27, member 27-54,
  // pocket 54-81, power 81-108, strip 0-26 high.

  function stepDrag1() {
    var d = win3.pocket
    harness.fakeShell.modelDelta = false
    harness.fakeShell.refuse = false
    harness.fakeShell.mutatorConfig = null
    d.bar = harness.facade3
    d.moduleName = "jrmmhm.pocket"
    Qt.callLater(harness.stepDrag2)
  }

  function stepDrag2() {
    var d = win3.pocket
    d.refreshWalk()
    // Open, so the member is drawn and can be dragged. Pinned for the session,
    // so nothing folds it while the reveal runs.
    d.sessionPinned = true
    harness.pending = harness.stepDrag3
    later.interval = 900
    later.restart()
  }

  // Aims the overlay at a scene point. The pointer's position is set before
  // the press, the way the PointHandler reports it.
  function aim(x, y) {
    var glass = win3.pocket.overlay
    glass.sceneX = x
    glass.sceneY = y
  }

  function stepDrag3() {
    var d = win3.pocket
    var glass = d.overlay
    probe("the gesture pocket resolves its member", function () { return d.resolution.slots.length }, 1)
    probe("and the member is drawn at full width", function () { return memberSlot3.width }, 27)

    // A: the button comes up first, the drag ends after the glide.
    harness.aim(80, 13)
    memberSlot3.dragSource = true
    glass.pressed = true
    probe("A: past the mark, the drag means taking the member out",
          function () { return d.dropIntent }, "remove")
    glass.pressed = false
    probe("A: the release during the glide keeps that answer",
          function () { return d.pendingIntent }, "remove")
    var writes = harness.fakeShell.inlineWrites
    memberSlot3.dragSource = false
    probe("A: and the drag ending after the glide takes the member out",
          function () {
            return harness.fakeShell.inlineWrites === writes + 1
              && String(harness.fakeShell.lastSettings.members).indexOf("omarchy.audio") === -1
          }, true)

    // B: the drag ends while the button is still down, as on 4.0.x and with
    // animations off.
    harness.aim(80, 13)
    memberSlot3.dragSource = true
    glass.pressed = true
    writes = harness.fakeShell.inlineWrites
    memberSlot3.dragSource = false
    glass.pressed = false
    probe("B: a drag that ends before the release takes the member out as before",
          function () {
            return harness.fakeShell.inlineWrites === writes + 1
              && String(harness.fakeShell.lastSettings.members).indexOf("omarchy.audio") === -1
          }, true)

    // C: a new press lands during the glide, inside the run. The host finishes
    // the glide from that press; the drop is still the one released.
    harness.aim(80, 13)
    memberSlot3.dragSource = true
    glass.pressed = true
    glass.pressed = false
    harness.aim(40, 13)
    glass.pressed = true
    probe("C: a press during the glide does not change what was released",
          function () { return d.pendingIntent }, "remove")
    writes = harness.fakeShell.inlineWrites
    memberSlot3.dragSource = false
    glass.pressed = false
    probe("C: and the member is taken out",
          function () {
            return harness.fakeShell.inlineWrites === writes + 1
              && String(harness.fakeShell.lastSettings.members).indexOf("omarchy.audio") === -1
          }, true)

    // Below the strip, still inside the surface: the host moves nothing there,
    // and neither may the pocket.
    harness.aim(80, 100)
    memberSlot3.dragSource = true
    glass.pressed = true
    probe("below the strip there is no drop target", function () { return d.localDrop }, null)
    probe("and the drag means nothing", function () { return d.dropIntent }, "none")
    writes = harness.fakeShell.inlineWrites
    glass.pressed = false
    memberSlot3.dragSource = false
    probe("so the release below the strip writes nothing",
          function () { return harness.fakeShell.inlineWrites }, writes)

    // A widget going in: power aimed at the mark's near half, the button first.
    harness.aim(55, 13)
    powerSlot3.dragSource = true
    glass.pressed = true
    probe("power on the mark's near half means taking it in",
          function () { return d.dropIntent }, "add")
    glass.pressed = false
    writes = harness.fakeShell.inlineWrites
    powerSlot3.dragSource = false
    probe("and released before the glide ends, it is taken in",
          function () {
            return harness.fakeShell.inlineWrites === writes + 1
              && String(harness.fakeShell.lastSettings.members).indexOf("omarchy.power") !== -1
          }, true)

    Qt.callLater(harness.stepRemove1)
  }

  // ------------------------------------------------ pulled off the bar
  //
  // From Omarchy 4.5.0 on, a widget let go of far enough past the bar is
  // removed from it (Bar.qml::removeBarDrag): its slot reports
  // `removalPending` from the release, and its entry leaves the layout once
  // the poof has played (commitBarRemoval). A member removed that way leaves
  // `members` too -- once its entry has left, and nothing else in the list
  // changes. A member that is merely missing, here `gone.plugin`, stays.

  function layout3(audio, power) {
    var right = [{ id: "omarchy.network" }]
    if (audio) right.push({ id: "omarchy.audio" })
    right.push({ id: "jrmmhm.pocket", members: "omarchy.audio" })
    if (power) right.push({ id: "omarchy.power" })
    return { left: [], center: [], right: right }
  }

  // A drag of `slot` let go of below the bar. `removed`: past the threshold,
  // so the host announces the removal before it clears the drag.
  function pullOff(slot, removed) {
    var glass = win3.pocket.overlay
    harness.aim(40, 120)
    slot.dragSource = true
    glass.pressed = true
    glass.pressed = false
    if (removed) slot.removalPending = true
    slot.dragSource = false
  }

  function stepRemove1() {
    var d = win3.pocket
    // Shortened from the widget's own, so R4 need not wait for it.
    if ("removalPatience" in d) d.removalPatience = 300
    d.settings = ({ members: "omarchy.audio, gone.plugin" })
    probe("R: the gesture pocket holds its member", function () { return d.resolution.slots.length }, 1)

    // R1: the host removes the member, after its poof.
    var writes = harness.fakeShell.inlineWrites
    harness.pullOff(memberSlot3, true)
    probe("R1: nothing is written while the removal is only announced",
          function () { return harness.fakeShell.inlineWrites }, writes)
    harness.facade3.layoutConfig = harness.layout3(false, true)
    memberSlot3.removalPending = false
    probe("R1: once its entry has left the layout, the member leaves members, and only it",
          function () {
            return harness.fakeShell.inlineWrites === writes + 1
              && harness.fakeShell.lastSettings.members === "gone.plugin"
          }, true)
    harness.facade3.layoutConfig = harness.layout3(true, true)

    // R2: let go of within the threshold. The host puts it back; nothing
    // changes.
    writes = harness.fakeShell.inlineWrites
    harness.pullOff(memberSlot3, false)
    probe("R2: a member let go of near the bar stays a member",
          function () { return harness.fakeShell.inlineWrites }, writes)

    // R3: a widget that is not a member is removed. Nothing to forget.
    harness.pullOff(powerSlot3, true)
    harness.facade3.layoutConfig = harness.layout3(true, false)
    powerSlot3.removalPending = false
    probe("R3: removing a widget that is not a member writes nothing",
          function () { return harness.fakeShell.inlineWrites }, writes)
    harness.facade3.layoutConfig = harness.layout3(true, true)

    // R4: the removal is announced and never written (the layout changed
    // under it, or the shell went away). Past the wait, an entry that leaves
    // later is not this gesture's doing.
    harness.pullOff(memberSlot3, true)
    memberSlot3.removalPending = false
    harness.pending = harness.stepRemove2
    later.interval = 450
    later.restart()
  }

  function stepRemove2() {
    var d = win3.pocket
    var writes = harness.fakeShell.inlineWrites
    harness.facade3.layoutConfig = harness.layout3(false, true)
    probe("R4: a removal the host never wrote is let go of, and nothing is written",
          function () { return harness.fakeShell.inlineWrites }, writes)
    harness.facade3.layoutConfig = harness.layout3(true, true)

    // R5: a second copy of the member's id, not the slot the pocket hides,
    // is pulled off. The member stays.
    var twin = memberCopy3.createObject(strip3)
    d.refreshWalk()
    probe("R5: the pocket still hides its first copy",
          function () { return d.driven.indexOf(memberSlot3) !== -1 && d.driven.indexOf(twin) === -1 }, true)
    harness.pullOff(twin, true)
    harness.facade3.layoutConfig = harness.layout3(false, true)
    probe("R5: removing the other copy writes nothing",
          function () { return harness.fakeShell.inlineWrites }, writes)
    twin.destroy()
    harness.facade3.layoutConfig = harness.layout3(true, true)
    d.settings = ({ members: "omarchy.audio" })
    harness.pending = harness.stepRemove3
    later.interval = 100
    later.restart()
  }

  function stepRemove3() {
    win3.pocket.refreshWalk()
    Qt.callLater(harness.stepFold1)
  }

  property Component memberCopy3: Component {
    Item {
      property string moduleName: "omarchy.audio"
      property string region: "right"
      property var activeItem: copyItem
      property bool hovered: false
      property bool dragSource: false
      property bool removalPending: false
      implicitWidth: 27
      implicitHeight: 26
      Item { id: copyItem }
    }
  }

  // ------------------------------------------------ the fold
  //
  // The pocket folds as soon as the pointer has left the mark and its members,
  // not once it has left the whole bar (docs/decisions/0026). Offscreen the
  // pointer rests at the window's corner, which on win3 is on the network
  // widget: a neighbour, on the bar, off the run.

  function stepFold1() {
    var d = win3.pocket
    // Off the bar, so the ticks below are about hover and nothing else.
    d.overlay.hovered = false
    d.sessionPinned = false
    memberSlot3.hovered = false
    d.expanded = true
    probe("unpinned, nothing holds the gesture pocket open", function () { return d.holdOpen }, false)

    // Driven tick by tick: one idle tick is a pointer crossing a sliver of the
    // bar between two slots, and must not fold it.
    d.foldTick()
    probe("one idle tick leaves it open", function () { return d.expanded }, true)
    memberSlot3.hovered = true
    d.foldTick()
    probe("a member hovered again starts the count over", function () { return d.idleTicks }, 0)
    memberSlot3.hovered = false
    d.foldTick()
    probe("so the next idle tick is a first one again", function () { return d.expanded }, true)
    d.foldTick()
    probe("and the second idle tick in a row folds it", function () { return d.expanded }, false)

    // Now on the timer alone, with the pointer still on the bar, on the
    // network widget before the run.
    d.expanded = true
    d.overlay.hovered = true
    d.overlay.sceneX = 13
    d.overlay.sceneY = 13
    harness.afterFold(harness.stepFold2)
  }

  function stepFold2() {
    var d = win3.pocket
    probe("with the pointer on a neighbour on the bar, the pocket folds on its own",
          function () { return d.expanded }, false)
    Qt.callLater(harness.stepFold3)
  }

  // The pointer resting where the run is while no member reports a hover. Qt
  // hovers on motion, so that is what a member looks like that has slid under
  // a still pointer -- and in the centre sections opening the pocket slides
  // the mark away from the pointer that opened it. Folding there opened and
  // folded the pocket forever, measured on the live bar (docs/decisions/0026).
  // The overlay's surface hover is what says where the pointer is.
  function stepFold3() {
    var d = win3.pocket
    memberSlot3.hovered = false
    // On the member's place from the start: the pocket opens with the pointer
    // on its run, and nothing holds it but where the pointer is. The real
    // handler is switched off for this, because offscreen it reports the
    // window's corner whenever an item moves, over the position put in here.
    d.overlay.hoverHandler.enabled = false
    d.overlay.hovered = true
    d.overlay.sceneX = 40
    d.overlay.sceneY = 13
    d.expanded = true
    // Past the 600 ms reveal, so the run stands where it will be measured.
    harness.pending = harness.stepFold4
    later.interval = 900
    later.restart()
  }

  function stepFold4() {
    var d = win3.pocket
    var glass = d.overlay
    glass.hovered = true
    glass.sceneX = 40
    glass.sceneY = 13
    d.foldTick()
    d.foldTick()
    d.foldTick()
    probe("the pointer over a member that reports no hover still holds it open",
          function () { return d.expanded }, true)
    glass.sceneX = 70
    d.foldTick()
    d.foldTick()
    probe("and over the mark", function () { return d.expanded }, true)
    glass.sceneX = 95
    d.foldTick()
    d.foldTick()
    probe("over the widget after the run it folds", function () { return d.expanded }, false)
    // Asked straight away from here on: the run is measured while it folds and
    // reopens, which is the moment it is at its narrowest, and these points are
    // outside it at any width.
    d.expanded = true
    glass.sceneX = 13
    d.foldTick()
    d.foldTick()
    probe("over the widget before the run it folds", function () { return d.expanded }, false)
    d.expanded = true
    glass.sceneX = 40
    glass.sceneY = 100
    d.foldTick()
    d.foldTick()
    probe("below the strip, in line with the run, it folds", function () { return d.expanded }, false)

    // An idle tick counted before a pin must not count after it: released, the
    // pocket gets its full grace again rather than folding on the first tick.
    d.expanded = true
    d.idleTicks = 1
    d.sessionPinned = true
    d.sessionPinned = false
    probe("releasing a pin starts the idle count over", function () { return d.idleTicks }, 0)
    d.expanded = false

    glass.rearmHover()
    Qt.callLater(harness.finish)
  }

  function finish() {
    console.warn(harness.failures === 0 ? "QML OK" : "QML FAILURES " + harness.failures)
    Qt.exit(harness.failures === 0 ? 0 : 1)
  }
}
