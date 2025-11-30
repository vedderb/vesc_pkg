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
        updateEditors()
        sendCode("(send-settings)")
    }

    ParamEditors {
        id: editors
    }

    function addSeparator(text) {
        var e = editors.createSeparator(scrollCol, text)
        e.Layout.columnSpan = 1
    }

    function addSeparatorMc(text) {
        var e = editors.createSeparator(scrollColMc, text)
        e.Layout.columnSpan = 1
    }

    function destroyEditors() {
        for(var i = scrollCol.children.length;i > 0;i--) {
            scrollCol.children[i - 1].destroy(1) // Only works with delay on android, seems to be a bug
        }

        for(var i = scrollColMc.children.length;i > 0;i--) {
            scrollColMc.children[i - 1].destroy(1) // Only works with delay on android, seems to be a bug
        }
    }

    function createEditorApp(param) {
        var e = editors.createEditorApp(scrollCol, param)
        e.Layout.preferredWidth = 500
        e.Layout.fillsWidth = true
    }

    function createEditorMc(param) {
        var e = editors.createEditorMc(scrollColMc, param)
        e.Layout.preferredWidth = 500
        e.Layout.fillsWidth = true
    }

    function updateEditors() {
        destroyEditors()

        var params = VescIf.appConfig().getParamsFromSubgroup("VESC Remote", "General")

        for (var i = 0;i < params.length;i++) {
            if (params[i].startsWith("::sep::")) {
                addSeparator(params[i].substr(7))
                } else {
                createEditorApp(params[i])
            }
        }

        params = VescIf.mcConfig().getParamsFromSubgroup("Additional Info", "Setup")

        for (var i = 0;i < params.length;i++) {
            if (params[i].startsWith("::sep::")) {
                addSeparatorMc(params[i].substr(7))
                } else {
                createEditorMc(params[i])
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent

        TabBar {
            id: tabBar
            currentIndex: swipeView.currentIndex
            Layout.fillWidth: true
            implicitWidth: 0
            clip: true

            property int buttons: 4
            property int buttonWidth: 120

            TabButton {
                text: qsTr("Detect Motor")
                width: Math.max(tabBar.buttonWidth, tabBar.width / tabBar.buttons)
            }
            TabButton {
                text: qsTr("Input")
                width: Math.max(tabBar.buttonWidth, tabBar.width / tabBar.buttons)
            }
            TabButton {
                text: qsTr("Controls")
                width: Math.max(tabBar.buttonWidth, tabBar.width / tabBar.buttons)
            }
            TabButton {
                text: qsTr("Vehicle")
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
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    ComboBox {
                        id: encoderBox
                        Layout.fillWidth: true
                        model: [
                        "Encoder: Sensorless",
                        "Encoder: VESC Labs ABI Encoder",
                        ]
                        currentIndex: 1

                        onCurrentIndexChanged: {

                        }
                    }

                    DoubleSpinBox {
                        id: currMaxBox
                        Layout.fillWidth: true
                        prefix: "Motor Current: "
                        suffix: " A"
                        decimals: 1
                        realFrom: 0.0
                        realTo: 1000
                        realValue: 550.0
                        realStepSize: 1
                    }

                    DoubleSpinBox {
                        id: currDetectBox
                        Layout.fillWidth: true
                        prefix: "Detect Current: "
                        suffix: " A"
                        decimals: 1
                        realFrom: 0.0
                        realTo: 1000
                        realValue: 100.0
                        realStepSize: 1
                    }

                    Button {
                        text: "Configure IPM Motor"
                        Layout.fillWidth: true

                        onClicked: {
                            confIpmDialog.open()
                        }

                        Dialog {
                            id: confIpmDialog
                            parent: appPage
                            standardButtons: Dialog.Ok | Dialog.Cancel
                            modal: true
                            focus: true
                            width: parent.width - 20
                            closePolicy: Popup.CloseOnEscape
                            title: "Configure IPM Motor"

                            Overlay.modal: Rectangle {
                                color: "#AA000000"
                            }

                            x: 10
                            y: Math.max((parent.height - height) / 2, 10)

                            Text {
                                color: Utility.getAppHexColor("lightText")
                                verticalAlignment: Text.AlignVCenter
                                anchors.centerIn: parent
                                width: appPage.width - 80
                                wrapMode: Text.WordWrap
                                text:
                                "This is going to spin up the motor. Make " +
                                "sure that nothing is in the way!"
                            }

                            onAccepted: {
                                sendCode("(conf-start " +
                                    encoderBox.currentIndex + " " +
                                    parseFloat(currMaxBox.realValue).toFixed(2) + " " +
                                    parseFloat(currDetectBox.realValue).toFixed(2) + ")")
                            }
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }
            }

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
                            id: thrMinBox
                            Layout.fillWidth: true
                            prefix: "Throttle Min: "
                            suffix: " V"
                            decimals: 2
                            realFrom: 0.0
                            realTo: 3.3
                            realValue: 0.58
                            realStepSize: 0.01
                        }

                        DoubleSpinBox {
                            id: thrMaxBox
                            Layout.fillWidth: true
                            prefix: "Throttle Max: "
                            suffix: " V"
                            decimals: 2
                            realFrom: 0.0
                            realTo: 3.3
                            realValue: 2.8
                            realStepSize: 0.01
                        }

                        DoubleSpinBox {
                            id: brkMinBox
                            Layout.fillWidth: true
                            prefix: "Brake Min: "
                            suffix: " V"
                            decimals: 2
                            realFrom: 0.0
                            realTo: 3.3
                            realValue: 0.58
                            realStepSize: 0.01
                        }

                        DoubleSpinBox {
                            id: brkMaxBox
                            Layout.fillWidth: true
                            prefix: "Brake Max: "
                            suffix: " V"
                            decimals: 2
                            realFrom: 0.0
                            realTo: 3.3
                            realValue: 2.8
                            realStepSize: 0.01
                        }

                        CheckBox {
                            Layout.fillWidth: true
                            id: useBrkBox
                            text: "Use Brake"
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: width * 0.5

                            CustomGauge {
                                id: throttleGauge
                                Layout.fillWidth: true
                                //Layout.preferredWidth: parent.width * 0.45
                                Layout.preferredHeight: width
                                maximumValue: 4
                                minimumValue: 0
                                tickmarkScale: 1
                                tickmarkSuffix: "V"
                                labelStep: 1
                                precision: 2
                                value: 0
                                unitText: "V"
                                typeText: "Throttle"
                            }

                            CustomGauge {
                                id: brakeGauge
                                Layout.fillWidth: true
                                //Layout.preferredWidth: parent.width * 0.45
                                Layout.preferredHeight: width
                                maximumValue: 4
                                minimumValue: 0
                                tickmarkScale: 1
                                tickmarkSuffix: "V"
                                labelStep: 1
                                precision: 2
                                value: 0
                                unitText: "V"
                                typeText: "Brake"
                            }

                            CustomGauge {
                                id: outGauge
                                Layout.fillWidth: true
                                //Layout.preferredWidth: parent.width * 0.45
                                Layout.preferredHeight: width
                                maximumValue: 100
                                minimumValue: -100
                                tickmarkScale: 1
                                tickmarkSuffix: "%"
                                labelStep: 20
                                precision: 0
                                value: 0
                                unitText: "%"
                                typeText: "Output"
                            }
                        }

                        CheckBox {
                            Layout.fillWidth: true
                            id: pollVoltBox
                            text: "Poll Voltage"
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Button {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 600
                                text: "Write"

                                onClicked: {
                                    sendCode("(save-config " +
                                    parseFloat(thrMinBox.realValue).toFixed(2) + " " +
                                    parseFloat(thrMaxBox.realValue).toFixed(2) + " " +
                                    parseFloat(brkMinBox.realValue).toFixed(2) + " " +
                                    parseFloat(brkMaxBox.realValue).toFixed(2) + " " +
                                    useBrkBox.checked +
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

            Page {
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Button {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 600
                            text: "Write"

                            onClicked: {
                                mCommands.setAppConf()
                            }
                        }

                        Button {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 600
                            text: "Read"

                            onClicked: {
                                mCommands.getAppConf()
                            }
                        }
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: parent.width
                        contentHeight: scrollCol.preferredHeight
                        clip: true

                        GridLayout {
                            id: scrollCol
                            width: column.width
                            columns: 1
                        }
                    }
                }
            }

            Page {
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Button {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 600
                            text: "Write"

                            onClicked: {
                                mCommands.setMcconf(true)
                            }
                        }

                        Button {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 600
                            text: "Read"

                            onClicked: {
                                mCommands.getMcconf()
                            }
                        }
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: parent.width
                        contentHeight: scrollCol.preferredHeight
                        clip: true

                        GridLayout {
                            id: scrollColMc
                            width: column.width
                            columns: 1
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
                if (pollVoltBox.checked) {
                    sendCode("(send-adc)")
                }
            }
        }
    }

    Connections {
        target: mCommands

        function onCustomAppDataReceived(data) {
            var str = data.toString()

            if (str.startsWith("settings")) {
                var tokens = str.split(" ")
                thrMinBox.realValue = Number(tokens[1])
                thrMaxBox.realValue = Number(tokens[2])
                brkMinBox.realValue = Number(tokens[3])
                brkMaxBox.realValue = Number(tokens[4])
                useBrkBox.checked = tokens[5] == "1"
                VescIf.emitStatusMessage("Settings Received!", true)
            } else if (str.startsWith("volts")) {
                var tokens = str.split(" ")
                throttleGauge.value = Number(tokens[1])
                brakeGauge.value = Number(tokens[2])
                outGauge.value = Number(tokens[3]) * 100.0
            } else if (str.startsWith("msg ")) {
                var msg = str.substring(4)
                VescIf.emitMessageDialog("Maxim STM", msg, false, false)
                mCommands.getMcconf()
            } else {
                VescIf.emitStatusMessage(str, true)
            }
        }
    }
}
