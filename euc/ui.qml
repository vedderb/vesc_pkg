/*
    Copyright 2022 Benjamin Vedder	benjamin@vedder.se

    This file is part of VESC Tool.

    VESC Tool is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    VESC Tool is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
    */

import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.3
import Vedder.vesc.utility 1.0

import Vedder.vesc.commands 1.0
import Vedder.vesc.configparams 1.0

// This example shows how to read and write settings using the custom
// config. It is also possible to send and receive custom data using
// send_app_data and set_app_data_handler on the euc-side and Commands
// onCustomAppDataReceived and mCommands.sendCustomAppData in qml.

Item {
    id: mainItem
    anchors.fill: parent
    anchors.margins: 5

    property Commands mCommands: VescIf.commands()
    property ConfigParams mMcConf: VescIf.mcConfig()
    property ConfigParams mCustomConf: VescIf.customConfig(0)
    
    Component.onCompleted: {
        params.addEditorCustom("pid_mode", 0)
        params.addEditorCustom("kp", 0)
        params.addEditorCustom("fault_delay_pitch", 0)
    }
    
    Connections {
        target: mCommands
        
        // This function will be called when VESC_IF->send_app_data is used. To
        // send data back mCommands.sendCustomAppData can be used. That data
        // will be received in the function registered with VESC_IF->set_app_data_handler
        onCustomAppDataReceived: {
            // Ints and floats can be extracted like this from the data
//            var dv = new DataView(data, 0)
//            var ind = 0
//            var cmd = dv.getUint8(ind++)
        }
    }

    ColumnLayout {
        id: gaugeColumn
        anchors.fill: parent
        
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            
            ParamList {
                id: params
                anchors.fill: parent
            }
        }
        
        RowLayout {
            Layout.fillWidth: true
            
            Button {
                text: "Read"
                Layout.fillWidth: true
                
                onClicked: {
                    mCommands.customConfigGet(0, false)
                }
            }
            
            Button {
                text: "Read Default"
                Layout.fillWidth: true
                
                onClicked: {
                    mCommands.customConfigGet(0, true)
                }
            }
            
            Button {
                text: "Write"
                Layout.fillWidth: true
                
                onClicked: {
                    mCommands.customConfigSet(0, mCustomConf)
                }
            }
        }
    }
}
