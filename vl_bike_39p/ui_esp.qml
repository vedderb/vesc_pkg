import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.3
import QtQuick.Controls.Material 2.2
import Vedder.vesc.utility 1.0

import Vedder.vesc.commands 1.0
import Vedder.vesc.configparams 1.0

Item {
    id: appPage

    anchors.fill: parent
    anchors.margins: 10

    property Commands mCommands: VescIf.commands()
    property ConfigParams mMcConf: VescIf.mcConfig()
    property ConfigParams mInfoConf: VescIf.infoConfig()

    Component.onCompleted: {

    }

    ColumnLayout {
        anchors.fill: parent

        TabBar {
            id: tabBar
            currentIndex: swipeView.currentIndex
            Layout.fillWidth: true
            implicitWidth: 0
            clip: true

            property int buttons: 1
            property int buttonWidth: 120

            TabButton {
                text: qsTr("Config")
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
                ScrollView {
                    anchors.fill: parent
                    contentWidth: parent.width
                    contentHeight: column.preferredHeight
                    clip: true

                    ColumnLayout {
                        id: column
                        anchors.fill: parent
                        spacing: 0

                        DoubleSpinBox {
                            id: indDutyBox
                            Layout.fillWidth: true
                            prefix: "Indicator Glow Duty: "
                            suffix: ""
                            decimals: 3
                            realFrom: 0.0
                            realTo: 1.0
                            realValue: 0.08
                            realStepSize: 0.01
                        }

                        DoubleSpinBox {
                            id: indFreqBox
                            Layout.fillWidth: true
                            prefix: "Indicator PWM: "
                            suffix: " Hz"
                            decimals: 0
                            realFrom: 80
                            realTo: 5000
                            realValue: 500
                            realStepSize: 10
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Button {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 600
                                text: "Write"

                                onClicked: {
                                    sendCode("(save-config " +
                                    parseFloat(indDutyBox.realValue).toFixed(3) + " " +
                                    parseFloat(indFreqBox.realValue).toFixed(0) + " " +
                                    ")"
                                    )
                                }
                            }

                            Button {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 600
                                text: "Read"

                                onClicked: {
                                    sendCode("(send-settings)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    function sendCode(str) {
        mCommands.sendCustomAppData(str + "\0") // Append null to ensure that the string is null-terminated
    }

    Timer {
        id: aliveTimer
        interval: 100
        running: true
        repeat: true

        onTriggered: {
            if (VescIf.isPortConnected()) {

            }
        }
    }

    Connections {
        target: mCommands

        function onCustomAppDataReceived(data) {
            var str = data.toString()

            if (str.startsWith("settings")) {
                var tokens = str.split(" ")
                indDutyBox.realValue = Number(tokens[1])
                indFreqBox.realValue = Number(tokens[2])
                VescIf.emitStatusMessage("Settings Received!", true)
            } else if (str.startsWith("msg ")) {
                var msg = str.substring(4)
                VescIf.emitMessageDialog("Maxim STM", msg, false, false)
            } else {
                VescIf.emitStatusMessage(str, true)
            }
        }
    }
}
