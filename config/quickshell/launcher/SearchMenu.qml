pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs

// Searchable list in the corner panel: a search row over a fixed number of
// result rows. The owner filters `results` by `query` and handles `accepted`.
PanelWindow { // qmllint disable uncreatable-type
    id: window

    property bool open: false
    // Rows to show, already filtered by `query`
    property var results: []
    readonly property alias query: input.text
    // Text for a result, and optionally the image beside it
    property var label: item => ""
    property var icon: null
    property string emptyText: ""
    // Fraction of the screen width
    property real panelWidth: Theme.panelWidth

    signal accepted(var item)

    function accept(item) {
        if (item === undefined)
            return;

        open = false;
        accepted(item);
    }

    visible: open
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    implicitWidth: Math.round(screen.width * panelWidth)
    implicitHeight: panel.height

    WlrLayershell.namespace: "launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
        bottom: true
        left: true
    }

    onVisibleChanged: {
        if (!visible)
            return;

        input.text = "";
        list.currentIndex = 0;
        input.forceActiveFocus();
        panel.appear();
    }

    Glass {
        id: panel

        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: parent.width
        height: content.implicitHeight + Theme.panelPadding * 2

        Column {
            id: content

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.panelPadding
            spacing: Theme.searchPadding

            Row {
                x: Theme.rowPadding
                width: parent.width - x * 2
                spacing: Theme.iconSpacing

                Text {
                    id: searchIcon
                    text: Theme.searchIcon
                    color: Theme.dimColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.searchFontSize
                }

                TextInput {
                    id: input

                    width: parent.width - searchIcon.width - parent.spacing
                    color: Theme.textColor
                    selectionColor: Theme.dividerColor
                    selectedTextColor: Theme.textColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.searchFontSize
                    font.weight: Theme.fontWeight
                    clip: true

                    onTextChanged: list.currentIndex = 0

                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier;
                        const count = window.results.length;
                        const page = Theme.maxRows;

                        if (event.key === Qt.Key_Escape) {
                            window.open = false;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            window.accept(window.results[list.currentIndex]);
                        } else if (count === 0) {
                            return;
                        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || (ctrl && event.key === Qt.Key_N)) {
                            list.currentIndex = (list.currentIndex + 1) % count;
                        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || (ctrl && event.key === Qt.Key_P)) {
                            list.currentIndex = (list.currentIndex + count - 1) % count;
                        } else if (event.key === Qt.Key_PageDown) {
                            list.currentIndex = Math.min(list.currentIndex + page, count - 1);
                        } else if (event.key === Qt.Key_PageUp) {
                            list.currentIndex = Math.max(list.currentIndex - page, 0);
                        } else {
                            return;
                        }
                        event.accepted = true;
                    }

                    Text {
                        visible: input.text.length === 0
                        text: Theme.placeholder
                        color: Theme.dimColor
                        font: input.font
                    }
                }
            }

            // Divider under the search row, same colour as the bar's separators
            Rectangle {
                width: parent.width
                height: 1
                color: Theme.dividerColor
            }

            // Always room for maxRows, however many results there are
            Item {
                width: parent.width
                height: Theme.maxRows * (Theme.rowHeight + Theme.rowSpacing) - Theme.rowSpacing

                ListView {
                    id: list

                    anchors.fill: parent
                    model: window.results
                    spacing: Theme.rowSpacing
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 0

                    delegate: Rectangle {
                        id: row

                        required property var modelData
                        required property int index

                        width: list.width
                        height: Theme.rowHeight
                        color: ListView.isCurrentItem ? Theme.selectedColor : "transparent"

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            x: Theme.rowPadding
                            width: parent.width - x * 2
                            spacing: Theme.iconSpacing

                            IconImage {
                                id: icon
                                anchors.verticalCenter: parent.verticalCenter
                                visible: window.icon !== null
                                implicitSize: Theme.iconSize
                                source: visible ? window.icon(row.modelData) : ""
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - (icon.visible ? icon.width + parent.spacing : 0)
                                text: window.label(row.modelData)
                                // Clipboard contents can look like markup
                                textFormat: Text.PlainText
                                color: Theme.textColor
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.weight: Theme.fontWeight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: list.currentIndex = row.index
                            onClicked: window.accept(row.modelData)
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: window.results.length === 0
                    text: window.emptyText
                    color: Theme.dimColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }
        }
    }
}
