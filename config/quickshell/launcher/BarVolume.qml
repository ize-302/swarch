import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs

// The bar's volume (waybar's custom/volume module): the speaker glyph and
// the output volume, with a music note in place of the speaker while
// something is playing, which waybar's own volume module can't know. This
// writes $XDG_RUNTIME_DIR/volume.json ({ text, class }) and signals waybar
// (SIGRTMIN+10) to read it again.
//
// The class is the level, for style.css's colours: "" below 31%, then
// "mid", "loud" (51%, the louder speaker glyph), "high" (71%) and "over"
// (past 100%); "muted" while muted.
Scope {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property int percent: Math.round((sink?.audio?.volume ?? 0) * 100)
    readonly property bool playing: Mpris.players.values.some(player => player.isPlaying)

    readonly property string level: percent >= 101 ? "over" : percent >= 71 ? "high" : percent >= 51 ? "loud" : percent >= 31 ? "mid" : ""

    readonly property string status: {
        if (!sink)
            return JSON.stringify({
                text: ""
            });
        // Each glyph with the gap after it that looks even: the narrow
        // muted speaker a thin space, the wide loud one a space and a thin
        const icon = playing && !muted ? Theme.musicIcon + " " : muted ? Theme.volumeMutedIcon + " " : percent >= 51 ? Theme.volumeHighIcon + "  " : Theme.volumeLowIcon + " ";
        return JSON.stringify({
            text: icon + percent + "%",
            class: muted ? "muted" : level
        });
    }

    onStatusChanged: file.setText(status + "\n")
    Component.onCompleted: file.setText(status + "\n")

    // Volumes are only there for nodes that are tracked
    PwObjectTracker {
        objects: [root.sink]
    }

    FileView {
        id: file

        path: Quickshell.env("XDG_RUNTIME_DIR") + "/volume.json"
        printErrors: false
        onSaved: Quickshell.execDetached(["pkill", "-RTMIN+10", "-x", "waybar"])
    }
}
