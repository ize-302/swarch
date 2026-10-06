import QtQuick
import QtQuick.Window
import QtQuick.Controls

Item {
    id: spinnerContainer
    width: (spinner.width + Config.spinnerSpacing + spinnerText.width) * Config.automaticScale(Screen.devicePixelRatio)
    height: childrenRect.height * Config.automaticScale(Screen.devicePixelRatio)

    Behavior on opacity {
        enabled: Config.enableAnimations
        NumberAnimation {
            duration: 150
        }
    }
    Behavior on visible {
        enabled: Config.enableAnimations && Config.spinnerDisplayText
        ParallelAnimation {
            running: spinnerContainer.visible && Config.spinnerDisplayText
            NumberAnimation {
                target: spinnerText
                property: Config.loginAreaPosition === "left" ? "anchors.leftMargin" : (Config.loginAreaPosition === "right" ? "anchors.rightMargin" : "anchors.topMargin")
                from: -spinner.height
                to: Config.spinnerSpacing
                duration: 300
                easing.type: Easing.OutQuart
            }
            NumberAnimation {
                target: spinner
                property: "opacity"
                from: 0.0
                to: 1.0
                duration: 200
            }
        }
    }

    // Three fading bars, after "bars-fade" from SVG Spinners by Utkarsh Verma (MIT):
    // https://github.com/n3r4zzurr0/svg-spinners
    Item {
        id: spinner
        width: Config.spinnerIconSize * Config.automaticScale(Screen.devicePixelRatio)
        height: width
        opacity: Config.spinnerDisplayText ? 0.0 : 1.0

        // Position in the 800ms cycle; each bar starts 150ms after the previous one
        property real phase: 0
        NumberAnimation on phase {
            running: spinnerContainer.visible && Config.enableAnimations
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
                color: Config.spinnerColor
                opacity: Config.enableAnimations ? (elapsed < 750 ? 1.0 - 0.8 * elapsed / 750 : 0.2) : [1.0, 0.4, 0.3][index]
            }
        }

        Component.onCompleted: {
            if (Config.loginAreaPosition === "left") {
                anchors.left = parent.left;
                anchors.verticalCenter = parent.verticalCenter;
            } else if (Config.loginAreaPosition === "right") {
                anchors.right = parent.right;
                anchors.verticalCenter = parent.verticalCenter;
            } else {
                anchors.top = parent.top;
                anchors.horizontalCenter = parent.horizontalCenter;
            }
        }
    }

    Text {
        id: spinnerText
        visible: Config.spinnerDisplayText
        text: Config.spinnerText
        color: Config.spinnerColor
        font.pixelSize: Config.spinnerFontSize * Config.automaticScale(Screen.devicePixelRatio)
        font.weight: Config.spinnerFontWeight
        font.family: Config.spinnerFontFamily

        Component.onCompleted: {
            if (Config.loginAreaPosition === "left") {
                anchors.left = spinner.right;
                anchors.leftMargin = Config.spinnerSpacing;
                anchors.verticalCenter = parent.verticalCenter;
            } else if (Config.loginAreaPosition === "right") {
                anchors.right = spinner.left;
                anchors.rightMargin = Config.spinnerSpacing;
                anchors.verticalCenter = parent.verticalCenter;
            } else {
                anchors.top = spinner.bottom;
                anchors.topMargin = Config.spinnerSpacing;
                anchors.horizontalCenter = parent.horizontalCenter;
            }
        }

        onVisibleChanged: {
            if (visible && Config.enableAnimations && Config.spinnerDisplayText) {
                spinnerTextInterval.running = true;
            } else {
                spinnerTextAnimation.running = false;
                spinnerTextInterval.running = false;
            }
        }

        SequentialAnimation on scale {
            id: spinnerTextAnimation
            running: false
            loops: Animation.Infinite
            NumberAnimation {
                from: 1.0
                to: 1.05
                duration: 900
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                from: 1.05
                to: 1.0
                duration: 900
                easing.type: Easing.InOutQuad
            }
        }
    }

    Timer {
        id: spinnerTextInterval
        interval: 3500
        repeat: false
        running: false
        onTriggered: {
            spinnerTextAnimation.running = true;
        }
    }

    Component.onDestruction: {
        if (spinnerTextInterval) {
            spinnerTextInterval.running = false;
            spinnerTextInterval.stop();
        }
        if (spinnerTextAnimation) {
            spinnerTextAnimation.running = false;
            spinnerTextAnimation.stop();
        }
    }
}
