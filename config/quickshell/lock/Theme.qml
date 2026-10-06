pragma Singleton

import QtQuick
import Quickshell

// Tokyo Night, flat and square. Values mirror the SDDM theme
// (config/sddm/themes/custom/configs/default.conf) so the login and
// lock screens look the same.
Singleton {
    readonly property string fontFamily: "JetBrainsMono NF"
    readonly property color background: "#15161e"

    // Clock screen
    readonly property string clockFormat: "hh:mm"
    readonly property int clockFontSize: 70
    readonly property int clockFontWeight: 700
    readonly property color clockColor: "#c0caf5"

    readonly property string dateFormat: "ddd dd MMM"
    readonly property string dateLocale: "en_US"
    readonly property int dateFontSize: 14
    readonly property int dateFontWeight: 500
    readonly property color dateColor: "#4caf50"
    readonly property int dateMarginTop: -5

    readonly property string hintText: "Press any key"
    readonly property int hintFontSize: 16
    readonly property int hintFontWeight: 500
    readonly property color hintColor: "#565f89"
    readonly property int hintMarginBottom: 100

    // Unlock prompt
    readonly property int avatarSize: 120

    readonly property int usernameFontSize: 16
    readonly property int usernameFontWeight: 500
    readonly property color usernameColor: "#c0caf5"
    readonly property int usernameMargin: 10

    readonly property int inputWidth: 220
    readonly property int inputHeight: 34
    readonly property int inputFontSize: 12
    readonly property int inputIconSize: 16
    readonly property color inputContentColor: "#c0caf5"
    readonly property color inputBackgroundColor: "#1a1b26"
    readonly property int inputMarginTop: 10
    readonly property string maskCharacter: "●"
    readonly property int maskCharacterSpacing: 5

    readonly property color buttonBackgroundColor: "#4caf50"
    readonly property color buttonActiveBackgroundColor: "#66bb6a"
    readonly property int buttonIconSize: 18

    readonly property string spinnerText: "waking the penguin"
    readonly property int spinnerFontSize: 14
    readonly property int spinnerFontWeight: 500
    readonly property int spinnerIconSize: 30
    readonly property color spinnerColor: "#4caf50"
    readonly property int spinnerSpacing: 5

    readonly property int messageFontSize: 11
    readonly property int messageFontWeight: 400
    readonly property color messageNormalColor: "#a9b1d6"
    readonly property color messageErrorColor: "#f44336"
    readonly property int messageMarginTop: 10

    // Seconds without input before the prompt falls back to the clock
    readonly property int promptTimeout: 30
}
