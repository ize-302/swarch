import QtQuick
import qs

// Panel background shared by the menus: translucent, with a lit top and right
// edge. Left and bottom touch the screen edge and the bar, unless the panel
// is floating: then every corner is rounded and every edge lit. A full width
// panel, like the bar, only has its top edge lit and no rounded corner.
Rectangle {
    id: glass

    property bool floating: false
    property int cornerRadius: Theme.panelRadius
    property bool fullWidth: false
    // The lit edge's colour; red for a critical notification
    property color edgeColor: Theme.edgeColor
    // Slides in from the screen's right edge instead of rising out of the bar
    property bool fromRight: false

    color: Theme.glassPanelColor
    radius: floating ? cornerRadius : 0
    // The one corner that touches neither the screen edge nor the bar
    topRightRadius: fullWidth ? radius : cornerRadius

    // Rises out of the bar (or slides in from the right)
    function appear() {
        animation.restart();
    }

    transform: Translate {
        id: slide
    }

    ParallelAnimation {
        id: animation

        NumberAnimation {
            target: slide
            property: glass.fromRight ? "x" : "y"
            from: 16
            to: 0
            duration: Theme.animationDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: glass
            property: "opacity"
            from: 0
            to: 1
            duration: Theme.animationDuration
        }
    }

    // The lit edge is an outline that follows the corner; its sides on the
    // screen edge and the bar hang outside the panel and are clipped away
    // (unless floating)
    Item {
        anchors.fill: parent
        clip: true

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: glass.floating ? 0 : -border.width
            anchors.bottomMargin: glass.floating ? 0 : -border.width
            anchors.rightMargin: glass.fullWidth ? -border.width : 0
            color: "transparent"
            radius: glass.radius
            topLeftRadius: glass.topLeftRadius
            topRightRadius: glass.topRightRadius
            border.width: 1
            border.color: glass.edgeColor
        }
    }
}
