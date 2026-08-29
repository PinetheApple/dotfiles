// Capsule-shaped recording OSD.
//
// A 260x46 pill floating above the bottom edge, showing discrete
// rounded bars driven by the daemon's per-frame mic peaks. The ring
// carries the daemon state so the current mode is readable from colour
// alone; the bars stay neutral so they read as level, not status.
//
// The surface is sized to the pill rather than anchored full-screen,
// and its whole area is subtracted from the input region, so pointer
// events reach the windows underneath.

import QtQuick
import Quickshell
import Quickshell.Wayland
import "voxtype-shared" as VT

PanelWindow {
    id: panel

    /// Current daemon state: idle / recording / streaming / transcribing.
    property string daemonState: "idle"

    /// Shared audio bridge, passed in by the shell root.
    property var audio: null

    property int pillWidth: 260
    property int pillHeight: 46
    property int bottomMargin: 64

    /// Bar geometry, in pixels.
    property int barWidth: 3
    property int barGap: 3

    /// Horizontal padding between the ring and the first/last bar.
    property int sidePadding: 14

    /// Seconds of audio the bars span.
    property real windowSecs: 1.6

    /// Multiplier applied to each peak before it becomes a bar height.
    /// Voice peaks sit around 0.1-0.3 of full scale, so this scales the
    /// envelope up to fill the pill.
    property real gain: 3.2

    readonly property color ringColor:
        daemonState === "recording"    ? VT.Theme.recordingColor
      : daemonState === "streaming"    ? VT.Theme.streamingColor
      : daemonState === "transcribing" ? VT.Theme.transcribingColor
      :                                  VT.Theme.idleColor

    visible: daemonState !== "idle" && daemonState !== ""

    anchors.bottom: true
    implicitWidth: pillWidth
    implicitHeight: pillHeight + bottomMargin
    color: "transparent"

    WlrLayershell.namespace: "voxtype-osd-pill"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    mask: Region {
        intersection: Intersection.Subtract
        x: 0; y: 0
        width: panel.width
        height: panel.height
    }

    /// Number of bars that fit between the side paddings.
    readonly property int barCount:
        Math.floor((pillWidth - 2 * sidePadding + barGap) / (barWidth + barGap))

    /// Newest-on-right ring of per-bar peaks (0.0..1.0).
    property var bars: []

    /// Frames are pushed at ~100 Hz but there are only `barCount` bars
    /// across `windowSecs`, so several frames collapse into one bar.
    /// We keep the loudest peak of the current bucket, which tracks
    /// transients better than averaging.
    property real bucketPeak: 0
    property int bucketCount: 0
    readonly property int framesPerBar:
        Math.max(1, Math.round(windowSecs * 100 / Math.max(1, barCount)))

    function _reset() {
        bars = [];
        bucketPeak = 0;
        bucketCount = 0;
        canvas.requestPaint();
    }

    Connections {
        target: panel.audio
        enabled: panel.audio !== null

        function onFrameReceived(peak, rms, vad, tsMs) {
            panel.bucketPeak = Math.max(panel.bucketPeak, peak);
            panel.bucketCount += 1;
            if (panel.bucketCount < panel.framesPerBar) {
                return;
            }
            const next = panel.bars.slice();
            next.push(panel.bucketPeak);
            while (next.length > panel.barCount) {
                next.shift();
            }
            panel.bars = next;
            panel.bucketPeak = 0;
            panel.bucketCount = 0;
            canvas.requestPaint();
        }

        function onDisconnected() {
            panel._reset();
        }
    }

    onDaemonStateChanged: {
        if (daemonState === "idle" || daemonState === "") {
            _reset();
        }
    }

    Rectangle {
        id: pill
        width: panel.pillWidth
        height: panel.pillHeight
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: panel.bottomMargin

        radius: height / 2
        color: Qt.rgba(0.05, 0.05, 0.06, 0.92)
        border.width: 2
        border.color: panel.ringColor

        // Grow in from slightly small so the pill appears rather than
        // pops. Mirrors the 120 ms the stock OSD uses for its fades.
        scale: panel.visible ? 1.0 : 0.92
        opacity: panel.visible ? 1.0 : 0.0
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 120 } }

        // While transcribing there is no audio to show, so the ring
        // breathes to signal that work is still in flight.
        SequentialAnimation on border.color {
            running: panel.daemonState === "transcribing"
            loops: Animation.Infinite
            ColorAnimation { to: Qt.darker(VT.Theme.transcribingColor, 1.8); duration: 700 }
            ColorAnimation { to: VT.Theme.transcribingColor; duration: 700 }
        }

        Canvas {
            id: canvas
            anchors.fill: parent
            anchors.leftMargin: panel.sidePadding
            anchors.rightMargin: panel.sidePadding
            anchors.topMargin: 10
            anchors.bottomMargin: 10

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);

                const step = panel.barWidth + panel.barGap;
                const cy = height / 2;
                const maxHalf = height / 2;
                const minHalf = panel.barWidth / 2;

                // Right-align the run of bars so new audio enters from
                // the right and the row stays centred once it fills.
                const runWidth = panel.barCount * step - panel.barGap;
                const x0 = (width - runWidth) / 2;

                // Empty slots sit on the left until the ring fills, so
                // the newest bar is always flush against the right.
                const startIdx = panel.barCount - panel.bars.length;

                ctx.fillStyle = VT.Theme.textColor;
                for (let i = 0; i < panel.barCount; i++) {
                    const v = i >= startIdx ? panel.bars[i - startIdx] : 0;
                    const half = Math.max(minHalf, Math.min(maxHalf, v * maxHalf * panel.gain));
                    const x = x0 + i * step;
                    ctx.beginPath();
                    ctx.roundedRect(x, cy - half, panel.barWidth, half * 2, minHalf, minHalf);
                    ctx.fill();
                }
            }
        }
    }
}
