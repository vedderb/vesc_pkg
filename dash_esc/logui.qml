import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.3

import Vedder.vesc.commands 1.0
import Vedder.vesc.configparams 1.0
import Vedder.vesc.utility 1.0

Item {
    id: container
    anchors.fill: parent
    anchors.margins: 10

    property Commands mCommands: VescIf.commands()

    Component.onCompleted: {
        if (VescIf.getLastFwRxParams().hw.includes("Express")) {
            canId.value = -2
        }

        sendCode("(send-settings)")
        sendCode("(send-modes)")
    }

    ColumnLayout {
        anchors.fill: parent

        Text {
            Layout.fillWidth: true
            color: Utility.getAppHexColor("lightText")
            horizontalAlignment: Text.AlignHCenter
            font.pointSize: 20
            text: "Dash ESC"
        }

        TabBar {
            id: tabBar
            currentIndex: swipeView.currentIndex
            Layout.fillWidth: true
            implicitWidth: 0
            clip: true

            property int buttons: 2
            property int buttonWidth: 120

            TabButton {
                text: qsTr("Logging")
                width: Math.max(tabBar.buttonWidth, tabBar.width / tabBar.buttons)
            }
            TabButton {
                text: qsTr("Modes")
                width: Math.max(tabBar.buttonWidth, tabBar.width / tabBar.buttons)
            }
        }

        SwipeView {
            id: swipeView
            currentIndex: tabBar.currentIndex
            Layout.fillHeight: true
            Layout.fillWidth: true
            clip: true

            Page {
                GridLayout {
                    columns: 2

                    anchors.fill: parent

                    GroupBox {
                        Layout.fillWidth: true
                        Layout.columnSpan: 2
                        title: "Data to log"

                        GridLayout {
                            anchors.fill: parent
                            columns: 2

                            CheckBox {
                                id: gnssLog
                                text: "GNSS"
                            }

                            CheckBox {
                                id: localLog
                                text: "Local Values"
                                checked: true
                            }

                            CheckBox {
                                id: canLog
                                text: "CAN Values"
                            }

                            CheckBox {
                                id: bmsLog
                                text: "BMS Values"
                            }
                        }
                    }

                    Text {
                        color: Utility.getAppHexColor("lightText")
                        text: "Logger CAN ID"
                    }

                    SpinBox {
                        id: canId
                        Layout.fillWidth: true
                        from: -2
                        to: 254
                        value: 2
                    }

                    Text {
                        color: Utility.getAppHexColor("lightText")
                        text: "Log Rate"
                    }

                    DoubleSpinBox {
                        id: logRate
                        Layout.fillWidth: true
                        realFrom: 1
                        realTo: 200
                        realValue: 10
                        decimals: 0
                        suffix: " Hz"
                    }

                    CheckBox {
                        Layout.columnSpan: 2
                        id: startAtBoot
                        text: "Start logging at boot"
                    }

                    Item {
                        Layout.fillHeight: true
                        Layout.columnSpan: 2
                    }

                    RowLayout {
                        Layout.columnSpan: 2

                        Button {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 500
                            text: "Start Log"

                            onClicked: {
                                var cmd = "(start-log " + makeArgStr() + ")"
                                sendCode(cmd)
                            }
                        }

                        Button {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 500
                            text: "Stop Log"

                            onClicked: {
                                sendCode("(stop-log " + canId.value + ")")
                            }
                        }
                    }
                }
            }

            Page {
                ScrollView {
                    id: profileScroll
                    anchors.fill: parent
                    contentWidth: parent.width
                    contentHeight: scrollCol.preferredHeight
                    clip: true

                    ColumnLayout {
                        id: scrollCol
                        width: profileScroll.width - 30

                        GroupBox {
                            Layout.fillWidth: true
                            Layout.columnSpan: 2
                            title: "Reverse"

                            GridLayout {
                                anchors.fill: parent
                                columns: 2

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Speed"
                                }

                                DoubleSpinBox {
                                    id: modeRSpeed
                                    Layout.fillWidth: true
                                    realFrom: 0.5
                                    realTo: 250.0
                                    realValue: 15.0
                                    decimals: 1
                                    suffix: " km/h"
                                }

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Current"
                                }

                                DoubleSpinBox {
                                    id: modeRCurrent
                                    Layout.fillWidth: true
                                    realFrom: 0.0
                                    realTo: 100.0
                                    realValue: 100.0
                                    decimals: 0
                                    realStepSize: 10.0
                                    suffix: " %"
                                }

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Brake"
                                }

                                DoubleSpinBox {
                                    id: modeRCurrentBrake
                                    Layout.fillWidth: true
                                    realFrom: 0.0
                                    realTo: 100.0
                                    realValue: 100.0
                                    decimals: 0
                                    realStepSize: 10.0
                                    suffix: " %"
                                }
                            }
                        }

                        GroupBox {
                            Layout.fillWidth: true
                            Layout.columnSpan: 2
                            title: "Neutral"

                            GridLayout {
                                anchors.fill: parent
                                columns: 2

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Brake"
                                }

                                DoubleSpinBox {
                                    id: modeNCurrentBrake
                                    Layout.fillWidth: true
                                    realFrom: 0.0
                                    realTo: 100.0
                                    realValue: 100.0
                                    decimals: 0
                                    realStepSize: 10.0
                                    suffix: " %"
                                }
                            }
                        }

                        GroupBox {
                            Layout.fillWidth: true
                            Layout.columnSpan: 2
                            title: "Mode 1"

                            GridLayout {
                                anchors.fill: parent
                                columns: 2

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Speed"
                                }

                                DoubleSpinBox {
                                    id: mode1Speed
                                    Layout.fillWidth: true
                                    realFrom: 0.0
                                    realTo: 250.0
                                    realValue: 20.0
                                    decimals: 1
                                    suffix: " km/h"
                                }

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Current"
                                }

                                DoubleSpinBox {
                                    id: mode1Current
                                    Layout.fillWidth: true
                                    realFrom: 0.0
                                    realTo: 100.0
                                    realValue: 50.0
                                    decimals: 0
                                    realStepSize: 10.0
                                    suffix: " %"
                                }

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Brake"
                                }

                                DoubleSpinBox {
                                    id: mode1CurrentBrake
                                    Layout.fillWidth: true
                                    realFrom: 0.0
                                    realTo: 100.0
                                    realValue: 100.0
                                    decimals: 0
                                    realStepSize: 10.0
                                    suffix: " %"
                                }
                            }
                        }

                        GroupBox {
                            Layout.fillWidth: true
                            Layout.columnSpan: 2
                            title: "Mode 2"

                            GridLayout {
                                anchors.fill: parent
                                columns: 2

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Speed"
                                }

                                DoubleSpinBox {
                                    id: mode2Speed
                                    Layout.fillWidth: true
                                    realFrom: 0.0
                                    realTo: 250.0
                                    realValue: 25.0
                                    decimals: 1
                                    suffix: " km/h"
                                }

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Current"
                                }

                                DoubleSpinBox {
                                    id: mode2Current
                                    Layout.fillWidth: true
                                    realFrom: 0.0
                                    realTo: 100.0
                                    realValue: 60.0
                                    decimals: 0
                                    realStepSize: 10.0
                                    suffix: " %"
                                }

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Brake"
                                }

                                DoubleSpinBox {
                                    id: mode2CurrentBrake
                                    Layout.fillWidth: true
                                    realFrom: 0.0
                                    realTo: 100.0
                                    realValue: 100.0
                                    decimals: 0
                                    realStepSize: 10.0
                                    suffix: " %"
                                }
                            }
                        }

                        GroupBox {
                            Layout.fillWidth: true
                            Layout.columnSpan: 2
                            title: "Mode 3"

                            GridLayout {
                                anchors.fill: parent
                                columns: 2

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Speed"
                                }

                                DoubleSpinBox {
                                    id: mode3Speed
                                    Layout.fillWidth: true
                                    realFrom: 0.0
                                    realTo: 250.0
                                    realValue: 250.0
                                    decimals: 1
                                    suffix: " km/h"
                                }

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Current"
                                }

                                DoubleSpinBox {
                                    id: mode3Current
                                    Layout.fillWidth: true
                                    realFrom: 0.0
                                    realTo: 100.0
                                    realValue: 100.0
                                    decimals: 0
                                    realStepSize: 10.0
                                    suffix: " %"
                                }

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Brake"
                                }

                                DoubleSpinBox {
                                    id: mode3CurrentBrake
                                    Layout.fillWidth: true
                                    realFrom: 0.0
                                    realTo: 100.0
                                    realValue: 100.0
                                    decimals: 0
                                    realStepSize: 10.0
                                    suffix: " %"
                                }
                            }
                        }

                        Item {
                            Layout.fillHeight: true
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Button {
                Layout.fillWidth: true
                Layout.preferredWidth: 500

                text: "Read Config"

                onClicked: {
                    sendCode("(send-settings)")
                    sendCode("(send-modes)")
                }
            }

            Button {
                Layout.fillWidth: true
                Layout.preferredWidth: 500

                text: "Save Config"

                onClicked: {
                    sendCode("(save-config " + makeArgStr() + " " + startAtBoot.checked + ")")
                    sendCode("(save-modes " + makeModeStr() + ")")
                }
            }

            Button {
                Layout.fillWidth: true
                Layout.preferredWidth: 500

                text: "Defaults"

                onClicked: {
                    sendCode("(restore-settings)")
                    sendCode("(send-settings)")
                    sendCode("(send-modes)")
                }
            }
        }
    }

    function makeModeStr() {
        return "" +
        parseFloat(modeRSpeed.realValue).toFixed(1) + " " +
        parseFloat(modeRCurrent.realValue / 100.0).toFixed(2) + " " +
        parseFloat(modeRCurrentBrake.realValue / 100.0).toFixed(2) + " " +
        parseFloat(modeNCurrentBrake.realValue / 100.0).toFixed(2) + " " +
        parseFloat(mode1Speed.realValue).toFixed(1) + " " +
        parseFloat(mode1Current.realValue / 100.0).toFixed(2) + " " +
        parseFloat(mode1CurrentBrake.realValue / 100.0).toFixed(2) + " " +
        parseFloat(mode2Speed.realValue).toFixed(1) + " " +
        parseFloat(mode2Current.realValue / 100.0).toFixed(2) + " " +
        parseFloat(mode2CurrentBrake.realValue / 100.0).toFixed(2) + " " +
        parseFloat(mode3Speed.realValue).toFixed(1) + " " +
        parseFloat(mode3Current.realValue / 100.0).toFixed(2) + " " +
        parseFloat(mode3CurrentBrake.realValue / 100.0).toFixed(2)
    }

    function makeArgStr() {
        return "" +
        canId.value + " " +
        gnssLog.checked + " " +
        localLog.checked + " " +
        canLog.checked + " " +
        bmsLog.checked + " " +
        parseFloat(logRate.realValue).toFixed(2)
    }

    function sendCode(str) {
        mCommands.sendCustomAppData(str + "\0") // Append null to ensure that the string is null-terminated
    }

    Connections {
        target: mCommands

        function onCustomAppDataReceived(data) {
            var str = data.toString()

            if (str.startsWith("settings")) {
                var tokens = str.split(" ")
                canId.value = Number(tokens[1])
                startAtBoot.checked = Number(tokens[2])
                logRate.realValue = Number(tokens[3])
                gnssLog.checked = Number(tokens[4])
                localLog.checked = Number(tokens[5])
                canLog.checked = Number(tokens[6])
                bmsLog.checked = Number(tokens[7])
                } else if (str.startsWith("msg ")) {
                var msg = str.substring(4)
                VescIf.emitMessageDialog("Logger", msg, false, false)
            }
            else if (str.startsWith("modes")) {
                var tokens = str.split(" ")
                modeRSpeed.realValue = Number(tokens[1])
                modeRCurrent.realValue = Number(tokens[2]) * 100.0
                modeRCurrentBrake.realValue = Number(tokens[3]) * 100.0

                modeNCurrentBrake.realValue = Number(tokens[4]) * 100.0

                mode1Speed.realValue = Number(tokens[5])
                mode1Current.realValue = Number(tokens[6]) * 100.0
                mode1CurrentBrake.realValue = Number(tokens[7]) * 100.0

                mode2Speed.realValue = Number(tokens[8])
                mode2Current.realValue = Number(tokens[9]) * 100.0
                mode2CurrentBrake.realValue = Number(tokens[10]) * 100.0

                mode3Speed.realValue = Number(tokens[11])
                mode3Current.realValue = Number(tokens[12]) * 100.0
                mode3CurrentBrake.realValue = Number(tokens[13]) * 100.0
                }
            else if (str.startsWith("msg ")) {
                var msg = str.substring(4)
                VescIf.emitMessageDialog("Logger", msg, false, false)
            }
            else {
                VescIf.emitStatusMessage(str, true)
            }
        }
    }

    Dialog {
        id: commDialog
        title: "Processing..."
        closePolicy: Popup.NoAutoClose
        modal: true
        focus: true

        width: parent.width - 20
        x: 10
        y: parent.height / 2 - height / 2
        parent: container

        ProgressBar {
            anchors.fill: parent
            indeterminate: visible
        }
    }
}
