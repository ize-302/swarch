pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.I3
import Quickshell.Io
import Quickshell.Wayland
import qs

// Caps lock popup, like macOS's: a rounded glass square centred across the
// bottom of the screen with the focus, just above the bar, a caps lock icon and
// "ON" (or dimmed, "OFF"). It stays up while caps lock is on, and shows OFF
// for a moment once it's switched off. Clicks go through it.
//
// The state is the keyboards' caps lock lights
// (/sys/class/leds/*::capslock), which sway keeps the same on every
// keyboard. They're read a few times a second; sysfs doesn't say when they
// change.
Scope {
    id: root

    property bool on: false
    property bool shown: false
    // The first reading is what it already was, not a change: it only shows
    // the popup if caps lock is already on
    property bool armed: false

    readonly property var focusedScreen: Quickshell.screens.find(screen => screen.name === I3.focusedMonitor?.name) ?? null

    function update(lit) {
        if (lit === on && armed)
            return;
        on = lit;
        const first = !armed;
        armed = true;
        if (first && !lit)
            return;
        if (!shown) {
            shown = true;
            panel.appear();
        }
        // Up until it's off; OFF only for a moment
        if (lit)
            hide.stop();
        else
            hide.restart();
    }

    // Reads the lights in a loop and prints 1 or 0 when caps lock changes
    // (and once to start). Every keyboard's, found again each time, so
    // keyboards plugged in later count. One process; a file reader
    // re-reading sysfs kept its old value.
    Process {
        id: watcher

        command: ["python3", "-c", `
import glob, time
last = None
while True:
    lit = False
    for path in glob.glob("/sys/class/leds/*::capslock/brightness"):
        try:
            with open(path) as file:
                lit = lit or file.read().strip() not in ("", "0")
        except OSError:
            pass
    if lit != last:
        print(int(lit), flush=True)
        last = lit
    time.sleep(${Theme.capsLockPoll / 1000})
`]
        running: true

        stdout: SplitParser {
            onRead: line => root.update(line.trim() === "1")
        }

        // Gone: again in a moment, without spinning if it keeps failing
        onExited: restart.start()
    }

    Timer {
        id: restart
        interval: 5000
        onTriggered: watcher.running = true
    }

    Timer {
        id: hide
        interval: Theme.capsLockTimeout
        onTriggered: root.shown = false
    }

    PanelWindow { // qmllint disable uncreatable-type
        visible: root.shown
        screen: root.focusedScreen
        color: "transparent"
        // Above the bar, not over it
        exclusionMode: ExclusionMode.Normal
        implicitWidth: panel.width
        implicitHeight: panel.height
        // Clicks go through to whatever is underneath
        mask: Region {}

        // Only the bottom anchored: the layer shell centres it across
        anchors.bottom: true
        margins.bottom: Theme.centredGap

        // Blurred behind (`layer_effects "launcher"`), but no drop shadow:
        // it's meant to be subtle.
        WlrLayershell.namespace: "launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Glass {
            id: panel

            floating: true
            width: Theme.capsLockSize
            height: Theme.capsLockSize
            // More see-through than the menus, plain, with a faint edge
            color: Theme.popupColor
            edgeColor: Theme.popupEdgeColor

            Column {
                anchors.centerIn: parent
                spacing: Theme.rowSpacing

                // Material Symbols' caps lock badge, drawn white and tinted
                // like the text under it
                Image {
                    id: icon
                    visible: false
                    width: Theme.capsLockIconSize
                    height: Theme.capsLockIconSize
                    sourceSize: Qt.size(width, height)
                    source: Qt.resolvedUrl("icons/capslock.svg")
                }

                MultiEffect {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: icon.width
                    height: icon.height
                    source: icon
                    colorization: 1
                    colorizationColor: root.on ? Theme.keyTextColor : Theme.dimColor
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.on ? "ON" : "OFF"
                    color: root.on ? Theme.keyTextColor : Theme.dimColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.capsLockFontSize
                    font.weight: Theme.fontWeight
                }
            }
        }
    }
}
