/*
    Copyright 2026 Jeremy Maddox

    This file is part of the VESC Package VL Link Status.

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program. If not, see <http://www.gnu.org/licenses/>.
    */

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.3
import QtQuick.Controls.Material 2.2
import Vedder.vesc.utility 1.0
import Vedder.vesc.commands 1.0

Item {
    id: appPage
    anchors.fill: parent
    anchors.margins: 10

    property Commands mCommands: VescIf.commands()

    // --- state pushed up from the lisp -----------------------------------
    property bool haveData: false
    property bool canOk:    false
    property int  canCount: 0
    property int  canFirst: -1
    property bool modemOn:  false
    property bool modemRdy: false
    property bool simOk:    false
    property bool netAtt:   false
    property int  rssi:     -999
    property real vin:      -1
    property bool sdOk:     false
    property bool logging:  false
    property int  logFields: 0
    property string carrier: ""
    property real logRate:   10.0
    property bool logLte:    true
    property bool logAtBoot: false
    property bool smsOn:     false
    property int  nPending:  0
    property string ownerNum: ""
    property bool guardOn:   false
    property int  lockState: -1
    property real tripKm:    0
    property real tripWh:    0
    property real battPct:   -1

    // Cloud / MQTT. mqttLast mirrors the lisp side:
    //   0 idle  1 published  2 publish failed  3 connect failed  4 no context
    property bool mqttOn:    false
    property bool mqttUp:    false
    property int  mqttLast:  0
    property int  mqttAge:   -1
    property string apnStr:    ""
    property string hostStr:   ""
    property string portStr:   "1883"
    property string userStr:   ""
    property string passStr:   ""
    property string clientStr: ""
    property string topicStr:  ""
    property int  mqttInt:   60

    // Where the firmware writes logs. Paths are relative to file_basepath.
    readonly property string logDir: "/log_can"

    readonly property color colGreen:  Utility.getAppHexColor("green")
    readonly property color colOrange: Utility.getAppHexColor("orange")
    readonly property color colRed:    Utility.getAppHexColor("red")
    readonly property color colDim:    Utility.getAppHexColor("disabledText")
    readonly property color colText:   Utility.getAppHexColor("lightText")
    readonly property color colCard:   Utility.getAppHexColor("lightBackground")

    function canDotColor() {
        if (!haveData) return colDim
        return canOk ? colGreen : colRed
    }

    function canLine() {
        if (!haveData) return "Waiting for device"
        if (!canOk) return "No nodes found"
        var s = canCount + (canCount === 1 ? " node" : " nodes") + "  \u00b7  ID " + canFirst
        if (vin > 0) s += "  \u00b7  " + vin.toFixed(1) + " V"
        if (battPct >= 0) s += "  \u00b7  " + battPct.toFixed(0) + " %"
        return s
    }

    function lteDotColor() {
        if (!haveData || !modemOn) return colDim
        if (netAtt) return colGreen
        if (simOk) return colOrange
        return colRed
    }

    function lteLine() {
        if (!haveData) return "Waiting for device"
        if (!modemOn) return "Modem off"
        if (!modemRdy) return "Starting up"
        if (!simOk) return "No SIM"
        if (!netAtt) return "Searching for network"
        var s = carrier.length > 0 ? carrier : "Registered"
        if (rssi > -900) s += "  \u00b7  " + rssi + " dBm"
        return s
    }

    // 0-5 bars. Below -110 dBm is unusable, above -70 is full scale.
    function sigBars() {
        if (!haveData || !modemRdy || rssi <= -900) return 0
        if (rssi >= -70)  return 5
        if (rssi >= -80)  return 4
        if (rssi >= -90)  return 3
        if (rssi >= -100) return 2
        if (rssi >= -110) return 1
        return 0
    }

    function sdDotColor() {
        if (!haveData) return colDim
        if (!sdOk) return colRed
        return logging ? colGreen : colOrange
    }

    function sdLine() {
        if (!haveData) return "Waiting for device"
        if (!sdOk) return "No card"
        if (logging) return "Recording  \u00b7  " + logFields + " fields @ " + logRate.toFixed(0) + " Hz"
        return "Card ready  \u00b7  idle"
    }

    function cloudDotColor() {
        if (!haveData || !mqttOn) return colDim
        if (mqttUp && mqttLast === 1) return colGreen
        if (mqttUp) return colOrange
        // Amber, not red, while an attempt is pending. Red is for a
        // verdict that came back, not for work still in progress.
        if (mqttLast === 0) return colOrange
        return colRed
    }

    function cloudLine() {
        if (!haveData) return "Waiting for device"
        if (!mqttOn) return "Off"
        if (!netAtt) return "Waiting for the network"
        if (!mqttUp) {
            // A failure code only means something once an attempt has
            // actually finished and lost. While one is in flight the code
            // still holds the PREVIOUS verdict, and reporting that reads
            // as a hard error during what is really just a slow startup --
            // the modem needs ten to twenty seconds to attach before the
            // first connect can even be tried.
            if (mqttLast === 0) return "Connecting to " + hostStr
            // Past that, distinguish the two failures that look identical
            // from outside: no data context is an APN or plan problem, a
            // refusal is credentials or the wrong host.
            if (mqttLast === 4) return "No data context \u00b7 check APN"
            if (mqttLast === 3) return "Broker refused \u00b7 retrying"
            return "Connecting to " + hostStr
        }
        var s = "Connected \u00b7 " + hostStr
        if (mqttLast === 2) return "Connected \u00b7 last publish failed"
        if (mqttAge >= 0) s += "  \u00b7  sent " + mqttAge + " s ago"
        else s += "  \u00b7  no sample yet"
        return s
    }

    // Strings are pasted into a lisp form on the device, which is read
    // back with (read data). Only the quote and the backslash can break
    // out of a string literal there; parentheses inside one are harmless.
    function lispStr(str) {
        // split/join rather than a regex: a character class containing a
        // quote is a reliable way to confuse every QML syntax highlighter
        // and half the linters, for no gain over this.
        return str.split("\"").join("")
                  .split("\\").join("")
                  .replace(/[\x00-\x1f]/g, "")
                  .trim()
    }

    // Assign, do not bind. `text: userStr` looks equivalent but a QML
    // binding is destroyed the first time the user types into the field,
    // and after that the device's own value can never get back in. The
    // field then reads empty on the next connection while the device still
    // holds a good token -- and Save writes that emptiness back over it.
    // Skipped while the field has focus so it cannot yank text out from
    // under someone mid-edit.
    function setField(f, v) {
        // Never while a save is in flight. The device is mid-update, so
        // anything it echoes back is the OLD configuration and writing it
        // into the field would clobber what is being sent.
        if (saveStep >= 0) {
            return
        }
        if (f && !f.activeFocus && f.text !== v) {
            f.text = v
        }
    }

    function sendCode(str) {
        // Append the null so the lisp side reads a terminated string
        mCommands.sendCustomAppData(str + "\0")
    }

    // Saving sends five forms. Fired back to back over BLE they can arrive
    // faster than the device evaluates them and one gets dropped, so they
    // go out one per tick.
    //
    // Driven by an integer step and not by a queue array. A JavaScript
    // array in a `property var` is not reliably written back after being
    // mutated in place -- push() can land on a copy, leaving the queue
    // permanently empty and every form silently discarded. An int property
    // has no such ambiguity.
    property int saveStep: -1

    // Snapshot every field at the moment Save is pressed.
    //
    // The forms go out one per timer tick, so reading the fields as each
    // tick fires leaves a window of several hundred milliseconds where a
    // cf frame can arrive and setField can overwrite what was just typed
    // -- the field is no longer focused, because pressing Save took focus
    // away from it. The symptom is typing a new token and watching the old
    // one get saved instead.
    property string sHost: ""
    property string sPort: ""
    property string sUser: ""
    property string sPass: ""
    property string sClient: ""
    property string sTopic: ""
    property string sApn: ""
    property string sNum: ""
    property int sRate: 10
    property bool sLte: false
    property bool sBoot: false
    property bool sSms: false
    property bool sMqtt: false
    property int sInt: 60

    function saveSettings() {
        sHost   = lispStr(hostField.text)
        sPort   = portField.text
        sUser   = lispStr(userField.text)
        sPass   = lispStr(passField.text)
        sClient = lispStr(clientField.text)
        sTopic  = lispStr(topicField.text)
        sApn    = lispStr(apnField.text)
        sNum    = numField.text.replace(/[^0-9]/g, "")
        sRate   = rateBox.rates[rateBox.currentIndex]
        sLte    = lteBox.checked
        sBoot   = bootBox.checked
        sSms    = smsBox.checked
        sMqtt   = mqttBox.checked
        sInt    = Math.round(intSlider.value)
        saveStep = 0
        saveTimer.running = true
    }

    function saveForm(n) {
        switch (n) {
        case 0:
            return "(cfg " + sRate + ".0 " + (sLte ? "1" : "0") + " " +
                   (sBoot ? "1" : "0") + ")"
        case 1:
            return "(sms-cfg \"" + sNum + "\" " + (sSms ? "1" : "0") + ")"
        // Broker details before the enable, so the modem thread never
        // picks up a reconnect against a half-updated configuration.
        case 2:
            return "(mqtt-broker \"" + sHost + "\" " +
                   (parseInt(sPort) > 0 ? parseInt(sPort) : 1883) + " \"" +
                   sUser + "\" \"" + sPass + "\")"
        case 3:
            return "(mqtt-ident \"" + sClient + "\" \"" + sTopic +
                   "\" \"" + sApn + "\")"
        case 4:
            return "(mqtt-set " + (sMqtt ? "1" : "0") + " " + sInt + ")"
        }
        return ""
    }

    Timer {
        id: saveTimer
        // 500 ms, not 150. Status frames go up every second and cf frames
        // come back in bursts; five forms fired 150 ms apart into that
        // shared the link badly enough that the longest ones -- the broker
        // and ident forms, at 68 and 50 bytes against 15 for the others --
        // were the ones that went missing.
        interval: 500
        repeat: true
        running: false
        onTriggered: {
            if (saveStep < 0 || saveStep > 4) {
                running = false
                saveStep = -1
                // Read the whole configuration back rather than trusting
                // that it landed. The fields repopulate from the device,
                // so anything that did not arrive is visible immediately.
                sendCode("(ui-sync)")
                return
            }
            sendCode(saveForm(saveStep))
            saveStep = saveStep + 1
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        TabBar {
            id: tabBar
            Layout.fillWidth: true
            TabButton { text: "Status" }
            TabButton { text: "Logs" }
            TabButton { text: nPending > 0 ? "Access (" + nPending + ")" : "Access" }
            TabButton { text: "Settings" }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

            // ================= STATUS =================
            ColumnLayout {
                spacing: 10

                // ---- CAN ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 78
                    radius: 6
                    color: colCard

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 14

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 16; height: 16; radius: 8
                            color: canDotColor()
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: "CAN Bus"
                                color: colText
                                font.pixelSize: 17
                                font.bold: true
                            }

                            Text {
                                Layout.fillWidth: true
                                text: canLine()
                                color: colDim
                                font.pixelSize: 14
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // ---- LTE ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 78
                    radius: 6
                    color: colCard

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 14

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 16; height: 16; radius: 8
                            color: lteDotColor()
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: "LTE"
                                color: colText
                                font.pixelSize: 17
                                font.bold: true
                            }

                            Text {
                                Layout.fillWidth: true
                                text: lteLine()
                                color: colDim
                                font.pixelSize: 14
                                elide: Text.ElideRight
                            }
                        }

                        // Signal meter. Row sets x only, so each bar is
                        // pushed to a common baseline by hand.
                        Row {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 3

                            Repeater {
                                model: 5
                                Rectangle {
                                    width: 5
                                    radius: 1
                                    height: 6 + index * 4
                                    y: 22 - height
                                    color: index < sigBars() ? lteDotColor() : colDim
                                    opacity: index < sigBars() ? 1.0 : 0.25
                                }
                            }
                        }
                    }
                }

                // ---- Storage ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 78
                    radius: 6
                    color: colCard

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 14

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 16; height: 16; radius: 8
                            color: sdDotColor()
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: "Storage"
                                color: colText
                                font.pixelSize: 17
                                font.bold: true
                            }

                            Text {
                                Layout.fillWidth: true
                                text: sdLine()
                                color: colDim
                                font.pixelSize: 14
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // ---- Cloud ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 78
                    radius: 6
                    color: colCard

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 14

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 16; height: 16; radius: 8
                            color: cloudDotColor()
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: "Cloud"
                                color: colText
                                font.pixelSize: 17
                                font.bold: true
                            }

                            Text {
                                Layout.fillWidth: true
                                text: cloudLine()
                                color: colDim
                                font.pixelSize: 14
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            visible: mqttOn && mqttUp
                            text: mqttInt + " s"
                            color: colDim
                            font.pixelSize: 13
                        }
                    }
                }

                // ---- Trip ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 78
                    radius: 6
                    color: colCard

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 14

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 16; height: 16; radius: 8
                            color: lockState === 1 ? colRed
                                   : (lockState < 0 ? colOrange
                                                    : (guardOn ? colOrange : colDim))
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: "Trip"
                                color: colText
                                font.pixelSize: 17
                                font.bold: true
                            }

                            Text {
                                Layout.fillWidth: true
                                text: !haveData ? "Waiting for device"
                                      : tripKm.toFixed(2) + " km  \u00b7  " +
                                        tripWh.toFixed(0) + " Wh" +
                                        (tripKm > 0.05
                                            ? "  \u00b7  " + (tripWh / tripKm).toFixed(0) + " Wh/km"
                                            : "") +
                                        (lockState === 1 ? "  \u00b7  LOCKED"
                                            : lockState < 0 ? "  \u00b7  lock unknown" : "") +
                                        (guardOn ? "  \u00b7  guarded" : "")
                                color: colDim
                                font.pixelSize: 14
                                elide: Text.ElideRight
                            }
                        }

                        Button {
                            text: "Reset"
                            implicitHeight: 40
                            enabled: VescIf.isPortConnected()
                            onClicked: sendCode("(trip-reset)")
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Button {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        text: guardOn ? "Guard On" : "Guard Off"
                        enabled: VescIf.isPortConnected()
                        onClicked: sendCode("(guard-set " + (guardOn ? "0" : "1") + ")")
                    }

                    Button {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        text: lockState === 1 ? "Unlock" : "Lock"
                        enabled: VescIf.isPortConnected() && canOk
                        onClicked: sendCode("(lock-set " + (lockState === 1 ? "0" : "1") + ")")
                    }
                }

                Button {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    text: logging ? "Stop Logging" : "Start Logging"
                    enabled: VescIf.isPortConnected() && sdOk
                    onClicked: sendCode(logging ? "(log-end)" : "(log-begin)")
                }

                Button {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    text: "Rescan CAN Bus"
                    enabled: VescIf.isPortConnected()
                    onClicked: {
                        sendCode("(rescan)")
                        VescIf.emitStatusMessage("Scanning CAN bus...", true)
                    }
                }
            }

            // ================= LOGS =================
            ColumnLayout {
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Tap Open to load a log into the log analysis view."
                    color: colDim
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }

                // Above the list, not below it. The list grows with the
                // card contents, and a control underneath it ends up off
                // the bottom of the pane on a short window -- the same way
                // the Save button did in Settings.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Button {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        text: "Refresh"
                        enabled: VescIf.isPortConnected() && !busy.running
                        onClicked: refreshFiles()
                    }

                    Button {
                        Layout.preferredHeight: 48
                        text: "Cancel"
                        visible: busy.running
                        onClicked: mCommands.fileBlockCancel()
                    }
                }

                ListView {
                    id: fileList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 6
                    model: ListModel { id: fileModel }

                    delegate: Rectangle {
                        width: fileList.width
                        height: 56
                        radius: 6
                        color: colCard

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            spacing: 8

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: model.name
                                    color: colText
                                    font.pixelSize: 15
                                    elide: Text.ElideMiddle
                                }

                                Text {
                                    text: (model.size / 1024).toFixed(1) + " kB"
                                    color: colDim
                                    font.pixelSize: 12
                                }
                            }

                            Button {
                                text: "Open"
                                implicitHeight: 40
                                enabled: !busy.running
                                onClicked: openLog(model.name)
                            }

                            Button {
                                text: "\u00d7"
                                implicitWidth: 44
                                implicitHeight: 40
                                enabled: !busy.running
                                onClicked: removeLog(model.name)
                            }
                        }
                    }
                }

                ProgressBar {
                    id: dlProgress
                    Layout.fillWidth: true
                    visible: busy.running
                    from: 0
                    to: 100
                    value: 0
                }

                Text {
                    Layout.fillWidth: true
                    visible: busy.running
                    text: dlProgress.value.toFixed(0) + " %"
                    color: colDim
                    font.pixelSize: 12
                }

            }
            // ================= ACCESS =================
            // ScrollView because this pane grows with the roster and will
            // not fit a phone screen once a few members are added.
            //
            // Left as a direct child of the tab. Wrapping it in a
            // ColumnLayout to pin a button outside the scroll area makes
            // the ScrollView's width depend on its content's implicit
            // width, which depends back on the ScrollView -- a binding
            // loop QML resolves by zeroing something, and the pane comes
            // up broken. Refresh goes first INSIDE the column instead.
            ScrollView {
                id: accessScroll
                clip: true
                contentWidth: availableWidth
                contentHeight: accCol.implicitHeight + 120

            ColumnLayout {
                id: accCol
                width: accessScroll.availableWidth
                spacing: 8

                Button {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    text: "Refresh"
                    enabled: VescIf.isPortConnected()
                    onClicked: sendCode("(ui-sync)")
                }

                Text {
                    Layout.fillWidth: true
                    text: smsOn
                          ? "Unknown numbers that text the Link appear here for approval."
                          : "SMS control is off. Enable it in Settings."
                    color: colDim
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }

                Text {
                    Layout.fillWidth: true
                    visible: pendingModel.count > 0
                    text: "Requests"
                    color: colText
                    font.pixelSize: 15
                    font.bold: true
                }

                Repeater {
                    model: ListModel { id: pendingModel }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 56
                        radius: 6
                        color: colCard

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            spacing: 8

                            Rectangle {
                                width: 10; height: 10; radius: 5
                                color: colOrange
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "+" + model.num
                                color: colText
                                font.pixelSize: 15
                                elide: Text.ElideRight
                            }

                            Button {
                                text: "Allow"
                                implicitHeight: 40
                                onClicked: sendCode("(member-approve \"" + model.num + "\")")
                            }

                            Button {
                                text: "Deny"
                                implicitHeight: 40
                                onClicked: sendCode("(member-deny \"" + model.num + "\")")
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "Members"
                    color: colText
                    font.pixelSize: 15
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    visible: memberModel.count === 0
                    text: "None yet."
                    color: colDim
                    font.pixelSize: 13
                }

                Repeater {
                    model: ListModel { id: memberModel }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 56
                        radius: 6
                        color: colCard

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: "+" + model.num
                                color: model.en ? colText : colDim
                                font.pixelSize: 15
                                elide: Text.ElideRight
                            }

                            Switch {
                                checked: model.en
                                onToggled: sendCode("(member-set " + model.slot +
                                                    " " + (checked ? "1" : "0") + ")")
                            }

                            Button {
                                text: "\u00d7"
                                implicitWidth: 44
                                implicitHeight: 40
                                onClicked: sendCode("(member-del " + model.slot + ")")
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 8 }

                Text {
                    Layout.fillWidth: true
                    text: "Lock is latched by a package on the controller, not held " +
                          "by this one. Nothing is reported as locked until the " +
                          "controller confirms it \u2014 \"unknown\" means no reply " +
                          "came back, so treat the vehicle as unlocked."
                    color: colDim
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }

            }
            }

            // ================= SETTINGS =================
            // Flickable + Column, deliberately, not ScrollView +
            // ColumnLayout.
            //
            // A ColumnLayout computes its implicitHeight from its children
            // at their IMPLICIT widths, and a word-wrapping Text at its
            // implicit width is one long line exactly one line tall. A
            // paragraph that renders four lines deep is therefore counted
            // as one, the pane under-reports its own height by hundreds of
            // pixels, and the bottom of it becomes unreachable. A Column
            // instead stacks children at their ACTUAL heights, so
            // contentHeight is simply the Column's height and there is
            // nothing left to infer.
            //
            // Save sits outside the Flickable. It is the one control that
            // must never be unreachable.
            ColumnLayout {
                spacing: 8

                // At the TOP, not the bottom.
                //
                // A save button below a scrolling pane is only reachable
                // if the pane fits the window, and this one does not on
                // every screen -- the content is simply taller than VESC
                // Tool gives the tab, so the button ends up off the bottom
                // edge where no amount of scrolling reaches it. Above the
                // scroll area it is always on screen by construction.
                Button {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    text: saveStep < 0 ? "Save Settings" : "Saving..."
                    enabled: VescIf.isPortConnected() && saveStep < 0
                    onClicked: {
                        if (mqttBox.checked && lispStr(userField.text) === "") {
                            VescIf.emitStatusMessage(
                                "Cloud telemetry needs a token in the username field",
                                false)
                            return
                        }
                        saveSettings()
                        VescIf.emitStatusMessage("Saving settings...", true)
                    }
                }

                Flickable {
                    id: setFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    // Zeroed preferred height, because a scrollable item
                    // otherwise asks the layout for its whole content
                    // height and squeezes the Save button off the pane.
                    Layout.preferredHeight: 0
                    Layout.minimumHeight: 0
                    clip: true
                    contentWidth: width
                    contentHeight: setCol.height
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {
                        policy: setFlick.contentHeight > setFlick.height
                                ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                    }

                    Column {
                        id: setCol
                        width: setFlick.width
                        spacing: 14

                        Text {
                            width: parent.width
                            text: "Saved to the device. Applies to the next recording."
                            color: colDim
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                        }

                        Row {
                            width: parent.width
                            spacing: 10

                            Text {
                                text: "Log rate"
                                color: colText
                                font.pixelSize: 15
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Item {
                                width: parent.width - 150 - parent.spacing
                                height: 1
                            }

                            ComboBox {
                                id: rateBox
                                width: 140
                                model: ["1 Hz", "5 Hz", "10 Hz", "20 Hz", "50 Hz"]
                                property var rates: [1, 5, 10, 20, 50]
                                currentIndex: {
                                    var i = rates.indexOf(Math.round(logRate))
                                    return i < 0 ? 2 : i
                                }
                            }
                        }

                        Switch {
                            id: lteBox
                            width: parent.width
                            text: "Log LTE signal and attach state"
                            checked: logLte
                        }

                        Switch {
                            id: bootBox
                            width: parent.width
                            text: "Start logging automatically"
                            checked: logAtBoot
                        }

                        Text {
                            width: parent.width
                            visible: bootBox.checked
                            text: "Waits up to 60 s for a CAN node. No shutdown event " +
                                  "exists on this hardware, so stop logging before " +
                                  "cutting power or the file tail may be lost."
                            color: colDim
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: colDim
                            opacity: 0.3
                        }

                        Switch {
                            id: smsBox
                            width: parent.width
                            text: "SMS control"
                            checked: smsOn
                        }

                        Column {
                            width: parent.width
                            visible: smsBox.checked
                            spacing: 4

                            TextField {
                                id: numField
                                width: parent.width
                                placeholderText: "Allowed number, e.g. +15551234567"
                                inputMethodHints: Qt.ImhDialableCharactersOnly
                                text: ownerNum
                            }

                            Text {
                                width: parent.width
                                text: "Approved numbers only, matched on the last 10 " +
                                      "digits. Read-only by design \u2014 caller ID is " +
                                      "forgeable, so nothing here moves the vehicle."
                                color: colDim
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: colDim
                            opacity: 0.3
                        }

                        Switch {
                            id: mqttBox
                            width: parent.width
                            text: "Cloud telemetry (MQTT)"
                            checked: mqttOn
                        }

                        Column {
                            width: parent.width
                            visible: mqttBox.checked
                            spacing: 8

                            TextField {
                                id: hostField
                                width: parent.width
                                placeholderText: "Broker host, e.g. mqtt.thingsboard.cloud"
                                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                            }

                            Row {
                                width: parent.width
                                spacing: 10

                                Text {
                                    text: "Port"
                                    color: colText
                                    font.pixelSize: 15
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Item {
                                    width: parent.width - 110 - 40 - parent.spacing
                                    height: 1
                                }

                                TextField {
                                    id: portField
                                    width: 110
                                    placeholderText: "1883"
                                    inputMethodHints: Qt.ImhDigitsOnly
                                }
                            }

                            TextField {
                                id: userField
                                width: parent.width
                                placeholderText: "Username / ThingsBoard access token"
                                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                            }

                            TextField {
                                id: passField
                                width: parent.width
                                placeholderText: "Password (blank for ThingsBoard)"
                                echoMode: TextInput.Password
                                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                            }

                            TextField {
                                id: clientField
                                width: parent.width
                                placeholderText: "Client ID"
                                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                            }

                            TextField {
                                id: topicField
                                width: parent.width
                                placeholderText: "Topic"
                                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                            }

                            TextField {
                                id: apnField
                                width: parent.width
                                placeholderText: "APN (leave blank to use the network's)"
                                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                            }

                            Row {
                                width: parent.width

                                Text {
                                    text: "Publish every"
                                    color: colText
                                    font.pixelSize: 15
                                }

                                Item {
                                    width: parent.width - 200
                                    height: 1
                                }

                                Text {
                                    text: Math.round(intSlider.value) + " s"
                                    color: colText
                                    font.pixelSize: 15
                                    font.bold: true
                                }
                            }

                            Slider {
                                id: intSlider
                                width: parent.width
                                from: 15
                                to: 600
                                stepSize: 15
                                value: mqttInt
                            }

                            Text {
                                width: parent.width
                                text: "A floor, not a guarantee: connecting costs a " +
                                      "handshake of ten seconds or more on Cat-M1. " +
                                      "Each sample is a few hundred bytes."
                                color: colDim
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                width: parent.width
                                text: "Plain TCP, not TLS \u2014 the SIM7070G's TLS " +
                                      "stack is not reachable through these commands. " +
                                      "Use a token scoped to this device only."
                                color: colOrange
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }
                        }

                        Item { width: 1; height: 8 }
                    }
                }

            }
        }
    }

    // Drives the progress bar while a blocking transfer runs. fileBlockRead
    // spins its own event loop, so this keeps ticking during the transfer.
    Timer {
        id: busy
        interval: 200
        repeat: true
        running: false
        onTriggered: dlProgress.value = mCommands.getFilePercentage()
    }

    function refreshFiles() {
        fileModel.clear()
        var files = mCommands.fileBlockList(logDir)
        if (!files || files.length === 0) {
            VescIf.emitStatusMessage("No logs found in " + logDir, false)
            return
        }
        for (var i = 0; i < files.length; i++) {
            if (files[i].isDir) {
                continue
            }
            fileModel.append({ "name": files[i].name, "size": files[i].size })
        }
    }

    function openLog(name) {
        busy.running = true
        dlProgress.value = 0

        var data = mCommands.fileBlockRead(logDir + "/" + name)

        busy.running = false

        if (!data || data.length === 0) {
            VescIf.emitStatusMessage("Could not read " + name, false)
            return
        }

        // Hands the bytes straight to VESC Tool's log analysis view. This is
        // what makes logs usable on mobile, where there is no file browser
        // and nowhere to save a file to.
        if (VescIf.loadRtLogFile(data)) {
            VescIf.emitStatusMessage("Loaded " + name, true)
        } else {
            VescIf.emitStatusMessage("Could not parse " + name, false)
        }
    }

    function removeLog(name) {
        if (mCommands.fileBlockRemove(logDir + "/" + name)) {
            VescIf.emitStatusMessage("Deleted " + name, true)
            refreshFiles()
        } else {
            VescIf.emitStatusMessage("Could not delete " + name, false)
        }
    }

    Connections {
        target: mCommands

        function onCustomAppDataReceived(data) {
            var str = data.toString().replace(/\0/g, "").trim()

            // Roster arrives as its own short frames because it will not
            // fit inside the 100 byte status frame.
            if (str.startsWith("mb ")) {
                var m = str.split(/\s+/)
                if (m.length < 4) return
                var slot = parseInt(m[1])
                if (slot === 0) {
                    memberModel.clear()
                    pendingModel.clear()
                    ownerNum = m[2] === "-" ? "" : m[2]
                } else if (m[2] !== "-") {
                    memberModel.append({ "slot": slot,
                                         "num": m[2],
                                         "en": m[3] === "1" })
                }
                return
            }

            if (str.startsWith("pd ")) {
                pendingModel.append({ "num": str.substring(3).trim() })
                return
            }

            // MQTT configuration, one frame per field. It cannot ride in
            // the status frame: a broker host or topic would blow the 100
            // byte budget, and "-" stands in for an empty value so the
            // frame never ends in a dangling separator.
            if (str.startsWith("cf ")) {
                var c = str.split(/\s+/)
                if (c.length < 3) return
                var v = c.slice(2).join(" ")
                if (v === "-") v = ""
                switch (parseInt(c[1])) {
                case 0: apnStr    = v; setField(apnField, v);    break
                case 1: hostStr   = v; setField(hostField, v);   break
                case 2: portStr   = v; setField(portField, v);   break
                case 3: userStr   = v; setField(userField, v);   break
                case 4: passStr   = v; setField(passField, v);   break
                case 5: clientStr = v; setField(clientField, v); break
                case 6: topicStr  = v; setField(topicField, v);  break
                case 7: mqttInt   = parseInt(v); break
                }
                return
            }

            if (str === "rx") {
                return
            }

            if (!str.startsWith("st ")) {
                return
            }

            var t = str.split(/\s+/)
            if (t.length < 15) {
                return
            }

            // Booleans arrive packed into one integer -- the device has a
            // 2560 cons cell heap and building eleven separate string
            // fragments once a second exhausted it.
            var f     = parseInt(t[1])
            canOk     = (f & 1) !== 0
            modemOn   = (f & 2) !== 0
            modemRdy  = (f & 4) !== 0
            simOk     = (f & 8) !== 0
            netAtt    = (f & 16) !== 0
            sdOk      = (f & 32) !== 0
            logging   = (f & 64) !== 0
            logLte    = (f & 128) !== 0
            logAtBoot = (f & 256) !== 0
            smsOn     = (f & 512) !== 0
            guardOn   = (f & 1024) !== 0
            mqttOn    = (f & 2048) !== 0
            mqttUp    = (f & 4096) !== 0

            canCount  = parseInt(t[2])
            canFirst  = parseInt(t[3])
            rssi      = parseInt(t[4])
            vin       = parseFloat(t[5])
            logFields = parseInt(t[6])
            logRate   = parseFloat(t[7])
            nPending  = parseInt(t[8])
            lockState = parseInt(t[9])
            tripKm    = parseFloat(t[10])
            tripWh    = parseFloat(t[11])
            battPct   = parseFloat(t[12])
            mqttLast  = parseInt(t[13])
            mqttAge   = parseInt(t[14])
            // Everything past index 14 is the carrier name, which may itself
            // contain spaces, so rejoin rather than taking a single token.
            carrier   = t.length > 15 ? t.slice(15).join(" ") : ""

            if (!haveData) {
                // First status frame: ask for the roster, which is not
                // broadcast on a timer the way status is.
                sendCode("(ui-sync)")
            }
            haveData  = true
        }
    }
}
