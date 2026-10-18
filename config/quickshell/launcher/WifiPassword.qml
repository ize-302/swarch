pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Wayland
import qs

// A Wi-Fi network's password, asked in a glass panel in the middle of the
// screen like the bluetooth pairing prompts (BluetoothAgent.qml): a new
// secured network picked on the control panel's Network page, or one whose
// password was wrong or has changed. Enter (or Join) connects, Escape (or
// Cancel) gives up. It stays up while connecting, Join spinning, and says
// why if that didn't work. The control panel (ControlPanel.qml) says which network it's
// for (`passwordFor`) and does the joining.
Scope {
    id: root

    // The control panel: its network, failures and actions
    required property var panel
    readonly property WifiNetwork network: panel.passwordFor
    readonly property bool busy: panel.passwordBusy
    // Red: what went wrong connecting from here, or a saved password
    // turned down
    readonly property string error: {
        if (panel.passwordError)
            return panel.passwordError;
        if (network && panel.failures[network.name] === ConnectionFailReason.WifiAuthTimeout)
            return "That password didn't work. It may have changed; type it again.";
        return "";
    }

    function submit() {
        if (input.text !== "" && !busy)
            panel.submitPassword(input.text);
    }

    PanelWindow { // qmllint disable uncreatable-type
        id: window

        visible: root.network !== null
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        implicitWidth: Theme.pairingWidth
        implicitHeight: glass.height

        // With the drop shadow (`layer_effects "launcher-shadow"` in sway).
        // No edges anchored: the layer shell centres it.
        WlrLayershell.namespace: "launcher-shadow"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        onVisibleChanged: {
            input.text = "";
            if (!visible)
                return;
            input.forceActiveFocus();
            glass.appear();
        }

        Glass {
            id: glass

            floating: true
            width: parent.width
            height: content.implicitHeight + Theme.keybindPadding * 2

            Column {
                id: content

                x: Theme.keybindPadding
                y: Theme.keybindPadding
                width: parent.width - x * 2
                spacing: Theme.keybindPadding / 2

                Row {
                    spacing: Theme.iconSpacing

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.network ? root.panel.networkIcon(root.network) : ""
                        color: Theme.textColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.searchFontSize + 4
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: content.width - Theme.searchFontSize * 2
                        text: "Join " + (root.network?.name ?? "")
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.textColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.searchFontSize
                        font.weight: Font.Bold
                    }
                }

                Text {
                    width: parent.width
                    text: root.error || "This network needs a password."
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: root.error ? Theme.closeColor : Theme.keyTextColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.controlFontSize
                    font.weight: Theme.fontWeight
                }

                // Underlined like the pairing prompt's PIN
                TextInput {
                    id: input

                    width: parent.width
                    echoMode: TextInput.Password
                    readOnly: root.busy
                    color: Theme.textColor
                    selectionColor: Theme.dividerColor
                    selectedTextColor: Theme.textColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.searchFontSize
                    font.weight: Theme.fontWeight
                    clip: true

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            root.submit();
                        else if (event.key === Qt.Key_Escape)
                            root.panel.cancelPassword();
                        else
                            return;
                        event.accepted = true;
                    }

                    Text {
                        visible: input.text.length === 0
                        text: Theme.passwordPlaceholder
                        color: Theme.dimColor
                        font: input.font
                    }

                    Rectangle {
                        anchors.top: parent.bottom
                        anchors.topMargin: 3
                        width: parent.width
                        height: 1
                        color: input.activeFocus ? Theme.keyTextColor : Theme.dividerColor
                    }
                }

                // Cancel, then Join in blue like a switch that's on
                Row {
                    anchors.right: parent.right
                    topPadding: Theme.rowSpacing
                    spacing: Theme.keySpacing * 2

                    KeyCap {
                        opacity: root.busy ? 0.5 : 1
                        text: "Cancel"
                        fontSize: Theme.controlFontSize
                        height: Theme.pairingButtonHeight
                        minWidth: Theme.pairingButtonWidth
                        lit: cancelMouse.containsMouse

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.panel.cancelPassword()
                        }
                    }

                    Rectangle {
                        width: Math.max(Theme.pairingButtonWidth, join.implicitWidth + Theme.keyPadding * 2)
                        height: Theme.pairingButtonHeight
                        radius: Theme.cornerRadius
                        color: Theme.toggleOnColor
                        opacity: input.text === "" || root.busy ? 0.5 : joinMouse.containsMouse ? 0.85 : 1

                        Text {
                            id: join
                            anchors.centerIn: parent
                            text: "Join"
                            opacity: root.busy ? 0 : 1
                            color: "white"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.controlFontSize
                            font.weight: Font.DemiBold
                        }

                        // Connecting
                        Spinner {
                            anchors.centerIn: parent
                            visible: root.busy
                            width: Theme.controlFontSize
                            height: Theme.controlFontSize
                            color: "white"
                        }

                        MouseArea {
                            id: joinMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.submit()
                        }
                    }
                }
            }
        }
    }
}
