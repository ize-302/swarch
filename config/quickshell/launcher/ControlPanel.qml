pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.I3
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs

// The bar's popups for sound, Wi-Fi and bluetooth: the glass panel of the
// other menus, floating just above the bar by the right edge. Its main view
// is the sound popup: what's playing (MediaRow.qml), and the output and input
// volume. Toggled by ~/.local/bin/control-panel
// (`qs -c launcher ipc call controlPanel toggleControlPanel`), Super+A or a
// click on the bar's volume; `control-panel Network` (the bar's Wi-Fi) and
// `control-panel Bluetooth` (its bluetooth) open those pages on their own,
// and going back from them closes the popup. The notifications have their
// own panel (NotificationCenter.qml).
//
// Opened from the bar (`control-panel --pointer`), it's centred over the
// module that was clicked, kept on the screen: where the pointer is (from
// shell.qml). From the keyboard, it's at the right edge.
//
// Up and Down move between rows, Left and Right (or h and l) move the
// selected slider or skip back and forward on what's playing, m mutes a
// volume, Enter plays or pauses, mutes a volume, makes a device
// the default, turns Wi-Fi or bluetooth on or off, or connects to a network
// or device (asking for a new network's password), Delete forgets a network
// or bluetooth device, and s searches for bluetooth devices.
//
// On the Network page, Right (or l, or the › on a row) opens a network's
// details: its addresses, signal and security
// (~/.local/bin/network-info), whether it connects by itself, and Connect or
// Disconnect and Forget. "Join other network…" asks for the name and
// password of a hidden one.
//
// On the Bluetooth page, the same opens a device's details: its type,
// battery and address, Connect or Disconnect (or Pair), whether it
// reconnects by itself, its audio profile for headphones and speakers
// (~/.local/bin/bluetooth-audio), and Forget.
//
// The main view has a section per thing, split by lines, with just its
// slider or switch. The lists (audio devices, networks,
// bluetooth devices) are on a page per section: a click on the section's
// header, Space, or Right on a switch opens the selected row's page in place
// of the main view, and Escape, Backspace, Left or a click on the page's
// title goes back.
Scope {
    id: root

    property bool open: false
    property int current: 0
    // The page it was opened on from the bar ("Network", "Bluetooth"), which
    // closes it on going back, or "" for the sound popup
    property string entryPage: ""

    // Centred on the pointer, opened from a bar module; where it is
    // (shell.qml), -1 until known. Shown once it's placed, or after a
    // moment at the right edge if the pointer can't be found.
    property bool atPointer: false
    property real pointerX: -1
    property var pointerScreen: null
    property bool placeWaited: false
    readonly property bool placed: !atPointer || pointerX >= 0 || placeWaited

    // The player to show: one that's playing, else one with a track,
    // paused
    readonly property MprisPlayer player: {
        const players = Mpris.players.values.filter(player => player.trackTitle || player.isPlaying);
        return players.find(player => player.isPlaying) ?? players[0] ?? null;
    }

    readonly property list<PwNode> sinks: Pipewire.nodes.values.filter(node => node.type === PwNodeType.AudioSink)
    readonly property list<PwNode> sources: Pipewire.nodes.values.filter(node => node.type === PwNodeType.AudioSource)

    readonly property NetworkDevice wifiDevice: Networking.devices.values.find(device => device.type === DeviceType.Wifi) ?? null
    // Cables plugged in
    readonly property list<NetworkDevice> wiredDevices: Networking.devices.values.filter(device => device.type === DeviceType.Wired && device.hasLink)
    // The nearest networks; the connected one first, then saved ones
    readonly property list<WifiNetwork> networks: {
        if (!wifiDevice || !Networking.wifiEnabled)
            return [];
        const rank = network => network.connected ? 0 : network.known ? 1 : 2;
        const networks = wifiDevice.networks.values.filter(network => network.name);
        return networks.sort((a, b) => rank(a) - rank(b) || b.signalStrength - a.signalStrength).slice(0, Theme.maxNetworks);
    }
    // The network a password is being typed for, and why recent attempts
    // failed (name -> ConnectionFailReason)
    property WifiNetwork passwordFor: null
    property var failures: ({})
    // A saved network's new password, for network-info's stdin
    property string newPassword: ""

    // The section whose page is open, or "" for the main view; the main view
    // each time the panel opens. Also "Details" (a network's) and "Join" (a
    // hidden network), which open from the Network page.
    property string page: ""

    // The network whose details are open, and what network-info said
    // about it
    property WifiNetwork detailsFor: null
    property var details: ({})
    // The bluetooth device whose details are open, and its audio profiles
    // from bluetooth-audio
    property BluetoothDevice deviceFor: null
    property var audio: ({})
    // Joining a hidden network: the name typed, and what happened
    property string joinName: ""
    property string joinPassword: ""
    property bool joinBusy: false
    property string joinError: ""

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool bluetoothOn: adapter?.enabled ?? false
    // Paired devices, and while searching the named ones nearby; connected
    // ones first
    readonly property list<BluetoothDevice> bluetoothDevices: {
        if (!bluetoothOn)
            return [];
        const searching = adapter.discovering;
        const devices = adapter.devices.values.filter(device => device.paired || (searching && device.deviceName));
        const rank = device => device.connected ? 0 : device.paired ? 1 : 2;
        return devices.sort((a, b) => rank(a) - rank(b) || a.name.localeCompare(b.name));
    }

    // One per row, with the section it's in: a volume
    // ({ kind: "volume", node }), an audio device to make the default ({ kind: "device", node }), a cable
    // ({ kind: "wired", device }), the Wi-Fi switch ({ kind: "wifi" }), a
    // network ({ kind: "network", network }) and the password for it
    // ({ kind: "password", network }), the bluetooth switch
    // ({ kind: "bluetooth" }) or a bluetooth device
    // ({ kind: "bluetoothDevice", device }). List rows (`list`) are on the
    // section's page; the rest are on the main view.
    readonly property var rows: {
        const rows = [];
        const add = (section, devices, fallback) => {
            if (fallback)
                rows.push({
                    section: section,
                    kind: "volume",
                    node: fallback
                });
            for (const node of devices)
                rows.push({
                    section: section,
                    kind: "device",
                    list: true,
                    node: node
                });
        };
        if (player)
            rows.push({
                section: "Now playing",
                kind: "media",
                player: player
            });
        add("Output", sinks, Pipewire.defaultAudioSink);
        add("Input", sources, Pipewire.defaultAudioSource);
        if (wifiDevice) {
            // At the top of the page, which opens even while Wi-Fi is off
            rows.push({
                section: "Network",
                kind: "wifi",
                list: true
            });
        }
        // Cables plugged in, under the switch
        for (const device of wiredDevices)
            rows.push({
                section: "Network",
                kind: "wired",
                list: true,
                device: device
            });
        if (wifiDevice) {
            for (const network of networks) {
                rows.push({
                    section: "Network",
                    kind: "network",
                    list: true,
                    network: network
                });
                if (network === passwordFor)
                    rows.push({
                        section: "Network",
                        kind: "password",
                        list: true,
                        network: network
                    });
            }
            if (Networking.wifiEnabled)
                rows.push({
                    section: "Network",
                    kind: "join",
                    list: true
                });
        }
        if (adapter) {
            // At the top of the page, which opens even while bluetooth is
            // off
            rows.push({
                section: "Bluetooth",
                kind: "bluetooth",
                list: true
            });
            for (const device of bluetoothDevices)
                rows.push({
                    section: "Bluetooth",
                    kind: "bluetoothDevice",
                    list: true,
                    device: device
                });
        }
        if (page === "Details")
            return detailsRows();
        if (page === "Device")
            return deviceRows();
        if (page === "Join")
            return joinRows();
        // Sliders and switches are only on the main view; a page is just the
        // section's list
        return rows.filter(row => page === "" ? !row.list : row.section === page && row.list);
    }

    // A network's details page: what's known about it ({ kind: "info",
    // label, value }), then Connect or Disconnect, the switch for joining it
    // by itself, and Forget
    function detailsRows() {
        const network = detailsFor;
        if (!network)
            return [];
        const section = network.name;
        const rows = [];
        const info = (label, value) => {
            if (value)
                rows.push({
                    section: section,
                    kind: "info",
                    list: true,
                    label: label,
                    value: String(value)
                });
        };
        info("Status", network.connected ? "Connected" : network.known ? "Saved" : "Not saved");
        info("Signal", details.signal !== undefined ? details.signal + "%" : "");
        info("Band", root.band(details.frequency));
        info("Link speed", details.rate);
        info("Security", details.security);
        info("IP address", details.ip);
        info("Gateway", details.gateway);
        info("DNS", (details.dns ?? []).join(", "));
        info("MAC address", details.mac);
        rows.push({
            section: section,
            kind: "connect",
            list: true,
            network: network
        });
        if (details.uuid)
            rows.push({
                section: section,
                kind: "autoconnect",
                list: true
            });
        if (network.known)
            rows.push({
                section: section,
                kind: "forget",
                list: true,
                network: network
            });
        return rows;
    }

    // A bluetooth device's page: what it is, then Connect, Disconnect or
    // Pair, the switch for reconnecting by itself, its audio profiles
    // ({ kind: "profile", name, label, codec }), and Forget
    function deviceRows() {
        const device = deviceFor;
        if (!device)
            return [];
        const section = device.name || device.address;
        const rows = [];
        const info = (label, value) => {
            if (value)
                rows.push({
                    section: section,
                    kind: "info",
                    list: true,
                    label: label,
                    value: String(value)
                });
        };
        info("Type", root.deviceType(device.icon));
        info("Status", device.connected ? "Connected" : device.paired ? "Paired" : "Not paired");
        info("Battery", device.batteryAvailable ? Math.round(device.battery * 100) + "%" : "");
        info("Address", device.address);
        rows.push({
            section: section,
            kind: "btConnect",
            list: true,
            device: device
        });
        if (device.paired)
            rows.push({
                section: section,
                kind: "btTrust",
                list: true,
                device: device
            });
        if (device.connected)
            for (const profile of audio.profiles ?? [])
                rows.push({
                    section: section,
                    kind: "profile",
                    list: true,
                    device: device,
                    name: profile.name,
                    label: profile.label,
                    codec: profile.codec
                });
        if (device.paired)
            rows.push({
                section: section,
                kind: "btForget",
                list: true,
                device: device
            });
        return rows;
    }

    // "audio-headset" -> "Headphones"
    function deviceType(icon) {
        const types = {
            "audio-headset": "Headphones",
            "audio-headphones": "Headphones",
            "audio-card": "Speaker",
            "input-keyboard": "Keyboard",
            "input-mouse": "Mouse",
            "input-tablet": "Tablet",
            "input-gaming": "Game controller",
            "phone": "Phone",
            "computer": "Computer",
            "camera-video": "Camera",
            "printer": "Printer"
        };
        return types[icon] ?? "";
    }

    function openDevice(device) {
        deviceFor = device;
        audio = {};
        page = "Device";
        current = 0;
        root.loadAudio();
        pageSlide.direction = 1;
        pageSlide.restart();
    }

    function loadAudio() {
        if (!deviceFor?.connected)
            return;
        audioProcess.command = [Theme.bluetoothAudio, "show", deviceFor.address];
        audioProcess.running = true;
    }

    function setProfile(name) {
        audio = Object.assign({}, audio, {
            active: name
        });
        Quickshell.execDetached([Theme.bluetoothAudio, "set", deviceFor.address, name]);
    }

    // The hidden network form: its name, its password, and how it went
    function joinRows() {
        const section = "Join other network";
        const rows = [
            {
                section: section,
                kind: "joinName",
                list: true
            },
            {
                section: section,
                kind: "joinPassword",
                list: true
            }
        ];
        if (joinBusy || joinError)
            rows.push({
                section: section,
                kind: "joinStatus",
                list: true,
                error: !joinBusy
            });
        return rows;
    }

    // "5280 MHz" -> "5 GHz"
    function band(frequency) {
        const mhz = parseInt(frequency ?? "");
        if (!mhz)
            return "";
        return mhz >= 5925 ? "6 GHz" : mhz >= 4900 ? "5 GHz" : "2.4 GHz";
    }

    // Slides in from the right, like a section's page
    function openDetails(network) {
        detailsFor = network;
        details = {};
        page = "Details";
        current = 0;
        root.loadDetails();
        pageSlide.direction = 1;
        pageSlide.restart();
    }

    function loadDetails() {
        if (!detailsFor)
            return;
        detailsProcess.command = [Theme.networkInfo, "show", detailsFor.name];
        detailsProcess.running = true;
    }

    function setAutoconnect(on) {
        if (!details.uuid)
            return;
        details = Object.assign({}, details, {
            autoconnect: on
        });
        Quickshell.execDetached([Theme.networkInfo, "autoconnect", details.uuid, on ? "yes" : "no"]);
    }

    function openJoin() {
        joinName = "";
        joinPassword = "";
        joinError = "";
        page = "Join";
        current = 0;
        pageSlide.direction = 1;
        pageSlide.restart();
    }

    // Puts the keys in the row's field, for the join form
    function focusRow(index) {
        current = index;
        Qt.callLater(() => rowRepeater.itemAt(index)?.focusField());
    }

    // The password goes to network-info on its stdin, once it's running
    function join() {
        if (!joinName || joinBusy)
            return;
        joinBusy = true;
        joinError = "";
        joinProcess.command = [Theme.networkInfo, "join", joinName];
        joinProcess.running = true;
    }

    function isSlider(row) {
        return row.kind === "volume";
    }

    // "HDMI / DisplayPort 3 Output" -> "HDMI / DisplayPort 3": the section
    // already says it's an output
    function deviceName(node) {
        return (node.nickname || node.description || node.name).replace(/ Output$/, "");
    }

    function isDefault(node) {
        return node === Pipewire.defaultAudioSink || node === Pipewire.defaultAudioSource;
    }

    // Unmutes too
    function setVolume(row, volume) {
        row.node.audio.muted = false;
        row.node.audio.volume = volume;
    }

    function toggleMute(row) {
        row.node.audio.muted = !row.node.audio.muted;
    }

    // One step up or down a volume, on the step grid. Never pushes past
    // 100%, but leaves a volume already past it there.
    function step(row, direction) {
        const value = row.node.audio.volume;
        const next = Math.round((value + direction * Theme.volumeStep) * 20) / 20;
        root.setVolume(row, Math.max(0, Math.min(next, Math.max(value, 1))));
    }

    // Blocked by rfkill (like the bar's click, which this mirrors) can't be
    // undone over bluez
    function toggleBluetooth() {
        if (adapter.state === BluetoothAdapterState.Blocked)
            Quickshell.execDetached(["sh", "-c", "rfkill unblock bluetooth && sleep 1 && bluetoothctl power on"]);
        else
            adapter.enabled = !adapter.enabled;
    }

    // Pairs a new device, or connects or disconnects a paired one. A
    // connected device is trusted, so it reconnects by itself later.
    function toggleDevice(device) {
        if (device.pairing) {
            device.cancelPair();
        } else if (!device.paired) {
            device.pair();
        } else if (device.connected) {
            device.disconnect();
        } else {
            device.trusted = true;
            device.connect();
        }
    }

    // Signal bars for a network: an outline below 25%, then one to three
    // filled, like the bar's
    function networkIcon(network) {
        const strength = network.signalStrength > 1 ? network.signalStrength / 100 : network.signalStrength;
        const bars = Math.max(0, Math.min(3, Math.floor(strength * 4)));
        return Theme.wifiStrengthIcons[bars];
    }

    // The Wi-Fi switch's glyph: the connected network's bars, an outline
    // when on but not connected, struck through when off
    function wifiGlyph() {
        if (!Networking.wifiEnabled)
            return Theme.wifiOffIcon;
        const connected = wifiDevice?.networks.values.find(network => network.connected);
        return connected ? root.networkIcon(connected) : Theme.wifiStrengthIcons[0];
    }

    function isSecured(network) {
        return network.security !== WifiSecurityType.Open && network.security !== WifiSecurityType.Owe;
    }

    function setFailure(network, reason) {
        const failures = Object.assign({}, root.failures);
        if (reason === undefined)
            delete failures[network.name];
        else
            failures[network.name] = reason;
        root.failures = failures;
    }

    // Disconnects, connects with what's saved, or asks for the password of
    // a new secured network
    function toggleNetwork(network) {
        root.setFailure(network);
        if (network.connected) {
            network.disconnect();
        } else if (network.known || !root.isSecured(network)) {
            network.connect();
        } else {
            root.askPassword(network);
        }
    }

    // Opens the password row under the network and moves to it
    function askPassword(network) {
        passwordFor = network;
        Qt.callLater(() => root.current = root.rows.findIndex(row => row.kind === "password"));
    }

    // A new network connects with it; a saved one (its password was wrong,
    // or has changed) gets it saved by network-info, then connects
    function submitPassword(password) {
        const network = passwordFor;
        passwordFor = null;
        list.forceActiveFocus();
        if (!network || !password)
            return;
        root.setFailure(network);
        if (network.known) {
            newPassword = password;
            passwordProcess.command = [Theme.networkInfo, "password", network.name];
            passwordProcess.running = true;
        } else {
            network.connectWithPsk(password);
        }
    }

    // A connection failed: shown on its row. One that wants a password
    // (none saved, or the saved one is wrong) asks for it on the Network
    // page, opening the panel if it's closed, as nm-applet's dialog did.
    function connectionFailed(network, reason) {
        root.setFailure(network, reason);
        if (reason !== ConnectionFailReason.NoSecrets && reason !== ConnectionFailReason.WifiAuthTimeout)
            return;
        if (!open)
            open = true;
        if (page !== "Network")
            root.openPage("Network");
        root.askPassword(network);
    }

    function cancelPassword() {
        passwordFor = null;
        list.forceActiveFocus();
    }

    // Sections with a page: audio devices, and Wi-Fi and bluetooth (their
    // pages have their switches)
    function hasPage(section) {
        if (section === "Output" || section === "Input")
            return true;
        if (section === "Network")
            return wifiDevice !== null || wiredDevices.length > 0;
        if (section === "Bluetooth")
            return adapter !== null;
        return false;
    }

    // Slides in from the side it's going to
    function openPage(section) {
        if (!root.hasPage(section))
            return;
        page = section;
        current = 0;
        pageSlide.direction = 1;
        pageSlide.restart();
    }

    // Back to the main view, on the section's row; from a network's details
    // or the join form, back to the Network page, and from a device's,
    // the Bluetooth page
    function closePage() {
        const section = page;
        // Opened on this page from the bar: nothing to go back to
        if (section === entryPage) {
            open = false;
            return;
        }
        if (section === "Device") {
            const device = deviceFor;
            page = "Bluetooth";
            deviceFor = null;
            current = Math.max(0, rows.findIndex(row => row.device === device));
        } else if (section === "Details" || section === "Join") {
            const network = detailsFor;
            page = "Network";
            detailsFor = null;
            current = Math.max(0, rows.findIndex(row => section === "Join" ? row.kind === "join" : row.network === network));
            list.forceActiveFocus();
        } else {
            page = "";
            current = Math.max(0, rows.findIndex(row => row.section === section));
        }
        pageSlide.direction = -1;
        pageSlide.restart();
    }

    // What a section is set to, for the main view: the device in use, the
    // connected network, the connected bluetooth devices
    function summary(section) {
        if (section === "Output")
            return Pipewire.defaultAudioSink ? root.deviceName(Pipewire.defaultAudioSink) : "";
        if (section === "Input")
            return Pipewire.defaultAudioSource ? root.deviceName(Pipewire.defaultAudioSource) : "";
        if (section === "Network")
            return wiredDevices.some(device => device.connected) ? "Ethernet" : wifiDevice?.networks.values.find(network => network.connected)?.name ?? "";
        if (section === "Bluetooth")
            return bluetoothDevices.filter(device => device.connected).map(device => device.name).join(", ");
        if (section === "Now playing") {
            // "Mozilla zen" -> "Zen"
            const name = (player?.identity ?? "").replace(/^Mozilla /, "");
            return name.charAt(0).toUpperCase() + name.slice(1);
        }
        return "";
    }

    // Looks for new bluetooth devices, which then join the list
    function toggleSearch() {
        if (bluetoothOn)
            adapter.discovering = !adapter.discovering;
    }

    function activate(row) {
        if (row.kind === "media") {
            row.player.togglePlaying();
        } else if (row.kind === "device") {
            if (row.node.type === PwNodeType.AudioSink)
                Pipewire.preferredDefaultAudioSink = row.node;
            else
                Pipewire.preferredDefaultAudioSource = row.node;
        } else if (row.kind === "volume") {
            root.toggleMute(row);
        } else if (row.kind === "bluetooth") {
            root.toggleBluetooth();
        } else if (row.kind === "bluetoothDevice") {
            root.toggleDevice(row.device);
        } else if (row.kind === "wifi") {
            Networking.wifiEnabled = !Networking.wifiEnabled;
        } else if (row.kind === "network") {
            root.toggleNetwork(row.network);
        } else if (row.kind === "wired") {
            if (row.device.connected)
                row.device.disconnect();
            else
                row.device.network?.connect();
        } else if (row.kind === "join") {
            root.openJoin();
        } else if (row.kind === "connect") {
            root.toggleNetwork(row.network);
            if (row.network.connected || row.network.known || !root.isSecured(row.network))
                return;
            // A new secured network asks for its password on the Network page
            root.closePage();
        } else if (row.kind === "autoconnect") {
            root.setAutoconnect(!details.autoconnect);
        } else if (row.kind === "forget") {
            row.network.forget();
            root.closePage();
        } else if (row.kind === "btConnect") {
            root.toggleDevice(row.device);
        } else if (row.kind === "btTrust") {
            row.device.trusted = !row.device.trusted;
        } else if (row.kind === "profile") {
            root.setProfile(row.name);
        } else if (row.kind === "btForget") {
            row.device.forget();
            root.closePage();
        }
    }

    // Searching for bluetooth devices, and scanning for networks, only while
    // the panel is open
    onOpenChanged: {
        if (wifiDevice)
            wifiDevice.scannerEnabled = open;
        if (open) {
            page = "";
        } else {
            entryPage = "";
            atPointer = false;
            placeWaited = false;
            passwordFor = null;
            detailsFor = null;
            deviceFor = null;
            if (adapter?.discovering)
                adapter.discovering = false;
        }
    }

    IpcHandler {
        target: "controlPanel"

        // The sound popup; again closes it. From another page, switches.
        function toggleControlPanel(): void {
            root.toggleSound(false);
        }

        // The same, over the bar module under the pointer
        function toggleControlPanelAtPointer(): void {
            root.toggleSound(true);
        }

        // Opens it on the main view, whatever it showed before
        function showControlPanel(): void {
            root.entryPage = "";
            root.page = "";
            root.open = true;
        }

        // Opens the panel on a section's page ("Network", "Bluetooth", ...)
        // on its own. Again on the same page closes it.
        function openSection(section: string): void {
            root.toggleSection(section, false);
        }

        // The same, over the bar module under the pointer
        function openSectionAtPointer(section: string): void {
            root.toggleSection(section, true);
        }
    }

    function toggleSound(atPointer) {
        if (open && page === "") {
            open = false;
            return;
        }
        if (!open)
            root.atPointer = atPointer;
        entryPage = "";
        page = "";
        current = 0;
        open = true;
    }

    function toggleSection(section, atPointer) {
        if (open && page === section) {
            open = false;
            return;
        }
        if (!open)
            root.atPointer = atPointer;
        open = true;
        entryPage = section;
        root.openPage(section);
    }

    // The pointer wasn't found: the right edge, rather than nothing
    Timer {
        running: root.open && !root.placed
        interval: 500
        onTriggered: root.placeWaited = true
    }

    Process {
        id: detailsProcess

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.details = JSON.parse(text);
                } catch (error) {}
            }
        }
    }

    // Again while the details are open: signal, and addresses once it
    // connects
    Timer {
        running: root.open && root.page === "Details"
        repeat: true
        interval: 4000
        onTriggered: if (!detailsProcess.running)
            root.loadDetails()
    }

    Process {
        id: audioProcess

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.audio = JSON.parse(text);
                } catch (error) {}
            }
        }
    }

    // A device that connects (or switches profile) while its page is open
    Connections {
        target: root.deviceFor

        function onConnectedChanged() {
            root.loadAudio();
        }
    }

    Timer {
        running: root.open && root.page === "Device" && (root.deviceFor?.connected ?? false)
        repeat: true
        interval: 4000
        onTriggered: if (!audioProcess.running)
            root.loadAudio()
    }

    // Every network nearby, not just the ones listed, so a saved network
    // failing on its own (its password changed) asks too
    Instantiator {
        model: root.wifiDevice ? root.wifiDevice.networks.values : []

        delegate: Connections {
            required property WifiNetwork modelData

            target: modelData

            function onConnectionFailed(reason) {
                root.connectionFailed(modelData, reason);
            }
        }
    }

    Process {
        id: passwordProcess

        stdinEnabled: true

        onStarted: {
            write(root.newPassword + "\n");
            root.newPassword = "";
        }
    }

    Process {
        id: joinProcess

        stdinEnabled: true

        onStarted: {
            write(root.joinPassword + "\n");
            root.joinPassword = "";
        }

        stdout: StdioCollector {
            onStreamFinished: {
                root.joinBusy = false;
                let result = {};
                try {
                    result = JSON.parse(text);
                } catch (error) {
                    result = {
                        error: "Couldn't join"
                    };
                }
                if (result.ok) {
                    if (root.page === "Join")
                        root.closePage();
                } else {
                    root.joinError = result.error || "Couldn't join";
                }
            }
        }
    }

    // Volumes are only there for nodes that are tracked
    PwObjectTracker {
        objects: root.open ? [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] : []
    }

    PanelWindow { // qmllint disable uncreatable-type
        id: window

        visible: root.open && root.placed
        screen: (root.atPointer && root.pointerX >= 0 ? root.pointerScreen : null) ?? Quickshell.screens.find(screen => screen.name === I3.focusedMonitor?.name) ?? null
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        implicitWidth: Math.round((screen?.width ?? 1920) * Theme.controlWidth)
        implicitHeight: panel.height

        WlrLayershell.namespace: "launcher-shadow"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        anchors {
            bottom: true
            right: true
        }
        margins.bottom: Theme.floatingGap
        // Centred on the pointer, kept on the screen
        margins.right: {
            if (!root.atPointer || root.pointerX < 0 || !screen)
                return Theme.floatingGap;
            const right = screen.width - root.pointerX - implicitWidth / 2;
            return Math.round(Math.max(Theme.floatingGap, Math.min(right, screen.width - implicitWidth - Theme.floatingGap)));
        }

        onVisibleChanged: {
            if (!visible)
                return;

            root.current = 0;
            list.forceActiveFocus();
            panel.appear();
        }

        Glass {
            id: panel

            floating: true

            width: parent.width
            height: list.height + Theme.panelPadding * 2

            Column {
                id: list

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.panelPadding

                transform: Translate {
                    id: listSlide
                }

                // A page slides in from the right, the main view back from
                // the left
                ParallelAnimation {
                    id: pageSlide

                    property int direction: 1

                    NumberAnimation {
                        target: listSlide
                        property: "x"
                        from: pageSlide.direction * Theme.pageSlide
                        to: 0
                        duration: Theme.animationDuration
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: list
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Theme.animationDuration
                    }
                }

                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    const count = root.rows.length;
                    const row = root.rows[Math.min(root.current, count - 1)];

                    if (event.key === Qt.Key_Escape && root.page !== "") {
                        root.closePage();
                    } else if (event.key === Qt.Key_Escape) {
                        root.open = false;
                    } else if (event.key === Qt.Key_Backspace && root.page !== "") {
                        root.closePage();
                    } else if (count === 0) {
                        return;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.activate(row);
                    } else if (event.key === Qt.Key_Space && root.page === "") {
                        root.openPage(row.section);
                    } else if (event.key === Qt.Key_S && root.page === "Bluetooth") {
                        root.toggleSearch();
                    } else if (row.kind === "media" && (event.key === Qt.Key_Right || event.key === Qt.Key_L)) {
                        row.player.next();
                    } else if (row.kind === "media" && (event.key === Qt.Key_Left || event.key === Qt.Key_H)) {
                        row.player.previous();
                    } else if (event.key === Qt.Key_M && row.kind === "volume") {
                        root.toggleMute(row);
                    } else if (event.key === Qt.Key_Delete && row.kind === "bluetoothDevice" && row.device.paired) {
                        row.device.forget();
                    } else if (event.key === Qt.Key_Delete && row.kind === "network" && row.network.known) {
                        row.network.forget();
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || event.key === Qt.Key_J || (ctrl && event.key === Qt.Key_N)) {
                        root.current = (root.current + 1) % count;
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || event.key === Qt.Key_K || (ctrl && event.key === Qt.Key_P)) {
                        root.current = (root.current + count - 1) % count;
                    } else if (root.page === "Network" && row.kind === "network" && (event.key === Qt.Key_Right || event.key === Qt.Key_L)) {
                        root.openDetails(row.network);
                    } else if (root.page === "Bluetooth" && row.kind === "bluetoothDevice" && (event.key === Qt.Key_Right || event.key === Qt.Key_L)) {
                        root.openDevice(row.device);
                    } else if (!root.isSlider(row) && root.page === "" && (event.key === Qt.Key_Right || event.key === Qt.Key_L)) {
                        root.openPage(row.section);
                    } else if (!root.isSlider(row) && root.page !== "" && (event.key === Qt.Key_Left || event.key === Qt.Key_H)) {
                        root.closePage();
                    } else if (root.isSlider(row) && (event.key === Qt.Key_Right || event.key === Qt.Key_L)) {
                        root.step(row, 1);
                    } else if (root.isSlider(row) && (event.key === Qt.Key_Left || event.key === Qt.Key_H)) {
                        root.step(row, -1);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                Repeater {
                    id: rowRepeater

                    model: root.rows

                    ControlRow {
                        panel: root
                    }
                }

                Text {
                    visible: root.rows.length === 0
                    x: Theme.rowPadding
                    height: Theme.rowHeight
                    verticalAlignment: Text.AlignVCenter
                    text: Theme.controlEmptyText
                    color: Theme.dimColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.controlFontSize
                }
            }
        }
    }
}
