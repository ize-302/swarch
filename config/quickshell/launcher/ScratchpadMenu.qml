import QtQuick
import Quickshell
import Quickshell.I3
import Quickshell.Io
import Quickshell.Widgets
import qs

// Windows parked in sway's scratchpad, as a full width strip of preview cards
// sitting on the bar. Each preview is grabbed with `grim -T` once, as soon as
// the window is parked: sway stops redrawing hidden windows, so that frame
// stays accurate until the window comes back out. The list follows sway's
// window events, so opening the strip shows it straight away.
//
// Opened by double tapping Super (sway's `nop scratchpad-tap` release
// binding, heard here over sway IPC, no process spawned), or by
// ~/.local/bin/scratchpad-menu (`qs -c launcher ipc call scratchpad
// toggleScratchpadMenu`) from waybar. Enter takes the window out of the
// scratchpad onto a new empty workspace and follows it there; Delete, or the
// × on a hovered card, closes it.
Scope {
    id: root

    property alias open: menu.open
    // One per scratchpad container: { id, appId, title, toplevel, width }
    property var entries: []
    // Workspace numbers in use, and whether the focused one is empty
    property var workspaces: ({ used: [], focusedEmpty: false, focused: 0 })
    // Container id -> preview image URL, kept while the window stays parked
    property var previews: ({})
    // Ids already grabbed (or tried), so a window that can't be grabbed
    // isn't retried until it leaves the scratchpad
    property var tried: ({})
    // A window event came in while the tree was being read
    property bool stale: false
    // Time of the last lone Super tap, for the double tap
    property real lastTap: 0
    // Where the previews go, one PNG per container id
    readonly property string previewDir: Quickshell.env("XDG_RUNTIME_DIR") + "/scratchpad-previews"

    // Windows inside a container. Usually the container itself, but a whole
    // split can be sent to the scratchpad too.
    function windows(node) {
        if (node.nodes.length === 0)
            return [node];

        return node.nodes.reduce((found, child) => found.concat(root.windows(child)), []);
    }

    // Hidden scratchpad windows float on the "__i3_scratch" workspace
    function parse(tree) {
        const output = tree.nodes.find(output => output.name === "__i3");
        const workspace = output?.nodes.find(workspace => workspace.name === "__i3_scratch");

        return (workspace?.floating_nodes ?? []).map(node => {
            const windows = root.windows(node);
            return {
                id: node.id,
                // XWayland windows have a class instead of an app id
                appId: windows[0].app_id ?? windows[0].window_properties?.class ?? "",
                title: windows.map(window => window.name ?? "").join(" · "),
                // A split sent to the scratchpad is previewed by its first window
                toplevel: windows[0].foreign_toplevel_identifier ?? "",
                width: windows[0].rect.width
            };
        });
    }

    // Which workspaces exist, from the same tree
    function workspaceState(tree) {
        const contains = node => node.focused || node.nodes.some(contains) || node.floating_nodes.some(contains);
        const state = { used: [], focusedEmpty: false, focused: 0 };
        for (const output of tree.nodes) {
            if (output.name === "__i3")
                continue;
            for (const workspace of output.nodes) {
                state.used.push(workspace.num);
                if (contains(workspace)) {
                    state.focused = workspace.num;
                    state.focusedEmpty = workspace.nodes.length + workspace.floating_nodes.length === 0;
                }
            }
        }
        return state;
    }

    // An empty workspace for a window brought out: the focused one when it's
    // empty, else the lowest number not in use
    function emptyWorkspace() {
        if (root.workspaces.focusedEmpty)
            return root.workspaces.focused;

        let number = 1;
        while (root.workspaces.used.includes(number))
            number++;
        return number;
    }

    // New entry list from sway: forget the previews of windows that left the
    // scratchpad (one parked again later gets a fresh grab), then grab the
    // ones still missing
    function update(entries) {
        const ids = entries.map(entry => String(entry.id));
        const previews = {};
        const tried = {};
        for (const id of Object.keys(root.tried)) {
            if (!ids.includes(id)) {
                Quickshell.execDetached(["rm", "-f", root.previewDir + "/" + id + ".png"]);
                continue;
            }
            tried[id] = true;
            if (id in root.previews)
                previews[id] = root.previews[id];
        }
        root.previews = previews;
        root.tried = tried;
        // A new list resets the selection; keep it in place (on the next card
        // when the selected one was closed)
        const selected = menu.view.currentIndex;
        root.entries = entries;
        menu.view.currentIndex = Math.max(0, Math.min(selected, entries.length - 1));

        if (grabber.running)
            return;
        const missing = entries.filter(entry => entry.toplevel && !(String(entry.id) in tried));
        for (const entry of missing)
            tried[String(entry.id)] = true;
        root.capture(missing);
    }

    // Grab the given previews at once: id, toplevel and scale for each window.
    // Scaled so the image is about twice as wide as a card, sharp on HiDPI.
    function capture(entries) {
        const args = [];
        for (const entry of entries)
            args.push(String(entry.id), entry.toplevel, String(Math.min(1, menu.cardWidth * 2 / entry.width).toFixed(3)));
        if (args.length === 0)
            return;

        grabber.command = ["sh", "-c", `
            dir=$1; shift
            mkdir -p "$dir"
            while [ $# -gt 0 ]; do
                (grim -T "$2" -s "$3" "$dir/$1.png" && echo "$1") &
                shift 3
            done
            wait`, "sh", root.previewDir].concat(args);
        grabber.running = true;
    }

    // Re-read the tree; if it's being read already, once more after that
    function refresh() {
        if (lister.running)
            root.stale = true;
        else
            lister.running = true;
    }

    // Close a parked window without bringing it out. Its card goes when
    // sway's window event comes in.
    function close(entry) {
        Quickshell.execDetached(["swaymsg", `[con_id=${entry.id}] kill`]);
    }

    // Workspace for a number row key: 1…9, 0 for 10, else 0. Read from the
    // physical key (xkb keycodes 10…19), since with Shift held the key is "!"
    // and so on, whatever the layout.
    function workspaceKey(event) {
        const code = event.nativeScanCode;
        return code >= 10 && code <= 19 ? code - 9 : 0;
    }

    // Cheap (one get_tree), in case an event was missed
    Component.onCompleted: refresh()
    onOpenChanged: if (open)
        refresh()

    // Lone Super taps (`bindsym --release Super_L nop scratchpad-tap`): the
    // second within doubleTapInterval toggles the strip. Window and workspace
    // events keep the list, previews and free workspaces current while the
    // strip is closed.
    I3IpcListener {
        subscriptions: ["binding", "window", "workspace"]

        onIpcEvent: event => {
            if (event.type !== "binding") {
                refreshTimer.restart();
                return;
            }

            if (JSON.parse(event.data).binding?.command !== "nop scratchpad-tap")
                return;

            const now = Date.now();
            if (now - root.lastTap <= Theme.doubleTapInterval) {
                root.lastTap = 0;
                root.open = !root.open;
            } else {
                root.lastTap = now;
            }
        }
    }

    // Window events come in bursts (a move is several)
    Timer {
        id: refreshTimer
        interval: 50
        onTriggered: root.refresh()
    }

    IpcHandler {
        target: "scratchpad"

        function toggleScratchpadMenu(): void {
            root.open = !root.open;
        }
    }

    Process {
        id: lister
        command: ["swaymsg", "-t", "get_tree"]

        onExited: if (root.stale) {
            root.stale = false;
            lister.running = true;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const tree = JSON.parse(text);
                    root.workspaces = root.workspaceState(tree);
                    root.update(root.parse(tree));
                } catch (error) {
                    root.update([]);
                }
            }
        }
    }

    // Prints each container id whose preview is ready. Windows parked while
    // it ran are picked up by a refresh when it's done.
    Process {
        id: grabber

        onExited: root.refresh()

        stdout: SplitParser {
            onRead: id => {
                // A new URL each time, so the Image doesn't show a stale grab
                const previews = Object.assign({}, root.previews);
                previews[id] = "file://" + root.previewDir + "/" + id + ".png?" + Date.now();
                root.previews = previews;
            }
        }
    }

    SearchMenu {
        id: menu

        shadow: true
        // The cards keep cardSpacing around them too
        panelPadding: Theme.cardSpacing
        card: windowCard
        searchable: false
        results: root.entries
        label: entry => entry.title
        icon: entry => Quickshell.iconPath(DesktopEntries.heuristicLookup(entry.appId)?.icon ?? entry.appId, "application-x-executable")
        emptyText: Theme.scratchpadEmptyText

        // Showing it puts it on the current workspace and tiling it takes it
        // out of the scratchpad; then it moves to an empty workspace, and
        // focus follows.
        onAccepted: entry => {
            const workspace = root.emptyWorkspace();
            Quickshell.execDetached(["swaymsg", `[con_id=${entry.id}] scratchpad show, floating disable, move container to workspace number ${workspace}, workspace number ${workspace}`]);
        }

        // Delete closes the selected window and keeps the strip open.
        // Alt+1…9, Alt+0: send the window to that workspace instead and stay
        // here, like Super+Shift+number. Alt+Shift+number follows it there.
        keyHandler: (event, entry) => {
            if (event.key === Qt.Key_Delete) {
                root.close(entry);
                return true;
            }

            const workspace = root.workspaceKey(event);
            if (!(event.modifiers & Qt.AltModifier) || workspace === 0)
                return false;

            const follow = event.modifiers & Qt.ShiftModifier ? `, workspace number ${workspace}` : "";
            menu.open = false;
            Quickshell.execDetached(["swaymsg", `[con_id=${entry.id}] scratchpad show, floating disable, move container to workspace number ${workspace}${follow}`]);
            return true;
        }
    }

    // A window's card: its preview, then its icon and title. Tinted like the
    // key caps, lit like the panel edge when selected.
    Component {
        id: windowCard

        Item {
            id: cell

            required property var modelData
            required property int index
            readonly property bool selected: ListView.isCurrentItem
            readonly property bool closing: closeMouse.containsMouse
            readonly property string iconSource: Quickshell.iconPath(DesktopEntries.heuristicLookup(modelData.appId)?.icon ?? modelData.appId, "application-x-executable")

            width: menu.cardWidth
            height: ListView.view.height

            Rectangle {
                id: card

                anchors.fill: parent
                anchors.margins: Theme.cardSpacing
                radius: Theme.cornerRadius
                color: cell.selected ? Theme.hoverColor : Theme.keyColor
                border.width: cell.selected ? 2 : 1
                // Red while the close button is pointed at, white
                // around the selected one
                border.color: cell.closing ? Theme.closeColor : cell.selected ? Theme.selectedColor : "transparent"

                Behavior on border.color {
                    ColorAnimation {
                        duration: Theme.animationDuration
                    }
                }

                // Runs to the card's edges, inside its border, with the
                // card's rounded top corners
                ClippingRectangle {
                    id: thumbnail

                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: title.top
                    anchors.topMargin: card.border.width
                    anchors.leftMargin: card.border.width
                    anchors.rightMargin: card.border.width
                    color: "transparent"
                    topLeftRadius: card.radius - card.border.width
                    topRightRadius: card.radius - card.border.width
                    bottomLeftRadius: 0
                    bottomRightRadius: 0

                    // Fills the whole thumbnail, cropping what doesn't fit;
                    // the window's top (title, tabs) is kept
                    Image {
                        id: preview
                        anchors.fill: parent
                        source: root.previews[cell.modelData.id] ?? ""
                        fillMode: Image.PreserveAspectCrop
                        verticalAlignment: Image.AlignTop
                        asynchronous: true
                        cache: false
                        smooth: true
                        mipmap: true
                        opacity: cell.selected ? 1 : 0.75
                    }

                    // Until the preview is ready, or when it can't be grabbed
                    IconImage {
                        anchors.centerIn: parent
                        visible: preview.status !== Image.Ready
                        implicitSize: Theme.iconSize * 2
                        source: cell.iconSource
                        opacity: 0.5
                    }

                    // Red wash over the window about to be closed
                    Rectangle {
                        anchors.fill: parent
                        color: Theme.closeColor
                        opacity: cell.closing ? 0.18 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Theme.animationDuration
                            }
                        }
                    }
                }

                // Line between the preview and the title, inside the border
                Rectangle {
                    anchors.bottom: title.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: card.border.width
                    anchors.rightMargin: card.border.width
                    height: 1
                    color: Theme.edgeColor
                }

                Row {
                    id: title

                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Theme.rowPadding
                    anchors.rightMargin: Theme.rowPadding
                    height: Theme.cardTitleHeight
                    spacing: Theme.iconSpacing

                    IconImage {
                        id: icon
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: Theme.iconSize * 0.8
                        source: cell.iconSource
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - icon.width - parent.spacing
                        text: cell.modelData.title
                        textFormat: Text.PlainText
                        color: cell.selected ? Theme.textColor : Theme.keyTextColor
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.keyFontSize
                        font.weight: Theme.fontWeight
                    }
                }
            }

            MouseArea {
                id: cardMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: cell.ListView.view.currentIndex = cell.index
                onClicked: menu.accept(cell.modelData)
            }

            // Close button: a round glass button that pops onto the top
            // right corner of a hovered card. Pointed at, it fills red like
            // the bar's urgent workspace, its × turns a quarter, and the card
            // blushes red to show what goes.
            Rectangle {
                id: closeButton

                readonly property bool shown: cardMouse.containsMouse || closeMouse.containsMouse

                // Hangs off the card's top right corner, out by the space
                // around the card on both sides: as far as it goes before
                // the strip clips it
                anchors.top: card.top
                anchors.right: card.right
                anchors.margins: -Theme.cardSpacing
                width: Theme.closeButtonSize
                height: Theme.closeButtonSize
                radius: width / 2
                color: cell.closing ? Theme.closeColor : Theme.panelColor
                border.width: 1
                border.color: cell.closing ? Theme.closeColor : Theme.edgeColor
                opacity: shown ? 1 : 0
                visible: opacity > 0
                scale: !shown ? 0.6 : closeMouse.pressed ? 0.85 : 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.animationDuration
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: Theme.animationDuration * 1.5
                        easing.type: Easing.OutBack
                    }
                }
                Behavior on color {
                    ColorAnimation {
                        duration: Theme.animationDuration
                    }
                }

                // The ×, two bars crossed, crisper than a glyph
                Item {
                    anchors.centerIn: parent
                    width: parent.width * 0.42
                    height: width
                    rotation: cell.closing ? 90 : 0

                    Behavior on rotation {
                        NumberAnimation {
                            duration: Theme.animationDuration * 2
                            easing.type: Easing.OutCubic
                        }
                    }

                    Repeater {
                        model: [45, -45]

                        Rectangle {
                            required property int modelData

                            anchors.centerIn: parent
                            width: parent.width * Math.SQRT2
                            height: 2
                            radius: 1
                            rotation: modelData
                            antialiasing: true
                            color: cell.closing ? Theme.panelColor : Theme.textColor
                        }
                    }
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close(cell.modelData)
                }
            }
        }
    }
}
