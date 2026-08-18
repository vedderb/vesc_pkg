// Settings page companion to code_esp.lisp (VESC Express).

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.3

import Vedder.vesc.utility 1.0
import Vedder.vesc.commands 1.0

Item {
    id: mainItem
    anchors.fill: parent

    property string tabTitle: "Bridge settings"

    property Commands mCommands: VescIf.commands()
    property color bgCard: Utility.getAppHexColor("lightBackground")
    property color colText: Utility.getAppHexColor("normalText")
    property color colTextDim: Utility.getAppHexColor("lightText")
    property color colAccent: Utility.getAppHexColor("vescGreenMedium")

    property real teleSpeed: 0
    property int teleMotorTemp: 0
    property real teleVoltage: 0
    property real teleCurrent: 0
    property int teleIndicator: 0
    property int teleRearLight: 0
    property int teleThrottle: 0
    property int teleBrake: 0
    property int teleHours: 0
    property int teleMinutes: 0
    property int teleSeconds: 0
    property int teleProfile: 0
    property int teleMode: 0
    property int teleUseOther: -1

    // Raw 0-255 from 0x100. The VESC side maps 200 to full scale 3.3 V, so
    // anything above 200 is already clipped by the time it reaches the ADC.
    function adcLabel(raw) {
        return raw + "  (" + (raw / 200.0 * 3.3).toFixed(2) + " V)"
    }

    // BMS clock. Reads 00:00:00 until the Segway app sets it -- it lives in
    // RAM only, so it restarts from zero on every reboot.
    function two(n) { return (n < 10 ? "0" : "") + n }
    function clockLabel() {
        return two(teleHours) + ":" + two(teleMinutes) + ":" + two(teleSeconds)
    }

    // Bitfield, not an enum -- bit 0 left, bit 1 right, bit 7 underglow.
    // Matches code_esp.lisp's apply-indicators.
    function indicatorLabel(b) {
        var left = (b & 0x01) !== 0
        var right = (b & 0x02) !== 0
        if (left && right) return "Hazard"
        if (left) return "Left"
        if (right) return "Right"
        return "Off"
    }

    // Variant-specific values, same grouping as code_esp.lisp's rear-* defines.
    function rearLightLabel(b) {
        if (b === 0x12) return "Charging"
        if (b === 0x14 || b === 0x44 || b === 0x54) return "On"
        if (b === 0x16 || b === 0x56) return "Brake"
        if (b === 0x18 || b === 0x48 || b === 0x58) return "Flashing brake"
        if (b === 0x64) return "XLight"
        return "Off"
    }

    // 0x203 byte 0. 0x04 is GT3-only and shares the Sport limit.
    function modeName(b) {
        if (b === 0x01) return "Walk"
        if (b === 0x02) return "Eco"
        if (b === 0x03) return "Sport"
        if (b === 0x04) return "Race"
        if (b === 0x05) return "Drive"
        if (b === 0x00) return "--"
        return "0x" + b.toString(16)
    }

    // cmd: 0x01 get, 0x02 set
    function buildSettingsBuffer(cmd) {
        var buffer = new ArrayBuffer(13)
        var dv = new DataView(buffer)
        dv.setUint8(0, cmd)
        dv.setUint8(1, disableProfSwSwitch.checked ? 1 : 0)
        dv.setUint8(2, freezeBattSwitch.checked ? 1 : 0)
        dv.setUint8(3, bmsModeCombo.currentIndex)
        dv.setUint8(4, bypassSpeedLimitSwitch.checked ? 1 : 0)
        dv.setUint8(5, underglowOnParkSwitch.checked ? 1 : 0)
        dv.setUint8(6, enableChargeLightSwitch.checked ? 1 : 0)
        dv.setUint8(7, externalAdcSwitch.checked ? 1 : 0)
        dv.setUint8(8, useOtherProfilesSwitch.checked ? 1 : 0)
        dv.setUint8(9, walkSpin.value)
        dv.setUint8(10, ecoSpin.value)
        dv.setUint8(11, driveSpin.value)
        dv.setUint8(12, sportSpin.value)
        return buffer
    }

    // Raw bytes of the last settings reply, so a repeated poll only touches a
    // control when Express's value actually changed. Comparing against the
    // control instead would stomp the rider's edit on the next poll.
    property var lastSettings: []

    function setIfChanged(dv, i, apply) {
        if (i >= dv.byteLength) {
            return
        }
        var v = dv.getUint8(i)
        if (lastSettings[i] !== v) {
            lastSettings[i] = v
            apply(v)
        }
    }

    // Background polls must not narrate. Without this the 2s poll would
    // overwrite "Saving..." before the rider ever saw it.
    property bool quietRequest: false

    function requestSettings(silent) {
        quietRequest = (silent === true)
        if (!quietRequest) {
            statusText.text = "Loading..."
        }
        mCommands.sendCustomAppData(buildSettingsBuffer(0x01))
    }

    function saveSettings() {
        quietRequest = false
        statusText.text = "Saving..."
        mCommands.sendCustomAppData(buildSettingsBuffer(0x02))
    }

    Connections {
        target: mCommands

        // tag: 0x01 settings reply, 0x03 telemetry
        function onCustomAppDataReceived(data) {
            var dv = new DataView(data)
            if (data.byteLength < 1) {
                return
            }
            var tag = dv.getUint8(0)

            if (tag === 0x01 && data.byteLength >= 5) {
                setIfChanged(dv, 1, function(v) { disableProfSwSwitch.checked = (v !== 0) })
                setIfChanged(dv, 2, function(v) { freezeBattSwitch.checked = (v !== 0) })
                setIfChanged(dv, 3, function(v) { bmsModeCombo.currentIndex = v })
                setIfChanged(dv, 4, function(v) { bypassSpeedLimitSwitch.checked = (v !== 0) })
                setIfChanged(dv, 5, function(v) { underglowOnParkSwitch.checked = (v !== 0) })
                setIfChanged(dv, 6, function(v) { enableChargeLightSwitch.checked = (v !== 0) })
                setIfChanged(dv, 7, function(v) { externalAdcSwitch.checked = (v !== 0) })
                setIfChanged(dv, 8, function(v) { useOtherProfilesSwitch.checked = (v !== 0) })
                setIfChanged(dv, 9, function(v) { walkSpin.value = v })
                setIfChanged(dv, 10, function(v) { ecoSpin.value = v })
                setIfChanged(dv, 11, function(v) { driveSpin.value = v })
                setIfChanged(dv, 12, function(v) { sportSpin.value = v })
                settingsLoaded = true
                if (!quietRequest) {
                    statusText.text = "Loaded from Express"
                }
            } else if (tag === 0x03 && data.byteLength >= 11) {
                teleSpeed = dv.getInt16(1, true) / 10.0
                teleMotorTemp = dv.getInt8(3)
                teleVoltage = dv.getUint16(4, true) / 10.0
                teleCurrent = dv.getInt16(6, true) / 10.0
                teleIndicator = dv.getUint8(8)
                teleRearLight = dv.getUint8(9)
                teleProfile = dv.getUint8(10)
                if (data.byteLength >= 18) {
                    teleThrottle = dv.getUint8(11)
                    teleBrake = dv.getUint8(12)
                    teleHours = dv.getUint8(13)
                    teleMinutes = dv.getUint8(14)
                    teleSeconds = dv.getUint8(15)
                    teleMode = dv.getUint8(16)
                    // Express clears this itself when the dashboard goes off,
                    // so follow it -- but only on an actual change, otherwise
                    // the 300ms telemetry would fight the switch while it is
                    // being toggled.
                    var uo = dv.getUint8(17)
                    if (uo !== teleUseOther) {
                        teleUseOther = uo
                        useOtherProfilesSwitch.checked = (uo !== 0)
                    }
                }
            }
        }
    }

    property bool settingsLoaded: false

    // Component.onCompleted fires once, and is lost if the script or the
    // connection isn't ready yet -- which is why the states only appeared
    // after pressing Reload. Poll instead: fast until the first reply lands,
    // then slowly, so externally-changed values keep flowing in.
    Timer {
        interval: settingsLoaded ? 2000 : 500
        repeat: true
        running: true
        onTriggered: requestSettings(true)
    }

    Component.onCompleted: requestSettings(false)
    onVisibleChanged: if (visible) requestSettings(true)

    Flickable {
        anchors.fill: parent
        contentHeight: pageColumn.height
        clip: true

        ColumnLayout {
            id: pageColumn
            width: parent.width
            spacing: 14

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 14
                Layout.bottomMargin: 0
                spacing: 4

                Text {
                    text: "VESC X3 Bridge"
                    color: colText
                    font.weight: Font.Black
                    font.pointSize: 20
                    Layout.fillWidth: true
                }

            }

            // Card: live status
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.preferredHeight: statusGrid.implicitHeight + 28
                radius: 10
                color: bgCard

                GridLayout {
                    id: statusGrid
                    anchors.fill: parent
                    anchors.margins: 14
                    columns: 2
                    columnSpacing: 16
                    rowSpacing: 10

                    Text { text: "Speed"; color: colTextDim; font.pointSize: 12; Layout.fillWidth: true }
                    Text { text: teleSpeed.toFixed(1) + " km/h"; color: colText; font.pointSize: 12; Layout.alignment: Qt.AlignRight }

                    Text { text: "Drive profile"; color: colTextDim; font.pointSize: 12; Layout.fillWidth: true }
                    Text { text: modeName(teleMode); color: colText; font.pointSize: 12; Layout.alignment: Qt.AlignRight }

                    Text { text: "Speed limit"; color: colTextDim; font.pointSize: 12; Layout.fillWidth: true }
                    Text { text: teleProfile + " km/h"; color: colText; font.pointSize: 12; Layout.alignment: Qt.AlignRight }

                    Text { text: "Motor temp"; color: colTextDim; font.pointSize: 12; Layout.fillWidth: true }
                    Text { text: teleMotorTemp + " °C"; color: colText; font.pointSize: 12; Layout.alignment: Qt.AlignRight }

                    Text { text: "Voltage"; color: colTextDim; font.pointSize: 12; Layout.fillWidth: true }
                    Text { text: teleVoltage.toFixed(1) + " V"; color: colText; font.pointSize: 12; Layout.alignment: Qt.AlignRight }

                    Text { text: "Current"; color: colTextDim; font.pointSize: 12; Layout.fillWidth: true }
                    Text { text: teleCurrent.toFixed(1) + " A"; color: colText; font.pointSize: 12; Layout.alignment: Qt.AlignRight }

                    Text { text: "Lights"; color: colTextDim; font.pointSize: 12; Layout.fillWidth: true }
                    Text { text: indicatorLabel(teleIndicator) + " / " + rearLightLabel(teleRearLight); color: colText; font.pointSize: 12; Layout.alignment: Qt.AlignRight }

                    Text { text: "Throttle"; color: colTextDim; font.pointSize: 12; Layout.fillWidth: true }
                    Text { text: adcLabel(teleThrottle); color: colText; font.pointSize: 12; Layout.alignment: Qt.AlignRight }

                    Text { text: "Brake"; color: colTextDim; font.pointSize: 12; Layout.fillWidth: true }
                    Text { text: adcLabel(teleBrake); color: colText; font.pointSize: 12; Layout.alignment: Qt.AlignRight }

                    Text { text: "BMS clock"; color: colTextDim; font.pointSize: 12; Layout.fillWidth: true }
                    Text { text: clockLabel(); color: colText; font.pointSize: 12; Layout.alignment: Qt.AlignRight }
                }
            }

            // Settings tabs
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                spacing: 0

                TabBar {
                    id: settingsTabBar
                    Layout.fillWidth: true
                    background: Rectangle { color: "transparent" }

                    TabButton { text: "Display Settings" }
                    TabButton { text: "Light Control" }
                    TabButton { text: "Profiles" }
                    TabButton { text: "BMS Mode" }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: settingsStack.implicitHeight + 28
                    radius: 10
                    color: bgCard

                    StackLayout {
                        id: settingsStack
                        anchors.fill: parent
                        anchors.margins: 14
                        currentIndex: settingsTabBar.currentIndex

                        // Display Settings
                        GridLayout {
                            columns: 2
                            columnSpacing: 16
                            rowSpacing: 18

                            Text {
                                text: "Disable profile switching"
                                color: colText
                                font.pointSize: 12
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                            Switch { id: disableProfSwSwitch; Layout.alignment: Qt.AlignRight }

                            Text {
                                text: "Freeze battery percentage under 11%"
                                color: colText
                                font.pointSize: 12
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                            Switch { id: freezeBattSwitch; Layout.alignment: Qt.AlignRight }

                            Text {
                                text: "Bypass Speed limit warning"
                                color: colText
                                font.pointSize: 12
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                            Switch { id: bypassSpeedLimitSwitch; Layout.alignment: Qt.AlignRight }

                            Text {
                                text: "External ADC"
                                color: colText
                                font.pointSize: 12
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                            Switch { id: externalAdcSwitch; Layout.alignment: Qt.AlignRight }
                        }

                        // Light Control
                        GridLayout {
                            columns: 2
                            columnSpacing: 16
                            rowSpacing: 18

                            Text {
                                text: "Underglow on park"
                                color: colText
                                font.pointSize: 12
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                            Switch { id: underglowOnParkSwitch; Layout.alignment: Qt.AlignRight }

                            Text {
                                text: "Enable charge light"
                                color: colText
                                font.pointSize: 12
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                            Switch { id: enableChargeLightSwitch; Layout.alignment: Qt.AlignRight }
                        }

                        // Profiles
                        ColumnLayout {
                            spacing: 18

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 16
                                rowSpacing: 18

                                Text {
                                    text: "Use temporary profiles"
                                    color: colText
                                    font.pointSize: 12
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                }
                                Switch { id: useOtherProfilesSwitch; Layout.alignment: Qt.AlignRight }
                            }

                            Text {
                                text: "Profiles overwrite the dashboard profiles temporary, as soon "
                                    + "as the dashboard turns off this option is turned off "
                                    + "automatically. Holding throttle and brake both over 50% for "
                                    + "2 seconds also turns it off."
                                color: colTextDim
                                font.pointSize: 10
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 16
                                rowSpacing: 12
                                enabled: useOtherProfilesSwitch.checked

                                Text { text: "Walk"; color: colText; font.pointSize: 12; Layout.fillWidth: true }
                                SpinBox {
                                    id: walkSpin
                                    from: 1; to: 100; value: 5
                                    editable: true
                                    textFromValue: function(v) { return v + " km/h" }
                                    valueFromText: function(t) { return parseInt(t) }
                                    Layout.alignment: Qt.AlignRight
                                }

                                Text { text: "Eco"; color: colText; font.pointSize: 12; Layout.fillWidth: true }
                                SpinBox {
                                    id: ecoSpin
                                    from: 1; to: 100; value: 15
                                    editable: true
                                    textFromValue: function(v) { return v + " km/h" }
                                    valueFromText: function(t) { return parseInt(t) }
                                    Layout.alignment: Qt.AlignRight
                                }

                                Text { text: "Drive"; color: colText; font.pointSize: 12; Layout.fillWidth: true }
                                SpinBox {
                                    id: driveSpin
                                    from: 1; to: 100; value: 20
                                    editable: true
                                    textFromValue: function(v) { return v + " km/h" }
                                    valueFromText: function(t) { return parseInt(t) }
                                    Layout.alignment: Qt.AlignRight
                                }

                                Text { text: "Sport"; color: colText; font.pointSize: 12; Layout.fillWidth: true }
                                SpinBox {
                                    id: sportSpin
                                    from: 1; to: 100; value: 25
                                    editable: true
                                    textFromValue: function(v) { return v + " km/h" }
                                    valueFromText: function(t) { return parseInt(t) }
                                    Layout.alignment: Qt.AlignRight
                                }
                            }
                        }

                        // BMS Mode
                        GridLayout {
                            columns: 2
                            columnSpacing: 16
                            rowSpacing: 18

                            Text {
                                text: "BMS mode"
                                color: colText
                                font.pointSize: 12
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                            ComboBox {
                                id: bmsModeCombo
                                model: ["Use VESC BMS", "Use Ninebot BMS/JBD2X3Bridge"]
                                Layout.alignment: Qt.AlignRight
                                Layout.preferredWidth: 210
                            }
                        }
                    }
                }
            }

            // Card: actions + status
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.bottomMargin: 14
                Layout.preferredHeight: actionsColumn.implicitHeight + 28
                radius: 10
                color: bgCard

                ColumnLayout {
                    id: actionsColumn
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Button {
                            text: "Reload from Express"
                            Layout.fillWidth: true
                            onClicked: requestSettings()
                        }
                        Button {
                            text: "Save to Express"
                            Layout.fillWidth: true
                            highlighted: true
                            onClicked: saveSettings()
                        }
                    }

                    Text {
                        id: statusText
                        color: colAccent
                        font.pointSize: 11
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: ""
                    }
                }
            }
        }
    }
}
