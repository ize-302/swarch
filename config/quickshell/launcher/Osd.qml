import QtQuick
import Quickshell
import Quickshell.I3
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs

// Volume popup: a small upright glass gauge halfway down the right edge of
// the screen, in the caps lock popup's glass, the percentage over the
// control panel's slider stood up over its glyph, shown for a moment on the
// screen with the focus whenever the output volume changes or the output or
// microphone is muted (from the volume keys, the bar or any app). Clicks go
// through it.
Scope {
    id: root

    // Not while the control panel is open: it shows the same thing
    property bool suppressed: false
    property bool shown: false
    // "output", or "input" (the microphone)
    property string mode: "output"
    // Volumes report in once when the daemon starts; that isn't a change
    property bool armed: false

    readonly property var focusedScreen: Quickshell.screens.find(screen => screen.name === I3.focusedMonitor?.name) ?? null
    readonly property PwNode node: mode === "input" ? Pipewire.defaultAudioSource : Pipewire.defaultAudioSink
    readonly property bool muted: node?.audio?.muted ?? false
    readonly property real level: node?.audio?.volume ?? 0

    function show(mode) {
        if (!armed || suppressed)
            return;

        root.mode = mode;
        if (!shown) {
            shown = true;
            panel.appear();
        }
        hide.restart();
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    Connections {
        target: Pipewire.defaultAudioSink?.audio ?? null

        function onVolumesChanged() {
            root.show("output");
        }

        function onMutedChanged() {
            root.show("output");
        }
    }

    // The microphone's own volume is left out: apps turn it up and down
    // by themselves
    Connections {
        target: Pipewire.defaultAudioSource?.audio ?? null

        function onMutedChanged() {
            root.show("input");
        }
    }

    Timer {
        running: Pipewire.ready
        interval: 1000
        onTriggered: root.armed = true
    }

    Timer {
        id: hide
        interval: Theme.osdTimeout
        onTriggered: root.shown = false
    }

    onSuppressedChanged: if (suppressed)
        shown = false

    PanelWindow { // qmllint disable uncreatable-type
        visible: root.shown
        screen: root.focusedScreen
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        implicitWidth: panel.width
        implicitHeight: panel.height
        // Clicks go through to whatever is underneath
        mask: Region {}

        // Only the right edge anchored: the layer shell centres it down the
        // screen
        anchors.right: true
        margins.right: Theme.floatingGap

        // Blurred behind (`layer_effects "launcher"`), but no drop shadow,
        // like the caps lock popup
        WlrLayershell.namespace: "launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Glass {
            id: panel

            floating: true
            fromRight: true
            width: Theme.osdWidth
            height: Theme.osdHeight
            // The caps lock popup's fainter glass
            color: Theme.popupColor
            edgeColor: Theme.popupEdgeColor

            Column {
                anchors.centerIn: parent
                spacing: Theme.iconSpacing

                // Plain, like the caps lock popup's ON: a key cap is too wide
                Text {
                    id: percent

                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.muted ? "mute" : Math.round(root.level * 100) + "%"
                    color: Theme.keyTextColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.osdFontSize
                    font.weight: Theme.fontWeight
                }

                // The control panel's slider, stood up: filled from the
                // bottom
                Rectangle {
                    id: track

                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Theme.sliderHeight
                    height: panel.height - Theme.panelPadding * 2 - percent.height - icon.height - parent.spacing * 2
                    radius: width / 2
                    color: Theme.sliderTrackColor

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Math.max(track.width, track.height * Math.max(0, Math.min(root.level, 1)))
                        radius: parent.radius
                        color: Theme.sliderColor(root.level, root.muted)
                        visible: root.level > 0

                        Behavior on height {
                            NumberAnimation {
                                duration: Theme.animationDuration
                            }
                        }
                    }
                }

                // The control panel's glyphs: the bar's speaker, or the
                // microphone
                Text {
                    id: icon

                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Theme.iconSize
                    horizontalAlignment: Text.AlignHCenter
                    text: root.mode === "input" ? (root.muted ? Theme.micMutedIcon : Theme.micIcon) : Theme.volumeIcon(root.level, root.muted)
                    color: Theme.volumeColor(root.level, root.muted)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.controlFontSize
                }
            }
        }
    }
}
