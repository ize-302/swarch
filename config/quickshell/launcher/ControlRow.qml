pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import qs

// One row of the control panel (ControlPanel.qml), its section's header over
// the first: what's playing, a slider (a volume), a switch (Wi-Fi,
// bluetooth), a device or
// network on a page, a password being typed, or a network's details and the
// hidden network form. What kind it is, and what it shows, comes from the
// row (`modelData`, one of the panel's `rows`); clicks and keys go to the
// panel.
Column {
    id: entry

    // The panel (ControlPanel.qml): its rows, state and actions
    required property var panel
    required property var modelData
    required property int index

    readonly property string kind: modelData.kind
    readonly property PwNode node: modelData.node ?? null
    // A bluetooth device, or a wired network device
    readonly property var device: modelData.device ?? null
    readonly property WifiNetwork network: modelData.network ?? null
    readonly property bool slider: panel.isSlider(modelData)
    // Wi-Fi and bluetooth on or off, and a network joining by itself
    readonly property bool toggle: kind === "bluetooth" || kind === "wifi" || kind === "autoconnect" || kind === "btTrust"
    // Typed into: a new network's password, the hidden network form
    readonly property bool input: kind === "password" || kind === "joinName" || kind === "joinPassword"
    // Only shows something: a network's details, how joining went
    readonly property bool passive: kind === "info" || kind === "joinStatus"
    // Sliders, switches and the password are full size;
    // lists are a little smaller
    readonly property bool main: !modelData.list || kind === "password"
    readonly property bool muted: node?.audio?.muted ?? false
    readonly property real level: node?.audio?.volume ?? 0
    // Under the mouse or picked with the keys: there's
    // no highlight, the row's text, knob or switch
    // brightens instead
    readonly property bool active: panel.current === index

    // Glyph before a main row; lists are plain text
    readonly property string glyph: {
        if (kind === "volume")
            return node.type === PwNodeType.AudioSink ? Theme.volumeIcon(level, muted) : muted ? Theme.micMutedIcon : Theme.micIcon;
        if (kind === "bluetooth")
            return !panel.bluetoothOn ? Theme.bluetoothOffIcon : panel.bluetoothDevices.some(device => device.connected) ? Theme.bluetoothConnectedIcon : Theme.bluetoothIcon;
        if (kind === "wifi")
            return panel.wifiGlyph();
        return "";
    }
    // One colour for every glyph, like the key caps' text; dim when off or
    // muted. Only a volume boosted past 100% stands out.
    readonly property color glyphColor: {
        if (toggle)
            return on ? Theme.controlIconColor : Theme.controlIconOffColor;
        if (muted)
            return Theme.controlIconOffColor;
        return level > 1.005 ? Theme.closeColor : Theme.controlIconColor;
    }
    // A switch's row says what it's connected to
    readonly property bool on: {
        if (kind === "wifi")
            return Networking.wifiEnabled;
        if (kind === "bluetooth")
            return panel.bluetoothOn;
        if (kind === "autoconnect")
            return panel.details.autoconnect === true;
        if (kind === "btTrust")
            return device.trusted;
        return false;
    }
    readonly property string label: {
        if (kind === "device")
            return panel.deviceName(node);
        if (kind === "bluetooth") {
            const state = panel.adapter.state;
            if (state === BluetoothAdapterState.Enabling)
                return "Turning on…";
            if (state === BluetoothAdapterState.Disabling)
                return "Turning off…";
            if (state === BluetoothAdapterState.Blocked)
                return "Off (blocked)";
            // On its page, the switch just says what it is
            if (modelData.list)
                return "Bluetooth";
            return on ? panel.summary("Bluetooth") || "No devices" : "Off";
        }
        if (kind === "bluetoothDevice")
            return device.name || device.address;
        if (kind === "wifi") {
            if (!Networking.wifiHardwareEnabled)
                return "Off (hardware switch)";
            // On its page, the switch just says what it is
            if (modelData.list)
                return "Wi-Fi";
            return on ? panel.summary("Network") || "Not connected" : "Off";
        }
        if (kind === "network")
            return network.name;
        if (kind === "wired")
            return "Ethernet";
        if (kind === "info")
            return modelData.label;
        if (kind === "connect")
            return network.connected ? "Disconnect" : "Connect";
        if (kind === "autoconnect")
            return "Connect automatically";
        if (kind === "forget")
            return "Forget this network";
        if (kind === "btConnect")
            return device.pairing ? "Cancel pairing" : device.connected ? "Disconnect" : device.paired ? "Connect" : "Pair";
        if (kind === "btTrust")
            return "Connect automatically";
        if (kind === "btForget")
            return "Forget this device";
        if (kind === "profile")
            return modelData.label;
        if (kind === "join")
            return "Join other network…";
        if (kind === "joinStatus")
            return panel.joinBusy ? "Joining " + panel.joinName + "…" : panel.joinError;
        return "";
    }
    // Dimmed text after the label
    readonly property string detail: {
        if (kind === "network") {
            if (network.state === ConnectionState.Connecting)
                return "connecting…";
            if (network.state === ConnectionState.Disconnecting)
                return "disconnecting…";
            const failure = panel.failures[network.name];
            if (failure !== undefined)
                return failure === ConnectionFailReason.NoSecrets || failure === ConnectionFailReason.WifiAuthTimeout ? "wrong password" : "failed";
            return network.known && !network.connected ? "saved" : "";
        }
        if (kind === "wired")
            return device.linkSpeed ? device.linkSpeed + " Mb/s" : "";
        if (kind === "info")
            return modelData.value;
        if (kind === "profile")
            return modelData.codec;
        if (kind !== "bluetoothDevice")
            return "";
        if (device.pairing)
            return "pairing…";
        if (device.state === BluetoothDeviceState.Connecting)
            return "connecting…";
        if (device.state === BluetoothDeviceState.Disconnecting)
            return "disconnecting…";
        if (!device.paired)
            return "new";
        return device.connected && device.batteryAvailable ? Math.round(device.battery * 100) + "%" : "";
    }
    // The device in use, a connected network or
    // bluetooth device; a switch that's on
    readonly property bool checked: {
        if (kind === "device")
            return panel.isDefault(node);
        if (kind === "bluetoothDevice" || kind === "wired")
            return device.connected;
        if (kind === "network")
            return network.connected;
        if (kind === "profile")
            return panel.audio.active === modelData.name;
        return false;
    }
    readonly property bool bright: checked || active || (main && kind !== "bluetooth" && kind !== "wifi") || on

    // Rows sit on the glass like the other menus' rows,
    // under a header per section
    readonly property bool first: index === 0 || panel.rows[index - 1].section !== modelData.section

    width: parent ? parent.width : 0
    spacing: Theme.rowSpacing
    bottomPadding: Theme.rowSpacing

    // On the main view, a line across between one
    // section and the next, with room either side; the
    // headers themselves have none
    Item {
        width: parent.width
        height: Theme.sectionGap
        visible: entry.first && entry.index > 0 && panel.page === ""

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 1
            color: Theme.dividerColor
        }
    }

    SectionHeader {
        width: parent.width
        visible: entry.first
        text: entry.modelData.section
        // Just the name, like the notification centre's app
        // headers
        line: false
        opensPage: panel.page === "" && panel.hasPage(entry.modelData.section)
        // On a page, the header is the title and goes
        // back
        back: panel.page !== ""
        titleSize: Theme.controlFontSize
        // A page's title and its Search cap run to the
        // ends of the divider under them
        inset: back ? 0 : Theme.rowPadding
        // A slider has no label of its own, so the header
        // says which device it's for
        summary: !back && ["Output", "Input", "Now playing"].includes(entry.modelData.section) ? panel.summary(entry.modelData.section) : ""
        // A page opened from the bar closes rather than going back, so
        // its title has no back chevron
        arrow: panel.page !== panel.entryPage
        // The bluetooth page searches from its title
        action: {
            if (back && entry.modelData.section === "Bluetooth" && panel.bluetoothOn)
                return panel.adapter.discovering ? "Searching…" : "Search";
            return "";
        }
        actionActive: entry.modelData.section === "Bluetooth" && (panel.adapter?.discovering ?? false)
        onClicked: back ? panel.closePage() : panel.openPage(entry.modelData.section)
        onActionClicked: panel.toggleSearch()
    }

    Item {
        width: parent.width
        height: entry.kind === "media" ? mediaView.implicitHeight + Theme.rowSpacing * 2 : Theme.rowHeight

        // A faint tint under the row the keys or the mouse are on. A page's
        // rows run flush with its title, so there it reaches into the
        // panel's padding to leave room around the text.
        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: panel.page !== "" ? -Theme.rowPadding : 0
            anchors.rightMargin: panel.page !== "" ? -Theme.rowPadding : 0
            visible: entry.active && !entry.passive
            radius: Theme.cornerRadius
            color: Theme.currentRowColor
        }

        MouseArea {
            id: rowMouse

            anchors.fill: parent
            hoverEnabled: true
            // What's playing has its own buttons
            cursorShape: entry.slider || entry.passive || entry.kind === "media" ? Qt.ArrowCursor : entry.input ? Qt.IBeamCursor : Qt.PointingHandCursor
            onPositionChanged: panel.current = entry.index
            onClicked: {
                if (entry.input)
                    panel.focusRow(entry.index);
                else if (!entry.slider && !entry.passive && entry.kind !== "media")
                    panel.activate(entry.modelData);
            }
        }

        Loader {
            id: mediaView

            x: Theme.rowPadding
            y: Theme.rowSpacing
            width: parent.width - x * 2
            active: entry.kind === "media"

            sourceComponent: MediaRow {
                player: entry.modelData.player
                active: entry.active
            }
        }

        Row {
            id: content

            visible: entry.kind !== "media"
            anchors.verticalCenter: parent.verticalCenter
            // Flush with a page's title and divider, like
            // the title itself
            x: panel.page !== "" ? 0 : Theme.rowPadding
            width: parent.width - x * 2
            spacing: Theme.iconSpacing

            // The glyph, on main rows only. The volume
            // glyph mutes on a click.
            Item {
                id: icon

                anchors.verticalCenter: parent.verticalCenter
                visible: entry.glyph !== ""
                width: Theme.iconSize
                height: Theme.iconSize

                Text {
                    anchors.centerIn: parent
                    text: entry.glyph
                    color: entry.glyphColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.controlFontSize

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        enabled: entry.kind === "volume"
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.toggleMute(entry.modelData)
                    }
                }
            }

            // A volume's slider has no label; its header names the device
            Text {
                id: label

                anchors.verticalCenter: parent.verticalCenter
                visible: !entry.slider && !entry.input
                width: parent.width - (end.visible ? end.width + parent.spacing : 0) - (icon.visible ? icon.width + parent.spacing : 0) - (detail.visible ? detail.width + parent.spacing : 0) - (signal.visible ? signal.width + parent.spacing : 0) - (more.visible ? more.width + parent.spacing : 0)
                text: entry.label
                textFormat: Text.PlainText
                elide: Text.ElideRight
                // The device in use or what's connected is white
                // and bold, its check white too.
                // Forget and a failed join are red; a detail's name dim.
                color: {
                    if (entry.kind === "forget" || entry.kind === "btForget" || (entry.kind === "joinStatus" && entry.modelData.error))
                        return Theme.closeColor;
                    if (entry.passive)
                        return Theme.dimColor;
                    return entry.checked ? Theme.selectedColor : entry.bright ? Theme.textColor : Theme.keyTextColor;
                }
                font.family: Theme.fontFamily
                font.pixelSize: Theme.controlFontSize
                font.weight: entry.checked ? Theme.selectedWeight : Theme.unselectedWeight

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.animationDuration
                    }
                }
            }

            // A new network's password, or the hidden network's name or
            // password, underlined like a field. A password: Enter
            // connects, Escape gives up. The form: Enter (or Tab, or Down)
            // on the name goes to the password, Up back; Enter on the
            // password joins, Escape goes back.
            TextInput {
                id: password

                anchors.verticalCenter: parent.verticalCenter
                visible: entry.input
                width: parent.width
                echoMode: entry.kind === "joinName" ? TextInput.Normal : TextInput.Password
                color: Theme.textColor
                selectionColor: Theme.dividerColor
                selectedTextColor: Theme.textColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.controlFontSize
                font.weight: Theme.fontWeight
                clip: true

                Component.onCompleted: if (entry.kind === "password" || entry.kind === "joinName")
                    forceActiveFocus()

                onTextChanged: {
                    if (entry.kind === "joinName")
                        panel.joinName = text;
                    else if (entry.kind === "joinPassword")
                        panel.joinPassword = text;
                }

                Keys.onPressed: event => {
                    const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
                    if (entry.kind === "password") {
                        if (enter)
                            panel.submitPassword(text);
                        else if (event.key === Qt.Key_Escape)
                            panel.cancelPassword();
                        else
                            return;
                    } else if (event.key === Qt.Key_Escape) {
                        panel.closePage();
                    } else if (entry.kind === "joinName" && (enter || event.key === Qt.Key_Tab || event.key === Qt.Key_Down)) {
                        panel.focusRow(entry.index + 1);
                    } else if (entry.kind === "joinPassword" && enter) {
                        panel.join();
                    } else if (entry.kind === "joinPassword" && (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up)) {
                        panel.focusRow(entry.index - 1);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                Text {
                    visible: password.text.length === 0
                    text: entry.kind === "joinName" ? "Network name" : entry.kind === "joinPassword" ? "Password (none if it's open)" : Theme.passwordPlaceholder
                    color: Theme.dimColor
                    font: password.font
                }

                Rectangle {
                    anchors.top: parent.bottom
                    anchors.topMargin: 3
                    width: parent.width
                    height: 1
                    color: password.activeFocus ? Theme.keyTextColor : Theme.dividerColor
                }
            }

            Slider {
                anchors.verticalCenter: parent.verticalCenter
                visible: entry.slider
                width: parent.width - percent.width - parent.spacing - (icon.visible ? icon.width + parent.spacing : 0) - (label.visible ? label.width + parent.spacing : 0)
                active: entry.active
                value: entry.level
                color: Theme.sliderColor(entry.level, entry.muted)
                onMoved: value => {
                    panel.current = entry.index;
                    panel.setVolume(entry.modelData, value);
                }
            }

            // A key cap, like the key bindings menu's;
            // as wide as "100%" so it doesn't jump
            KeyCap {
                id: percent

                anchors.verticalCenter: parent.verticalCenter
                visible: entry.slider
                minWidth: Math.ceil(percentWidth.advanceWidth) + Theme.keyPadding * 2
                text: entry.muted ? "mute" : Math.round(entry.level * 100) + "%"
                fontSize: Theme.controlSmallFontSize
                lit: entry.active
            }

            Text {
                id: detail

                anchors.verticalCenter: parent.verticalCenter
                visible: text !== ""
                text: entry.detail
                // A detail's value reads like the label elsewhere
                color: entry.kind === "info" ? Theme.textColor : entry.checked ? Theme.selectedColor : Theme.dimColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.controlSmallFontSize
                font.weight: Theme.fontWeight
            }

            // A network's signal bars, dimmed, with a small lock
            // before them when it needs a password
            Row {
                id: signal

                anchors.verticalCenter: parent.verticalCenter
                visible: entry.kind === "network"
                spacing: 3

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: signal.visible && panel.isSecured(entry.network)
                    text: Theme.lockIcon
                    color: entry.checked ? Theme.selectedColor : Theme.dimColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.controlSmallFontSize - 1
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: signal.visible ? panel.networkIcon(entry.network) : ""
                    color: entry.checked ? Theme.selectedColor : Theme.dimColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.controlFontSize
                }
            }

            // Opens the network's or device's details
            Text {
                id: more

                anchors.verticalCenter: parent.verticalCenter
                visible: entry.kind === "network" || entry.kind === "bluetoothDevice"
                text: Theme.pageIcon
                color: moreMouse.containsMouse || entry.active ? Theme.textColor : Theme.dimColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sectionFontSize

                MouseArea {
                    id: moreMouse

                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: entry.kind === "network" ? panel.openDetails(entry.network) : panel.openDevice(entry.device)
                }
            }

            // The switch. What's in use or connected has no
            // check: it's white and semibold.
            Toggle {
                id: end

                anchors.verticalCenter: parent.verticalCenter
                visible: entry.toggle
                checked: entry.on
            }
        }
    }

    // Keys to this row's field, for the join form
    function focusField() {
        password.forceActiveFocus();
    }

    // The widest volume, so the sliders line up
    TextMetrics {
        id: percentWidth
        text: "100%"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.controlSmallFontSize
        font.weight: Theme.fontWeight
    }
}
