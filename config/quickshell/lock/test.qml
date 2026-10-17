import QtQuick
import Quickshell
import qs

// The lock UI in a normal window, for working on it without locking the
// session: `qs -p ~/.config/quickshell/lock/test.qml`. The password is still
// checked through PAM. LOCK_PREVIEW=prompt, typed, error or busy opens it in
// that state, for screenshots.
ShellRoot {
    LockContext {
        id: lockContext
        onUnlocked: Qt.quit()

        Component.onCompleted: {
            const state = Quickshell.env("LOCK_PREVIEW") ?? "";
            if (state === "")
                return;
            showPrompt = true;
            if (state === "typed" || state === "busy")
                currentText = "password";
            if (state === "busy")
                unlockInProgress = true;
            if (state === "error")
                Qt.callLater(() => fail("Wrong password"));
        }
    }

    FloatingWindow {
        implicitWidth: 960
        implicitHeight: 540
        color: Theme.background

        LockSurface {
            anchors.fill: parent
            context: lockContext
        }
    }

    Connections {
        target: Quickshell
        function onLastWindowClosed() {
            Qt.quit();
        }
    }
}
