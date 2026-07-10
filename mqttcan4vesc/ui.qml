// MQTTCAN4VESC configuration panel.
//
// Talks to mqttcan4vesc.lisp on the VESC Express with a small text protocol over
// custom app data (see docs/qml-panel.md):
//   out:  "GET" | "SET <key> <value>" | "SAVE" | "TEL" | "TEST" | "DEFAULTS" | "REBOOT"
//   in:   "CFG\n<k=v>..." | "TEL\n<k=v>..." | "ACK ..." | "ERR ..." | "TEST ..."
//
// Single scrollable column so it works on narrow mobile VESC Tool.

import QtQuick 2.15
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.3

import Vedder.vesc.commands 1.0
import Vedder.vesc.utility 1.0

Item {
    id: root
    anchors.fill: parent
    anchors.margins: 10

    property Commands mCommands: VescIf.commands()
    property color txt: Utility.getAppHexColor("lightText")

    Component.onCompleted: {
        sendCmd("GET")   // populate fields
        telTimer.start()
    }

    // Poll telemetry/status ~1 Hz
    Timer {
        id: telTimer
        interval: 1000
        repeat: true
        onTriggered: sendCmd("TEL")
    }

    ScrollView {
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: root.width - 20
            spacing: 8

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                color: txt
                font.pointSize: 18
                text: "MQTTCAN4VESC"
            }

            // ---------------- Live status ----------------
            GroupBox {
                Layout.fillWidth: true
                title: "Status"
                label: Label { color: txt; text: parent.title }

                GridLayout {
                    anchors.fill: parent
                    columns: 2
                    columnSpacing: 10
                    rowSpacing: 2

                    Label { color: txt; text: "WiFi" }
                    Label { id: stWifi;   color: txt; text: "-" }
                    Label { color: txt; text: "MQTT" }
                    Label { id: stMqtt;   color: txt; text: "-" }
                    Label { color: txt; text: "CAN frames" }
                    Label { id: stFrames; color: txt; text: "-" }
                    Label { color: txt; text: "Speed" }
                    Label { id: stSpeed;  color: txt; text: "-" }
                    Label { color: txt; text: "Torque" }
                    Label { id: stTorque; color: txt; text: "-" }
                    Label { color: txt; text: "V in" }
                    Label { id: stVin;    color: txt; text: "-" }
                    Label { color: txt; text: "Temp FET / Motor" }
                    Label { id: stTemp;   color: txt; text: "-" }
                    Label { color: txt; text: "Current in" }
                    Label { id: stCurr;   color: txt; text: "-" }
                    Label { color: txt; text: "Config from" }
                    Label { id: stSrc;    color: txt; text: "-" }
                    Label { color: txt; text: "Last save" }
                    Label { id: stSave;   color: txt; text: "-"; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    Label { color: txt; text: "Version" }
                    Label { id: stVer;    color: txt; text: "-"; font.pointSize: 8 }
                }
            }

            // ---------------- WiFi (configured in the firmware, not here) ----
            GroupBox {
                Layout.fillWidth: true
                title: "WiFi"
                label: Label { color: txt; text: parent.title }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 4

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: txt
                        font.pointSize: 8
                        text: "WiFi is configured on the device itself, not from this panel: " +
                              "VESC Express → WiFi → set WiFi Mode = Station and fill in " +
                              "Station Mode SSID / Key, then write and reboot. The firmware " +
                              "connects and reconnects automatically; this package only uses the link."
                    }
                }
            }

            // ---------------- MQTT broker ----------------
            GroupBox {
                Layout.fillWidth: true
                title: "MQTT Broker"
                label: Label { color: txt; text: parent.title }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 4

                    Label { color: txt; text: "Host (max 63)" }
                    TextField { id: fHost; Layout.fillWidth: true; maximumLength: 63 }

                    Label { color: txt; text: "Port" }
                    TextField {
                        id: fPort
                        Layout.fillWidth: true
                        inputMethodHints: Qt.ImhDigitsOnly
                        validator: IntValidator { bottom: 1; top: 65535 }
                    }

                    Label { color: txt; text: "Username (max 32, blank = no auth)" }
                    TextField { id: fUser; Layout.fillWidth: true; maximumLength: 32 }

                    Label { color: txt; text: "Password (max 32)" }
                    RowLayout {
                        Layout.fillWidth: true
                        TextField {
                            id: fMqttPass
                            Layout.fillWidth: true
                            maximumLength: 32
                            echoMode: showMqttPass.checked ? TextInput.Normal : TextInput.Password
                        }
                        CheckBox { id: showMqttPass; text: "Show" }
                    }
                }
            }

            // ---------------- Publishing ----------------
            GroupBox {
                Layout.fillWidth: true
                title: "Publishing"
                label: Label { color: txt; text: parent.title }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 4

                    Label { color: txt; text: "Topic prefix (max 48)" }
                    TextField { id: fPrefix; Layout.fillWidth: true; maximumLength: 48 }

                    Label { color: txt; text: "Publish mode" }
                    ComboBox {
                        id: fMode
                        Layout.fillWidth: true
                        model: ["json", "topics", "both"]
                    }

                    Label { color: txt; text: "Publish interval (s, 0.1 - 5.0)" }
                    TextField {
                        id: fInterval
                        Layout.fillWidth: true
                        validator: DoubleValidator { bottom: 0.1; top: 5.0; decimals: 2 }
                    }

                    Label { color: txt; text: "MQTT keepalive (s, 10 - 300)" }
                    TextField {
                        id: fKeepalive
                        Layout.fillWidth: true
                        inputMethodHints: Qt.ImhDigitsOnly
                        validator: IntValidator { bottom: 10; top: 300 }
                    }
                }
            }

            // ---------------- CAN ----------------
            GroupBox {
                Layout.fillWidth: true
                title: "CAN"
                label: Label { color: txt; text: parent.title }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 4

                    Label { color: txt; text: "CAN mode" }
                    ComboBox {
                        id: fCanMode
                        Layout.fillWidth: true
                        model: ["raw", "vesc", "sim"]
                    }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: txt
                        font.pointSize: 8
                        text: fCanMode.currentText === "vesc"
                            ? "vesc (recommended): full status 1-6 decode AND VESC Tool can reach the ESC over CAN. Falls back to canget-* polling if no status frames arrive. Reboot after Save to switch modes."
                            : fCanMode.currentText === "sim"
                              ? "sim: publishes simulated telemetry — no VESC needed. For bench/demo testing of the MQTT chain. Reboot after Save to switch modes."
                              : "raw: full status 1-6 decode; disables VESC-protocol CAN (no VESC Tool bridging). Only for firmware that hides CAN events in vesc mode. Reboot after Save to switch modes."
                    }

                    Label { color: txt; text: "Controller VESC ID (0 - 254)" }
                    RowLayout {
                        Layout.fillWidth: true
                        TextField {
                            id: fVescId
                            Layout.fillWidth: true
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 0; top: 254 }
                        }
                        Button { text: "Detect"; onClicked: sendCmd("DETECT") }
                    }
                }
            }

            // ---------------- Motor / decode ----------------
            GroupBox {
                Layout.fillWidth: true
                title: "Motor"
                label: Label { color: txt; text: parent.title }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 4

                    Label { color: txt; text: "Speed divisor (pole pairs)" }
                    TextField {
                        id: fSpeedDiv
                        Layout.fillWidth: true
                        validator: DoubleValidator { bottom: 0.0001; top: 1000 }
                    }

                    Label { color: txt; text: "Torque constant (Nm per raw 0.1 A)" }
                    TextField {
                        id: fTorqueK
                        Layout.fillWidth: true
                        validator: DoubleValidator { bottom: 0; top: 100 }
                    }
                }
            }

            // ---------------- Actions ----------------
            Button {
                Layout.fillWidth: true
                text: "Save & Apply"
                onClicked: saveAll()
            }
            RowLayout {
                Layout.fillWidth: true
                Button { Layout.fillWidth: true; text: "Test Connection"; onClicked: sendCmd("TEST") }
                Button { Layout.fillWidth: true; text: "Reload"; onClicked: sendCmd("GET") }
            }
            RowLayout {
                Layout.fillWidth: true
                Button {
                    Layout.fillWidth: true
                    text: "Restore Defaults"
                    onClicked: {
                        VescIf.emitMessageDialog("Restore Defaults",
                            "Reset all settings to factory defaults?", true, false)
                        sendCmd("DEFAULTS")
                    }
                }
                Button {
                    Layout.fillWidth: true
                    text: "Reboot"
                    onClicked: sendCmd("REBOOT")
                }
            }

            // ---------------- Log ----------------
            Label { color: txt; text: "Log" }
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                clip: true
                TextArea {
                    id: logArea
                    readOnly: true
                    font.family: "DejaVu Sans Mono"
                    font.pointSize: 8
                    wrapMode: TextEdit.Wrap
                }
            }
        }
    }

    // ================= Protocol =================

    function sendCmd(str) {
        mCommands.sendCustomAppData(str + "\0")   // null-terminate for lisp
    }

    function log(s) {
        logArea.text += s + "\n"
        // Without this the newest line (notably the device's ACK/ERR SAVE reply,
        // which arrives after saveAll's own message) scrolls out of view and the
        // panel looks as though the device never answered.
        logArea.cursorPosition = logArea.length
    }

    // ---- paced command queue -------------------------------------------------
    //
    // Custom app data reaches the script through lbm_event(), which SILENTLY
    // DROPS the message when the event handler's mailbox is fuller than the
    // event queue (eval_cps.c: lbm_event). The same mailbox carries every
    // event-can-eid frame -- six status messages at up to 50 Hz -- so firing
    // 12 SETs and a SAVE back-to-back reliably lost the tail of the burst.
    // Symptom: the SETs applied (RAM), SAVE vanished with no reply, and nothing
    // ever reached EEPROM.
    //
    // So: send one command per tick, and do not consider a save done until the
    // device acknowledges it. Re-send SAVE if it goes unanswered.

    property var cmdQueue: []
    property int saveTries: 0
    readonly property int maxSaveTries: 5

    Timer {                      // drains cmdQueue, one command per tick
        id: sendTimer
        interval: 60
        repeat: true
        onTriggered: {
            if (root.cmdQueue.length === 0) { sendTimer.stop(); return }
            var c = root.cmdQueue.shift()
            sendCmd(c)
            if (c === "SAVE") saveWatchdog.restart()
        }
    }

    Timer {                      // SAVE unanswered -> assume dropped, retry
        id: saveWatchdog
        interval: 1500
        repeat: false
        onTriggered: {
            if (root.saveTries < root.maxSaveTries) {
                root.saveTries++
                log("No reply to SAVE (likely dropped) - retry " + root.saveTries
                    + "/" + root.maxSaveTries)
                root.cmdQueue.push("SAVE")
                sendTimer.start()
            } else {
                log("SAVE failed: device never acknowledged after "
                    + root.maxSaveTries + " attempts.")
                stSave.text = "FAILED - no reply from device"
            }
        }
    }

    function queueCmds(list) {
        for (var i = 0; i < list.length; i++) root.cmdQueue.push(list[i])
        sendTimer.start()
    }

    function saveAll() {
        // no wifi_ssid / wifi_pass: WiFi lives in the Express firmware config
        root.saveTries = 0
        stSave.text = "saving..."
        queueCmds([
            "SET mqtt_host " + fHost.text,
            "SET mqtt_port " + fPort.text,
            "SET mqtt_user " + fUser.text,
            "SET mqtt_pass " + fMqttPass.text,
            "SET topic_prefix " + fPrefix.text,
            "SET pub_mode " + fMode.currentText,
            "SET pub_interval " + fInterval.text,
            "SET keepalive " + fKeepalive.text,
            "SET can_mode " + fCanMode.currentText,
            "SET vesc_id " + fVescId.text,
            "SET speed_div " + fSpeedDiv.text,
            "SET torque_k " + fTorqueK.text,
            "SAVE"
        ])
        log("Save queued (" + root.cmdQueue.length + " commands)...")
    }

    // Parse a "TYPE\nk=v\nk=v..." reply into a JS object of key->value.
    function parseKv(str) {
        var o = {}
        var lines = str.split("\n")
        for (var i = 1; i < lines.length; i++) {   // line 0 is the type token
            var line = lines[i]
            if (line.length === 0) continue
            var eq = line.indexOf("=")              // split on FIRST '=' only
            if (eq < 0) continue
            o[line.substring(0, eq)] = line.substring(eq + 1)
        }
        return o
    }

    function applyCfg(str) {
        var c = parseKv(str)
        if ("mqtt_host" in c)    fHost.text = c.mqtt_host
        if ("mqtt_port" in c)    fPort.text = c.mqtt_port
        if ("mqtt_user" in c)    fUser.text = c.mqtt_user
        if ("mqtt_pass" in c)    fMqttPass.text = c.mqtt_pass
        if ("topic_prefix" in c) fPrefix.text = c.topic_prefix
        if ("pub_mode" in c)     fMode.currentIndex = Math.max(0, fMode.model.indexOf(c.pub_mode))
        if ("pub_interval" in c) fInterval.text = c.pub_interval
        if ("keepalive" in c)    fKeepalive.text = c.keepalive
        if ("can_mode" in c)     fCanMode.currentIndex = Math.max(0, fCanMode.model.indexOf(c.can_mode))
        if ("vesc_id" in c)      fVescId.text = c.vesc_id
        if ("speed_div" in c)    fSpeedDiv.text = c.speed_div
        if ("torque_k" in c)     fTorqueK.text = c.torque_k
    }

    function applyTel(str) {
        var t = parseKv(str)
        if ("wifi_state" in t)   stWifi.text = t.wifi_state
        if ("mqtt_state" in t)   stMqtt.text = t.mqtt_state + (("mqtt_err" in t && t.mqtt_err !== "none") ? "  [" + t.mqtt_err + "]" : "")
        if ("can_frames" in t)   stFrames.text = t.can_frames
        if ("motor_speed" in t)  stSpeed.text = t.motor_speed
        if ("motor_torque" in t) stTorque.text = t.motor_torque
        if ("v_in" in t)         stVin.text = t.v_in
        if ("temp_fet" in t)     stTemp.text = t.temp_fet + " / " + (("temp_motor" in t) ? t.temp_motor : "-")
        if ("current_in" in t)   stCurr.text = t.current_in
        if ("cfg_src" in t)      stSrc.text = t.cfg_src === "eeprom" ? "EEPROM (saved)" : "DEFAULTS (nothing saved)"
        if ("pkg_ver" in t)      stVer.text = t.pkg_ver
    }

    Connections {
        target: mCommands

        function onCustomAppDataReceived(data) {
            var str = data.toString()
            if (str.startsWith("CFG"))       applyCfg(str)
            else if (str.startsWith("TEL"))  applyTel(str)
            else if (str.startsWith("DETECT")) {
                // Reply forms: "DETECT 111", "DETECT 1,2,3", "DETECT none", "DETECT sim".
                // Only a numeric node id may reach the VESC ID field. In sim mode the
                // device answers "sim"; writing that into the field made Save & Apply
                // send "SET vesc_id sim", which the device parsed as 0 and stored.
                var rest = str.substring(6).replace(/\0/g, "").trim()
                log("Detect: " + (rest.length > 0 ? rest : "(empty reply)"))
                var first = rest.split(",")[0].trim()
                if (/^[0-9]+$/.test(first)) {
                    var id = parseInt(first, 10)
                    if (id >= 0 && id <= 254) fVescId.text = String(id)
                    else log("Detect: ignoring out-of-range id " + first)
                } else if (rest.length > 0 && rest !== "none" && rest !== "sim") {
                    log("Detect: ignoring non-numeric reply \"" + rest + "\"")
                }
            }
            // "ACK SET <key>" is frequent during a save and stays quiet, but the
            // one-shot "ACK SAVE" is the only proof the EEPROM record was written
            // and verified. Never hide it.
            else if (str.startsWith("ACK SAVE")) {
                saveWatchdog.stop()
                log("Saved to EEPROM and verified.")
                stSave.text = "OK - written and verified"
                // Re-read what the device actually stored. A SET may itself have
                // been dropped, in which case the panel would otherwise keep
                // showing the typed value rather than the saved one.
                root.cmdQueue.push("GET")
                sendTimer.start()
            }
            else if (str.startsWith("ACK"))  { /* quiet: acks are frequent during save */ }
            else if (str.startsWith("ERR")) {
                log(str)
                if (str.startsWith("ERR SAVE")) {
                    saveWatchdog.stop()
                    stSave.text = str.substring(4)
                }
            }
            else if (str.startsWith("TEST")) {
                log(str)
                VescIf.emitMessageDialog("Test Connection", str, true, false)
            } else {
                log(str)
            }
        }
    }
}
