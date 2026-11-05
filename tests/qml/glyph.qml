import QtQuick
import Quickshell
import qs.Ui
import "plugin" as Pk

// The mark's dots sit in the middle of their slot, closed and open.
//
// Omarchy 4.5.0 fits every bar icon to its painted bounds (Ui/OpticalGlyph.qml,
// "Normalize bar icon size and alignment"), and the dots-horizontal glyph the
// mark used came out of that 2 px above the middle closed and 2.5 px right of
// it open, while the host's own arithmetic reported no error at all. So this
// asks the pixels, not the host: the real pocket, drawn by the real
// BarIconButton out of the installed shell, grabbed, and its ink measured.
//
// 1 px of tolerance, because a glyph's ink is whole pixels and the previous
// host drew this mark half a pixel off; the 2 px this case exists for fail it.
//
// Needs the bar's Nerd Font: tests/qml/run.sh skips the case where fontconfig
// knows none, rather than measuring an empty box.
QtObject {
  id: harness

  property int failures: 0

  function check(label, actual, expected) {
    if (actual === expected) return
    harness.failures++
    console.warn("FAIL: " + label + "\n  expected: " + expected + "\n  actual:   " + actual)
  }

  // The bar's colours and font as the facade hands them to a plugin.
  property PluginBarApi facade: PluginBarApi {
    pluginId: "jrmmhm.pocket"
    moduleName: "jrmmhm.pocket"
    foreground: "white"
    fontFamily: "monospace"
    barSize: 26
    layoutConfig: ({ left: [], center: [], right: [{ id: "jrmmhm.pocket" }] })
  }

  property FloatingWindow win: FloatingWindow {
    id: win
    visible: true
    color: "black"
    implicitWidth: 60
    implicitHeight: 40

    Item {
      id: slot
      property string moduleName: "jrmmhm.pocket"
      property string region: "right"
      property var activeItem: pocket
      property bool hovered: false
      property bool dragSource: false
      width: 27
      height: 26

      Pk.BarWidget {
        id: pocket
        bar: harness.facade
        moduleName: "jrmmhm.pocket"
      }
    }

    // Reads a grab back as pixels.
    Canvas {
      id: reader
      width: 27
      height: 26
      visible: false
      property var pendingUrl: ""
      property var onPixels: null
      onImageLoaded: requestPaint()
      onPaint: {
        if (!pendingUrl || !isImageLoaded(pendingUrl)) return
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.drawImage(pendingUrl, 0, 0)
        var data = ctx.getImageData(0, 0, width, height)
        var done = onPixels
        onPixels = null
        if (done) done(data)
      }
    }
  }

  // The middle of the ink's bounding box, in slot coordinates, or null when
  // nothing was drawn.
  function inkCentre(data) {
    var minX = 1e9, maxX = -1, minY = 1e9, maxY = -1
    for (var y = 0; y < data.height; y++) {
      for (var x = 0; x < data.width; x++) {
        var i = (y * data.width + x) * 4
        var lum = (data.data[i] + data.data[i + 1] + data.data[i + 2]) / 3
        if (lum <= 40) continue
        if (x < minX) minX = x
        if (x > maxX) maxX = x
        if (y < minY) minY = y
        if (y > maxY) maxY = y
      }
    }
    if (maxX < 0) return null
    return { x: (minX + maxX + 1) / 2, y: (minY + maxY + 1) / 2 }
  }

  function measure(label, next) {
    slot.grabToImage(function (result) {
      reader.pendingUrl = result.url
      reader.onPixels = function (data) {
        var centre = harness.inkCentre(data)
        if (centre === null) {
          harness.check(label + ": the mark draws something", false, true)
        } else {
          var off = Math.max(Math.abs(centre.x - slot.width / 2), Math.abs(centre.y - slot.height / 2))
          harness.check(label + ": ink centre within 1 px of the slot's ("
                        + centre.x + ", " + centre.y + ")", off <= 1, true)
        }
        next()
      }
      reader.loadImage(result.url)
      reader.requestPaint()
    })
  }

  property Timer starter: Timer {
    interval: 800
    running: true
    onTriggered: harness.measure("closed", harness.open)
  }

  function open() {
    pocket.sessionPinned = true
    later.restart()
  }

  // Past the 600 ms reveal, so the dots have finished turning.
  property Timer later: Timer {
    interval: 1000
    onTriggered: harness.measure("open", harness.finish)
  }

  function finish() {
    console.warn(harness.failures === 0 ? "QML OK" : "QML FAILURES " + harness.failures)
    Qt.exit(harness.failures === 0 ? 0 : 1)
  }
}
