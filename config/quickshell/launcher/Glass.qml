import QtQuick
import qs

// Panel background shared by the menus: translucent, with a sheen fading down
// from the top and a lit top and right edge. Left and bottom touch the screen
// edge and the bar.
Rectangle {
    id: glass

    color: Theme.panelColor
    // The one corner that touches neither the screen edge nor the bar
    topRightRadius: Theme.cornerRadius

    // Rises out of the bar
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
            property: "y"
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

    Rectangle {
        anchors.fill: parent
        topRightRadius: glass.topRightRadius
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Theme.sheenTop
            }
            GradientStop {
                position: 0.45
                color: Theme.sheenMiddle
            }
            GradientStop {
                position: 1
                color: "transparent"
            }
        }
    }
    // The lit edge is an outline that follows the corner; its left and bottom
    // sides hang outside the panel and are clipped away
    Item {
        anchors.fill: parent
        clip: true

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -border.width
            anchors.bottomMargin: -border.width
            color: "transparent"
            topRightRadius: glass.topRightRadius
            border.width: 1
            border.color: Theme.edgeColor
        }
    }
}
