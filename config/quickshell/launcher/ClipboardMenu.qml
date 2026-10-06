import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Clipboard history (cliphist) in the same corner panel as the app launcher.
// Toggled by ~/.local/bin/clipboard-menu
// (`qs -c launcher ipc call clipboard toggle`). Enter copies the entry again.
Scope {
    id: root

    property alias open: menu.open
    // Lines of `cliphist list`, newest first: "<id>\t<preview>"
    property list<string> entries

    // Every word of the query has to appear in the preview
    function search(query, entries) {
        const words = query.toLowerCase().split(/\s+/).filter(word => word);
        if (words.length === 0)
            return entries;

        return entries.filter(entry => {
            const text = entry.toLowerCase();
            return words.every(word => text.includes(word));
        });
    }

    onOpenChanged: if (open)
        lister.running = true

    IpcHandler {
        target: "clipboard"

        function toggle(): void {
            root.open = !root.open;
        }
    }

    Process {
        id: lister
        command: ["cliphist", "list"]

        stdout: StdioCollector {
            onStreamFinished: root.entries = text.split("\n").filter(line => line)
        }
    }

    SearchMenu {
        id: menu

        panelWidth: Theme.clipboardWidth
        results: root.search(query, root.entries)
        label: entry => entry.slice(entry.indexOf("\t") + 1)
        emptyText: Theme.clipboardEmptyText

        // cliphist finds the entry by the id at the start of the line
        onAccepted: entry => Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | cliphist decode | wl-copy", "sh", entry])
    }
}
