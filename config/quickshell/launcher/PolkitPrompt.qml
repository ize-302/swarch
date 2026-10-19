pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Polkit
import Quickshell.Wayland
import qs

// The session's polkit agent: when an app needs an administrator (mounting a
// disk, a system setting), the password is asked in a glass panel in the
// middle of the screen like the Wi-Fi password (WifiPassword.qml). Enter (or
// Authenticate) answers, Escape (or Cancel) refuses. It stays up while polkit
// checks, Authenticate spinning, and asks again after a wrong password.
//
// Without an agent, those apps are refused instead of asking: one only runs
// while this shell does.
Scope {
    id: root

    readonly property AuthFlow flow: agent.flow
    // Waiting on polkit: after a password, until it asks again or finishes
    readonly property bool busy: flow !== null && !flow.isResponseRequired
    readonly property string error: {
        if (!flow)
            return "";
        if (flow.supplementaryIsError && flow.supplementaryMessage)
            return flow.supplementaryMessage;
        return flow.failed ? "That password didn't work." : "";
    }

    function submit() {
        if (flow && flow.isResponseRequired)
            flow.submit(input.text);
    }

    function cancel() {
        flow?.cancelAuthenticationRequest();
    }

    // The next identity, when there's more than one to authenticate as
    function nextIdentity() {
        const identities = flow?.identities ?? [];
        if (identities.length < 2)
            return;
        const at = identities.indexOf(flow.selectedIdentity);
        flow.selectedIdentity = identities[(at + 1) % identities.length];
    }

    PolkitAgent {
        id: agent
    }

    // A new prompt (or the same one again, after a wrong password) starts
    // empty
    Connections {
        target: root.flow

        function onIsResponseRequiredChanged() {
            if (root.flow.isResponseRequired) {
                input.text = "";
                input.forceActiveFocus();
            }
        }
    }

    PanelWindow { // qmllint disable uncreatable-type
        id: window

        visible: agent.isActive && root.flow !== null
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
                        text: Theme.lockIcon
                        color: Theme.textColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.searchFontSize + 4
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: content.width - Theme.searchFontSize * 2
                        text: "Authentication required"
                        elide: Text.ElideRight
                        color: Theme.textColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.searchFontSize
                        font.weight: Font.Bold
                    }
                }

                // What the app wants to do, in polkit's words
                Text {
                    width: parent.width
                    text: root.flow?.message ?? ""
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Theme.keyTextColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.controlFontSize
                    font.weight: Theme.fontWeight
                }

                // Who it's asking for: the next one on a click, when there's a
                // choice (several users in the wheel group)
                Text {
                    readonly property var identities: root.flow?.identities ?? []

                    visible: identities.length > 0
                    width: parent.width
                    text: "As " + (root.flow?.selectedIdentity?.displayName ?? "") + (identities.length > 1 ? "  ›" : "")
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Theme.dimColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.controlFontSize
                    font.weight: Theme.fontWeight

                    MouseArea {
                        anchors.fill: parent
                        enabled: parent.identities.length > 1 && !root.busy
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.nextIdentity()
                    }
                }

                // Underlined like the Wi-Fi password
                TextInput {
                    id: input

                    width: parent.width
                    echoMode: root.flow?.responseVisible ? TextInput.Normal : TextInput.Password
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
                            root.cancel();
                        else
                            return;
                        event.accepted = true;
                    }

                    // polkit's own prompt ("Password: "), else ours
                    Text {
                        visible: input.text.length === 0
                        text: (root.flow?.inputPrompt ?? "").replace(/:\s*$/, "") || Theme.passwordPlaceholder
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

                // Red: a wrong password; otherwise what polkit says, if anything
                Text {
                    visible: text !== ""
                    width: parent.width
                    text: root.error || (root.flow?.supplementaryMessage ?? "")
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: root.error ? Theme.closeColor : Theme.keyTextColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.controlFontSize
                    font.weight: Theme.fontWeight
                }

                // Cancel, then Authenticate in blue like a switch that's on
                Row {
                    anchors.right: parent.right
                    topPadding: Theme.rowSpacing
                    spacing: Theme.keySpacing * 2

                    KeyCap {
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
                            onClicked: root.cancel()
                        }
                    }

                    Rectangle {
                        width: Math.max(Theme.pairingButtonWidth, authenticate.implicitWidth + Theme.keyPadding * 2)
                        height: Theme.pairingButtonHeight
                        radius: Theme.cornerRadius
                        color: Theme.toggleOnColor
                        opacity: root.busy ? 0.5 : authenticateMouse.containsMouse ? 0.85 : 1

                        Text {
                            id: authenticate
                            anchors.centerIn: parent
                            text: "Authenticate"
                            opacity: root.busy ? 0 : 1
                            color: "white"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.controlFontSize
                            font.weight: Font.DemiBold
                        }

                        // Checking
                        Spinner {
                            anchors.centerIn: parent
                            visible: root.busy
                            width: Theme.controlFontSize
                            height: Theme.controlFontSize
                            color: "white"
                        }

                        MouseArea {
                            id: authenticateMouse
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
