// Voxtype pill OSD — custom Quickshell entry point.
//
// Replaces the bundled OsdSurface card with a capsule-shaped level
// meter, and adds the live transcript and post-meeting review panels.
// The shared modules stay upstream's.
//
// Run standalone for testing:
//   qs -p ~/.config/voxtype/quickshell-pill

import QtQuick
import Quickshell
import "voxtype-shared" as VT

ShellRoot {
    id: shell

    VT.StateReader {
        id: stateReader
    }

    VT.AudioBridge {
        id: audio
    }

    PillOsd {
        daemonState: stateReader.state
        audio: audio
    }

    TranscriptPanel {}

    ReviewPanel {}
}
