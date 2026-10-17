pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.I3
import Quickshell.Io
import Quickshell.Wayland
import qs

// Date panel: the pomodoro timer (PomodoroCard.qml) over a month calendar
// (Calendar.qml), each a card of its own like the notification centre's,
// as wide, floating just above the bar by the right edge. Toggled by
// ~/.local/bin/date-panel (`qs -c launcher ipc call datePanel toggleDatePanel`)
// or a click on the bar's clock.
//
// Left and Right (or h and l) move the calendar a month, t comes back to
// this month, p starts or pauses the timer, and Escape closes it.
//
// Opened from the bar's clock (`date-panel --pointer`), it's centred over
// the clock, kept on the screen; from the keyboard, it's at the right edge
// (like NotificationCenter.qml).
Scope {
    id: root

    property bool open: false

    // Centred on the pointer, opened from the bar; where it is (shell.qml),
    // -1 until known. Shown once it's placed, or after a moment at the
    // right edge if the pointer can't be found.
    property bool atPointer: false
    property real pointerX: -1
    property var pointerScreen: null
    property bool placeWaited: false
    readonly property bool placed: !atPointer || pointerX >= 0 || placeWaited
    // The pomodoro timer (Pomodoro.qml)
    property var pomodoro: null

    onOpenChanged: {
        if (!open) {
            atPointer = false;
            placeWaited = false;
        }
    }

    // The pointer wasn't found: the right edge, rather than nothing
    Timer {
        running: root.open && !root.placed
        interval: 500
        onTriggered: root.placeWaited = true
    }

    IpcHandler {
        target: "datePanel"

        function toggleDatePanel(): void {
            root.open = !root.open;
        }

        // The same, over the bar's clock under the pointer
        function toggleDatePanelAtPointer(): void {
            if (!root.open)
                root.atPointer = true;
            root.open = !root.open;
        }

        function openDatePanel(): void {
            root.open = true;
        }

        function closeDatePanel(): void {
            root.open = false;
        }
    }

    PanelWindow { // qmllint disable uncreatable-type
        id: window

        visible: root.open && root.placed
        screen: (root.atPointer && root.pointerX >= 0 ? root.pointerScreen : null) ?? Quickshell.screens.find(screen => screen.name === I3.focusedMonitor?.name) ?? null
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        implicitWidth: Theme.notificationWidth
        implicitHeight: panel.height

        // No drop shadow, as there's no panel to cast one: just the blur
        // behind the cards (sway's `layer_effects "launcher"`)
        WlrLayershell.namespace: "launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        anchors {
            bottom: true
            right: true
        }
        margins.bottom: Theme.floatingGap
        // Centred on the pointer, kept on the screen
        margins.right: {
            if (!root.atPointer || root.pointerX < 0 || !screen)
                return Theme.floatingGap;
            const right = screen.width - root.pointerX - implicitWidth / 2;
            return Math.round(Math.max(Theme.floatingGap, Math.min(right, screen.width - implicitWidth - Theme.floatingGap)));
        }

        onVisibleChanged: {
            if (!visible)
                return;

            calendar.reset();
            content.forceActiveFocus();
            panel.appear();
        }

        Glass {
            id: panel

            // Only there to rise into place: the cards are the glass
            floating: true
            color: "transparent"
            edgeColor: "transparent"

            width: parent.width
            height: content.height

            Column {
                id: content

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Theme.notificationSpacing

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
                        root.open = false;
                    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                        calendar.step(-1);
                    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                        calendar.step(1);
                    } else if (event.key === Qt.Key_T) {
                        calendar.reset();
                    } else if (event.key === Qt.Key_P && root.pomodoro) {
                        root.pomodoro.toggle();
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                PomodoroCard {
                    width: parent.width
                    pomodoro: root.pomodoro
                }

                // At the bottom, just above the bar's clock
                Calendar {
                    id: calendar
                    width: parent.width
                }
            }
        }
    }
}
