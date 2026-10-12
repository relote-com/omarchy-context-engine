import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// One box for the engine: find, remember, ask, or read what changed.
// Summon with a mode:
//   omarchy-shell shell summon relote.context-engine '{"mode":"find"}'
// Tab cycles modes, Enter runs, Esc clears then closes. All engine traffic
// goes through bin/ce, so the overlay holds no key and speaks no HTTP itself.

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (root.manifest && root.manifest.id) || "relote.context-engine"
  readonly property string ce: String(Qt.resolvedUrl("bin/ce")).replace(/^file:\/\//, "")
  readonly property var modes: ["find", "remember", "ask", "brief"]
  readonly property var modeLabels: ({ find: "Find", remember: "Remember", ask: "Ask", brief: "What changed" })
  readonly property var placeholders: ({
    find: "Search your memory…",
    remember: "Something worth keeping — first line is the title",
    ask: "Ask your engine's agent…",
    brief: "Enter to load what changed since you last looked"
  })

  property bool opened: false
  property string mode: "find"
  property string status: "unknown"   // unknown | ok | not-signed-in | unreachable
  property string engine: ""
  property bool busy: false
  property string result: ""
  property string error: ""

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color scrim: Color.menu.scrim
  property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  readonly property int pad: Style.spacing.panelPadding
  readonly property int cardWidth: Math.min(Style.space(640), panel.width - Style.gapsOut * 4)
  readonly property int resultMax: Math.round(panel.height * 0.55)

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    var nextMode = root.modes.indexOf(payload.mode) >= 0 ? payload.mode : "find"
    var reopenSame = root.opened && nextMode === root.mode

    root.mode = nextMode
    root.opened = true
    if (!reopenSame) {
      root.result = ""
      root.error = ""
      input.text = payload.text || ""
    }
    statusProc.running = true
    if (root.mode === "brief" && !root.result) root.run()
    Qt.callLater(function() { input.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function cycle(step) {
    var i = root.modes.indexOf(root.mode)
    root.mode = root.modes[(i + step + root.modes.length) % root.modes.length]
    root.result = ""
    root.error = ""
    if (root.mode === "brief") root.run()
  }

  function setup() {
    root.dismiss()
    Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-launch-floating-terminal-with-presentation",
                             Util.shellQuote(root.ce) + " setup"])
  }

  function run() {
    if (root.status === "not-signed-in") { root.setup(); return }

    var text = input.text.trim()
    if (root.mode === "remember") {
      if (!text) return
      // Detached: the note saves while the box is already gone, and ce
      // reports the outcome as a notification either way.
      Util.execArgv([root.ce, "remember", "--quiet", "--notify", text])
      input.text = ""
      root.dismiss()
      return
    }
    if (root.mode === "ask" && !text) return
    if (runProc.running) return

    var args = root.mode === "find" ? ["find", "--markdown", "--limit", "10"].concat(text ? [text] : [])
             : root.mode === "ask" ? ["ask", text]
             : ["brief"]
    root.busy = true
    root.error = ""
    root.result = ""
    runProc.command = [root.ce].concat(args)
    runProc.running = true
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

  Process {
    id: runProc
    stdout: StdioCollector {
      id: runOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: runErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.busy = false
      var out = String(runOut.text || "").trim()
      var note = String(runErr.text || "").trim()
      if (exitCode !== 0) {
        root.error = note || "The engine did not answer."
        return
      }
      // A note on a success (ask falling back to find) says why, above the answer.
      root.result = (note ? "_" + note + "_\n\n" : "") + (out || "Nothing found.")
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "context-engine"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: column.implicitHeight + root.pad * 2 + card.contentTopInset + card.contentBottomInset
      radius: Style.cornerRadius
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.round(parent.height * 0.18)
      color: root.background
      borderSpec: root.borderSpec

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        id: column
        x: root.pad + card.contentLeftInset
        y: root.pad + card.contentTopInset
        width: card.width - root.pad * 2 - card.contentLeftInset - card.contentRightInset
        spacing: Style.space(10)

        // Mode row: the four things the box does, and which engine it talks to.
        Row {
          width: parent.width
          spacing: Style.space(6)

          Text {
            text: "󰧑"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            anchors.verticalCenter: parent.verticalCenter
          }

          Repeater {
            model: root.modes
            delegate: Rectangle {
              required property string modelData
              readonly property bool active: modelData === root.mode
              anchors.verticalCenter: parent.verticalCenter
              radius: Style.cornerRadius
              color: active ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14) : "transparent"
              implicitWidth: label.implicitWidth + Style.space(14)
              implicitHeight: label.implicitHeight + Style.space(6)

              Text {
                id: label
                anchors.centerIn: parent
                text: root.modeLabels[modelData]
                color: root.foreground
                opacity: parent.active ? 1 : 0.55
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              MouseArea {
                anchors.fill: parent
                onClicked: {
                  root.mode = modelData
                  root.result = ""
                  root.error = ""
                  if (modelData === "brief") root.run()
                  input.forceActiveFocus()
                }
              }
            }
          }
        }

        TextField {
          id: input
          width: parent.width
          foreground: root.foreground
          font.pixelSize: Style.font.heading
          placeholderText: root.status === "not-signed-in"
            ? "Not connected — press Enter to set up Context Engine"
            : root.placeholders[root.mode]
          readOnly: root.mode === "brief"

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              if (input.text) input.text = ""
              else root.dismiss()
              event.accepted = true
            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
              root.cycle(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.run()
              event.accepted = true
            }
          }
        }

        // Results: the engine's own rendering, which is Markdown for a reader.
        Flickable {
          id: results
          visible: root.busy || root.result !== "" || root.error !== ""
          width: parent.width
          height: Math.min(resultText.implicitHeight, root.resultMax)
          contentWidth: width
          contentHeight: resultText.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Text {
            id: resultText
            width: results.width
            wrapMode: Text.Wrap
            textFormat: root.error || root.busy || root.mode === "brief" ? Text.PlainText : Text.MarkdownText
            text: root.busy ? (root.mode === "ask" ? "Thinking…" : "Looking…")
                : root.error ? root.error
                : root.result
            color: root.foreground
            opacity: root.busy ? 0.6 : 1
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            onLinkActivated: function(link) { Qt.openUrlExternally(link) }
          }
        }

        Text {
          width: parent.width
          text: (root.status === "ok"
                  ? "Saving to " + (root.engine || "your engine")
                  : root.status === "unreachable" ? "Context Engine did not answer this key"
                  : root.status === "not-signed-in" ? "Not connected" : "")
                + "   ·   Tab switch   ·   Enter run   ·   Esc close"
          color: root.foreground
          opacity: 0.45
          elide: Text.ElideRight
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
