pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs

// A notification in the notification centre (NotificationCenter.qml), laid
// out like a new notification's card (Notifications.qml): the app's icon, the
// app's name dimmed with its age and a × after it, the summary, the body
// under it, and its other actions as key caps. The × shows under the mouse or
// when it's picked with the keys.
//
// A collapsed stack (`stack` above 1: more from the same app behind it)
// shows the edges of two cards peeking out underneath, and its × dismisses
// the whole stack. Spread out, the stack's notifications are one card with
// its header: `joinedAbove` squares the top corners and draws a divider,
// `joinedBelow` squares the bottom ones.
Item {
    id: card

    // The notification, and the server it came from (Notifications.qml),
    // for its icon and age
    required property var notification
    required property var server
    // How many it stands for: 1, or the size of a collapsed stack
    property int stack: 1
    // Picked with the keys: lighter, as under the mouse
    property bool selected: false
    property bool joinedAbove: false
    property bool joinedBelow: false
    readonly property bool hovered: hover.hovered

    signal clicked
    signal closeClicked

    implicitHeight: face.height + (stack > 1 ? Theme.noteCardStackPeek * 2 : 0)

    HoverHandler {
        id: hover
    }

    // The cards behind a stack, narrower and lower, peeking out underneath:
    // only their bottoms, cut off at the edge above them, as the cards are
    // see-through
    Repeater {
        model: card.stack > 1 ? 2 : 0

        Item {
            required property int index

            x: Theme.noteCardStackInset * (index + 1)
            y: face.height + Theme.noteCardStackPeek * index
            width: card.width - x * 2
            height: Theme.noteCardStackPeek
            clip: true

            Rectangle {
                // Only its bottom edge shows
                y: parent.height - height
                width: parent.width
                height: Theme.noteCardStackPeek * 2
                radius: Theme.cornerRadius
                color: Theme.noteCardColor
                opacity: 1 - parent.index * 0.35
            }
        }
    }

    Rectangle {
        id: face

        width: parent.width
        height: content.implicitHeight + Theme.panelPadding * 2
        topLeftRadius: card.joinedAbove ? 0 : Theme.cornerRadius
        topRightRadius: card.joinedAbove ? 0 : Theme.cornerRadius
        bottomLeftRadius: card.joinedBelow ? 0 : Theme.cornerRadius
        bottomRightRadius: card.joinedBelow ? 0 : Theme.cornerRadius
        color: hover.hovered || card.selected ? Theme.noteCardHoverColor : Theme.noteCardColor

        Behavior on color {
            ColorAnimation {
                duration: Theme.animationDuration
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: card.clicked()
        }

        // Between it and what's above it on the same card
        Rectangle {
            visible: card.joinedAbove
            x: Theme.panelPadding
            width: parent.width - x * 2
            height: 1
            color: Theme.dividerColor
        }

        Row {
            id: content

            x: Theme.panelPadding
            y: Theme.panelPadding
            width: parent.width - x * 2
            spacing: Theme.iconSpacing

            // The app's icon, or the picture sent with it
            IconImage {
                property int tried: 0
                readonly property list<string> candidates: card.notification ? card.server.icons(card.notification) : []

                implicitSize: Theme.notificationIconSize
                source: candidates[tried] ?? ""
                onStatusChanged: if (status === Image.Error && tried < candidates.length - 1)
                    tried++
            }

            Column {
                width: parent.width - Theme.notificationIconSize - parent.spacing
                spacing: Theme.rowSpacing

                // The app's name, dimmed like a section header. Not in a
                // spread-out stack, whose header names it: there the age and
                // the × move onto the summary's line.
                Item {
                    id: topLine

                    visible: !card.joinedAbove
                    width: parent.width
                    height: Math.max(app.implicitHeight, meta.implicitHeight)

                    Text {
                        id: app
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - meta.width - Theme.iconSpacing
                        text: (card.notification?.appName || "Notification").toUpperCase()
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.dimColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.sectionFontSize
                        font.weight: Theme.fontWeight
                        font.letterSpacing: 1
                    }
                }

                Item {
                    id: summaryLine

                    width: parent.width
                    height: summary.implicitHeight
                    visible: summary.text !== ""

                    Text {
                        id: summary

                        // A line's height, to centre the age and × on the first
                        readonly property real lineHeight: lineCount > 0 ? contentHeight / lineCount : implicitHeight

                        width: parent.width - (card.joinedAbove ? meta.width + Theme.iconSpacing : 0)
                        text: card.notification?.summary ?? ""
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: Theme.textColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.controlFontSize
                        font.weight: Theme.fontWeight
                    }
                }

                // Its age, and the × that dismisses it (or the stack)
                Row {
                    id: meta

                    parent: card.joinedAbove ? summaryLine : topLine
                    anchors.right: parent.right
                    y: ((card.joinedAbove ? summary.lineHeight : topLine.height) - height) / 2
                    spacing: Theme.iconSpacing

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: card.notification ? card.server.age(card.notification) : ""
                        color: Theme.dimColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.controlSmallFontSize
                        font.weight: Theme.fontWeight
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: hover.hovered || card.selected ? 1 : 0
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
                            onClicked: card.closeClicked()
                        }
                    }
                }

                // Apps may send simple markup (bold, italics, links)
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: card.notification?.body ?? ""
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
                    readonly property list<var> actions: (card.notification?.actions ?? []).filter(action => action.identifier !== "default")

                    width: parent.width
                    visible: actions.length > 0
                    topPadding: Theme.rowSpacing
                    spacing: Theme.keySpacing

                    Repeater {
                        model: parent.actions

                        KeyCap {
                            id: actionCap

                            required property var modelData

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
