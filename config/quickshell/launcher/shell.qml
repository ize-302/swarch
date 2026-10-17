//@ pragma IconTheme Papirus

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// App launcher: a glass panel in the bottom left corner, on top of the status
// bar. Runs as a daemon (`qs -c launcher -d`) and is toggled by
// ~/.local/bin/app-menu (`qs -c launcher ipc call launcher toggleAppMenu`). The same
// daemon serves the power menu (PowerMenu.qml), the clipboard menu
// (ClipboardMenu.qml), the scratchpad menu (ScratchpadMenu.qml), the key
// bindings menu (KeybindMenu.qml), the control panel (ControlPanel.qml), the
// notification centre (NotificationCenter.qml), the date panel
// (DatePanel.qml), the volume popup (Osd.qml),
// the notifications
// (Notifications.qml), the bluetooth pairing prompts (BluetoothAgent.qml)
// the caps lock popup (CapsLock.qml), the bar's volume (BarVolume.qml) and
// the pomodoro timer (Pomodoro.qml).
ShellRoot {
    id: root

    // Desktop entry id -> times launched. Most used apps are listed first.
    property var history: ({})
    readonly property list<QtObject> menus: [appMenu, powerMenu, clipboardMenu, scratchpadMenu, keybindMenu, controlPanel, notificationCenter, datePanel]
    readonly property bool anyOpen: menus.some(menu => menu.open)
    // Where the pointer was when a menu opened (x on its screen), from the
    // click catcher below, which appears under it, moved to the middle of the
    // bar module there (~/.local/bin/bar-anchor); -1 until it's known.
    // Popups opened from a bar module centre themselves on it.
    property real pointerX: -1
    property var pointerScreen: null
    property bool pointerSeen: false

    // A surface appearing under a still pointer isn't told where it is, so
    // the pointer is nudged a pixel and back once the catcher is up
    onAnyOpenChanged: {
        pointerX = -1;
        pointerSeen = false;
        if (anyOpen)
            nudge.restart();
    }

    // The middle of the module under the pointer; the pointer itself if
    // that fails
    Process {
        id: anchor

        property real screenX: 0
        property real pointer: -1

        stdout: StdioCollector {
            onStreamFinished: {
                const x = parseFloat(text);
                root.pointerX = isNaN(x) ? anchor.pointer : x - anchor.screenX;
            }
        }
    }

    Timer {
        id: nudge
        interval: 30
        onTriggered: Quickshell.execDetached(["sh", "-c", "swaymsg -q -- seat - cursor move 1 0; swaymsg -q -- seat - cursor move -1 0"])
    }

    // The menus share the corner, so only one is open at a time
    function closeOthers(menu) {
        for (const other of menus) {
            if (other !== menu)
                other.open = false;
        }
    }

    // A click outside the open menu closes it: while one is open, a clear
    // layer covers every screen, the bar too, under the menus (which are on
    // the overlay layer). The click only closes; it doesn't reach the
    // window under it.
    Variants {
        model: Quickshell.screens

        PanelWindow { // qmllint disable uncreatable-type
            id: catcherWindow

            required property var modelData

            screen: modelData
            visible: root.anyOpen
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.namespace: "launcher-catcher"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            MouseArea {
                id: catcher

                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                hoverEnabled: true
                onPressed: root.closeOthers(null)

                // The first place the pointer is seen once a menu opens:
                // where it was clicked
                function note(x) {
                    if (root.pointerSeen)
                        return;
                    const screen = catcherWindow.modelData;
                    root.pointerSeen = true;
                    root.pointerScreen = screen;
                    anchor.screenX = screen.x;
                    anchor.pointer = x;
                    anchor.command = [Theme.barAnchor, String(screen.x + x), String(screen.y + screen.height - Theme.barHeight), String(Theme.barHeight)];
                    anchor.running = true;
                }

                onPositionChanged: mouse => note(mouse.x)
            }
        }
    }

    // Every word of the query has to appear somewhere in the entry. Matches
    // on the name win over matches on the description, keywords or command.
    function search(query, apps, history) {
        const words = query.toLowerCase().split(/\s+/).filter(word => word);
        const matches = [];

        for (const app of apps) {
            const name = app.name.toLowerCase();
            const text = [name, app.genericName, app.keywords.join(" "), app.execString].join(" ").toLowerCase();
            if (!words.every(word => text.includes(word)))
                continue;

            let rank = 2;
            if (words.length === 0 || name.startsWith(words[0]))
                rank = 0;
            else if (words.every(word => name.includes(word)))
                rank = 1;

            matches.push({
                app: app,
                rank: rank,
                uses: history[app.id] ?? 0
            });
        }

        matches.sort((a, b) => a.rank - b.rank || b.uses - a.uses || a.app.name.localeCompare(b.app.name));
        return matches.map(match => match.app);
    }

    function launch(app) {
        const updated = Object.assign({}, history);
        updated[app.id] = (updated[app.id] ?? 0) + 1;
        history = updated;
        historyFile.setText(JSON.stringify(updated));

        if (app.runInTerminal)
            Quickshell.execDetached({
                command: Theme.terminal.concat(app.command),
                workingDirectory: app.workingDirectory
            });
        else
            app.execute();
    }

    SearchMenu {
        id: appMenu

        shadow: true
        results: root.search(query, DesktopEntries.applications.values, root.history)
        label: app => app.name
        icon: app => Quickshell.iconPath(app.icon, "application-x-executable")
        emptyText: Theme.emptyText

        onAccepted: app => root.launch(app)
        onOpenChanged: if (open)
            root.closeOthers(appMenu)
    }

    PowerMenu {
        id: powerMenu
        onOpenChanged: if (open)
            root.closeOthers(powerMenu)
    }

    ClipboardMenu {
        id: clipboardMenu
        onOpenChanged: if (open)
            root.closeOthers(clipboardMenu)
    }

    ScratchpadMenu {
        id: scratchpadMenu
        onOpenChanged: if (open)
            root.closeOthers(scratchpadMenu)
    }

    KeybindMenu {
        id: keybindMenu
        onOpenChanged: if (open)
            root.closeOthers(keybindMenu)
    }

    ControlPanel {
        id: controlPanel
        pointerX: root.pointerX
        pointerScreen: root.pointerScreen
        onOpenChanged: if (open)
            root.closeOthers(controlPanel)
    }

    NotificationCenter {
        id: notificationCenter
        pointerX: root.pointerX
        pointerScreen: root.pointerScreen
        server: notifications
        onOpenChanged: if (open)
            root.closeOthers(notificationCenter)
    }

    DatePanel {
        id: datePanel
        pointerX: root.pointerX
        pointerScreen: root.pointerScreen
        pomodoro: pomodoro
        onOpenChanged: if (open)
            root.closeOthers(datePanel)
    }

    Pomodoro {
        id: pomodoro
    }

    BluetoothAgent {}

    CapsLock {}

    BarVolume {}

    Osd {
        suppressed: controlPanel.open
    }

    Notifications {
        id: notifications
        suppressed: controlPanel.open || notificationCenter.open
    }

    IpcHandler {
        target: "launcher"

        function toggleAppMenu(): void {
            appMenu.open = !appMenu.open;
        }

        function openAppMenu(): void {
            appMenu.open = true;
        }

        function closeAppMenu(): void {
            appMenu.open = false;
        }
    }

    FileView {
        id: historyFile
        path: Quickshell.statePath("history.json")
        blockLoading: true
        printErrors: false

        onLoaded: {
            try {
                root.history = JSON.parse(text());
            } catch (error) {
                root.history = {};
            }
        }
    }
}
