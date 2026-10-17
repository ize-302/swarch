import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import qs

// State shared by the lock surfaces of every monitor, so they all show the
// same prompt and typed password.
Scope {
    id: root

    signal unlocked
    // A wrong password, or PAM refused: the field shakes
    signal failed

    property string currentText: ""
    property bool showPrompt: false
    property bool unlockInProgress: false
    property string message: ""
    property bool messageIsError: false
    // Last thing PAM said during the current attempt, e.g. pam_faillock's
    // "The account is locked due to 3 failed logins"
    property string pamInfo: ""
    property bool capsLock: false

    onCurrentTextChanged: {
        if (currentText !== "")
            message = "";
        promptTimer.restart();
    }

    onShowPromptChanged: {
        if (!showPrompt) {
            currentText = "";
            message = "";
        }
    }

    function tryUnlock() {
        if (currentText === "" || unlockInProgress)
            return;

        unlockInProgress = true;
        message = "";
        pamInfo = "";
        pam.start();
    }

    function fail(text) {
        currentText = "";
        message = text;
        messageIsError = true;
        unlockInProgress = false;
        failed();
    }

    Timer {
        id: promptTimer
        interval: Theme.promptTimeout * 1000
        running: root.showPrompt && !root.unlockInProgress
        onTriggered: root.showPrompt = false
    }

    PamContext {
        id: pam

        // Same stack swaylock uses (/etc/pam.d/swaylock just includes login)
        config: "login"

        onPamMessage: {
            if (responseRequired) {
                respond(root.currentText);
            } else if (message !== "") {
                root.pamInfo = message;
                root.message = message;
                root.messageIsError = messageIsError;
            }
        }

        onCompleted: result => {
            if (result === PamResult.Success) {
                root.unlockInProgress = false;
                root.unlocked();
            } else if (result === PamResult.MaxTries) {
                root.fail("Too many attempts");
            } else if (result === PamResult.Error) {
                root.fail("Authentication error");
            } else {
                // Keep PAM's own reason: a locked out account rejects the
                // correct password too, which "Wrong password" would hide.
                root.fail(root.pamInfo || "Wrong password");
            }
        }

        onError: error => root.fail("Authentication error: " + PamError.toString(error))
    }

    // Reads the keyboards' caps lock lights, as the launcher's caps lock
    // popup does (config/quickshell/launcher/CapsLock.qml), for the
    // field's ⇪
    Process {
        id: capsWatcher

        command: ["python3", "-c", `
import glob, time
last = None
while True:
    lit = False
    for path in glob.glob("/sys/class/leds/*::capslock/brightness"):
        try:
            with open(path) as file:
                lit = lit or file.read().strip() not in ("", "0")
        except OSError:
            pass
    if lit != last:
        print(int(lit), flush=True)
        last = lit
    time.sleep(${Theme.capsLockPoll / 1000})
`]
        running: true

        stdout: SplitParser {
            onRead: line => root.capsLock = line.trim() === "1"
        }
    }
}
