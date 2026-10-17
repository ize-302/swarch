pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.I3
import Quickshell.Io
import Quickshell.Wayland
import qs

// Notification centre: the notifications kept by the server
// (Notifications.qml), grouped by app, the app with the newest first. No
// panel: the title and each notification are cards of their own, like new
// notifications (Notifications.qml) and as wide, floating just above the bar
// by the right edge, like the control panel. Toggled by
// ~/.local/bin/notification-center
// (`qs -c launcher ipc call notificationCenter toggleNotificationCenter`),
// Super+Shift+N or a click on the bar's bell (waybar's custom/notifications).
//
// The title has a do not disturb key cap and Clear; while do not disturb is
// on, a row under it says how long for: an hour, until morning, or until
// it's turned off. Up and Down (or j and k) move between notifications,
// Enter runs one's default action, Delete dismisses it, c clears them all,
// d turns do not disturb on or off (h for an hour, m until morning), and
// Escape closes it. Scrolls when
// there are more than fit.
//
// Opened from the bar's bell (`notification-center --pointer`), it's
// centred over the bell, kept on the screen; from the keyboard, it's at the
// right edge (like ControlPanel.qml).
Scope {
    id: root

    property bool open: false
    property int current: 0

    // Centred on the pointer, opened from the bar; where it is (shell.qml),
    // -1 until known. Shown once it's placed, or after a moment at the
    // right edge if the pointer can't be found.
    property bool atPointer: false
    property real pointerX: -1
    property var pointerScreen: null
    property bool placeWaited: false
    readonly property bool placed: !atPointer || pointerX >= 0 || placeWaited
    // The notification server (Notifications.qml)
    property var server: null
    readonly property var notifications: server ? Array.from(server.notifications) : []

    // Apps whose stack is spread out (app -> true); stacks start collapsed
    property var expanded: ({})

    // Grouped by app, the app with the newest first. An app with more than
    // one is a stack: collapsed, its newest card ({ kind: "card",
    // notification, group, stack: how many }); spread out, a header
    // ({ kind: "header", group, count }) over a card for each.
    readonly property var rows: {
        const groups = new Map();
        for (const notification of notifications) {
            const app = notification.appName || "Other";
            groups.set(app, (groups.get(app) ?? []).concat([notification]));
        }
        const rows = [];
        for (const [app, list] of groups) {
            if (list.length > 1 && expanded[app]) {
                rows.push({
                    kind: "header",
                    group: app,
                    count: list.length
                });
                // Under the header on one card, divided, the last one
                // rounding off its bottom
                for (const [index, notification] of list.entries())
                    rows.push({
                        kind: "card",
                        group: app,
                        notification: notification,
                        stack: 1,
                        joined: true,
                        last: index === list.length - 1
                    });
            } else {
                rows.push({
                    kind: "card",
                    group: app,
                    notification: list[0],
                    stack: list.length
                });
            }
        }
        return rows;
    }

    // Spreads a stack out, or collapses it again
    function setExpanded(app, on) {
        const expanded = Object.assign({}, root.expanded);
        if (on)
            expanded[app] = true;
        else
            delete expanded[app];
        root.expanded = expanded;
    }

    // Every notification from an app, for clearing a stack
    function dismissGroup(app) {
        for (const notification of notifications.filter(notification => (notification.appName || "Other") === app))
            notification.dismiss();
        root.setExpanded(app, false);
    }

    // A click or Enter: a collapsed stack spreads out, a header collapses
    // its stack, a card runs its default action
    function activate(row) {
        if (row.kind === "header")
            root.setExpanded(row.group, false);
        else if (row.stack > 1)
            root.setExpanded(row.group, true);
        else
            server.activate(row.notification);
    }

    // The × or Delete: a stack (collapsed, or its header) goes whole
    function dismiss(row) {
        if (row.kind === "header" || row.stack > 1)
            root.dismissGroup(row.group);
        else
            row.notification.dismiss();
    }

    // "3 new", "5 notifications"; nothing when there are none, the list
    // says so
    function countLabel() {
        const unread = Math.min(server?.unread ?? 0, notifications.length);
        if (unread > 0)
            return unread + " new";
        const count = notifications.length;
        return count === 0 ? "" : count === 1 ? "1 notification" : count + " notifications";
    }

    function toggleDoNotDisturb() {
        server.doNotDisturb = !server.doNotDisturb;
    }

    // The selected row stays on screen
    function reveal() {
        const item = repeater.itemAt(current);
        if (!item)
            return;
        if (item.y < flick.contentY)
            flick.contentY = item.y;
        else if (item.y + item.height > flick.contentY + flick.height)
            flick.contentY = item.y + item.height - flick.height;
    }

    onCurrentChanged: Qt.callLater(root.reveal)
    // Dismissing the last row moves up to the new last
    onRowsChanged: current = Math.max(0, Math.min(current, rows.length - 1))

    // Opening it reads them all
    onOpenChanged: {
        if (open && server)
            server.markRead();
        if (!open) {
            atPointer = false;
            placeWaited = false;
            expanded = {};
        }
    }

    // The pointer wasn't found: the right edge, rather than nothing
    Timer {
        running: root.open && !root.placed
        interval: 500
        onTriggered: root.placeWaited = true
    }

    IpcHandler {
        target: "notificationCenter"

        function toggleNotificationCenter(): void {
            root.open = !root.open;
        }

        // The same, over the bar's clock under the pointer
        function toggleNotificationCenterAtPointer(): void {
            if (!root.open)
                root.atPointer = true;
            root.open = !root.open;
        }

        function openNotificationCenter(): void {
            root.open = true;
        }

        function closeNotificationCenter(): void {
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

            root.current = 0;
            flick.contentY = 0;
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
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    const count = root.rows.length;
                    const row = root.rows[Math.min(root.current, count - 1)];

                    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
                        root.open = false;
                    } else if (event.key === Qt.Key_D && root.server) {
                        root.toggleDoNotDisturb();
                    } else if (event.key === Qt.Key_H && root.server) {
                        root.server.setDoNotDisturb("hour");
                    } else if (event.key === Qt.Key_M && root.server) {
                        root.server.setDoNotDisturb("morning");
                    } else if (count === 0) {
                        return;
                    } else if (event.key === Qt.Key_C) {
                        root.server.clear();
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.activate(row);
                    } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_X) {
                        root.dismiss(row);
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || event.key === Qt.Key_J || (ctrl && event.key === Qt.Key_N)) {
                        root.current = (root.current + 1) % count;
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || event.key === Qt.Key_K || (ctrl && event.key === Qt.Key_P)) {
                        root.current = (root.current + count - 1) % count;
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                // The title card: the title and how many there are, then a
                // do not disturb button (blue while it's on, like a switch)
                // and Clear All
                Rectangle {
                    width: parent.width
                    height: titleRows.height + Theme.panelPadding
                    radius: Theme.cornerRadius
                    color: Theme.noteCardColor

                    Column {
                        id: titleRows

                        x: Theme.panelPadding
                        y: Theme.panelPadding / 2
                        width: parent.width - x * 2

                        Item {
                            width: parent.width
                            height: Theme.noteCardButtonHeight + Theme.rowSpacing * 2

                            Text {
                                id: title
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Notifications"
                                color: Theme.textColor
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.searchFontSize
                                font.weight: Font.DemiBold
                            }

                            Text {
                                anchors.left: title.right
                                anchors.leftMargin: Theme.iconSpacing
                                anchors.baseline: title.baseline
                                text: root.countLabel()
                                color: (root.server?.unread ?? 0) > 0 ? Theme.accentColor : Theme.dimColor
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.controlSmallFontSize
                                font.weight: Theme.fontWeight
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.keySpacing * 2

                                Rectangle {
                                    readonly property bool on: root.server?.doNotDisturb ?? false

                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Theme.noteCardButtonHeight
                                    height: width
                                    radius: Theme.cornerRadius
                                    color: on ? Theme.toggleOnColor : doNotDisturbMouse.containsMouse ? Theme.hoverColor : Theme.keyColor

                                    Text {
                                        anchors.centerIn: parent
                                        text: Theme.doNotDisturbIcon
                                        color: parent.on ? "white" : Theme.keyTextColor
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.controlFontSize
                                    }

                                    MouseArea {
                                        id: doNotDisturbMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleDoNotDisturb()
                                    }
                                }

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: root.rows.length > 0
                                    width: clearLabel.implicitWidth + Theme.keyPadding * 2
                                    height: Theme.noteCardButtonHeight
                                    radius: Theme.cornerRadius
                                    color: clearMouse.containsMouse ? Theme.hoverColor : Theme.keyColor

                                    Text {
                                        id: clearLabel
                                        anchors.centerIn: parent
                                        text: "Clear All"
                                        color: Theme.textColor
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.controlSmallFontSize
                                        font.weight: Font.DemiBold
                                    }

                                    MouseArea {
                                        id: clearMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.server.clear()
                                    }
                                }
                            }
                        }

                        // How long do not disturb lasts, while it's on: the choice
                        // lit and bold, and when it ends
                        Item {
                            visible: root.server?.doNotDisturb ?? false
                            width: parent.width
                            height: Theme.rowHeight

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: (root.server?.doNotDisturbEnd() ?? "") ? "Ends " + root.server.doNotDisturbEnd() : "Do not disturb"
                                color: Theme.dimColor
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.controlSmallFontSize
                                font.weight: Theme.fontWeight
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.keySpacing

                                Repeater {
                                    model: [
                                        {
                                            duration: "hour",
                                            text: "1 hour"
                                        },
                                        {
                                            duration: "morning",
                                            text: "Until morning"
                                        },
                                        {
                                            duration: "",
                                            text: "Until off"
                                        }
                                    ]

                                    KeyCap {
                                        id: durationCap

                                        required property var modelData

                                        text: modelData.text
                                        fontSize: Theme.controlSmallFontSize
                                        lit: (root.server?.doNotDisturbFor ?? "") === modelData.duration || durationMouse.containsMouse
                                        bold: (root.server?.doNotDisturbFor ?? "") === modelData.duration
                                        weight: Theme.unselectedWeight
                                        litTextColor: bold ? Theme.selectedColor : Theme.textColor

                                        MouseArea {
                                            id: durationMouse
                                            anchors.fill: parent
                                            anchors.margins: -2
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.server.setDoNotDisturb(durationCap.modelData.duration)
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            visible: root.rows.length === 0
                            height: Theme.rowHeight
                            verticalAlignment: Text.AlignVCenter
                            text: (root.server?.doNotDisturb ?? false) ? Theme.doNotDisturbText : Theme.noNotificationsText
                            color: Theme.dimColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.controlFontSize
                            font.weight: Theme.fontWeight
                        }
                    }
                }

                // The fade at the bottom of the list (the Flickable's mask
                // below): opaque, then clear over the last
                // notificationFadeHeight
                Item {
                    id: fade

                    visible: false
                    layer.enabled: true
                    width: flick.width
                    height: flick.height

                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop {
                                position: 0
                                color: "white"
                            }
                            GradientStop {
                                position: Math.max(0, 1 - Theme.notificationFadeHeight / Math.max(1, fade.height))
                                color: "white"
                            }
                            GradientStop {
                                position: 1
                                color: "transparent"
                            }
                        }
                    }
                }

                // Up to notificationCenterMaxHeight of the screen, then
                // scrolls, fading out at the bottom while there's more below
                Flickable {
                    id: flick

                    readonly property bool moreBelow: contentY + height < contentHeight - 1

                    visible: root.rows.length > 0
                    width: parent.width
                    height: Math.min(list.height, window.screen.height * Theme.notificationCenterMaxHeight)
                    contentHeight: list.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    layer.enabled: moreBelow
                    layer.effect: OpacityMask {
                        maskSource: fade
                    }

                    Column {
                        id: list

                        width: flick.width

                        Repeater {
                            id: repeater

                            model: root.rows

                            Item {
                                id: entry

                                required property var modelData
                                required property int index
                                readonly property bool header: modelData.kind === "header"
                                // Space above each card; none inside a
                                // spread-out stack's
                                readonly property int gap: index > 0 && !modelData.joined ? Theme.notificationSpacing : 0

                                width: list.width
                                height: gap + (header ? groupHeader.height : notificationCard.implicitHeight)

                                // A spread-out stack's app, with Show less
                                // and a × that clears the stack, on a card
                                // like the title's
                                Rectangle {
                                    id: groupHeader

                                    visible: entry.header
                                    y: entry.gap
                                    width: parent.width
                                    height: Theme.noteCardButtonHeight + Theme.rowSpacing * 2 + Theme.panelPadding / 2
                                    // The top of the stack's card
                                    topLeftRadius: Theme.cornerRadius
                                    topRightRadius: Theme.cornerRadius
                                    color: Theme.noteCardColor

                                    Text {
                                        x: Theme.panelPadding
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: entry.modelData.group ?? ""
                                        color: root.current === entry.index ? Theme.selectedColor : Theme.unselectedColor
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.controlFontSize
                                        font.weight: Font.DemiBold
                                    }

                                    Row {
                                        anchors.right: parent.right
                                        anchors.rightMargin: Theme.panelPadding
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.keySpacing * 2

                                        Rectangle {
                                            width: lessLabel.implicitWidth + Theme.keyPadding * 2
                                            height: Theme.noteCardButtonHeight
                                            radius: Theme.cornerRadius
                                            color: lessMouse.containsMouse ? Theme.hoverColor : Theme.keyColor

                                            Text {
                                                id: lessLabel
                                                anchors.centerIn: parent
                                                text: "Show less"
                                                color: Theme.textColor
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.controlSmallFontSize
                                                font.weight: Font.DemiBold
                                            }

                                            MouseArea {
                                                id: lessMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.setExpanded(entry.modelData.group, false)
                                            }
                                        }

                                        Rectangle {
                                            width: Theme.noteCardButtonHeight
                                            height: width
                                            radius: Theme.cornerRadius
                                            color: groupCloseMouse.containsMouse ? Theme.hoverColor : Theme.keyColor

                                            Text {
                                                anchors.centerIn: parent
                                                text: Theme.closeIcon
                                                color: Theme.keyTextColor
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.controlSmallFontSize
                                            }

                                            MouseArea {
                                                id: groupCloseMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.dismissGroup(entry.modelData.group)
                                            }
                                        }
                                    }
                                }

                                NotificationCard {
                                    id: notificationCard

                                    visible: !entry.header
                                    y: entry.gap
                                    width: parent.width
                                    joinedAbove: entry.modelData.joined ?? false
                                    joinedBelow: (entry.modelData.joined ?? false) && !entry.modelData.last
                                    notification: entry.modelData.notification ?? null
                                    server: root.server
                                    stack: entry.modelData.stack ?? 1
                                    selected: root.current === entry.index
                                    onClicked: root.activate(entry.modelData)
                                    onCloseClicked: root.dismiss(entry.modelData)
                                    onHoveredChanged: if (hovered)
                                        root.current = entry.index
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
