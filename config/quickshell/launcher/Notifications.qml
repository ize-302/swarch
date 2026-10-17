pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.I3
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import Quickshell.Widgets
import qs

// Notification server, in place of dunst: shows each notification as a glass
// card over the bar's right end, where dunst put them, and keeps them for the
// notification centre (NotificationCenter.qml).
//
// Cards stack up from just above the bar, the newest lowest, at most
// maxPopups at once; they float, clear of the bar and the screen edge. They go after the app's timeout (or notificationTimeout), which
// pauses under the mouse; critical ones stay and have a red edge. A click
// runs the notification's default action, a right click or the × dismisses
// it, and its other actions are key caps.
//
// The bar's bell (waybar's custom/notifications) has an orange dot while
// there are new ones and a line through it during do not disturb: this
// writes $XDG_RUNTIME_DIR/notifications.json and signals waybar
// (SIGRTMIN+8) to read it again.
Scope {
    id: root

    // No cards while the notification centre (they're in there) or the
    // control panel, in the same corner, is open
    property bool suppressed: false
    // Do not disturb: no cards, except critical ones
    property bool doNotDisturb: false
    // How long for: "hour", "morning" (until doNotDisturbMorning o'clock),
    // or "" until it's turned off; and when it ends (ms, 0 for never)
    property string doNotDisturbFor: ""
    property real doNotDisturbUntil: 0
    // Cards on screen, newest first
    property list<Notification> popups: []

    // Every notification kept, newest first
    readonly property list<Notification> notifications: server.trackedNotifications.values.slice().reverse()
    // Arrived since the notification centre was last opened
    property int unread: 0
    // When each one arrived (id -> ms), and now, ticking while there are any,
    // for "5m ago"
    property var receivedAt: ({})
    property real now: Date.now()

    // Turns do not disturb on for an hour, until morning, or ("") until
    // it's turned off
    function setDoNotDisturb(duration) {
        const end = new Date();
        if (duration === "hour") {
            end.setTime(end.getTime() + 3600000);
        } else if (duration === "morning") {
            if (end.getHours() >= Theme.doNotDisturbMorning)
                end.setDate(end.getDate() + 1);
            end.setHours(Theme.doNotDisturbMorning, 0, 0, 0);
        }
        doNotDisturb = true;
        doNotDisturbFor = duration;
        doNotDisturbUntil = duration ? end.getTime() : 0;
    }

    // "17:20", "08:00", or "" when it doesn't end
    function doNotDisturbEnd() {
        if (!doNotDisturb || doNotDisturbUntil === 0)
            return "";
        return Qt.formatTime(new Date(doNotDisturbUntil), "HH:mm");
    }

    // The centre's been looked at
    function markRead() {
        unread = 0;
    }

    function clear() {
        popups = [];
        for (const notification of notifications)
            notification.dismiss();
    }

    // "now", "5m", "2h", "3d"
    function age(notification) {
        const seconds = (now - (receivedAt[notification.id] ?? now)) / 1000;
        if (seconds < 60)
            return "now";
        if (seconds < 3600)
            return Math.floor(seconds / 60) + "m";
        if (seconds < 86400)
            return Math.floor(seconds / 3600) + "h";
        return Math.floor(seconds / 86400) + "d";
    }

    function isCritical(notification) {
        return notification.urgency === NotificationUrgency.Critical;
    }

    function received(notification) {
        notification.tracked = true;
        now = Date.now();
        const receivedAt = Object.assign({}, root.receivedAt);
        receivedAt[notification.id] = now;
        root.receivedAt = receivedAt;
        if (!notification.transient)
            unread++;
        root.playSound(notification);

        // Oldest first out of the history
        const kept = server.trackedNotifications.values;
        for (let i = 0; i < kept.length - Theme.maxNotifications; i++)
            kept[i].expire();

        if (doNotDisturb && !root.isCritical(notification)) {
            if (notification.transient)
                notification.expire();
            return;
        }
        popups = [notification].concat(popups.filter(popup => popup !== notification)).slice(0, Theme.maxPopups);
    }

    // The notification sound, as dunst played it: the one the app asks for
    // (sound-file), else message.oga. None when the app asks for silence
    // (suppress-sound), or during do not disturb unless it's critical.
    function playSound(notification) {
        const hints = notification.hints ?? {};
        if (hints["suppress-sound"] || (doNotDisturb && !root.isCritical(notification)))
            return;
        const file = (hints["sound-file"] ?? "").replace(/^file:\/\//, "");
        Quickshell.execDetached(["paplay", file || Theme.notificationSound]);
    }

    // The card goes; the notification stays for the centre, unless it only
    // ever meant to pop up
    function hide(notification) {
        popups = popups.filter(popup => popup !== notification);
        if (notification.transient)
            notification.expire();
    }

    // Its default action, which also closes it, or just the card
    function activate(notification) {
        const action = notification.actions.find(action => action.identifier === "default");
        if (action)
            action.invoke();
        else
            root.hide(notification);
    }

    // How long a card stays, in ms; 0 for until it's closed. Apps give
    // seconds or milliseconds, depending on the version of the spec they
    // read.
    function timeout(notification) {
        const timeout = notification.expireTimeout;
        if (timeout > 0)
            return timeout < 100 ? timeout * 1000 : timeout;
        return root.isCritical(notification) ? 0 : Theme.notificationTimeout;
    }

    // Pictures to try, best first: one sent with the notification (an
    // avatar, a screenshot), the icon it names, its app's desktop entry's,
    // then a plain one. The card moves down the list when one won't load.
    function icons(notification) {
        const icons = [];
        // An icon name passed as the image (notify-send -i) is only kept if
        // the icon theme has it
        const image = notification.image ?? "";
        if (image.startsWith("image://icon/"))
            icons.push(Quickshell.iconPath(image.slice("image://icon/".length), true));
        else if (image)
            icons.push(image);
        const name = notification.appIcon ?? "";
        if (name.startsWith("/") || name.startsWith("file:"))
            icons.push(name);
        else if (name)
            icons.push(Quickshell.iconPath(name, true));
        const entry = DesktopEntries.byId(notification.desktopEntry) ?? DesktopEntries.heuristicLookup(notification.appName);
        if (entry?.icon)
            icons.push(Quickshell.iconPath(entry.icon, true));
        icons.push(Quickshell.iconPath("dialog-information"));
        return icons.filter(icon => icon);
    }

    onSuppressedChanged: if (suppressed)
        popups = []

    // Cards already up go too, except critical ones
    onDoNotDisturbChanged: {
        if (doNotDisturb) {
            popups = popups.filter(popup => root.isCritical(popup));
        } else {
            doNotDisturbFor = "";
            doNotDisturbUntil = 0;
        }
        root.writeStatus();
    }
    onUnreadChanged: root.writeStatus()
    Component.onCompleted: root.writeStatus()

    // { text, class }: the bell, and "unread" or "dnd" for style.css
    function writeStatus() {
        const dot = unread > 0 ? `<span color='${Theme.accentColor}' size='small' rise='6pt'>●</span>` : "";
        status.setText(JSON.stringify({
            text: (doNotDisturb ? Theme.doNotDisturbIcon : unread > 0 ? Theme.bellUnreadIcon : Theme.bellIcon) + dot,
            class: doNotDisturb ? "dnd" : unread > 0 ? "unread" : ""
        }) + "\n");
    }

    // `qs -c launcher ipc call notifications toggleDoNotDisturb`, for keys
    // and scripts
    IpcHandler {
        target: "notifications"

        function toggleDoNotDisturb(): void {
            root.doNotDisturb = !root.doNotDisturb;
        }

        // "hour", "morning", or "" for until it's turned off
        function doNotDisturbFor(duration: string): void {
            root.setDoNotDisturb(duration);
        }

        function clear(): void {
            root.clear();
        }
    }

    FileView {
        id: status

        path: Quickshell.env("XDG_RUNTIME_DIR") + "/notifications.json"
        printErrors: false
        onSaved: Quickshell.execDetached(["pkill", "-RTMIN+8", "-x", "waybar"])
    }

    Timer {
        running: root.notifications.length > 0
        repeat: true
        interval: 30000
        onTriggered: root.now = Date.now()
    }

    // Ends a timed do not disturb. Checks the clock rather than waiting out
    // the time, which a suspend would stretch.
    Timer {
        running: root.doNotDisturbUntil > 0
        repeat: true
        interval: 15000
        onTriggered: if (Date.now() >= root.doNotDisturbUntil)
            root.doNotDisturb = false
    }

    NotificationServer {
        id: server

        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: notification => root.received(notification)
    }

    PanelWindow { // qmllint disable uncreatable-type
        visible: root.popups.length > 0 && !root.suppressed
        // On the screen with the focus
        screen: Quickshell.screens.find(screen => screen.name === I3.focusedMonitor?.name) ?? null
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        implicitWidth: Theme.notificationWidth
        implicitHeight: cards.implicitHeight
        // Clicks between and around the cards go through
        mask: Region {
            item: cards
        }

        WlrLayershell.namespace: "launcher-shadow"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
            bottom: true
            right: true
        }
        margins.bottom: Theme.floatingGap
        margins.right: Theme.floatingGap

        Column {
            id: cards

            width: parent.width
            spacing: Theme.notificationSpacing

            // Oldest at the top, so the newest sits by the bar
            Repeater {
                model: root.popups.slice().reverse()

                Glass {
                    id: card

                    required property Notification modelData
                    required property int index
                    readonly property bool critical: root.isCritical(modelData)
                    readonly property list<NotificationAction> actions: (modelData?.actions ?? []).filter(action => action.identifier !== "default")

                    floating: true
                    width: cards.width
                    height: content.implicitHeight + Theme.panelPadding * 2
                    // No lit edge, except red on a critical one
                    edgeColor: critical ? Theme.closeColor : "transparent"

                    Component.onCompleted: appear()

                    // The app closed it, or it was dismissed
                    Connections {
                        target: card.modelData

                        function onClosed() {
                            root.popups = root.popups.filter(popup => popup !== card.modelData);
                        }
                    }

                    Timer {
                        interval: root.timeout(card.modelData)
                        running: interval > 0 && !hover.hovered
                        onTriggered: root.hide(card.modelData)
                    }

                    HoverHandler {
                        id: hover
                    }

                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        onTapped: root.activate(card.modelData)
                    }

                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: card.modelData.dismiss()
                    }

                    Row {
                        id: content

                        x: Theme.panelPadding
                        y: Theme.panelPadding
                        width: parent.width - x * 2
                        spacing: Theme.iconSpacing

                        IconImage {
                            property int tried: 0
                            readonly property list<string> candidates: root.icons(card.modelData)

                            implicitSize: Theme.notificationIconSize
                            source: candidates[tried] ?? ""
                            onStatusChanged: if (status === Image.Error && tried < candidates.length - 1)
                                tried++
                        }

                        Column {
                            width: parent.width - Theme.notificationIconSize - parent.spacing
                            spacing: Theme.rowSpacing

                            // The app's name, dimmed like a section header,
                            // and the close button under the mouse
                            Item {
                                width: parent.width
                                height: Math.max(app.implicitHeight, close.implicitHeight)

                                Text {
                                    id: app
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - close.width - Theme.iconSpacing
                                    text: (card.modelData.appName || "Notification").toUpperCase()
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: card.critical ? Theme.closeColor : Theme.dimColor
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.sectionFontSize
                                    font.weight: Theme.fontWeight
                                    font.letterSpacing: 1
                                }

                                Text {
                                    id: close
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    opacity: hover.hovered ? 1 : 0
                                    text: Theme.closeIcon
                                    color: closeMouse.containsMouse ? Theme.textColor : Theme.keyTextColor
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.controlFontSize

                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: Theme.animationDuration
                                        }
                                    }

                                    MouseArea {
                                        id: closeMouse
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: card.modelData.dismiss()
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: card.modelData.summary
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                color: Theme.textColor
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.controlFontSize
                                font.weight: Theme.fontWeight
                            }

                            // Apps may send simple markup (bold, italics,
                            // links)
                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: card.modelData.body
                                textFormat: Text.StyledText
                                wrapMode: Text.Wrap
                                maximumLineCount: Theme.notificationBodyLines
                                elide: Text.ElideRight
                                color: Theme.keyTextColor
                                linkColor: Theme.textColor
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.controlSmallFontSize + 1
                                font.weight: Theme.fontWeight
                            }

                            // Its other actions, as key caps
                            Flow {
                                width: parent.width
                                visible: card.actions.length > 0
                                topPadding: Theme.rowSpacing
                                spacing: Theme.keySpacing

                                Repeater {
                                    model: card.actions

                                    KeyCap {
                                        id: actionCap

                                        required property NotificationAction modelData

                                        text: modelData.text
                                        fontSize: Theme.controlSmallFontSize
                                        lit: actionMouse.containsMouse

                                        MouseArea {
                                            id: actionMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: actionCap.modelData.invoke()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
