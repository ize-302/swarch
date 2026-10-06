pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// Power menu: the same corner panel as the app launcher, just wide enough
// for its labels. Toggled by ~/.local/bin/power-menu
// (`qs -c launcher ipc call power toggle`), which also carries out the choice.
Scope {
    id: root

    property bool open: false
    // Label, also the icon file name and the argument given to power-menu
    readonly property list<string> entries: ["lock", "logout", "sleep", "hibernate", "reboot", "shutdown"]
    property int current: 0

    function iconSource(entry) {
        return Qt.resolvedUrl("icons/" + entry + ".svg");
    }

    function run(entry) {
        open = false;
        Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/power-menu", entry]);
    }

    IpcHandler {
        target: "power"

        function toggle(): void {
            root.open = !root.open;
        }
    }

    // Measures the longest label (the font is monospace)
    TextMetrics {
        id: longest
        text: root.entries.reduce((a, b) => b.length > a.length ? b : a)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.weight: Theme.fontWeight
    }

    PanelWindow { // qmllint disable uncreatable-type
        visible: root.open
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        implicitWidth: panel.width
        implicitHeight: panel.height

        WlrLayershell.namespace: "launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        anchors {
            bottom: true
            left: true
        }

        onVisibleChanged: {
            if (!visible)
                return;

            root.current = 0;
            rows.forceActiveFocus();
            panel.appear();
        }

        Glass {
            id: panel

            // Tighter than the right: the icons carry their own inset
            readonly property int leftPadding: Theme.panelPadding - 4

            // Fitted to the longest label
            width: Math.ceil(longest.advanceWidth) + Theme.iconSize + Theme.iconSpacing + Theme.rowPadding * 2 + leftPadding + Theme.panelPadding
            height: rows.height + Theme.panelPadding * 2

            Column {
                id: rows

                anchors.verticalCenter: parent.verticalCenter
                x: panel.leftPadding
                width: parent.width - panel.leftPadding - Theme.panelPadding
                spacing: Theme.rowSpacing

                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    const count = root.entries.length;

                    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
                        root.open = false;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.run(root.entries[root.current]);
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || (ctrl && event.key === Qt.Key_N)) {
                        root.current = (root.current + 1) % count;
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || (ctrl && event.key === Qt.Key_P)) {
                        root.current = (root.current + count - 1) % count;
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                Repeater {
                    model: root.entries

                    Rectangle {
                        id: row

                        required property string modelData
                        required property int index

                        width: rows.width
                        height: Theme.rowHeight
                        color: root.current === index ? Theme.selectedColor : "transparent"

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            x: Theme.rowPadding
                            spacing: Theme.iconSpacing

                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.iconSize
                                height: Theme.iconSize
                                sourceSize: Qt.size(width, height)
                                source: root.iconSource(row.modelData)
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData
                                color: Theme.textColor
                                font: longest.font
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: root.current = row.index
                            onClicked: root.run(row.modelData)
                        }
                    }
                }
            }
        }
    }
}
