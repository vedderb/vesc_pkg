// Settings page companion to main.lisp (VESC Express).

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
    property int teleProfile: 0

    function indicatorLabel(b) {
        if (b === 1) return "Left"
        if (b === 2) return "Right"
        if (b === 3) return "Hazard"
        return "Off"
    }

    function rearLightLabel(b) {
        if (b === 0x12) return "Charging"
        if (b === 0x14) return "On"
        if (b === 0x16) return "Brake"
        if (b === 0x18) return "Flashing brake"
        return "Off"
    }

    function profileSpeedLimitKmh(b) {
        return Math.round(b / 2.0)
    }

    // cmd: 0x01 get, 0x02 set
    function buildSettingsBuffer(cmd) {
        var buffer = new ArrayBuffer(7)
        var dv = new DataView(buffer)
        dv.setUint8(0, cmd)
        dv.setUint8(1, disableProfSwSwitch.checked ? 1 : 0)
        dv.setUint8(2, freezeBattSwitch.checked ? 1 : 0)
        dv.setUint8(3, bmsModeCombo.currentIndex)
        dv.setUint8(4, bypassSpeedLimitSwitch.checked ? 1 : 0)
        dv.setUint8(5, underglowOnParkSwitch.checked ? 1 : 0)
        dv.setUint8(6, enableChargeLightSwitch.checked ? 1 : 0)
        return buffer
    }

    function requestSettings() {
        statusText.text = "Loading..."
        mCommands.sendCustomAppData(buildSettingsBuffer(0x01))
    }

    function saveSettings() {
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
                disableProfSwSwitch.checked = (dv.getUint8(1) !== 0)
                freezeBattSwitch.checked = (dv.getUint8(2) !== 0)
                bmsModeCombo.currentIndex = dv.getUint8(3)
                bypassSpeedLimitSwitch.checked = (dv.getUint8(4) !== 0)
                if (data.byteLength >= 7) {
                    underglowOnParkSwitch.checked = (dv.getUint8(5) !== 0)
                    enableChargeLightSwitch.checked = (dv.getUint8(6) !== 0)
                }
                statusText.text = "Loaded from Express"
            } else if (tag === 0x03 && data.byteLength >= 11) {
                teleSpeed = dv.getInt16(1, true) / 10.0
                teleMotorTemp = dv.getInt8(3)
                teleVoltage = dv.getUint16(4, true) / 10.0
                teleCurrent = dv.getInt16(6, true) / 10.0
                teleIndicator = dv.getUint8(8)
                teleRearLight = dv.getUint8(9)
                teleProfile = dv.getUint8(10)
            }
        }
    }

    Component.onCompleted: requestSettings()

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
                    text: "NinebotX3Bridge"
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

                    Text { text: "Speed limit"; color: colTextDim; font.pointSize: 12; Layout.fillWidth: true }
                    Text { text: profileSpeedLimitKmh(teleProfile) + " km/h"; color: colText; font.pointSize: 12; Layout.alignment: Qt.AlignRight }

                    Text { text: "Motor temp"; color: colTextDim; font.pointSize: 12; Layout.fillWidth: true }
                    Text { text: teleMotorTemp + " °C"; color: colText; font.pointSize: 12; Layout.alignment: Qt.AlignRight }

                    Text { text: "Voltage"; color: colTextDim; font.pointSize: 12; Layout.fillWidth: true }
                    Text { text: teleVoltage.toFixed(1) + " V"; color: colText; font.pointSize: 12; Layout.alignment: Qt.AlignRight }

                    Text { text: "Current"; color: colTextDim; font.pointSize: 12; Layout.fillWidth: true }
                    Text { text: teleCurrent.toFixed(1) + " A"; color: colText; font.pointSize: 12; Layout.alignment: Qt.AlignRight }

                    Text { text: "Lights"; color: colTextDim; font.pointSize: 12; Layout.fillWidth: true }
                    Text { text: indicatorLabel(teleIndicator) + " / " + rearLightLabel(teleRearLight); color: colText; font.pointSize: 12; Layout.alignment: Qt.AlignRight }
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
