pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs

// What's playing, in the sound popup (ControlPanel.qml): the artwork, the
// title and artist, previous, play or pause and next, then a progress bar
// with the time gone and the length. The bar seeks when the player can.
Column {
    id: media

    // The player (Zen, or any other MPRIS player)
    required property MprisPlayer player
    // Picked with the keys or under the mouse: the controls brighten
    property bool active: false

    spacing: Theme.rowSpacing * 2

    // "3:07", "1:02:45"
    function time(seconds) {
        const total = Math.max(0, Math.floor(seconds));
        const hours = Math.floor(total / 3600);
        const minutes = Math.floor(total / 60) % 60;
        const rest = String(total % 60).padStart(2, "0");
        return hours > 0 ? hours + ":" + String(minutes).padStart(2, "0") + ":" + rest : minutes + ":" + rest;
    }

    Row {
        width: parent.width
        spacing: Theme.iconSpacing

        // The artwork, or a note when there's none
        ClippingRectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.mediaArtSize
            height: Theme.mediaArtSize
            radius: Theme.cornerRadius
            color: Theme.keyColor

            Image {
                id: art
                anchors.fill: parent
                source: media.player?.trackArtUrl ?? ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: Theme.mediaArtSize * 2
                sourceSize.height: Theme.mediaArtSize * 2
                asynchronous: true
            }

            Text {
                anchors.centerIn: parent
                visible: art.status !== Image.Ready
                text: Theme.musicIcon
                color: Theme.dimColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.mediaArtSize / 2
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Theme.mediaArtSize - controls.width - parent.spacing * 2
            spacing: 2

            Text {
                width: parent.width
                text: media.player?.trackTitle || media.player?.identity || ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.textColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.controlFontSize
                font.weight: Font.DemiBold
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: media.player?.trackArtist ?? ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.keyTextColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.controlSmallFontSize
                font.weight: Theme.fontWeight
            }
        }

        // Previous, play or pause, next; dim when the player can't
        Row {
            id: controls

            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.keySpacing

            Repeater {
                model: [
                    {
                        action: "previous",
                        icon: Theme.previousIcon
                    },
                    {
                        action: "toggle",
                        icon: ""
                    },
                    {
                        action: "next",
                        icon: Theme.nextIcon
                    }
                ]

                Item {
                    id: button

                    required property var modelData
                    readonly property bool toggle: modelData.action === "toggle"
                    readonly property bool enabled: {
                        const player = media.player;
                        if (!player)
                            return false;
                        return toggle ? player.canTogglePlaying : modelData.action === "next" ? player.canGoNext : player.canGoPrevious;
                    }

                    width: toggle ? Theme.mediaPlaySize : Theme.mediaButtonSize
                    height: Theme.mediaPlaySize

                    // Play or pause stands out: a blue circle, like a switch
                    // that's on
                    Rectangle {
                        anchors.centerIn: parent
                        visible: button.toggle
                        width: Theme.mediaPlaySize
                        height: width
                        radius: width / 2
                        color: Theme.toggleOnColor
                        opacity: button.enabled ? (buttonMouse.containsMouse ? 0.85 : 1) : 0.4
                    }

                    Text {
                        anchors.centerIn: parent
                        text: button.toggle ? (media.player?.isPlaying ? Theme.pauseIcon : Theme.playIcon) : button.modelData.icon
                        color: button.toggle ? "white" : !button.enabled ? Theme.dimColor : buttonMouse.containsMouse || media.active ? Theme.textColor : Theme.keyTextColor
                        font.family: Theme.fontFamily
                        font.pixelSize: button.toggle ? Theme.controlFontSize + 2 : Theme.controlFontSize + 4
                    }

                    MouseArea {
                        id: buttonMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: button.enabled
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (button.toggle)
                                media.player.togglePlaying();
                            else if (button.modelData.action === "next")
                                media.player.next();
                            else
                                media.player.previous();
                        }
                    }
                }
            }
        }
    }

    // How far in, the bar, and how long. Hidden for a stream with no length.
    Row {
        width: parent.width
        visible: (media.player?.lengthSupported ?? false) && media.player.length > 0
        spacing: Theme.iconSpacing

        Text {
            id: elapsed
            anchors.verticalCenter: parent.verticalCenter
            width: timeWidth.advanceWidth
            horizontalAlignment: Text.AlignRight
            text: media.time(media.player?.position ?? 0)
            color: Theme.dimColor
            font: timeWidth.font
        }

        Slider {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - elapsed.width - total.width - parent.spacing * 2
            implicitHeight: Theme.rowHeight / 2
            value: media.player && media.player.length > 0 ? media.player.position / media.player.length : 0
            color: Theme.toggleOnColor
            interactive: media.player?.canSeek ?? false
            active: media.active
            onMoved: value => media.player.position = value * media.player.length
        }

        Text {
            id: total
            anchors.verticalCenter: parent.verticalCenter
            width: timeWidth.advanceWidth
            text: media.time(media.player?.length ?? 0)
            color: Theme.dimColor
            font: timeWidth.font
        }
    }

    // The player only says where it is when asked: once a second while
    // it plays and this is on screen
    Timer {
        running: media.visible && (media.player?.isPlaying ?? false)
        repeat: true
        interval: 1000
        onTriggered: media.player.positionChanged()
    }

    // As wide as a long time, so the bar doesn't jump
    TextMetrics {
        id: timeWidth
        text: "00:00"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.controlSmallFontSize
        font.weight: Theme.fontWeight
        font.features: {
            "tnum": 1
        }
    }
}
