import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "plugin" as Pk

// The real BarWidget.qml against the real facade — `Ui/PluginBarApi.qml` out of
// the installed shell, not a hand-written stand-in.
//
// A stand-in is what this case exists to avoid. The break this whole version
// answers was invisible to a suite whose fake bars all published the fifteen
// symbols the plugin reads, and a mock written from the same understanding
// would have repeated the same assumption. The facade is the host's own file:
// when Omarchy narrows it again, this case changes with it.
//
// It pins two things the live bar found and no other case can reach:
//   1. what the capability layer concludes about a facade;
//   2. that the overlay is built even though `bar` arrives AFTER
//      Component.onCompleted, which is how the host injects it — attaching from
//      onCompleted alone left hiding working and the gesture silently dead.
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
    function updateEntryInline(id, settings) {
      inlineWrites++
      lastSettings = settings
      return true
    }
    // Present and refusing, exactly as the facade's is for a plugin that does
    // not declare kind "bar". The plugin must not read the return value.
    function mutateShellConfig(mutator) { return false }
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
      property var activeItem: pocketA
      property bool hovered: false
      property bool dragSource: false
      width: 27
      height: 26

      // Deliberately created with NO bar. The host injects it from a callLater
      // after the loader completes, so at Component.onCompleted it is null and
      // every question asked of it answers as if there were no host at all.
      Pk.BarWidget {
        id: pocketA
        settings: ({ members: "omarchy.audio" })
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

    property Pk.BarWidget pocketItem: pocketA
    property Pk.BarWidget secondPocket: pocketB
  }

  property Timer starter: Timer {
    interval: 0
    running: true
    onTriggered: harness.step1()
  }

  function overlayCount() {
    var root = win.pocketItem.QsWindow ? win.pocketItem.QsWindow.contentItem : null
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

  function step3() {
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

    Qt.callLater(harness.finish)
  }

  function finish() {
    console.warn(harness.failures === 0 ? "QML OK" : "QML FAILURES " + harness.failures)
    Qt.exit(harness.failures === 0 ? 0 : 1)
  }
}
