import QtQuick
import Quickshell
import qs

// What one monitor shows while locked: the clock, then the unlock prompt once
// a key is pressed. Mirrors LockScreen.qml and LoginScreen.qml of the SDDM theme.
Rectangle {
    id: root

    required property LockContext context

    color: Theme.background

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            root.context.showPrompt = true;
            password.forceActiveFocus();
        }
    }

    Item {
        id: clockScreen
        anchors.fill: parent
        opacity: root.context.showPrompt ? 0.0 : 1.0

        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: Theme.dateMarginTop

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(clock.date, Theme.clockFormat)
                color: Theme.clockColor
                font.pixelSize: Theme.clockFontSize
                font.weight: Theme.clockFontWeight
                font.family: Theme.fontFamily
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: clock.date.toLocaleString(Qt.locale(Theme.dateLocale), Theme.dateFormat)
                color: Theme.dateColor
                font.pixelSize: Theme.dateFontSize
                font.weight: Theme.dateFontWeight
                font.family: Theme.fontFamily
            }
        }

        Text {
            anchors {
                bottom: parent.bottom
                bottomMargin: Theme.hintMarginBottom
                horizontalCenter: parent.horizontalCenter
            }
            text: Theme.hintText
            color: Theme.hintColor
            font.pixelSize: Theme.hintFontSize
            font.weight: Theme.hintFontWeight
            font.family: Theme.fontFamily
        }
    }

    // Hidden with opacity rather than `visible`, so the password input keeps
    // keyboard focus and can catch the key press that opens the prompt.
    Item {
        id: promptScreen
        anchors.fill: parent
        opacity: root.context.showPrompt ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }

        Column {
            id: promptContainer
            anchors.centerIn: parent
            scale: root.context.showPrompt ? 1.0 : 0.5

            Behavior on scale {
                NumberAnimation {
                    duration: 200
                }
            }

            Rectangle {
                id: avatar
                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.avatarSize
                height: Theme.avatarSize
                color: Theme.inputBackgroundColor

                // The user's picture where SDDM looks for it, falling back to the penguin
                readonly property list<url> sources: [
                    "file:///usr/share/sddm/faces/" + Quickshell.env("USER") + ".face.icon",
                    "file://" + Quickshell.env("HOME") + "/.face.icon",
                    "file://" + Quickshell.env("HOME") + "/.face",
                    Qt.resolvedUrl("icons/avatar.svg")
                ]
                property int sourceIndex: 0

                Image {
                    anchors.fill: parent
                    source: avatar.sources[avatar.sourceIndex]
                    sourceSize: Qt.size(width, height)
                    fillMode: Image.PreserveAspectCrop
                    mipmap: true

                    onStatusChanged: {
                        // Deferred: changing the source from its own status handler is a binding loop
                        if (status === Image.Error && avatar.sourceIndex < avatar.sources.length - 1)
                            Qt.callLater(() => avatar.sourceIndex++);
                    }
                }
            }

            Item {
                width: 1
                height: Theme.usernameMargin
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Quickshell.env("USER")
                color: Theme.usernameColor
                font.pixelSize: Theme.usernameFontSize
                font.weight: Theme.usernameFontWeight
                font.family: Theme.fontFamily
            }

            Item {
                width: 1
                height: Theme.inputMarginTop
            }

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(inputRow.width, spinner.width)
                height: root.context.unlockInProgress ? spinner.height : inputRow.height

                Row {
                    id: inputRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: root.context.unlockInProgress ? 0.0 : 1.0

                    Rectangle {
                        width: Theme.inputWidth
                        height: Theme.inputHeight
                        color: Theme.inputBackgroundColor

                        Image {
                            id: passwordIcon
                            x: (Theme.inputHeight - width) / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.inputIconSize
                            height: width
                            sourceSize: Qt.size(width, height)
                            source: "icons/password.svg"
                        }

                        Text {
                            anchors.fill: password
                            visible: password.text.length === 0
                            text: "Password"
                            color: Theme.inputContentColor
                            font.pixelSize: Theme.inputFontSize
                            font.family: Theme.fontFamily
                            verticalAlignment: Text.AlignVCenter
                        }

                        TextInput {
                            id: password
                            anchors {
                                fill: parent
                                leftMargin: Theme.inputHeight + 2
                                rightMargin: 10
                            }
                            focus: true
                            clip: true
                            readOnly: root.context.unlockInProgress
                            echoMode: TextInput.Password
                            passwordCharacter: Theme.maskCharacter
                            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                            color: Theme.inputContentColor
                            verticalAlignment: TextInput.AlignVCenter
                            font.pixelSize: Theme.inputFontSize
                            font.family: Theme.fontFamily
                            font.letterSpacing: Theme.maskCharacterSpacing

                            Component.onCompleted: forceActiveFocus()

                            onTextChanged: root.context.currentText = text
                            onAccepted: root.context.tryUnlock()

                            // Typing on one monitor shows up on all of them
                            Connections {
                                target: root.context
                                function onCurrentTextChanged() {
                                    password.text = root.context.currentText;
                                }
                            }

                            Keys.onPressed: event => {
                                if (!root.context.showPrompt) {
                                    // The key that opens the prompt isn't typed into it
                                    if (event.key !== Qt.Key_Escape)
                                        root.context.showPrompt = true;
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Escape) {
                                    if (!root.context.unlockInProgress)
                                        root.context.showPrompt = false;
                                    event.accepted = true;
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: Theme.inputHeight
                        height: Theme.inputHeight
                        color: unlockButton.containsMouse ? Theme.buttonActiveBackgroundColor : Theme.buttonBackgroundColor

                        Image {
                            anchors.centerIn: parent
                            width: Theme.buttonIconSize
                            height: width
                            sourceSize: Qt.size(width, height)
                            source: "icons/arrow-right.svg"
                        }

                        MouseArea {
                            id: unlockButton
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                password.forceActiveFocus();
                                if (root.context.showPrompt)
                                    root.context.tryUnlock();
                                else
                                    root.context.showPrompt = true;
                            }
                        }
                    }
                }

                Spinner {
                    id: spinner
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.context.unlockInProgress
                }
            }

            Item {
                width: 1
                height: Theme.messageMarginTop
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                // Keeps its height when empty so the prompt doesn't jump
                text: root.context.unlockInProgress ? " " : (root.context.message || " ")
                color: root.context.messageIsError ? Theme.messageErrorColor : Theme.messageNormalColor
                font.pixelSize: Theme.messageFontSize
                font.weight: Theme.messageFontWeight
                font.family: Theme.fontFamily
            }
        }
    }
}
