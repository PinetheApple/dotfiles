// Live meeting transcript panel.
//
// Shows the transcript as it accumulates during a meeting.
//
// voxtype writes transcript.json only when the meeting stops, and its
// SQLite index stores no segments, so there is nothing to read from
// disk mid-meeting. The daemon does however announce every chunk it
// transcribes on its own log, so the panel tails the journal rather
// than transcribing the audio a second time. The daemon must run with
// `-v` for those lines to be emitted (see the systemd drop-in).
//
// Log text is truncated by the daemon at 50 characters, so these lines
// are previews; the exact transcript arrives in the review panel on
// stop.
//
// This is a FloatingWindow rather than a layer-shell surface so the
// compositor moves and stacks it — hand-rolled dragging of a layer
// surface fights itself, because the surface shifts under the pointer
// mid-drag.

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "voxtype-shared" as VT

FloatingWindow {
    id: root

    property string runtimeDir: {
        const xdg = Quickshell.env("XDG_RUNTIME_DIR");
        return xdg && xdg.length > 0 ? xdg + "/voxtype" : "/run/user/1000/voxtype";
    }

    /// Lines kept in the rolling view. Older ones scroll out of history.
    property int maxLines: 40

    /// How close to the bottom counts as "following the tail", in pixels.
    property int followThresholdPx: 48
    property int panelWidth: 460
    property int panelHeight: 300

    property string uiFont: "Adwaita Sans"
    property color bodyColor: Qt.rgba(0.87, 0.89, 0.92, 1.0)
    property color dimColor: Qt.rgba(0.42, 0.44, 0.48, 1.0)

    property string _status: "idle"
    property string _meetingId: ""
    property var _lines: []
    property int _elapsedSecs: 0
    property var _startedAtMs: 0

    readonly property bool active: _status === "recording" || _status === "paused"

    readonly property color statusColor:
        _status === "recording" ? VT.Theme.recordingColor
      : _status === "paused"    ? VT.Theme.transcribingColor
      :                           VT.Theme.idleColor

    visible: active
    title: "voxtype transcript"
    color: VT.Theme.bgColor
    implicitWidth: panelWidth
    implicitHeight: panelHeight

    function _consumeLogLine(line) {
        const speaker = /Transcribing (You|Remote) chunk/.exec(line);
        if (speaker) {
            root._pendingSpeaker = speaker[1];
            return;
        }

        const done = /Transcription completed in [0-9.]+s: "(.*)"/.exec(line);
        if (!done || root._status !== "recording") {
            return;
        }

        const text = done[1].replace(/\.\.\.$/, "").trim();
        if (text.length === 0) {
            return;
        }

        const next = root._lines.slice();
        next.push({
            stamp: root._formatElapsed(root._elapsedSecs),
            who: root._pendingSpeaker,
            text: text
        });
        while (next.length > root.maxLines) {
            next.shift();
        }
        root._lines = next;
        Qt.callLater(root._followTail);
    }

    /// Keeps the newest line in view, unless you have scrolled up to read
    /// back — then new text is left alone until you return to the bottom.
    function _followTail() {
        const flick = scroller.contentItem;
        const bottom = Math.max(0, flick.contentHeight - flick.height);
        if (bottom - flick.contentY <= root.followThresholdPx) {
            flick.contentY = bottom;
        }
    }

    function _formatElapsed(secs) {
        const m = String(Math.floor(secs / 60)).padStart(2, "0");
        const s = String(secs % 60).padStart(2, "0");
        return m + ":" + s;
    }

    FileView {
        id: stateFile
        path: root.runtimeDir + "/meeting_state"
        watchChanges: true
        printErrors: false

        onLoaded: {
            const lines = (text() || "").trim().split("\n");
            root._status = (lines[0] || "idle").trim();
            const id = (lines[1] || "").trim();
            if (id !== root._meetingId) {
                root._meetingId = id;
                root._lines = [];
                root._elapsedSecs = 0;
                root._startedAtMs = id.length > 0 ? Date.now() : 0;
            }
        }

        onLoadFailed: {
            root._status = "idle";
            root._meetingId = "";
        }
    }

    // The daemon replaces meeting_state rather than rewriting it, which
    // drops the inotify watch, so poll it as well as watching it.
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: stateFile.reload()
    }

    // `Transcribing <speaker> chunk N` precedes each result line, so the
    // speaker is carried forward to the completion that follows it.
    property string _pendingSpeaker: ""

    Process {
        id: journalProcess
        command: ["journalctl", "--user", "-u", "voxtype", "-f", "-o", "cat",
                  "--since", "now"]
        running: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) { root._consumeLogLine(line); }
        }
    }

    Timer {
        interval: 1000
        running: root.active
        repeat: true
        onTriggered: {
            if (root._startedAtMs > 0) {
                root._elapsedSecs = Math.floor((Date.now() - root._startedAtMs) / 1000);
            }
        }
    }

    // Content height settles a frame after a line is appended, so follow
    // the tail again once the layout has actually grown.
    Connections {
        target: scroller.contentItem
        function onContentHeightChanged() { root._followTail(); }
    }

    Process { id: toggleProcess; command: ["voxtype-meeting-toggle"] }
    Process { id: pauseProcess; command: ["voxtype", "meeting", "pause"] }
    Process { id: resumeProcess; command: ["voxtype", "meeting", "resume"] }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: VT.Theme.bgColor

        Column {
            anchors.fill: parent
            spacing: 0

            Item {
                id: header
                width: parent.width
                height: 44

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 9

                    Rectangle {
                        width: 9
                        height: 9
                        radius: 4.5
                        color: root.statusColor
                        anchors.verticalCenter: parent.verticalCenter

                        SequentialAnimation on opacity {
                            running: root._status === "recording"
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 800 }
                            NumberAnimation { to: 1.0; duration: 800 }
                        }
                    }

                    Text {
                        text: (root._status === "paused" ? "Paused" : "Recording")
                              + " — system audio"
                        font.family: root.uiFont
                        font.pixelSize: 13
                        font.bold: true
                        color: VT.Theme.textColor
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._formatElapsed(root._elapsedSecs)
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    color: root.dimColor
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Qt.rgba(1, 1, 1, 0.07)
            }

            ScrollView {
                id: scroller
                width: parent.width
                height: root.panelHeight - header.height - footer.height - 1
                clip: true

                Column {
                    width: scroller.width
                    padding: 14
                    spacing: 7

                    Text {
                        visible: root._lines.length === 0
                        text: root._status === "paused" ? "Paused"
                              : "Recording. voxtype writes the transcript only when the "
                                + "meeting stops, so no text appears until then."
                        wrapMode: Text.WordWrap
                        width: scroller.width - 28
                        font.family: root.uiFont
                        font.pixelSize: 12
                        color: root.dimColor
                    }

                    Repeater {
                        model: root._lines

                        Row {
                            width: scroller.width - 28
                            spacing: 8

                            Text {
                                text: modelData.stamp
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                color: root.dimColor
                            }

                            Text {
                                visible: text.length > 0
                                text: modelData.who
                                font.family: root.uiFont
                                font.pixelSize: 12
                                color: VT.Theme.streamingColor
                            }

                            Text {
                                width: parent.width - 100
                                text: modelData.text
                                wrapMode: Text.WordWrap
                                font.family: root.uiFont
                                font.pixelSize: 13
                                color: index === root._lines.length - 1
                                       ? VT.Theme.textColor : root.bodyColor
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: footer
                width: parent.width
                height: 48
                color: "transparent"

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    PanelButton {
                        label: "Stop"
                        accent: VT.Theme.recordingColor
                        onClicked: toggleProcess.running = true
                    }

                    PanelButton {
                        label: root._status === "paused" ? "Resume" : "Pause"
                        accent: VT.Theme.textColor
                        onClicked: {
                            if (root._status === "paused") {
                                resumeProcess.running = true;
                            } else {
                                pauseProcess.running = true;
                            }
                        }
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: "ALT+SHIFT+T toggles"
                    font.family: root.uiFont
                    font.pixelSize: 11
                    color: root.dimColor
                }
            }
        }
    }

    component PanelButton: Rectangle {
        id: btn
        property string label: ""
        property color accent: VT.Theme.textColor
        signal clicked()

        width: 76
        height: 28
        radius: height / 2
        color: mouse.pressed ? Qt.rgba(1, 1, 1, 0.14)
             : mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10)
             : Qt.rgba(1, 1, 1, 0.05)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)

        Text {
            anchors.centerIn: parent
            text: btn.label
            font.family: root.uiFont
            font.pixelSize: 12
            color: btn.accent
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: btn.clicked()
        }
    }
}
