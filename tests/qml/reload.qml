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
// standing in for the registry loader. A slot whose `moduleSettings` change
// injects them at once, ahead of anything else listening, as the host's does.
// The pocket is handed the host's own Ui/PluginBarApi.qml and walks its window
// for slots, as on 4.0.3 and later. The file is written to the home
// tests/qml/run.sh gives this case.
//
// The frozen copy lacks a member the file holds and has no lock, so any write
// built from it shows; and its members are out of layout order, so the order
// repair would write it back on its own a turn after the reload.
//
// One pocket per window, one case per pocket:
// - `reloaded`: the file is taken over a moment after the reload, while
//   another widget's entry keeps rewriting the file; again, read fresh, after a
//   late injection of the frozen copy; and carried by the next write. A host
//   delta equal in value to the frozen copy is the host's and is kept.
// - `early`, `dropper`, `dragger`: a write, a drop, and the start of a drag,
//   each before the timer: each asks the file first.
// - `late`: its slot is found only after the timer, as when a monitor move
//   unmapped the surface.
// - `rebuilt`: the slot is current and the file lags it, the way a pocket the
//   bar rebuilt after a drag is born before the move is on disk. The older
//   file is never taken over, the order repair still writes, and a slot whose
//   `moduleSettings` follow its entry turns the file off.
QtObject {
  id: harness

  readonly property string selfId: "jrmmhm.pocket"
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
  readonly property string rebuiltPath: Quickshell.env("HOME") + "/.config/omarchy/rebuilt.json"

  // What the slots were built with when the shell last started.
  readonly property var frozen: ({ members: "mehiel.darky, omaplug" })
  // What shell.json holds since: a member taken in and a lock set.
  readonly property var current: ({ members: "omarchy.audio, omaplug, mehiel.darky", locked: "eDP-1" })
  // And later still, for a read that must not come from a cache.
  readonly property var newer: ({ members: "omarchy.audio, omaplug, mehiel.darky", locked: "eDP-1",
                                  pinned: "ASUS VG289" })
  readonly property var layoutIds: ["omarchy.tray", "omarchy.audio", "omaplug", "mehiel.darky", "jrmmhm.pocket"]

  function layout() {
    var right = []
    for (var i = 0; i < harness.layoutIds.length; i++) right.push({ id: harness.layoutIds[i] })
    return { left: [], center: [], right: right }
  }

  function configText(settings, tick) {
    var config = { version: 1, bar: { layout: harness.layout() } }
    var entry = { id: harness.selfId }
    for (var k in settings) entry[k] = settings[k]
    config.bar.layout.right[4] = entry
    if (tick !== undefined) config.bar.layout.right[0].tick = tick
    return JSON.stringify(config, null, 2) + "\n"
  }

  function same(a, b) { return JSON.stringify(a) === JSON.stringify(b) }
  function last() { return harness.writes.length > 0 ? harness.writes[harness.writes.length - 1].next : {} }

  // Writes built from the frozen copy: no `omarchy.audio`, or no lock.
  function staleWrites() {
    var n = 0
    for (var i = 0; i < harness.writes.length; i++) {
      var next = harness.writes[i].next
      if (String(next.members).indexOf("omarchy.audio") === -1 || next.locked === undefined) n++
    }
    return n
  }

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

  // Another widget's entry rewritten faster than any quiet period, as an
  // editor's autosave or a chatty plugin would.
  property Timer churn: Timer {
    interval: 300
    repeat: true
    property int tick: 0
    onTriggered: harness.configWriter.setText(harness.configText(harness.current, ++tick))
  }

  component Slot: Item {
    property string moduleName: ""
    property string region: "right"
    property var activeItem: null
    property bool dragSource: false
    property var moduleSettings: ({})
    onModuleSettingsChanged: if (activeItem) activeItem.settings = moduleSettings
    width: 32
    height: 30
  }

  // Bar.qml's order: injected in the loader's onLoaded, again a turn later, and
  // a turn after the slot names its active item. `claims: false` leaves the
  // naming to the test.
  function inject(slot, item, claims) {
    item.settings = slot.moduleSettings
    Qt.callLater(function () { item.settings = slot.moduleSettings })
    if (!claims) return
    slot.activeItem = item
    Qt.callLater(function () { item.settings = slot.moduleSettings })
  }

  component PocketWindow: FloatingWindow {
    id: w
    visible: true
    property QtObject h: null
    property var slotSettings: ({})
    property string path: ""
    property bool claims: true
    property alias slot: pocketSlot
    property alias loader: pocketLoader
    property alias omaplug: omaplugSlot
    Slot { moduleName: "omarchy.tray" }
    Slot { moduleName: "omarchy.audio" }
    Slot { id: omaplugSlot; moduleName: "omaplug" }
    Slot { moduleName: "mehiel.darky" }
    Slot {
      id: pocketSlot
      moduleName: "jrmmhm.pocket"
      moduleSettings: w.slotSettings
      Loader {
        id: pocketLoader
        active: false
        sourceComponent: Component { Pk.BarWidget { bar: w.h.facade; configPath: w.path } }
        onLoaded: w.h.inject(pocketSlot, item, w.claims)
      }
    }
  }

  property PocketWindow reloadedWin: PocketWindow { h: harness; slotSettings: harness.frozen; path: harness.configPath }
  property PocketWindow earlyWin: PocketWindow { h: harness; slotSettings: harness.frozen; path: harness.configPath }
  property PocketWindow dropperWin: PocketWindow { h: harness; slotSettings: harness.frozen; path: harness.configPath }
  property PocketWindow draggerWin: PocketWindow { h: harness; slotSettings: harness.frozen; path: harness.configPath }
  property PocketWindow lateWin: PocketWindow { h: harness; slotSettings: harness.frozen; path: harness.configPath; claims: false }
  property PocketWindow rebuiltWin: PocketWindow { h: harness; slotSettings: harness.current; path: harness.rebuiltPath }

  readonly property var windows: [reloadedWin, earlyWin, dropperWin, draggerWin, lateWin, rebuiltWin]
  readonly property var reloaded: reloadedWin.loader.item
  readonly property var early: earlyWin.loader.item
  readonly property var dropper: dropperWin.loader.item
  readonly property var dragger: draggerWin.loader.item
  readonly property var late: lateWin.loader.item
  readonly property var rebuilt: rebuiltWin.loader.item

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
    for (var i = 0; i < harness.windows.length; i++) harness.windows[i].loader.active = true
    harness.churn.start()
    harness.next(300)
  }

  function step2() {
    // Preconditions: the host's order was played, and nothing below is about
    // anything but these pockets' own slots.
    harness.check("reloaded: the pocket finds its own slot",
                  harness.reloaded.ownSlot === reloadedWin.slot, true)
    harness.check("reloaded: the host handed it the frozen copy",
                  harness.reloaded.settings === reloadedWin.slot.moduleSettings, true)
    harness.check("rebuilt: the pocket finds its own slot",
                  harness.rebuilt.ownSlot === rebuiltWin.slot, true)
    harness.check("before the timer, no pocket has asked the file",
                  harness.early.settingsChecked || harness.dropper.settingsChecked
                  || harness.dragger.settingsChecked, false)

    harness.check("early: a write goes out", harness.early.writeSettings({ pinned: "eDP-1" }), true)
    harness.check("early: it carries what the file holds", JSON.stringify(harness.last()),
                  JSON.stringify({ members: harness.current.members, locked: "eDP-1", pinned: "eDP-1" }))

    harness.dropper.commitDrop("remove", "omaplug")
    harness.check("dropper: a drop is decided on what the file holds", JSON.stringify(harness.last()),
                  JSON.stringify({ members: "omarchy.audio, mehiel.darky", locked: "eDP-1" }))

    draggerWin.omaplug.dragSource = true
    harness.check("dragger: a drag is decided on what the file holds",
                  JSON.stringify(harness.dragger.dragMembers),
                  JSON.stringify(["omarchy.audio", "omaplug", "mehiel.darky"]))
    draggerWin.omaplug.dragSource = false

    // The move lands on disk after the rebuilt pocket was born.
    harness.rebuiltWriter.setText(harness.configText(harness.current))
    harness.next(1500)
  }

  function step3() {
    harness.churn.stop()
    harness.check("reloaded: the file's entry is taken over, though the file kept changing",
                  JSON.stringify(harness.reloaded.settings), JSON.stringify(harness.current))
    harness.check("reloaded: and read as it says", JSON.stringify(harness.reloaded.memberIds),
                  JSON.stringify(["omarchy.audio", "omaplug", "mehiel.darky"]))
    harness.check("nothing was written from the frozen copy", harness.staleWrites(), 0)

    harness.check("rebuilt: the slot's current entry stands",
                  JSON.stringify(harness.rebuilt.settings), JSON.stringify(harness.current))
    harness.check("rebuilt: the older file was never taken over", harness.rebuilt.adoptedSettings, null)

    harness.check("late: no slot yet, so the file has not been asked", harness.late.settingsChecked, false)

    // The file moves on; then the host injects the frozen copy once more, and
    // the late pocket's walk finds its slot.
    harness.configWriter.setText(harness.configText(harness.newer))
    harness.reloaded.settings = reloadedWin.slot.moduleSettings
    lateWin.slot.activeItem = harness.late
    harness.next(1500)
  }

  function step4() {
    harness.check("reloaded: taken over again after a late injection, read fresh",
                  JSON.stringify(harness.reloaded.settings), JSON.stringify(harness.newer))
    harness.check("late: the file's entry is taken over once the slot is found",
                  JSON.stringify(harness.late.settings), JSON.stringify(harness.newer))
    harness.check("still nothing written from the frozen copy", harness.staleWrites(), 0)

    // The defect itself: the next write rebuilds the entry from `settings`.
    harness.check("reloaded: a write goes out", harness.reloaded.writeSettings({ pinned: "eDP-1" }), true)
    harness.check("reloaded: it carries what the file holds", JSON.stringify(harness.last()),
                  JSON.stringify({ members: harness.newer.members, locked: "eDP-1", pinned: "eDP-1" }))

    // The host's delta path delivers settings equal in value to the frozen
    // copy, while the file still holds the newer write. A delta is a new
    // object: it is the host's, and the file is not asked.
    harness.reloaded.settings = JSON.parse(JSON.stringify(harness.frozen))
    harness.next(1500)
  }

  function step5() {
    harness.check("reloaded: a host delta equal to the frozen copy is kept",
                  JSON.stringify(harness.reloaded.settings), JSON.stringify(harness.frozen))

    // The order repair waits for the file, and still runs after it: the host
    // hands the rebuilt pocket the old order back (0018).
    harness.writes = []
    harness.rebuilt.settings = ({ members: "mehiel.darky, omarchy.audio, omaplug", locked: "eDP-1" })
    harness.next(1500)
  }

  function step6() {
    harness.check("rebuilt: the order repair still writes, once the file was asked",
                  JSON.stringify(harness.last()), JSON.stringify(harness.current))

    // A host whose slots follow their entry (omacom/omarchy#7692): the slot's
    // own copy changes and is injected at once, while the file says something
    // older.
    harness.rebuiltWriter.setText(harness.configText({ members: "omaplug" }))
    rebuiltWin.slot.moduleSettings = ({ members: harness.current.members, pinned: "eDP-1" })
    harness.next(1500)
  }

  function step7() {
    harness.check("rebuilt: a slot that follows its entry turns the file off",
                  harness.rebuilt.slotTracksEntry, true)
    harness.check("rebuilt: and its copy stands", JSON.stringify(harness.rebuilt.settings),
                  JSON.stringify({ members: harness.current.members, pinned: "eDP-1" }))

    console.warn(harness.failures === 0 ? "QML OK" : "QML FAILURES " + harness.failures)
    Qt.exit(harness.failures === 0 ? 0 : 1)
  }
}
