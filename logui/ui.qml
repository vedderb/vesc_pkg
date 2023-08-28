import QtQuick 2.12
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
            text: "Data Logging"
        }
        
        GridLayout {
            columns: 2
            
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
        }
        
        Item {
            Layout.fillHeight: true
        }
        
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: -5
                        
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
            
            Button {
                Layout.fillWidth: true
                Layout.preferredWidth: 500
                text: "Save Config"
                
                onClicked: {
                    sendCode("(save-config " + makeArgStr() + " " + startAtBoot.checked + ")")
                }
            }
            
            Button {
                Layout.fillWidth: true
                Layout.preferredWidth: 500
                text: "Test SD-card"
                
                onClicked: {
                    commDialog.open()
                    if (canId.value >= 0) {
                        VescIf.canTmpOverride(true, canId.value)
                    }
                    
                    var ok = mCommands.fileBlockWrite("test.txt", "TestTxt")
                    
                    if (canId.value >= 0) {
                        VescIf.canTmpOverrideEnd()
                    }
                    commDialog.close()
                    
                    VescIf.emitMessageDialog(
                        "Express SD-Card Test",
                        ok ?
                            "Writing to the SD-card works!" :
                            
                            "Could not write to the SD-card. Make sure " +
                            "that it is formatted to FAT32. Also make sure " +
                            "that the logger CAN ID is correct. Note that not " +
                            "all SD-cards work even if they are formatted " +
                            "correctly.",
                        ok, false)
                }
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
            } else {
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
