//@ pragma IconTheme Papirus

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// App launcher: a glass panel in the bottom left corner, on top of the status
// bar. Runs as a daemon (`qs -c launcher -d`) and is toggled by
// ~/.local/bin/app-menu (`qs -c launcher ipc call launcher toggle`). The same
// daemon serves the power menu (PowerMenu.qml) and the clipboard menu
// (ClipboardMenu.qml).
ShellRoot {
    id: root

    // Desktop entry id -> times launched. Most used apps are listed first.
    property var history: ({})
    readonly property list<QtObject> menus: [appMenu, powerMenu, clipboardMenu]

    // The menus share the corner, so only one is open at a time
    function closeOthers(menu) {
        for (const other of menus) {
            if (other !== menu)
                other.open = false;
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

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            appMenu.open = !appMenu.open;
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
