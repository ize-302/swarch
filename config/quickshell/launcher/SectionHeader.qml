import QtQuick
import qs

// Group header: dimmed name, then (unless `line` is off) a thin line like the
// bar's separators. One that opens a page ends in a key cap with a short
// summary and a chevron, which brighten under the mouse, and emits `clicked`.
//
// A `back` one is a page's title, styled like the menus' search row: a back
// chevron and the title, a divider under them, and maybe an `action` key cap
// at the end that emits `actionClicked`.
Item {
    id: header

    property string text: ""
    property string summary: ""
    property bool opensPage: false
    property bool line: true
    property bool back: false
    // A page's title with its back chevron; off for one that closes
    property bool arrow: true
    // Space from the edges to the text
    property int inset: Theme.rowPadding
    // Size of a page's title
    property int titleSize: Theme.searchFontSize
    // Key cap at the end of a page's title, lit while it's running
    property string action: ""
    property bool actionActive: false

    signal clicked
    signal actionClicked

    // A page's title is at the top of the panel, pulled up into its padding
    // so there's as much space above the title as between it and its divider
    height: back ? label.y + label.height + Theme.searchPadding + 1 + Theme.searchPadding / 2 : Theme.sectionHeight

    // Back chevron, dim like the search row's magnifier
    Text {
        id: backIcon
        x: header.inset
        anchors.verticalCenter: label.verticalCenter
        visible: header.back && header.arrow
        text: Theme.backIcon
        color: mouse.containsMouse ? Theme.textColor : Theme.dimColor
        font.family: Theme.fontFamily
        font.pixelSize: header.titleSize
    }

    // A page's title sits as far from the panel's edge as from its divider;
    // a section's name sits low, by the row under it
    Text {
        id: label
        x: header.back && header.arrow ? backIcon.x + backIcon.width + Theme.iconSpacing : header.inset
        y: header.back ? Theme.searchPadding - Theme.panelPadding : header.height - height - Theme.rowSpacing
        text: header.back ? header.text : header.text.toUpperCase()
        color: header.back ? Theme.textColor : Theme.dimColor
        font.family: Theme.fontFamily
        font.pixelSize: header.back ? header.titleSize : Theme.sectionFontSize
        font.weight: Theme.fontWeight
        font.letterSpacing: header.back ? 0 : 1
    }

    Rectangle {
        visible: header.line && !header.back
        anchors.left: label.right
        anchors.leftMargin: Theme.iconSpacing
        anchors.right: summary.visible ? summary.left : more.visible ? more.left : parent.right
        anchors.rightMargin: summary.visible || more.visible ? Theme.iconSpacing : header.inset
        anchors.verticalCenter: label.verticalCenter
        height: 1
        color: Theme.dividerColor
    }

    // Under a page's title, like the search row's
    Rectangle {
        visible: header.back
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.searchPadding / 2
        width: parent.width
        height: 1
        color: Theme.dividerColor
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: header.opensPage || header.back
        enabled: header.opensPage || header.back
        cursorShape: Qt.PointingHandCursor
        onClicked: header.clicked()
    }

    KeyCap {
        id: summary
        anchors.right: more.visible ? more.left : parent.right
        anchors.rightMargin: more.visible ? Theme.keySpacing : header.inset
        anchors.verticalCenter: label.verticalCenter
        visible: header.summary !== "" && !header.back
        text: header.summary
        lit: mouse.containsMouse
    }

    Text {
        id: more
        anchors.right: parent.right
        anchors.rightMargin: header.inset
        anchors.verticalCenter: label.verticalCenter
        visible: header.opensPage && !header.back
        text: Theme.pageIcon
        color: mouse.containsMouse ? Theme.textColor : Theme.keyTextColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.sectionFontSize
    }

    KeyCap {
        anchors.right: parent.right
        anchors.rightMargin: header.inset
        anchors.verticalCenter: label.verticalCenter
        visible: header.back && header.action !== ""
        text: header.action
        fontSize: Math.min(Theme.keyFontSize, header.titleSize - 2)
        lit: header.actionActive || actionMouse.containsMouse

        MouseArea {
            id: actionMouse

            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: header.actionClicked()
        }
    }
}
