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
                from: -1
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
        
        RowLayout {
            Layout.fillWidth: true
            
            Button {
                Layout.fillWidth: true
                Layout.preferredWidth: 500
                text: "Start"
                
                onClicked: {
                    var cmd = "(start-log " + makeArgStr() + ")"
                    sendCode(cmd)
                }
            }
            
            Button {
                Layout.fillWidth: true
                Layout.preferredWidth: 500
                text: "Stop"
                
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
            VescIf.emitStatusMessage(data, true)
        }
    }
}
