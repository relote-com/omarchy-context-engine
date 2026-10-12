import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The engine in the bar: one glyph, dimmed until this computer is signed in.
// Left click finds, right click remembers, middle click shows what changed.
// Not signed in, any click opens setup.

BarWidget {
  id: root
  moduleName: "relote.context-engine"

  readonly property string ce: String(Qt.resolvedUrl("bin/ce")).replace(/^file:\/\//, "")
  readonly property string pluginId: "relote.context-engine"
  property string status: "unknown"
  property string engine: ""

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function summon(mode) {
    if (!root.bar) return
    root.bar.run("omarchy-shell shell toggle " + root.pluginId + " " + Util.shellQuote(JSON.stringify({ mode: mode })))
  }

  function setup() {
    if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation " + Util.shellQuote(Util.shellQuote(root.ce) + " setup"))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "relote.context-engine"

    function refresh(): void {
      root.broadcast("refresh")
    }
  }

  Process {
    id: statusProc
    command: [root.ce, "status", "--short"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").trim().split(" ")
        root.status = parts[0] || "unknown"
        root.engine = parts[1] || ""
      }
    }
  }

  Timer {
    interval: Math.max(60, Number(root.setting("refreshIntervalSec", 600))) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰧑"
    opacity: root.status === "ok" ? 1 : 0.45
    slotSize: Style.bar.statusSlot
    tooltipText: root.status === "ok"
      ? "Context Engine · " + (root.engine || "connected") + "\nClick find · Right-click remember · Middle what changed"
      : root.status === "unreachable" ? "Context Engine did not answer — click to set up again"
      : "Context Engine · click to set up"

    onPressed: function(b) {
      if (root.status === "not-signed-in" || root.status === "unreachable") { root.setup(); return }
      if (b === Qt.RightButton) root.summon("remember")
      else if (b === Qt.MiddleButton) root.summon("brief")
      else root.summon("find")
    }
  }
}
