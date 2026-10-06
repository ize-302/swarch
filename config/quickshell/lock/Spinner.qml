pragma ComponentBehavior: Bound

import QtQuick
import qs

Column {
    id: spinnerContainer
    spacing: Theme.spinnerSpacing

    // Three fading bars, after "bars-fade" from SVG Spinners by Utkarsh Verma (MIT):
    // https://github.com/n3r4zzurr0/svg-spinners
    Item {
        id: spinner
        width: Theme.spinnerIconSize
        height: width
        anchors.horizontalCenter: parent.horizontalCenter

        // Position in the 800ms cycle; each bar starts 150ms after the previous one
        property real phase: 0
        NumberAnimation on phase {
            running: spinnerContainer.visible
            from: 0
            to: 800
            duration: 800
            loops: Animation.Infinite
        }

        Repeater {
            model: 3
            Rectangle {
                required property int index
                readonly property real elapsed: (spinner.phase - index * 150 + 800) % 800

                // Drawn on the icon's 24x24 grid
                x: (1 + index * 8) * spinner.width / 24
                y: 4 * spinner.height / 24
                width: 6 * spinner.width / 24
                height: 14 * spinner.height / 24
                color: Theme.spinnerColor
                opacity: elapsed < 750 ? 1.0 - 0.8 * elapsed / 750 : 0.2
            }
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Theme.spinnerText
        color: Theme.spinnerColor
        font.pixelSize: Theme.spinnerFontSize
        font.weight: Theme.spinnerFontWeight
        font.family: Theme.fontFamily
    }
}
