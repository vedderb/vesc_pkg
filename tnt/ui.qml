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
import Qt.labs.settings 1.0

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

    readonly property var defaultQuicksaveNames: {
                "Float Quicksave 1": "Quicksave 1",
                "Float Quicksave 2": "Quicksave 2",
                "Float Quicksave 3": "Quicksave 3",
                "Float Quicksave 4": "Quicksave 4",
                "Float Quicksave 5": "Quicksave 5",
                "Float Quicksave 6": "Quicksave 6",
                "IMU Quicksave 1": "IMU Quicksave 1",
                "IMU Quicksave 2": "IMU Quicksave 2"
                }

    property Commands mCommands: VescIf.commands()
    property ConfigParams mMcConf: VescIf.mcConfig()
    property ConfigParams mAppConf: VescIf.appConfig()
    property ConfigParams mCustomConf: VescIf.customConfig(0)
    property var quicksaveNames: []

    

    // property var dialogParent: ApplicationWindow.overlay
    
    Settings {
        id: settingStorage
    }
    
    // Timer 1, 10hz for ble comms
    Timer {
        running: true
        repeat: true
        interval: 100
        
        onTriggered: {
            // Poll app data
            var buffer = new ArrayBuffer(2)
            var dv = new DataView(buffer)
            var ind = 0
            dv.setUint8(ind, 111); ind += 1
            dv.setUint8(ind, 0x1); ind += 1
            mCommands.sendCustomAppData(buffer)
            
         
        }
    }

    Connections {
        target: mCommands
        
        // This function will be called when VESC_IF->send_app_data is used. To
        // send data back mCommands.sendCustomAppData can be used. That data
        // will be received in the function registered with VESC_IF->set_app_data_handler
        onCustomAppDataReceived: {
            // Ints and floats can be extracted like this from the data
            var dv = new DataView(data, 0)
            var ind = 0
            var magicnr = dv.getUint8(ind); ind += 1;
            var msgtype = dv.getUint8(ind); ind += 1;

            if (magicnr != 111) {
                return;
            }
            if (msgtype == 1) {
                var voltage = dv.getFloat32(ind); ind += 4;
                var rollkp = dv.getFloat32(ind); ind += 4;
                var smoothpitch = dv.getFloat32(ind); ind += 4;
                var pitch = dv.getFloat32(ind); ind += 4;
                var roll = dv.getFloat32(ind); ind += 4;
                var scaledkp = dv.getFloat32(ind); ind += 4;
                var current = dv.getFloat32(ind); ind += 4;
                var state = dv.getInt8(ind); ind += 1;
                var setpointAdjustmentType = state >> 4;
                state = state &0xF;
                var switch_state = dv.getInt8(ind); ind += 1;
                var adc1 = dv.getFloat32(ind); ind += 4;
                var adc2 = dv.getFloat32(ind); ind += 4;

                var float_setpoint = dv.getFloat32(ind); ind += 4;
                var float_inputtilt = dv.getFloat32(ind); ind += 4;
                var throttle_val = dv.getFloat32(ind); ind += 4;
               
                var surge_lasttime = dv.getFloat32(ind); ind += 4;
                var surge_lastcycle = dv.getFloat32(ind); ind += 4;
                
                var lastwheelslip = dv.getFloat32(ind); ind += 4;
                var durwheelslip = dv.getFloat32(ind); ind += 4;
                var startaccel1 = dv.getFloat32(ind); ind += 4;
                var startaccel2 = dv.getFloat32(ind); ind += 4;
                var erpmfactor = dv.getFloat32(ind); ind += 4;                
                var wheelslipstart = dv.getFloat32(ind); ind += 4;
                var wheelsliplasterpm = dv.getFloat32(ind); ind += 4;
                var wheelsliperpm = dv.getFloat32(ind); ind += 4;
                var debugwheelslip = dv.getFloat32(ind); ind += 4;
                var wheelslipend = dv.getFloat32(ind); ind += 4;                
                
                // var debug1 = dv.getFloat32(ind); ind += 4;
                // var debug2 = dv.getFloat32(ind); ind += 4;

                var stateString
                if(state == 0){
                    stateString = "BOOT"	// we're in this state only for the first second or so then never again
                }else if(state == 1){
                    stateString = "RUNNING"
                }else if(state == 2){
                    stateString = "RUNNING_TILTBACK"
                }else if(state == 3){
                    stateString = "RUNNING_WHEELSLIP"
                }else if(state == 4){
                    stateString = "RUNNING_UPSIDEDOWN"
                }else if(state == 6){
                    stateString = "STOP_ANGLE_PITCH"
                }else if(state == 7){
                    stateString = "STOP_ANGLE_ROLL"
                }else if(state == 8){
                    stateString = "STOP_SWITCH_HALF"
                }else if(state == 9){
                    stateString = "STOP_SWITCH_FULL"
                }else if(state == 11){
                    if ((roll > 120) || (roll < -120)) {
                        stateString = "STARTUP UPSIDEDOWN"
                    }
                    else {
                        stateString = "STARTUP"
                    }
                }else if(state == 12){
                    stateString = "STOP_REVERSE"
                }else if(state == 13){
                    stateString = "STOP_QUICKSTOP"
                }else{
                    stateString = "UNKNOWN"
                }

                var suffix = ""
                if (setpointAdjustmentType == 0) {
                    suffix = "[CENTERING]";
                } else if (setpointAdjustmentType == 1) {
                    suffix = "[REVERSESTOP]";
                } else if (setpointAdjustmentType == 3) {
                    suffix = "[DUTY]";
                } else if (setpointAdjustmentType == 4) {
                    suffix = "[HV]";
                } else if (setpointAdjustmentType == 5) {
                    suffix = "[LV]";
                } else if (setpointAdjustmentType == 6) {
                    suffix = "[TEMP]";
                }
                if ((state > 0) && (state < 6)) {
                    stateString += suffix;
                }

                var switchString
                if(switch_state == 0){
                    switchString = "Off"
                }else if(switch_state == 1){
                    switchString = "Half"
                    /*HOW TO ACCESS CONFIG FROM QML???
                    if (adc1 >= VescIf.mcConfig().fault_adc1)
                        switchString += " [On|"
                    else
                        switchString += " [Off|"
                    if (adc2 >= VescIf.mcConfig().fault_adc2)
                        switchString += "On]"
                    else
                        switchString += "Off]"*/
                }else{
                    switchString = "On"
                }

                if(state == 15){
                    stateString = "DISABLED"
                    switchString = "Enable in TNT Cfg: Specs"
                    rt_state.text = "TNT Package is Disabled\n\n" +
                                    "You can re-enable it in\nTNT Cfg: Specs\n\n"
                    rt_data.text = "-- n/a --"
                    setpoints.text = "-- n/a --"
                    debug.text = "-- n/a --"
                }
                else {
                rt_state.text =
                    "State               : " + stateString + "\n" +
                    "Switch              : " + switchString + "\n" +
                    "ADC1 / ADC2         : " + adc1.toFixed(2) + "V / " + adc2.toFixed(2) + "V\n"    

                rt_data.text =
                    "Voltage             : " + voltage.toFixed(1) + "V\n" +
                    "Current             : " + current.toFixed(0) + " A\n" +
                    "Pitch               : " + pitch.toFixed(2) + "°\n" +
                    "Smooth Pitch        : " + smoothpitch.toFixed(2) + "°\n" +
                    "Effective Pitch Kp  : " + scaledkp.toFixed(0) + " \n" +
                    "Roll                : " + roll.toFixed(2) + "°\n" +
                    "Roll Kp             : " + rollkp.toFixed(2) + "\n" +
                    "Last Surge Time     : " + surge_lasttime.toFixed(0) + " s\n" +
                    "Last Surge Duration : " + surge_lastcycle.toFixed(3) + " s\n" +
                    "Last Wheelslip Time : " + lastwheelslip.toFixed(0) + " s \n" +
                    "Wheelslip Duration  : " + durwheelslip.toFixed(3) + " s \n"   
  
                setpoints.text =
                    "Setpoint            : " + float_setpoint.toFixed(2) + "°\n" +
                    "RemoteTilt Setpoint : " + float_inputtilt.toFixed(2) + "°\n" +
                    "Remote Input        : " + (throttle_val * 100).toFixed(0) + "%\n"
                    
                debug.text =
                    "Time to ReverseAccel: " + startaccel1.toFixed(3) + " s \n" +  
                    "Time to Reduce Accel: " + startaccel2.toFixed(3) + " s \n" +
                    "Start ERPM Factor   : " + erpmfactor.toFixed(1) + "\n" +  
                    "Wheelslip Start Acce: " + wheelslipstart.toFixed(1) + "\n" +
                    "Wheelslip ERPM      : " + wheelsliperpm.toFixed(0) + "\n" +
                    "Wheelslip Last ERPM : " + wheelsliplasterpm.toFixed(0) + "\n" +
                    "Wheelslip Debug/Last: " + debugwheelslip.toFixed(1) + "\n" +
                    "Wheelslip End Accel : " + wheelslipend.toFixed(1) + "\n" 
                }
            }
        }
    }

    Component.onCompleted: {
        restoreQuicksaveNames()
        restoreDownloadedTunes()
    }

    Dialog {
        id: quicksavePopup
        title: saveName
        standardButtons: Dialog.Save | Dialog.Discard | Dialog.Cancel
        modal: true
        focus: true
        width: parent.width - 20
        closePolicy: Popup.CloseOnEscape
        x: 10
        y: 10 + parent.height / 2 - height / 2
        parent: ApplicationWindow.overlay
        onAccepted: {
            if(quicksaveNameInput.text){
                quicksaveNames[saveName] = quicksaveNameInput.text
                quicksaveNames = quicksaveNames
                settingStorage.setValue("quicksave_names", JSON.stringify(quicksaveNames))
            }
            settingStorage.setValue(saveName, saveValue)
           
            quicksaveNameInput.text = ""
            VescIf.emitStatusMessage(saveName + " saved!", true)
        }
        onDiscarded: {
            VescIf.emitStatusMessage(quicksaveNames[saveName] + " discarded", true)

            quicksaveNames[saveName] = defaultQuicksaveNames[saveName]
            quicksaveNames = quicksaveNames
            settingStorage.setValue("quicksave_names", JSON.stringify(quicksaveNames))
            settingStorage.setValue(saveName, null)

            quicksaveNameInput.text = ""
            close()
        }
        onRejected: {
            quicksaveNameInput.text = ""
            VescIf.emitStatusMessage(saveName + " cancelled", false)
        }
        property var saveName: "Temp Name"
        property var saveValue: ""

        Overlay.modal: Rectangle {
            color: "#AA000000"
        }

        ColumnLayout {
            anchors.fill: parent
            Text {
                color: Utility.getAppHexColor("lightText")
                verticalAlignment: Text.AlignVCenter
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Do you want to overwrite this slot?"
            }
            TextField {
                id: quicksaveNameInput
                placeholderText: qsTr("Quicksave name (optional)")
                Layout.fillWidth: true
            }
        }
    }

    Dialog {
        id: downloadedTunePopup
        title: tune._name
        standardButtons: Dialog.Apply | Dialog.Cancel
        modal: true
        focus: true
        width: parent.width - 20
        closePolicy: Popup.CloseOnEscape
        x: 10
        y: 10 + parent.height / 2 - height / 2
        parent: ApplicationWindow.overlay
        onApplied: {
            applyDownloadedTune(tune)
            VescIf.emitStatusMessage(tune._name + " applied!", true)
            close()
        }
        onRejected: VescIf.emitStatusMessage(tune._name + " cancelled", false)
        property var tune: ""

        Overlay.modal: Rectangle {
            color: "#AA000000"
        }

        ColumnLayout {
            anchors.fill: parent
            Text {
                color: Utility.getAppHexColor("lightText")
                verticalAlignment: Text.AlignVCenter
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Applying this tune will OVERWRITE your current tune. Be sure to have a back-up ready if you would like to revert back at any time. Would you like to apply this tune?"
            }
        }
    }

    Dialog {
        id: quickloadErrorPopup
        title: "Quicksave Empty"
        standardButtons: Dialog.Ok
        modal: true
        focus: true
        width: parent.width - 20
        closePolicy: Popup.CloseOnEscape
        x: 10
        y: 10 + parent.height / 2 - height / 2
        parent: ApplicationWindow.overlay
        
        Overlay.modal: Rectangle {
            color: "#AA000000"
        }
        
        Text {
            color: Utility.getAppHexColor("lightText")
            verticalAlignment: Text.AlignVCenter
            anchors.fill: parent
            wrapMode: Text.WordWrap
            text: "Long Press a Quicksave slot to name and save your current tune, then tap it anytime to apply it instantly."
        }
    }

    ColumnLayout {
        id: root
        anchors.fill: parent
    

        TabBar {
            id: tabBar
            currentIndex: 0
            Layout.fillWidth: true
            clip: true
            enabled: true

            background: Rectangle {
                opacity: 1
                color: {color = Utility.getAppHexColor("lightBackground")}
            }
            property int buttons: 2
            property int buttonWidth: 120

            Repeater {
                model: ["RT Data", "Tunes"]
                TabButton {
                    text: modelData
                    onClicked:{
                        stackLayout.currentIndex = index
                    }
                }
            }
        }
        
        StackLayout {
            id: stackLayout
            Layout.fillWidth: true
            Layout.fillHeight: true
            // onCurrentIndexChanged: {tabBar.currentIndex = currentIndex

            ColumnLayout { // RT Data Page
                id: rtDataColumn
                
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    
                    ColumnLayout {
                        Text {
                            id: header0
                            color: Utility.getAppHexColor("lightText")
                            font.family: "DejaVu Sans Mono"
                            Layout.margins: 0
                            Layout.leftMargin: 0
                            Layout.fillWidth: true
                            text: "Trick n Trail App State"
                            font.underline: true
                            font.weight: Font.Black
                            font.pointSize: 14
                        }
                        Text {
                            id: rt_state
                            color: Utility.getAppHexColor("lightText")
                            font.family: "DejaVu Sans Mono"
                            Layout.margins: 0
                            Layout.leftMargin: 5
                            Layout.preferredWidth: parent.width/3
                            text: "Waiting for RT Data"
                        }
                        Text {
                            id: header1
                            color: Utility.getAppHexColor("lightText")
                            font.family: "DejaVu Sans Mono"
                            Layout.margins: 0
                            Layout.leftMargin: 0
                            Layout.fillWidth: true
                            text: "Trick n Trail App RT Data"
                            font.underline: true
                            font.weight: Font.Black
                            font.pointSize: 14
                        }
                        Text {
                            id: rt_data
                            color: Utility.getAppHexColor("lightText")
                            font.family: "DejaVu Sans Mono"
                            Layout.margins: 0
                            Layout.leftMargin: 5
                            Layout.preferredWidth: parent.width/3
                            text: "-\n"
                        }
                        Text {
                            id: header2
                            color: Utility.getAppHexColor("lightText")
                            font.family: "DejaVu Sans Mono"
                            Layout.margins: 0
                            Layout.leftMargin: 0
                            Layout.fillWidth: true
                            text: "Setpoints"
                            font.underline: true
                            font.weight: Font.Black
                            font.pointSize: 14
                        }
                        Text {
                            id: setpoints
                            color: Utility.getAppHexColor("lightText")
                            font.family: "DejaVu Sans Mono"
                            Layout.margins: 0
                            Layout.leftMargin: 5
                            Layout.preferredWidth: parent.width/3
                            text: "-\n"
                        }
                        Text {
                            id: header3
                            color: Utility.getAppHexColor("lightText")
                            font.family: "DejaVu Sans Mono"
                            Layout.margins: 0
                            Layout.leftMargin: 0
                            Layout.fillWidth: true
                            text: "DEBUG"
                            font.underline: true
                            font.weight: Font.Black
                        }
                        Text {
                            id: debug
                            color: Utility.getAppHexColor("lightText")
                            font.family: "DejaVu Sans Mono"
                            Layout.margins: 0
                            Layout.leftMargin: 5
                            Layout.preferredWidth: parent.width/3
                            text: "-"
                        }
                    }
                }
            }

            ColumnLayout { // Tunes Page
                id: tunesColumn

                Text {
                    id: floatQuicksaveHeader
                    color: Utility.getAppHexColor("lightText")
                    font.family: "DejaVu Sans Mono"
                    Layout.margins: 0
                    Layout.fillWidth: true
                    text: "Trick n Trail Package Quicksave Slots"
                    font.underline: true
                    font.weight: Font.Black
                    font.pointSize: 14
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    Repeater {
                        model: [
                            "TNT Quicksave 1", "TNT Quicksave 2", "TNT Quicksave 3",
                            "TNT Quicksave 4", "TNT Quicksave 5", "TNT Quicksave 6"
                        ]
                        Button {
                            text: quicksaveNames[modelData]
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            onPressAndHold: {
                                quicksaveFloat(modelData)
                            }
                            onClicked: {
                                quickloadFloat(modelData)
                            }
                        }
                    }
                }

                Text {
                    id: imuQuicksaveHeader
                    color: Utility.getAppHexColor("lightText")
                    font.family: "DejaVu Sans Mono"
                    Layout.margins: 0
                    Layout.fillWidth: true
                    text: "IMU Config Quicksave Slots"
                    font.underline: true
                    font.weight: Font.Black
                    font.pointSize: 14
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    Repeater {
                        model: ["IMU Quicksave 1", "IMU Quicksave 2"]
                        Button {
                            text: quicksaveNames[modelData]
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            onPressAndHold: {
                                quicksaveIMU(modelData)
                            }
                            onClicked: {
                                quickloadIMU(modelData)
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        id: tunesHeader
                        color: Utility.getAppHexColor("lightText")
                        font.family: "DejaVu Sans Mono"
                        Layout.margins: 0
                        Layout.fillWidth: true
                        text: "Tunes Archive"
                        font.underline: true
                        font.weight: Font.Black
                        font.pointSize: 14
                    }

                    Button {
                        id: downloadTunesButton
                        text: "Refresh"
                        Layout.alignment: Qt.AlignCenter
                        onClicked: {
                            downloadTunesButton.text = "Downloading Tunes..."
                            downloadedTunesModel.clear()
                            var http = new XMLHttpRequest()
                            // var url = "http://docs.google.com/spreadsheets/d/1bPH-gviDFyXvxx5s2cjs5BWTjqJOmRqB4Xi59itxbJ8/export?format=csv"
                            var url = "http://us-central1-mimetic-union-377520.cloudfunctions.net/float_package_tunes_via_http"
                            http.open("GET", url, true);
                            http.onreadystatechange = function() {
                                if (http.readyState == XMLHttpRequest.DONE) {
                                    downloadTunesButton.text = "Refresh"
                                    if (http.status == 200) {
                                        settingStorage.setValue("tunes_csv", http.responseText)
                                        restoreDownloadedTunes()
                                        VescIf.emitStatusMessage("Tune Download Success", true)
                                    } else {
                                        VescIf.emitStatusMessage("Tune Download Failed: " + http.status, false)
                                    }
                                }
                            }
                            http.send()
                        }
                    }
                }

                ListView {
                    id: downloadedTunesList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 5

                    model: ListModel {
                        id: downloadedTunesModel
                    }
                    delegate: Button {
                        text: tune._name
                        width: parent.width
                        onClicked: {
                            downloadedTunePopup.tune = tune
                            downloadedTunePopup.open()
                        }
                    }
                }

            }
                
        }
    }

    function quicksaveFloat(saveName){
        var params = [
            // {"name": "float_version", "type": "Double"},
            // {"name": "float_disable", "type": "Double"},
            {"name": "kp", "type": "Double"},
            {"name": "ki", "type": "Double"},
            {"name": "kd", "type": "Double"},
            {"name": "kp2", "type": "Double"},
            {"name": "mahony_kp", "type": "Double"},
            // {"name": "hertz", "type": "Int"},
            {"name": "fault_pitch", "type": "Double"},
            {"name": "fault_roll", "type": "Double"},
            // {"name": "fault_adc1", "type": "Double"},
            // {"name": "fault_adc2", "type": "Double"},
            {"name": "fault_delay_pitch", "type": "Int"},
            {"name": "fault_delay_roll", "type": "Int"},
            {"name": "fault_delay_switch_half", "type": "Int"},
            {"name": "fault_delay_switch_full", "type": "Int"},
            {"name": "fault_adc_half_erpm", "type": "Int"},
            {"name": "fault_is_dual_switch", "type": "Bool"},
            {"name": "fault_moving_fault_disabled", "type": "Bool"},
            {"name": "fault_darkride_enabled", "type": "Bool"},
            {"name": "fault_reversestop_enabled", "type": "Bool"},
            {"name": "tiltback_duty_angle", "type": "Double"},
            {"name": "tiltback_duty_speed", "type": "Double"},
            {"name": "tiltback_duty", "type": "Double"},
            {"name": "tiltback_hv_angle", "type": "Double"},
            {"name": "tiltback_hv_speed", "type": "Double"},
            // {"name": "tiltback_hv", "type": "Double"},
            {"name": "tiltback_lv_angle", "type": "Double"},
            {"name": "tiltback_lv_speed", "type": "Double"},
            // {"name": "tiltback_lv", "type": "Double"},
            {"name": "tiltback_return_speed", "type": "Double"},
            {"name": "tiltback_constant", "type": "Double"},
            {"name": "tiltback_constant_erpm", "type": "Int"},
            {"name": "tiltback_variable", "type": "Double"},
            {"name": "tiltback_variable_max", "type": "Double"},
            {"name": "tiltback_variable_erpm", "type": "Int"},
            // {"name": "inputtilt_remote_type", "type": "Enum"},
            {"name": "inputtilt_speed", "type": "Double"},
            {"name": "inputtilt_angle_limit", "type": "Double"},
            {"name": "inputtilt_smoothing_factor", "type": "Int"},
            {"name": "inputtilt_invert_throttle", "type": "Bool"},
            // {"name": "inputtilt_deadband", "type": "Double"},
            {"name": "remote_throttle_current_max", "type": "Double"},
            {"name": "remote_throttle_grace_period", "type": "Double"},
            {"name": "noseangling_speed", "type": "Double"},
            {"name": "startup_pitch_tolerance", "type": "Double"},
            {"name": "startup_roll_tolerance", "type": "Double"},
            {"name": "startup_speed", "type": "Double"},
            {"name": "startup_click_current", "type": "Double"},
            {"name": "startup_simplestart_enabled", "type": "Bool"},
            {"name": "startup_pushstart_enabled", "type": "Bool"},
            {"name": "startup_dirtylandings_enabled", "type": "Bool"},
            {"name": "brake_current", "type": "Double"},
            {"name": "ki_limit", "type": "Double"},
            {"name": "booster_angle", "type": "Double"},
            {"name": "booster_ramp", "type": "Double"},
            {"name": "booster_current", "type": "Double"},
            {"name": "brkbooster_angle", "type": "Double"},
            {"name": "brkbooster_ramp", "type": "Double"},
            {"name": "brkbooster_current", "type": "Double"},
            {"name": "torquetilt_start_current", "type": "Double"},
            {"name": "torquetilt_angle_limit", "type": "Double"},
            {"name": "torquetilt_on_speed", "type": "Double"},
            {"name": "torquetilt_off_speed", "type": "Double"},
            {"name": "torquetilt_strength", "type": "Double"},
            {"name": "torquetilt_strength_regen", "type": "Double"},
            {"name": "atr_strength_up", "type": "Double"},
            {"name": "atr_strength_down", "type": "Double"},
            {"name": "atr_threshold_up", "type": "Double"},
            {"name": "atr_threshold_down", "type": "Double"},
            {"name": "atr_torque_offset", "type": "Double"},
            {"name": "atr_speed_boost", "type": "Double"},
            {"name": "atr_angle_limit", "type": "Double"},
            {"name": "atr_on_speed", "type": "Double"},
            {"name": "atr_off_speed", "type": "Double"},
            {"name": "atr_response_boost", "type": "Double"},
            {"name": "atr_transition_boost", "type": "Double"},
            {"name": "atr_filter", "type": "Double"},
            // {"name": "atr_amps_accel_ratio", "type": "Double"},
            // {"name": "atr_amps_decel_ratio", "type": "Double"},
            {"name": "braketilt_strength", "type": "Double"},
            {"name": "braketilt_lingering", "type": "Double"},
            {"name": "turntilt_strength", "type": "Double"},
            {"name": "turntilt_angle_limit", "type": "Double"},
            {"name": "turntilt_start_angle", "type": "Double"},
            {"name": "turntilt_start_erpm", "type": "Int"},
            {"name": "turntilt_speed", "type": "Double"},
            {"name": "turntilt_erpm_boost", "type": "Int"},
            {"name": "turntilt_erpm_boost_end", "type": "Int"},
            {"name": "turntilt_yaw_aggregate", "type": "Int"},
            // {"name": "dark_pitch_offset", "type": "Double"},
            {"name": "is_buzzer_enabled", "type": "Bool"},
            {"name": "is_dutybuzz_enabled", "type": "Bool"},
            {"name": "is_footbuzz_enabled", "type": "Bool"},
            {"name": "is_surgebuzz_enabled", "type": "Bool"},
            {"name": "surge_duty_start", "type": "Double"},
            {"name": "surge_angle", "type": "Double"}
        ]
        for(var i in params){
            if(params[i].type == ("Double")){
                params[i].value = mCustomConf.getParamDouble(params[i].name)
            }else if(params[i].type == ("Int")){
                params[i].value = mCustomConf.getParamInt(params[i].name)
            }else if(params[i].type == ("Bool")){
                params[i].value = mCustomConf.getParamBool(params[i].name)
            }else if(params[i].type == ("Enum")){
                params[i].value = mCustomConf.getParamEnum(params[i].name)
            }
        }

        quicksavePopup.saveName = saveName
        quicksavePopup.saveValue = JSON.stringify(params)
        quicksavePopup.open()
    }

    function quickloadFloat(saveName){
        var json = settingStorage.value(saveName, "")
        if(!json){
            quickloadErrorPopup.open()
        }else{
            var params = JSON.parse(json)
            for(var i in params){
                if(params[i].type == ("Double")){
                    mCustomConf.updateParamDouble(params[i].name, params[i].value)
                }else if(params[i].type == ("Int")){
                    mCustomConf.updateParamInt(params[i].name, params[i].value)
                }else if(params[i].type == ("Bool")){
                    mCustomConf.updateParamBool(params[i].name, params[i].value)
                }else if(params[i].type == ("Enum")){
                    mCustomConf.updateParamEnum(params[i].name, params[i].value)
                }
            }
            mCommands.customConfigSet(0, mCustomConf)
        }
    }

    function quicksaveIMU(saveName){
        var params = [
            {"name": "imu_conf.mode", "type": "Enum"},
            {"name": "imu_conf.filter", "type": "Enum"},
            {"name": "imu_conf.accel_lowpass_filter_x", "type": "Double"},
            {"name": "imu_conf.accel_lowpass_filter_y", "type": "Double"},
            {"name": "imu_conf.accel_lowpass_filter_z", "type": "Double"},
            {"name": "imu_conf.gyro_lowpass_filter", "type": "Double"},
            {"name": "imu_conf.sample_rate_hz", "type": "Int"},
            {"name": "imu_conf.use_magnetometer", "type": "Bool"},
            {"name": "imu_conf.accel_confidence_decay", "type": "Double"},
            {"name": "imu_conf.mahony_kp", "type": "Double"},
            {"name": "imu_conf.mahony_ki", "type": "Double"},
            {"name": "imu_conf.madgwick_beta", "type": "Double"},
            {"name": "imu_conf.rot_roll", "type": "Double"},
            {"name": "imu_conf.rot_pitch", "type": "Double"},
            {"name": "imu_conf.rot_yaw", "type": "Double"},
            {"name": "imu_conf.accel_offsets__0", "type": "Double"},
            {"name": "imu_conf.accel_offsets__1", "type": "Double"},
            {"name": "imu_conf.accel_offsets__2", "type": "Double"},
            {"name": "imu_conf.gyro_offsets__0", "type": "Double"},
            {"name": "imu_conf.gyro_offsets__0", "type": "Double"},
            {"name": "imu_conf.gyro_offsets__0", "type": "Double"}
        ]
        for(var i in params){
            if(params[i].type == ("Double")){
                params[i].value = mAppConf.getParamDouble(params[i].name)
            }else if(params[i].type == ("Int")){
                params[i].value = mAppConf.getParamInt(params[i].name)
            }else if(params[i].type == ("Bool")){
                params[i].value = mAppConf.getParamBool(params[i].name)
            }else if(params[i].type == ("Enum")){
                params[i].value = mAppConf.getParamEnum(params[i].name)
            }
        }

        quicksavePopup.saveName = saveName
        quicksavePopup.saveValue = JSON.stringify(params)
        quicksavePopup.open()
    }

    function quickloadIMU(saveName){
        var json = settingStorage.value(saveName, "")
        if(!json){
            quickloadErrorPopup.open()
        }else{
            var params = JSON.parse(json)
            for(var i in params){
                if(params[i].type == ("Double")){
                    mAppConf.updateParamDouble(params[i].name, params[i].value)
                }else if(params[i].type == ("Int")){
                    mAppConf.updateParamInt(params[i].name, params[i].value)
                }else if(params[i].type == ("Bool")){
                    mAppConf.updateParamBool(params[i].name, params[i].value)
                }else if(params[i].type == ("Enum")){
                    mAppConf.updateParamEnum(params[i].name, params[i].value)
                }
            }
            mCommands.setAppConf()
        }
    }

    function restoreDownloadedTunes(){
        var tunes = parseCSV(settingStorage.value("tunes_csv", ""))
        for(var i in tunes){
            downloadedTunesModel.append({"tune": tunes[i]})
        }
    }

    function parseCSV(csv){
        var lines=csv.split("\r\n");
        var result = [];
        var tuneCount = lines[0].split(",").length - 1;

        for(var i=0; i < tuneCount; i++){
            result.push({})
        }

        for(var i=0; i<lines.length; i++) {
            var currentLine=lines[i].split(",")
            for(var j=0; j < tuneCount; j++) {
                if(currentLine[j+1]){
                    result[j][currentLine[0]] = currentLine[j+1]
                }
            }
        }

        return result; //JavaScript object
        // return JSON.stringify(result); //JSON
    }

    function applyDownloadedTune(tune){
        for (const [key, value] of Object.entries(tune)) {
            if(!key.startsWith("_")){
                var actualKey
                if(key.startsWith("double_")){
                    mCustomConf.updateParamDouble(key.substring(7), value)
                }else if(key.startsWith("int_")){
                    mCustomConf.updateParamInt(key.substring(4), value)
                }else if(key.startsWith("bool_")){
                    mCustomConf.updateParamBool(key.substring(5), parseInt(value))
                }else if(key.startsWith("enum_")){
                    mCustomConf.updateParamEnum(key.substring(5), value)
                }
                mCommands.customConfigSet(0, mCustomConf)
            }
        }
    }

    function restoreQuicksaveNames(){
        var json = settingStorage.value("quicksave_names", "")
        if(!json){
            quicksaveNames = defaultQuicksaveNames
        }else{
            quicksaveNames = JSON.parse(json)
        }
    }

}


