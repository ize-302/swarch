import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Pomodoro timer: focus for pomodoroFocus minutes, then a short break, with a
// long one after every pomodoroRounds focus sessions. Each one ends with a
// notification and waits for the next to be started. Shown on a card in the
// date panel (PomodoroCard.qml) and, while there's one going, on
// the bar (waybar's custom/pomodoro): this writes
// $XDG_RUNTIME_DIR/pomodoro.json ({ text, class, tooltip }) and signals
// waybar (SIGRTMIN+11) to read it again. Kept in the state directory, so
// restarting the daemon doesn't lose it.
//
// `qs -c launcher ipc call pomodoro toggle` (or skip, reset), and the bar
// module's clicks.
Scope {
    id: root

    // "focus", "short" or "long"
    property string phase: "focus"
    property bool running: false
    // When it ends, in ms since the epoch, while running
    property real endsAt: 0
    // Seconds left
    property int left: lengthOf("focus")
    // Focus sessions finished since the last long break
    property int done: 0

    readonly property int length: lengthOf(phase)
    // Nothing started: the bar module hides
    readonly property bool idle: !running && phase === "focus" && left === length && done === 0
    readonly property string label: phase === "focus" ? "Focus" : phase === "short" ? "Short break" : "Long break"
    readonly property string clock: Math.floor(left / 60) + ":" + String(left % 60).padStart(2, "0")

    function lengthOf(phase) {
        return (phase === "focus" ? Theme.pomodoroFocus : phase === "short" ? Theme.pomodoroShortBreak : Theme.pomodoroLongBreak) * 60;
    }

    function start() {
        if (running)
            return;
        endsAt = Date.now() + left * 1000;
        running = true;
        save();
    }

    function pause() {
        if (!running)
            return;
        tick();
        running = false;
        save();
    }

    function toggle() {
        if (running)
            pause();
        else
            start();
    }

    // On to the next one, without counting this one
    function skip() {
        advance(false);
    }

    function reset() {
        running = false;
        phase = "focus";
        done = 0;
        left = length;
        save();
    }

    function tick() {
        if (!running)
            return;
        left = Math.max(0, Math.ceil((endsAt - Date.now()) / 1000));
        if (left === 0)
            finish();
    }

    function finish() {
        const wasFocus = phase === "focus";
        advance(true);
        const body = wasFocus ? "Time for a " + (phase === "long" ? "long" : "short") + " break." : "Time to focus.";
        Quickshell.execDetached(["notify-send", "-a", "Pomodoro", "-i", "appointment-soon", (wasFocus ? "Focus" : "Break") + " over", body]);
    }

    // The next phase, ready and waiting; a finished focus session counts
    // towards the long break
    function advance(finished) {
        running = false;
        if (phase === "focus") {
            if (finished)
                done += 1;
            phase = done >= Theme.pomodoroRounds ? "long" : "short";
        } else {
            if (phase === "long")
                done = 0;
            phase = "focus";
        }
        left = length;
        save();
    }

    function save() {
        stateFile.setText(JSON.stringify({
            phase: phase,
            running: running,
            endsAt: endsAt,
            left: left,
            done: done
        }));
    }

    readonly property string status: JSON.stringify(idle ? {
        text: ""
    } : {
        text: (phase === "focus" ? Theme.pomodoroIcon : Theme.pomodoroBreakIcon) + " " + clock,
        class: [phase === "focus" ? "focus" : "break"].concat(running ? [] : ["paused"]),
        tooltip: label + (running ? "" : " (paused)")
    })

    onStatusChanged: barFile.setText(status + "\n")

    Timer {
        running: root.running
        repeat: true
        interval: 1000
        onTriggered: root.tick()
    }

    IpcHandler {
        target: "pomodoro"

        function toggle(): void {
            root.toggle();
        }

        function skip(): void {
            root.skip();
        }

        function reset(): void {
            root.reset();
        }
    }

    FileView {
        id: barFile

        path: Quickshell.env("XDG_RUNTIME_DIR") + "/pomodoro.json"
        printErrors: false
        onSaved: Quickshell.execDetached(["pkill", "-RTMIN+11", "-x", "waybar"])
    }

    // Where it was when the daemon last stopped; one that ended meanwhile
    // finishes now
    FileView {
        id: stateFile

        path: Quickshell.statePath("pomodoro.json")
        blockLoading: true
        printErrors: false

        onLoaded: {
            try {
                const state = JSON.parse(text());
                root.phase = ["focus", "short", "long"].includes(state.phase) ? state.phase : "focus";
                root.done = state.done ?? 0;
                root.left = state.left ?? root.length;
                root.endsAt = state.endsAt ?? 0;
                root.running = state.running ?? false;
                // After the load, as finishing saves to this same file
                Qt.callLater(root.tick);
            } catch (error) {}
            barFile.setText(root.status + "\n");
        }
        onLoadFailed: barFile.setText(root.status + "\n")
    }
}
