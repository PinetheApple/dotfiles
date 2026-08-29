// Post-meeting review panel.
//
// Opened by the meeting toggle script once a recording stops, by way of
// a flag file holding the meeting id. The transcript is already on the
// clipboard at that point, so this decides only what happens on disk:
// saved under a name you choose, or dropped.
//
// This is a FloatingWindow rather than a layer-shell surface so the
// compositor can move it and so the name field can take keyboard focus.

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

    /// Chrome font. Upstream's Theme is monospace-only, and a wall of
    /// monospace transcript is hard to read, so the panel carries its own.
    property string uiFont: "Adwaita Sans"
    property color bodyColor: Qt.rgba(0.78, 0.80, 0.84, 1.0)
    property color dimColor: Qt.rgba(0.42, 0.44, 0.48, 1.0)

    /// Where saved transcripts land. One markdown file per meeting.
    property string saveDir: Quickshell.env("HOME") + "/Recordings/Transcripts"

    property string _meetingId: ""
    property var _lines: []
    property string _status: ""
    property string _duration: ""

    readonly property int _wordCount: {
        let n = 0;
        for (const line of _lines) {
            const body = _body(line).trim();
            if (body.length > 0) {
                n += body.split(/\s+/).length;
            }
        }
        return n;
    }

    visible: _meetingId.length > 0
    implicitWidth: 560
    implicitHeight: 420
    title: "Meeting transcript"
    color: VT.Theme.bgColor

    /// Filesystem-safe stem derived from what the user typed. Anything
    /// outside [a-z0-9-] collapses to a dash so the name can be pasted
    /// straight into a shell command.
    function _slug(name) {
        const cleaned = name.toLowerCase().replace(/[^a-z0-9]+/g, "-")
                            .replace(/^-+|-+$/g, "");
        return cleaned.length > 0 ? cleaned : "meeting";
    }

    function _timestamp() {
        const d = new Date();
        const pad = n => String(n).padStart(2, "0");
        return d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate())
             + "-" + pad(d.getHours()) + pad(d.getMinutes());
    }

    function _stamp(line) {
        const match = /^\[(\d+:\d+)\]/.exec(line);
        return match ? match[1] : "";
    }

    function _body(line) {
        return line.replace(/^\[\d+:\d+\]\s*/, "");
    }

    function _close() {
        root._meetingId = "";
        root._lines = [];
        root._status = "";
        nameField.text = "";
    }

    function save() {
        if (_meetingId.length === 0) {
            return;
        }
        const file = saveDir + "/" + _timestamp() + "-" + _slug(nameField.text) + ".md";
        root._status = "Saving...";
        saveProcess.command = ["bash", "-c",
            "mkdir -p '" + saveDir + "' && "
          + "voxtype meeting export " + _meetingId + " --format markdown --timestamps > '" + file + "' && "
          + "voxtype meeting delete " + _meetingId + " --force"];
        saveProcess.running = true;
    }

    function discard() {
        if (_meetingId.length === 0) {
            return;
        }
        root._status = "Discarding...";
        discardProcess.command = ["voxtype", "meeting", "delete", _meetingId, "--force"];
        discardProcess.running = true;
    }

    // The flag is created and removed around each review, and a FileView
    // whose initial load fails on a missing path never recovers, so the
    // flag is read by polling instead of watched.
    Process {
        id: flagProcess
        command: ["cat", root.runtimeDir + "/review.flag"]

        stdout: StdioCollector {
            onStreamFinished: {
                const id = (text || "").trim();
                if (id.length === 0 || id === root._meetingId) {
                    return;
                }
                root._meetingId = id;
                exportProcess.running = true;
                showProcess.running = true;
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!flagProcess.running) {
                flagProcess.running = true;
            }
        }
    }

    Process {
        id: exportProcess
        command: ["voxtype", "meeting", "export", root._meetingId,
                  "--format", "text", "--timestamps"]

        stdout: StdioCollector {
            onStreamFinished: {
                const body = (text || "").trim();
                root._lines = body.length > 0 ? body.split("\n") : [];
            }
        }
    }

    Process {
        id: showProcess
        command: ["voxtype", "meeting", "show", root._meetingId]

        stdout: StdioCollector {
            onStreamFinished: {
                const body = text || "";
                const match = /Duration:\s*(.+)/.exec(body);
                root._duration = match ? match[1].trim() : "";
                if (/Meeting not found/.test(body)) {
                    root._status = "Meeting no longer exists — nothing to save";
                }
            }
        }
    }

    Process {
        id: saveProcess
        onExited: function(code) {
            if (code === 0) {
                clearFlag.running = true;
                root._close();
            } else {
                root._status = "Save failed - transcript left on disk";
            }
        }
    }

    Process {
        id: discardProcess
        onExited: function(code) {
            if (code === 0) {
                clearFlag.running = true;
                root._close();
            } else {
                root._status = "Delete failed - transcript still on disk";
            }
        }
    }

    Process {
        id: clearFlag
        command: ["rm", "-f", root.runtimeDir + "/review.flag"]
    }

    Rectangle {
        anchors.fill: parent
        color: VT.Theme.bgColor
        radius: 14
        focus: true

        Keys.onEscapePressed: root.discard()

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Item {
                id: headerRow
                width: parent.width
                height: 22

                Text {
                    id: wordCount
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._wordCount + " words"
                    font.family: root.uiFont
                    font.pixelSize: 12
                    color: root.dimColor
                }

                Row {
                    anchors.left: parent.left
                    anchors.right: wordCount.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                Text {
                    text: root._duration.length > 0
                          ? "Meeting transcript · " + root._duration
                          : "Meeting transcript"
                    font.family: root.uiFont
                    font.pixelSize: 15
                    font.bold: true
                    color: VT.Theme.textColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "copied to clipboard"
                    font.family: root.uiFont
                    font.pixelSize: 12
                    color: VT.Theme.streamingColor
                    anchors.verticalCenter: parent.verticalCenter
                }
                }
            }

            ScrollView {
                id: scroller
                width: parent.width
                height: parent.height - headerRow.height - nameField.height
                        - actionRow.height - 3 * parent.spacing
                clip: true

                Column {
                    width: scroller.width
                    spacing: 5

                    Repeater {
                        model: root._lines

                        Row {
                            width: scroller.width - 12
                            spacing: 8

                            Text {
                                text: root._stamp(modelData)
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                color: root.dimColor
                            }

                            Text {
                                width: parent.width - 52
                                text: root._body(modelData)
                                wrapMode: Text.WordWrap
                                font.family: root.uiFont
                                font.pixelSize: 13
                                color: root.bodyColor
                            }
                        }
                    }
                }
            }

            TextField {
                id: nameField
                width: parent.width
                placeholderText: "Name this transcript to save it"
                font.family: root.uiFont
                font.pixelSize: 13
                color: VT.Theme.textColor
                background: Rectangle {
                    radius: 999
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    border.color: nameField.activeFocus ? VT.Theme.accentColor
                                                        : Qt.rgba(1, 1, 1, 0.12)
                }
                onAccepted: root.save()
            }

            Row {
                id: actionRow
                width: parent.width
                spacing: 8

                ReviewButton {
                    label: "Save"
                    accent: VT.Theme.accentColor
                    onClicked: root.save()
                }

                ReviewButton {
                    label: "Discard"
                    accent: VT.Theme.recordingColor
                    onClicked: root.discard()
                }

                Text {
                    text: root._status.length > 0 ? root._status : "Esc discards"
                    font.family: root.uiFont
                    font.pixelSize: 11
                    color: root._status.length > 0 ? VT.Theme.streamingColor
                                                   : VT.Theme.idleColor
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    component ReviewButton: Rectangle {
        id: btn
        property string label: ""
        property string uiFont: root.uiFont
        property color accent: VT.Theme.accentColor
        signal clicked()

        width: 96
        height: 30
        radius: height / 2
        color: mouse.pressed ? Qt.rgba(1, 1, 1, 0.14)
             : mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10)
             : Qt.rgba(1, 1, 1, 0.05)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)

        Text {
            anchors.centerIn: parent
            text: btn.label
            font.family: btn.uiFont
            font.pixelSize: 13
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
