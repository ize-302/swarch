pragma Singleton

import QtQuick
import Quickshell

// Same glass as the status bar (config/waybar/style.css): translucent
// #15161e with a sheen fading down and a lit edge. sway's
// `layer_effects "launcher"` blurs what's behind.
Singleton {
    readonly property string fontFamily: "JetBrainsMono NF"
    readonly property int fontSize: 17
    readonly property int fontWeight: 500

    // Fraction of the screen width
    readonly property real panelWidth: 0.22
    readonly property int panelPadding: 14
    readonly property color panelColor: Qt.rgba(21 / 255, 22 / 255, 30 / 255, 0.96)
    readonly property color sheenTop: Qt.rgba(1, 1, 1, 0.05)
    readonly property color sheenMiddle: Qt.rgba(1, 1, 1, 0.01)
    readonly property color edgeColor: Qt.rgba(1, 1, 1, 0.16)
    // Top right corner of the menus
    readonly property int cornerRadius: 1

    // Search row
    readonly property int searchFontSize: 15
    readonly property string searchIcon: ""
    readonly property string placeholder: "Search…"
    readonly property color textColor: "#c0caf5"
    readonly property color dimColor: "#565f89"
    readonly property color dividerColor: "#414868"
    readonly property int searchPadding: 10

    // Results
    readonly property int maxRows: 12
    readonly property int rowHeight: 32
    readonly property int rowSpacing: 4
    readonly property int rowPadding: 8
    readonly property int iconSize: 22
    readonly property int iconSpacing: 10
    // Tint, like the bar's focused workspace button
    readonly property color selectedColor: Qt.rgba(192 / 255, 202 / 255, 245 / 255, 0.12)

    // Shown instead of the list when nothing matches
    readonly property string emptyText: "No apps found"

    // Clipboard menu: wider, entries are whole lines of text
    readonly property real clipboardWidth: 0.35
    readonly property string clipboardEmptyText: "Nothing found"

    readonly property int animationDuration: 120

    // For entries with Terminal=true
    readonly property list<string> terminal: ["alacritty", "-e"]
}
