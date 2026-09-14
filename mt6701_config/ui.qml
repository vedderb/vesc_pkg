import QtQuick 2.15
import QtQuick.Controls 2.12
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
    }

    ColumnLayout {
        anchors.fill: parent

        Text {
            Layout.fillWidth: true
            color: Utility.getAppHexColor("lightText")
            horizontalAlignment: Text.AlignHCenter
            font.pointSize: 20
            text: "MT6701 Config"
        }

        GridLayout {
            columns: 2

            Text {
                color: Utility.getAppHexColor("lightText")
                text: "Pole Pairs"
            }

            SpinBox {
                id: polePairs
                Layout.fillWidth: true
                from: 1
                to: 16
                value: 4
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 1
            rowSpacing: -5

            Button {
                Layout.fillWidth: true
                Layout.preferredWidth: 500
                text: "Read"

                onClicked: {
                    sendCode("(read-encoder)")
                }
            }

            Button {
                Layout.fillWidth: true
                Layout.preferredWidth: 500
                text: "Write"

                onClicked: {
                    var cmd = "(config-encoder " + polePairs.value + ")"
                    sendCode(cmd)
                }
            }
        }

        ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: terminalText.width
            clip: true

            TextArea {
                id: terminalText
                anchors.fill: parent
                readOnly: true
                font.family: "DejaVu Sans Mono"
            }
        }

        Button {
            Layout.fillWidth: true
            Layout.preferredWidth: 500
            text: "Clear Terminal"

            onClicked: {
                terminalText.text = ""
            }
        }
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

            } else if (str.startsWith("msg ")) {
                var msg = str.substring(4)
                VescIf.emitMessageDialog("Logger", msg, false, false)
            } else {
                terminalText.text += "\n" + str
            }
        }
    }
}
