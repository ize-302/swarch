pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs

// Searchable list in the corner panel: a search row over a fixed number of
// result rows, or a strip of cards when the owner gives a `card` delegate. The
// owner filters `results` by `query` and handles `accepted`.
PanelWindow { // qmllint disable uncreatable-type
    id: window

    property bool open: false
    // Rows to show, already filtered by `query`
    property var results: []
    readonly property alias query: input.text
    // Text for a result, and optionally the image beside it and the dimmed
    property var label: item => ""
    property var icon: null
    // text at the end of the row; a hint that is a list is drawn as key caps
    property var hint: null
    // Property of a result that groups the rows under a header, and whether
    // to show the number of results in the search row
    property string section: ""
    property bool showCount: false
    property string emptyText: ""
    // Fraction of the screen width
    property real panelWidth: Theme.panelWidth
    // Float in the middle of the screen instead of sitting in the corner
    property bool floating: false
    // Floating, but low: centred just above the bar instead of in the
    // middle of the screen
    property bool aboveBar: false
    // Small drop shadow under the panel; floating panels always have one
    property bool shadow: floating
    property int cornerRadius: Theme.panelRadius
    property color panelColor: Theme.glassPanelColor
    // Space between the panel's edges and its content
    property int panelPadding: Theme.panelPadding
    // Delegate for a strip of cards instead of rows: one row across the
    // whole screen, sitting on the bar and scrolling sideways. Its root gets
    // the ListView's `modelData` and `index`; ListView.isCurrentItem marks
    // the selected card.
    property Component card: null
    readonly property bool strip: card !== null
    readonly property int cardWidth: Math.round(screen.width * Theme.cardWidth)
    readonly property Item view: strip ? cards : list
    // Extra keys: called with the key event and the selected result before
    // the menu's own keys; returns true when it handled the key
    property var keyHandler: null

    // Without the search row the results aren't filtered and keys go
    // straight to the menu
    property bool searchable: true

    signal accepted(var item)

    function accept(item) {
        if (item === undefined)
            return;

        open = false;
        accepted(item);
    }

    // Keys for the search box, or for the menu itself when it has none
    function handleKey(event) {
        const selected = window.results[window.view.currentIndex];
        if (window.keyHandler && selected !== undefined && window.keyHandler(event, selected)) {
            event.accepted = true;
            return;
        }

        const ctrl = event.modifiers & Qt.ControlModifier;
        const count = window.results.length;
        const view = window.view;
        const current = view.currentIndex;
        // A page is the cards (or rows) that fit
        const page = window.strip ? Math.max(1, Math.floor(cards.width / window.cardWidth)) : Theme.maxRows;
        // h and l move along a strip with no search field to type into
        const vim = window.strip && !window.searchable && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));

        if (event.key === Qt.Key_Escape) {
            window.open = false;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            window.accept(window.results[current]);
        } else if (count === 0) {
            return;
        } else if (event.key === Qt.Key_Tab || (ctrl && event.key === Qt.Key_N) || (window.strip && event.key === Qt.Key_Right) || (vim && event.key === Qt.Key_L)) {
            view.currentIndex = (current + 1) % count;
        } else if (event.key === Qt.Key_Backtab || (ctrl && event.key === Qt.Key_P) || (window.strip && event.key === Qt.Key_Left) || (vim && event.key === Qt.Key_H)) {
            view.currentIndex = (current + count - 1) % count;
        } else if (event.key === Qt.Key_Down) {
            view.currentIndex = (current + 1) % count;
        } else if (event.key === Qt.Key_Up) {
            view.currentIndex = (current + count - 1) % count;
        } else if (event.key === Qt.Key_PageDown) {
            view.currentIndex = Math.min(current + page, count - 1);
        } else if (event.key === Qt.Key_PageUp) {
            view.currentIndex = Math.max(current - page, 0);
        } else {
            return;
        }
        event.accepted = true;
    }

    visible: open
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    implicitWidth: strip ? screen.width : Math.round(screen.width * panelWidth)
    implicitHeight: panel.height

    // sway draws the shadow (`layer_effects "launcher-shadow"`)
    WlrLayershell.namespace: shadow ? "launcher-shadow" : "launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // With no edges anchored, the layer shell centres the window; the strip
    // spans the bottom edge, on top of the bar
    anchors {
        bottom: !window.floating || window.strip || window.aboveBar
        left: !window.floating || window.strip
        right: window.strip
    }
    margins.bottom: window.floating && window.aboveBar ? Theme.centredGap : 0

    onVisibleChanged: {
        if (!visible)
            return;

        input.text = "";
        window.view.currentIndex = 0;
        (searchable ? input : keys).forceActiveFocus();
        panel.appear();
    }

    Glass {
        id: panel

        floating: window.floating
        cornerRadius: window.cornerRadius
        fullWidth: window.strip
        color: window.panelColor
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: parent.width
        height: content.implicitHeight + window.panelPadding * 2

        Item {
            id: keys
            Keys.onPressed: event => window.handleKey(event)
        }

        Column {
            id: content

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: window.panelPadding
            spacing: Theme.searchPadding

            Row {
                x: Theme.rowPadding
                width: parent.width - x * 2
                visible: window.searchable
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

                    width: parent.width - searchIcon.width - parent.spacing - (count.visible ? count.width + parent.spacing : 0)
                    color: Theme.textColor
                    selectionColor: Theme.dividerColor
                    selectedTextColor: Theme.textColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.searchFontSize
                    font.weight: Theme.fontWeight
                    clip: true

                    onTextChanged: window.view.currentIndex = 0

                    Keys.onPressed: event => window.handleKey(event)

                    Text {
                        visible: input.text.length === 0
                        text: Theme.placeholder
                        color: Theme.dimColor
                        font: input.font
                    }
                }

                Text {
                    id: count
                    visible: window.showCount
                    text: window.results.length
                    color: Theme.dimColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.sectionFontSize
                    font.weight: Theme.fontWeight
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Divider under the search row, same colour as the bar's separators
            Rectangle {
                width: parent.width
                height: 1
                visible: window.searchable
                color: Theme.dividerColor
            }

            // Always room for maxRows (or one row of cards), however many
            // results there are
            Item {
                width: parent.width
                height: window.strip ? Math.round(window.screen.height * Theme.cardHeight) : Theme.maxRows * (Theme.rowHeight + Theme.rowSpacing) - Theme.rowSpacing

                ListView {
                    id: cards

                    anchors.fill: parent
                    visible: window.strip
                    orientation: ListView.Horizontal
                    model: window.strip ? window.results : []
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 0
                    delegate: window.card

                    // The mouse wheel scrolls the strip sideways, half a card
                    // a notch; sideways swipes are left to the list itself
                    WheelHandler {
                        orientation: Qt.Vertical
                        onWheel: event => {
                            const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 120 * window.cardWidth / 2;
                            const end = cards.originX + Math.max(0, cards.contentWidth - cards.width);
                            cards.contentX = Math.max(cards.originX, Math.min(cards.contentX - delta, end));
                        }
                    }
                }

                // Fades over the strip's edges while there are more cards
                // that way
                Repeater {
                    model: window.strip ? [false, true] : []

                    delegate: Rectangle {
                        id: fade

                        required property bool modelData
                        readonly property bool atRight: modelData

                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: atRight ? undefined : parent.left
                        anchors.right: atRight ? parent.right : undefined
                        width: Theme.stripFadeWidth
                        opacity: (atRight ? cards.atXEnd : cards.atXBeginning) ? 0 : 1
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop {
                                position: 0
                                color: fade.atRight ? "transparent" : window.panelColor
                            }
                            GradientStop {
                                position: 1
                                color: fade.atRight ? window.panelColor : "transparent"
                            }
                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Theme.animationDuration
                            }
                        }
                    }
                }

                ListView {
                    id: list

                    anchors.fill: parent
                    visible: !window.strip
                    model: window.strip ? [] : window.results
                    spacing: Theme.rowSpacing
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 0

                    section.property: window.section
                    section.delegate: window.section ? sectionHeader : null

                    delegate: Rectangle {
                        id: row

                        required property var modelData
                        required property int index

                        width: list.width
                        height: Theme.rowHeight
                        color: ListView.isCurrentItem ? Theme.currentRowColor : "transparent"
                        radius: Theme.cornerRadius

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
                                width: parent.width - (icon.visible ? icon.width + parent.spacing : 0) - (hint.visible ? hint.width + parent.spacing : 0)
                                text: window.label(row.modelData)
                                // Clipboard contents can look like markup
                                textFormat: Text.PlainText
                                // The selected row white and bold
                                color: row.ListView.isCurrentItem ? Theme.selectedColor : Theme.unselectedColor
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.weight: row.ListView.isCurrentItem ? Theme.selectedWeight : Theme.unselectedWeight
                            }

                            Row {
                                id: hint

                                readonly property var value: visible ? window.hint(row.modelData) : ""
                                readonly property bool caps: typeof value === "object"

                                anchors.verticalCenter: parent.verticalCenter
                                visible: window.hint !== null
                                spacing: Theme.keySpacing

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !hint.caps
                                    text: hint.caps ? "" : hint.value
                                    textFormat: Text.PlainText
                                    color: Theme.dimColor
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    font.weight: Theme.fontWeight
                                }

                                // One tinted cap per key, like the bar's
                                // workspace buttons; brighter on the selected row
                                Repeater {
                                    model: hint.caps ? hint.value : []

                                    delegate: KeyCap {
                                        required property string modelData

                                        y: (hint.height - height) / 2
                                        text: modelData
                                        lit: row.ListView.isCurrentItem
                                    }
                                }
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

    // Group header, named by the section property's value
    Component {
        id: sectionHeader

        SectionHeader {
            required property string section

            width: ListView.view.width
            text: section
        }
    }
}
