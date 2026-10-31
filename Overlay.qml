import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui

// One box for the engine: find, remember, ask, or read what changed.
// Ask is not answered here: it hands the question to Omarchy's default agent
// (omarchy agent prompt), which reads the engine through its MCP server.
// Summon with a mode:
//   omarchy-shell shell summon relote.context-engine '{"mode":"find"}'
// Tab cycles modes, Enter runs (Shift+Enter starts a new line in Remember),
// Esc clears then closes. All engine traffic
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
    remember: "Something worth keeping — first line is the title, Shift+Enter for more",
    ask: "Ask your agent — it reads your engine…",
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
  property color accent: Color.menu.selectedText
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
    root.setMode(root.modes[(i + step + root.modes.length) % root.modes.length])
  }

  function setMode(next) {
    // A query carries into Ask as the start of a question; into Remember it
    // would be saved as the start of the title.
    if (next === "remember" && root.mode !== "remember") input.text = ""
    root.mode = next
    root.result = ""
    root.error = ""
    if (next === "brief") root.run()
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
    if (root.mode === "ask") {
      if (!text) return
      // Connect the default agent first if it has no engine yet, then open it
      // with the question; with no default agent, Omarchy offers the picker.
      Util.execArgv(["bash", "-c",
        '"$1" ensure-agent >/dev/null 2>&1; ' +
        'if [[ -n $(omarchy-default-agent) ]]; then exec omarchy-agent-prompt "$2"; ' +
        'else exec omarchy-agent --pick; fi',
        "ce-ask", root.ce, text])
      input.text = ""
      root.dismiss()
      return
    }
    if (runProc.running) return

    var args = root.mode === "find" ? ["find", "--markdown", "--limit", "10"].concat(text ? [text] : [])
             : ["brief", "--summary"]
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
      // A note on a success says why, above the result.
      root.result = (note ? "*" + note + "*\n\n" : "") + (out || "Nothing found.")
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
                  root.setMode(modelData)
                  input.forceActiveFocus()
                }
              }
            }
          }
        }

        // Multi-line, for Remember's title and body. Styled like the kit's
        // TextField, which only comes single-line.
        Controls.TextArea {
          id: input
          readonly property var borderSpec: Border.controlSpec(activeFocus ? "focus" : (hovered ? "hover-cursor" : "normal"), root.foreground, Color.accent)
          width: parent.width
          wrapMode: TextEdit.Wrap
          color: root.foreground
          selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
          selectedTextColor: root.foreground
          placeholderTextColor: Qt.darker(root.foreground, 1.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          leftPadding: Style.spacing.controlPaddingX + Border.left(borderSpec)
          rightPadding: Style.spacing.controlPaddingX + Border.right(borderSpec)
          topPadding: Style.spacing.inputPaddingY + Border.top(borderSpec)
          bottomPadding: Style.spacing.inputPaddingY + Border.bottom(borderSpec)
          background: BorderSurface {
            color: Style.controlFill(input.activeFocus, input.hovered, root.foreground, Color.accent)
            borderSpec: input.borderSpec
            radius: Style.cornerRadius
          }
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
              if (root.mode === "remember" && (event.modifiers & Qt.ShiftModifier)) {
                if (input.selectedText) input.remove(input.selectionStart, input.selectionEnd)
                input.insert(input.cursorPosition, "\n")
              } else {
                root.run()
              }
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
            text: root.busy ? "Looking…"
                : root.error ? root.error
                : root.result
            color: root.foreground
            linkColor: root.accent
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
                + (root.mode === "remember"
                   ? "   ·   Enter save   ·   Shift+Enter new line   ·   Esc close"
                   : "   ·   Tab switch   ·   Enter run   ·   Esc close")
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
