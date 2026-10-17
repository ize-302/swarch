pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// Session locker, started by ~/.local/bin/lock-screen (`qs -c lock`).
// Preview the UI in a normal window with `qs -p ~/.config/quickshell/lock/test.qml`.
ShellRoot {
    LockContext {
        id: lockContext

        onUnlocked: {
            // Unlock before exiting: if the locker goes away while the session
            // is still locked, sway keeps it locked with nothing to type into.
            lock.locked = false;
            Qt.quit();
        }
    }

    WlSessionLock {
        id: lock
        locked: true

        // One surface per monitor
        WlSessionLockSurface {
            color: Theme.background

            LockSurface {
                anchors.fill: parent
                context: lockContext
            }
        }
    }
}
