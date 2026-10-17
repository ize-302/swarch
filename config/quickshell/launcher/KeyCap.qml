import QtQuick
import qs

// Tinted cap around a short bit of text, like the bar's workspace buttons:
// a key in the key bindings menu, a volume or a device in the control panel.
// Brighter when lit.
Rectangle {
    id: cap

    property string text: ""
    property bool lit: false
    // At least this wide, so a changing number doesn't make it jump
    property int minWidth: 0
    property int fontSize: Theme.keyFontSize
    // The text's colour, and when lit
    property color textColor: Theme.keyTextColor
    property color litTextColor: Theme.textColor
    // A thin outline and no tint, like a printed key
    property bool outlined: false
    // Selected: bold, like the menus' selected rows; `weight` otherwise
    property bool bold: false
    property int weight: Theme.fontWeight

    width: Math.max(minWidth, label.implicitWidth + Theme.keyPadding * 2)
    height: Theme.keyHeight
    radius: Theme.cornerRadius
    color: lit ? Theme.hoverColor : outlined ? "transparent" : Theme.keyColor
    border.width: outlined ? 1 : 0
    border.color: Theme.dividerColor

    Text {
        id: label
        anchors.centerIn: parent
        text: cap.text
        textFormat: Text.PlainText
        color: cap.lit ? cap.litTextColor : cap.textColor
        font.family: Theme.fontFamily
        font.pixelSize: cap.fontSize
        font.weight: cap.bold ? Theme.selectedWeight : cap.weight
    }
}
