import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    property string answer: "Copy a question or image, then press Super+K."
    property bool revealed: false
    readonly property var settings: {
        const defaults = { opacity: 0.18, color: "#ffffff", fontSize: 14,
            xFraction: 0.25, widthFraction: 0.22, y: 2, height: 32,
            maxLines: 2, hideDelay: 60, initialDelay: 550 };
        try {
            return Object.assign(defaults, JSON.parse(Quickshell.env("COPAI_OVERLAY_SETTINGS") || "{}"));
        } catch (e) { return defaults; }
    }

    Process {
        id: request
        command: ["copai-ask"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.answer = JSON.parse(text).text; }
                catch (e) { root.answer = "Unable to read the answer. Try Super+K again."; }
            }
        }
        onExited: (code, status) => {
            if (code !== 0) root.answer = "The request failed. Try Super+K again.";
        }
    }

    IpcHandler {
        target: "copai"
        function ask(): void {
            if (request.running) return;
            root.answer = "Loading…";
            request.running = true;
        }
        function reveal(): void {
            // Niri 26.04 has no release bindings. Its initial repeat delay is
            // 500 ms, then 25 Hz; keep the overlay alive without taking focus.
            // Repeats arrive every 40 ms; allow 20 ms of scheduling slack.
            hideTimer.interval = root.revealed ? root.settings.hideDelay : root.settings.initialDelay;
            root.revealed = true;
            hideTimer.restart();
        }
        function hide(): void { root.revealed = false; }
    }

    Timer {
        id: hideTimer
        onTriggered: root.revealed = false
    }

    PanelWindow {
        id: panel
        visible: root.revealed
        anchors { left: true; right: true; top: true; bottom: true }
        // Match Honklet: draw over the bar without reserving space or input.
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "copai"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}

        Item {
            id: content
            anchors.fill: parent
            clip: true
            Text {
                id: answerText
                // Faint text in the bar area, just left of the workspace group.
                x: parent.width * root.settings.xFraction
                y: root.settings.y
                width: parent.width * root.settings.widthFraction
                height: root.settings.height
                verticalAlignment: Text.AlignVCenter
                maximumLineCount: root.settings.maxLines
                elide: Text.ElideRight
                text: root.answer
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                color: root.settings.color
                opacity: root.settings.opacity
                font.pixelSize: root.settings.fontSize
            }
        }
    }
}
