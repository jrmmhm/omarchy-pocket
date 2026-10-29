import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import "plugin" as Pk

// A reloaded pocket writes what shell.json holds, not what its slot was built
// with.
//
// After a hot reload the host injects the slot's frozen `moduleSettings`
// (omacom/omarchy#7691), and the inline write rebuilds the whole entry from
// `settings` (0019), so the next write put the old members and pins back.
// docs/decisions/0025 has the host's injection order, which inject() below
// plays against a slot item with a frozen `moduleSettings` and a Loader
// standing in for the registry loader. The pocket is handed the host's own Ui/PluginBarApi.qml and walks
// its window for slots, as on 4.0.3 and later. The file is written to the home
// tests/qml/run.sh gives this case.
//
// Two pockets in two windows:
// - `reloaded`: the file is newer than the slot. Asserted: the file's entry is
//   taken over once the file is quiet, again after a late injection of the
//   frozen copy, and carried by the next write; once the host delivers settings
//   of its own, the file is left be.
//   The frozen copy's members are out of layout order, so the order repair
//   would write it back on its own a turn after the reload; nothing may be
//   written before the file has been asked.
// - `rebuilt`: the slot is current and the file lags it, the way a pocket the
//   bar rebuilt after a drag is born before the move is on disk. Asserted: the
//   older file is never taken over, and the order repair still writes.
QtObject {
  id: harness

  readonly property string selfId: "jrmmhm.pocket"
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
  readonly property string rebuiltPath: Quickshell.env("HOME") + "/.config/omarchy/rebuilt.json"

  // What the slots were built with when the shell last started, in the order a
  // reorder since then has left behind (0018): the order repair writes on its
  // own as soon as it sees the list disagree with the bar.
  readonly property var frozen: ({ members: "mehiel.darky, omaplug" })
  // What shell.json holds since: a member taken in and a lock set.
  readonly property var current: ({ members: "omaplug, mehiel.darky", locked: "eDP-1" })

  function layout() {
    return { left: [], center: [], right: [{ id: "omarchy.tray" }, { id: "omaplug" },
      { id: "mehiel.darky" }, { id: harness.selfId }] }
  }

  function configText(settings) {
    var config = { version: 1, bar: { layout: harness.layout() } }
    var entry = { id: harness.selfId }
    for (var k in settings) entry[k] = settings[k]
    config.bar.layout.right[3] = entry
    return JSON.stringify(config, null, 2) + "\n"
  }

  function same(a, b) { return JSON.stringify(a) === JSON.stringify(b) }

  property var writes: []
  property QtObject fakeShell: QtObject {
    function updateEntryInline(id, next) {
      harness.writes.push({ id: id, next: JSON.parse(JSON.stringify(next)) })
      return true
    }
  }

  property PluginBarApi facade: PluginBarApi {
    pluginId: "jrmmhm.pocket"
    moduleName: "jrmmhm.pocket"
    layoutConfig: harness.layout()
    shell: harness.fakeShell
  }

  property FileView configWriter: FileView {
    path: harness.configPath
    blockWrites: true
    printErrors: false
  }

  property FileView rebuiltWriter: FileView {
    path: harness.rebuiltPath
    blockWrites: true
    printErrors: false
  }

  component Slot: Item {
    property string moduleName: ""
    property string region: "right"
    property var activeItem: null
    property var moduleSettings: ({})
    width: 32
    height: 30
  }

  function inject(slot, item) {
    item.settings = slot.moduleSettings
    Qt.callLater(function () { item.settings = slot.moduleSettings })
    slot.activeItem = item
    Qt.callLater(function () { item.settings = slot.moduleSettings })
  }

  property FloatingWindow reloadedWin: FloatingWindow {
    visible: true
    Slot { moduleName: "omarchy.tray" }
    Slot { moduleName: "omaplug" }
    Slot { moduleName: "mehiel.darky" }
    Slot {
      id: reloadedSlot
      moduleName: harness.selfId
      moduleSettings: harness.frozen
      Loader {
        id: reloadedLoader
        active: false
        sourceComponent: Component { Pk.BarWidget { bar: harness.facade } }
        onLoaded: harness.inject(reloadedSlot, item)
      }
    }
    property Item slot: reloadedSlot
    property Loader loader: reloadedLoader
  }

  // A third pocket whose walk finds its slot only after the quiet period, the
  // way a surface a monitor move unmapped comes back: injected like the
  // others, but its slot names it as the active item late (step3).
  property FloatingWindow lateWin: FloatingWindow {
    visible: true
    Slot { moduleName: "omarchy.tray" }
    Slot { moduleName: "omaplug" }
    Slot { moduleName: "mehiel.darky" }
    Slot {
      id: lateSlot
      moduleName: harness.selfId
      moduleSettings: harness.frozen
      Loader {
        id: lateLoader
        active: false
        sourceComponent: Component { Pk.BarWidget { bar: harness.facade } }
        onLoaded: {
          item.settings = lateSlot.moduleSettings
          Qt.callLater(function () { item.settings = lateSlot.moduleSettings })
        }
      }
    }
    property Item slot: lateSlot
    property Loader loader: lateLoader
  }

  property FloatingWindow rebuiltWin: FloatingWindow {
    visible: true
    Slot { moduleName: "omarchy.tray" }
    Slot { moduleName: "omaplug" }
    Slot { moduleName: "mehiel.darky" }
    Slot {
      id: rebuiltSlot
      moduleName: harness.selfId
      moduleSettings: harness.current
      Loader {
        id: rebuiltLoader
        active: false
        sourceComponent: Component {
          Pk.BarWidget { bar: harness.facade; configPath: harness.rebuiltPath }
        }
        onLoaded: harness.inject(rebuiltSlot, item)
      }
    }
    property Item slot: rebuiltSlot
    property Loader loader: rebuiltLoader
  }

  readonly property var reloaded: reloadedWin.loader.item
  readonly property var rebuilt: rebuiltWin.loader.item
  readonly property var late: lateWin.loader.item

  property int failures: 0

  function check(label, actual, expected) {
    if (actual === expected) return
    harness.failures++
    console.warn("FAIL: " + label + "\n  expected: " + expected + "\n  actual:   " + actual)
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
    harness.configWriter.setText(harness.configText(harness.current))
    harness.rebuiltWriter.setText(harness.configText(harness.frozen))
    reloadedWin.loader.active = true
    lateWin.loader.active = true
    rebuiltWin.loader.active = true
    harness.next(300)
  }

  function step2() {
    // Preconditions: the host's order was played, and nothing below is about
    // anything but these two pockets' own slots.
    harness.check("reloaded: the pocket finds its own slot",
                  harness.reloaded.ownSlot === reloadedWin.slot, true)
    harness.check("reloaded: the host handed it the frozen copy",
                  harness.same(harness.reloaded.settings, harness.frozen), true)
    harness.check("rebuilt: the pocket finds its own slot",
                  harness.rebuilt.ownSlot === rebuiltWin.slot, true)

    // The move lands on disk after the rebuilt pocket was born.
    harness.rebuiltWriter.setText(harness.configText(harness.current))
    harness.next(1500)
  }

  function step3() {
    harness.check("reloaded: the file's entry is taken over",
                  JSON.stringify(harness.reloaded.settings), JSON.stringify(harness.current))
    harness.check("reloaded: and read as it says",
                  JSON.stringify(harness.reloaded.memberIds), JSON.stringify(["omaplug", "mehiel.darky"]))
    harness.check("reloaded: nothing was written from the frozen copy", harness.writes.length, 0)

    harness.check("rebuilt: the slot's current entry stands",
                  JSON.stringify(harness.rebuilt.settings), JSON.stringify(harness.current))
    harness.check("rebuilt: the older file was never taken over",
                  harness.rebuilt.adoptedSettings, null)

    harness.check("late: no slot yet, so the file has not been asked", harness.late.settingsChecked, false)

    // The host injects the frozen copy once more, and the late pocket's walk
    // finds its slot.
    harness.reloaded.settings = reloadedWin.slot.moduleSettings
    lateWin.slot.activeItem = harness.late
    harness.next(1500)
  }

  function step4() {
    harness.check("reloaded: taken over again after a late injection",
                  JSON.stringify(harness.reloaded.settings), JSON.stringify(harness.current))
    harness.check("late: the file's entry is taken over once the slot is found",
                  JSON.stringify(harness.late.settings), JSON.stringify(harness.current))
    harness.check("reloaded: and still nothing written from the frozen copy", harness.writes.length, 0)

    // The defect itself: the next write rebuilds the entry from `settings`.
    var before = harness.writes.length
    harness.check("reloaded: a write goes out", harness.reloaded.writeSettings({ pinned: "eDP-1" }), true)
    var sent = harness.writes.length > before ? harness.writes[harness.writes.length - 1].next : {}
    harness.check("reloaded: the write carries the members the file holds",
                  sent.members, harness.current.members)
    harness.check("reloaded: and the lock", sent.locked, harness.current.locked)

    // The host's delta path delivers settings of its own, then the file
    // changes behind it.
    harness.reloaded.settings = ({ members: "omaplug", note: "from the host" })
    harness.configWriter.setText(harness.configText({ members: "" }))
    harness.next(1500)
  }

  function step5() {
    harness.check("reloaded: once the host is current, the file is left be",
                  JSON.stringify(harness.reloaded.settings),
                  JSON.stringify({ members: "omaplug", note: "from the host" }))

    // The order repair waits for the file, and still runs after it: the host
    // hands the rebuilt pocket the old order back (0018).
    harness.writes = []
    harness.rebuilt.settings = ({ members: "mehiel.darky, omaplug", locked: "eDP-1" })
    harness.next(1500)
  }

  function step6() {
    var sent = harness.writes.length > 0 ? harness.writes[harness.writes.length - 1].next : {}
    harness.check("rebuilt: the order repair still writes, once the file was asked",
                  JSON.stringify(sent), JSON.stringify({ members: "omaplug, mehiel.darky", locked: "eDP-1" }))

    console.warn(harness.failures === 0 ? "QML OK" : "QML FAILURES " + harness.failures)
    Qt.exit(harness.failures === 0 ? 0 : 1)
  }
}
