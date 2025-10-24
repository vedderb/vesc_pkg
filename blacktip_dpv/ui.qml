import Vedder.vesc.vescinterface 1.0
import "qrc:/mobile"

import QtQuick 2.7
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3
import QtQuick.Controls.Material 2.2

import Vedder.vesc.utility 1.0
import Vedder.vesc.commands 1.0
import Vedder.vesc.configparams 1.0

Item {
    id: dxrtData

    anchors.fill: parent
    anchors.margins: 10

    readonly property string const_BLACKTIP_DPV_VERSION: "<unknown>"
    readonly property string const_BLACKTIP_DPV_RELEASE_DATE: "<unknown>"

    readonly property var const_SCOOTER_MODELS: [
        "Blacktip series 2, with Bluetooth",
        "Blacktip series 2, No Bluetooth",
        "Blacktip series 1, No Bluetooth",
        "CudaX, With Bluetooth",
        "CudaX, No Bluetooth",
    ]

    readonly property int const_RELOAD_DELAY_MS: 1000


    property Commands mCommands: VescIf.commands()
    property ConfigParams mMcConf: VescIf.mcConfig()
    property ConfigParams mInfoConf: VescIf.infoConfig()
    property ConfigParams mAppConf: VescIf.appConfig()

    property bool readSettingsDone: false

    // Callback holder for delay timer
    property var _delayCb: null

    property int gaugeSize: big.width * 0.8
    property int gaugeSize2: big.width * 0.45

    property bool loading_values: false

    property string firmwareVersion: "&lt;unknown$gt;"

    property string detectedHardwareModel: "<unknown>"
    property string possibleScooterModels: ""

    Component.onCompleted: {
        mCommands.emitEmptySetupValues()
        updateFwText()
    }

    ColumnLayout {
        anchors.fill: parent

        TabBar {
            id: tabBar
            currentIndex: swipeView.currentIndex
            Layout.fillWidth: true
            implicitWidth: 0
            clip: true

            property int buttons: 3
            property int buttonWidth: 120

            TabButton {
                id: tab
                text: qsTr("Home")
                width: Math.max(tabBar.buttonWidth, tabBar.width / tabBar.buttons)
            }
            TabButton {
                text: qsTr("Settings")
                width: Math.max(tabBar.buttonWidth, tabBar.width / tabBar.buttons)
            }
            TabButton {
                text: qsTr("Speeds")
                width: Math.max(tabBar.buttonWidth, tabBar.width / tabBar.buttons)
            }
        }

        SwipeView {
            id: swipeView
            currentIndex: tabBar.currentIndex
            Layout.fillHeight: true
            Layout.fillWidth: true
            clip: true

            // Home page settings.
            Page {
                ScrollView {
                    id: homeScroll
                    anchors.fill: parent
                    clip: true
                    contentWidth: availableWidth

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        Rectangle {
                            id: big
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: "transparent"

                            CustomGauge {
                                id: speedGauge
                                width: gaugeSize
                                height:big.width
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.horizontalCenterOffset: -big.width / 10
                                anchors.verticalCenter: big.top
                                anchors.verticalCenterOffset: big.width / 1.9 + tab.height
                                minimumValue: -400
                                maximumValue: 1100
                                minAngle: -250
                                maxAngle: 12
                                labelStep: 200
                                value: 0
                                typeText: "RPM"

                                Image {
                                    anchors.centerIn: parent
                                    antialiasing: true
                                    height: big.width * 0.2
                                    fillMode: Image.PreserveAspectFit
                                    source : "https://raw.githubusercontent.com/vedderb/vesc_pkg/main/blacktip_dpv/assets/shark_with_laser.png"

                                    anchors.horizontalCenterOffset: -(big.width)/3.7
                                    anchors.verticalCenterOffset: -(big.width)/1.9
                                }

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text:
                                        "<b><u>Blacktip DPV:</u></b><br>" +
                                        "Configured scooter model:<br>" +
                                        "- " + (hardware_configuration.currentIndex >= 0 ? const_SCOOTER_MODELS[hardware_configuration.currentIndex] : "&lt;unknown&gt;") + "<br>" +
                                        "Runtime version:<br>" +
                                        "- " + const_BLACKTIP_DPV_VERSION + "<br>" +
                                        "Runtime build timestamp:<br>" +
                                        "- " + const_BLACKTIP_DPV_RELEASE_DATE + "<br>" +
                                        "VESC firmware version:<br>" +
                                        "- " + firmwareVersion
                                    font.pixelSize: big.width/22.0
                                    verticalAlignment: Text.AlignVCenter
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: 1.05 * big.width
                                    anchors.horizontalCenterOffset: 0.05 * big.width
                                    font.family:  "Roboto"
                                }

                                CustomGauge {
                                    id: batteryGauge
                                    width: gaugeSize2*1.2
                                    height: gaugeSize2*1.2
                                    anchors.centerIn: parent
                                    anchors.horizontalCenterOffset: 0.4 * gaugeSize
                                    anchors.verticalCenterOffset: -0.4 * gaugeSize
                                    minAngle: 10
                                    maxAngle: 350
                                    minimumValue: 0
                                    maximumValue: 100
                                    value: 0
                                    centerTextVisible: false
                                    property color greenColor: "green"
                                    property color orangeColor: Utility.getAppHexColor("orange")
                                    property color redColor: "red"
                                    nibColor: value > 50 ? greenColor : value > 20 ? orangeColor : redColor

                                    Text {
                                        id: batteryLabel
                                        color: Utility.getAppHexColor("lightText")
                                        text: "BATTERY"
                                        font.pixelSize: gaugeSize2/18.0
                                        verticalAlignment: Text.AlignVCenter
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: - gaugeSize2*0.12
                                        anchors.margins: 10
                                        font.family:  "Roboto"
                                    }

                                    Text {
                                        id: battValLabel
                                        color: Utility.getAppHexColor("lightText")
                                        text: parseFloat(batteryGauge.value).toFixed(0) +"%"
                                        font.pixelSize: gaugeSize2/6.0
                                        verticalAlignment: Text.AlignVCenter
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: gaugeSize2*0.015
                                        anchors.margins: 10
                                        font.family:  "Roboto"
                                    }

                                    Behavior on nibColor {
                                        ColorAnimation {
                                            duration: 1000;
                                            easing.type: Easing.InOutSine
                                            easing.overshoot: 3
                                        }
                                    }
                                }
                            }

                            CustomGauge {
                                id: escTempGauge
                                width:gaugeSize2
                                height:gaugeSize2
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.horizontalCenterOffset: -0.25 *big.width
                                anchors.verticalCenter: big.top
                                anchors.verticalCenterOffset: (1.05 * big.width) + tab.height

                                minimumValue: 0
                                maximumValue: 100
                                value: 0
                                labelStep: 20
                                property real throttleStartValue: 70
                                property color blueColor: Utility.getAppHexColor("tertiary2")
                                property color orangeColor: Utility.getAppHexColor("orange")
                                property color redColor: "red"
                                nibColor: value > throttleStartValue ? redColor : (value > 40 ? orangeColor: blueColor)
                                Behavior on nibColor {
                                    ColorAnimation {
                                        duration: 1000;
                                        easing.type: Easing.InOutSine
                                        easing.overshoot: 3
                                    }
                                }
                                unitText: "°C"
                                typeText: "TEMP\nESC"
                                minAngle: -160
                                maxAngle: 160
                            }

                            CustomGauge {
                                id: motTempGauge
                                width: gaugeSize2
                                height: gaugeSize2
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.horizontalCenterOffset: 0.25 *big.width
                                anchors.verticalCenter: big.top
                                anchors.verticalCenterOffset: (1.05 * big.width) + tab.height
                                maximumValue: 200
                                minimumValue: 0
                                minAngle: -160
                                maxAngle: 160
                                labelStep: 20
                                value: 0
                                unitText: "°C"
                                typeText: "TEMP\nMOTOR"
                                property real throttleStartValue: 70
                                property color blueColor: Utility.getAppHexColor("tertiary2")
                                property color orangeColor: Utility.getAppHexColor("orange")
                                property color redColor: "red"
                                nibColor: value > throttleStartValue ? redColor : (value > 40 ? orangeColor: blueColor)
                                Behavior on nibColor {
                                    ColorAnimation {
                                        duration: 1000;
                                        easing.type: Easing.InOutSine
                                        easing.overshoot: 3
                                    }
                                }
                            }
                        }
                    }
                }
            }

            /// Settings Page
            Page {
                background: Rectangle {
                    opacity: 0.0
                }

                ScrollView {
                    id: settingsScroll
                    anchors.fill: parent
                    clip: true
                    contentWidth: availableWidth

                    property bool has_changes: false

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        DoubleSpinBox {
                            id: no_speeds
                            Layout.fillWidth: true
                            decimals: 0
                            prefix: "No. Speeds: "
                            realFrom: 1
                            realTo: 8
                            realValue: 8
                            realStepSize: 1.0
                            onRealValueChanged: {
                               if (!loading_values) {
                                   settingsScroll.has_changes = true
                               }
                            }
                        }

                        DoubleSpinBox {
                            id: start_speed
                            Layout.fillWidth: true
                            decimals: 0
                            prefix: "Start Speed: "
                            realFrom: 1
                            realTo: no_speeds.realValue
                            realValue: 3
                            realStepSize: 1.0
                            onRealValueChanged: {
                               if (!loading_values) {
                                   settingsScroll.has_changes = true
                               }
                            }
                        }

                        DoubleSpinBox {
                            id: jump_speed
                            Layout.fillWidth: true
                            decimals: 0
                            prefix: "Jump Speed (3 Clicks while stopped): "
                            realFrom: 1
                            realTo: no_speeds.realValue
                            realValue: 6
                            realStepSize: 1.0
                            onRealValueChanged: {
                               if (!loading_values) {
                                   settingsScroll.has_changes = true
                               }
                            }
                        }

                        DoubleSpinBox {
                            id: ramp_rate
                            Layout.fillWidth: true
                            decimals: 0
                            prefix: "Speed Ramp Rate: "
                            realFrom: 600
                            realTo: 8000
                            realValue: 5000
                            realStepSize: 200
                            onRealValueChanged: {
                               if (!loading_values) {
                                   settingsScroll.has_changes = true
                               }
                            }
                        }

                        CheckBox {
                            id: safe_start
                            Layout.fillWidth: true
                            text: "Enable Safe Start"
                            checked: false
                            onClicked: {
                               if (!loading_values) {
                                   settingsScroll.has_changes = true
                               }
                            }
                        }

                        RowLayout {
                            spacing: 10 // Space between the buttons

                            Button {
                                Layout.fillWidth: true
                                text: "Undo Changes"
                                enabled: settingsScroll.has_changes
                                onClicked: {
                                    read_settings()

                                    settingsScroll.has_changes = false
                                }
                            }

                            Button {
                                Layout.fillWidth: true
                                text: "Save"
                                enabled: settingsScroll.has_changes
                                onClicked: {
                                    mMcConf.updateParamDouble("s_pid_ramp_erpms_s", ramp_rate.realValue, null)
                                    mCommands.setMcconf(false)

                                    write_settings()

                                    settingsScroll.has_changes = false
                                }
                            }
                        }

                        Button {
                            Layout.fillWidth: true
                            text: "Enable Smart Cruise (3 clicks while running)"
                            onClicked: {
                                smartCruiseDialog.open()
                            }
                        }

                        Button {
                            Layout.fillWidth: true
                            text: "Enable Untangle && Reverse (4 Clicks while stopped)"
                            onClicked: {
                                reverseDialog.open()
                            }
                        }

                        Button {
                            Layout.fillWidth: true
                            text: "Battery Configuration"
                            onClicked: {
                                batteryDialog.open()
                            }
                        }

                        Button {
                            Layout.fillWidth: true
                            text: "Beeper && Display Configuration"
                            onClicked: {
                                beeperDisplayDialog.open()
                            }
                        }

                        Item {
                            Layout.fillHeight: true
                            Layout.fillWidth: true
                        }

                        Button {
                            Layout.fillWidth: true
                            text: "Scooter Hardware Configuration"
                            onClicked: {
                                hardwareDialog.open()
                            }
                        }
                    }
                }
            }

            // Speeds Page
            Page {
                background: Rectangle {
                    opacity: 0.0
                }

                ScrollView {
                    id: speedsScroll
                    anchors.fill: parent
                    clip: true
                    contentWidth: availableWidth

                    property bool has_changes: false

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        DoubleSpinBox {
                            id: reverse_speed
                            Layout.fillWidth: true
                            visible: enable_reverse.checked
                            decimals: 0
                            prefix: "Reverse Speed: "
                            suffix: " %"
                            realFrom: 20
                            realTo: 50
                            realValue: 45
                            realStepSize: 1.0
                            onRealValueChanged: {
                               if (!loading_values) {
                                   speedsScroll.has_changes = true
                               }
                            }
                        }

                        DoubleSpinBox {
                            id: untangle_speed
                            Layout.fillWidth: true
                            visible: enable_reverse.checked
                            decimals: 0
                            prefix: "Untangle Speed: "
                            suffix: " %"
                            realFrom: (hardware_configuration.currentIndex < 2) ? 20 : 10
                            realTo: 30
                            realValue: 20
                            realStepSize: 1.0
                            onRealValueChanged: {
                                if (!loading_values) {
                                    speedsScroll.has_changes = true
                                }
                            }
                        }


                        DoubleSpinBox {
                            id: one_speed
                            Layout.fillWidth: true
                            decimals: 0
                            prefix: "Speed 1: "
                            suffix: " %"
                            realFrom: 20
                            realTo: 100
                            realValue: 30
                            realStepSize: 1.0
                            onRealValueChanged: {
                                if (!loading_values) {
                                    speedsScroll.has_changes = true
                                }
                            }
                        }

                        DoubleSpinBox {
                            id: two_speed
                            Layout.fillWidth: true
                            visible: no_speeds.realValue > 1
                            decimals: 0
                            prefix: "Speed 2: "
                            suffix: " %"
                            realFrom: 20
                            realTo: 100
                            realValue: 38
                            realStepSize: 1.0
                            onRealValueChanged: {
                                if (!loading_values) {
                                    speedsScroll.has_changes = true
                                }
                            }
                        }

                        DoubleSpinBox {
                            id: three_speed
                            Layout.fillWidth: true
                            visible: no_speeds.realValue > 2
                            decimals: 0
                            prefix: "Speed 3: "
                            suffix: " %"
                            realFrom: 20
                            realTo: 100
                            realValue: 46
                            realStepSize: 1.0
                            onRealValueChanged: {
                                if (!loading_values) {
                                    speedsScroll.has_changes = true
                                }
                            }
                        }

                        DoubleSpinBox {
                            id: four_speed
                            Layout.fillWidth: true
                            visible: no_speeds.realValue > 3
                            decimals: 0
                            prefix: "Speed 4: "
                            suffix: " %"
                            realFrom: 20
                            realTo: 100
                            realValue: 54
                            realStepSize: 1.0
                            onRealValueChanged: {
                                if (!loading_values) {
                                    speedsScroll.has_changes = true
                                }
                            }
                        }

                        DoubleSpinBox {
                            id: five_speed
                            Layout.fillWidth: true
                            visible: no_speeds.realValue > 4
                            decimals: 0
                            prefix: "Speed 5: "
                            suffix: " %"
                            realFrom: 20
                            realTo: 100
                            realValue: 62
                            realStepSize: 1.0
                            onRealValueChanged: {
                                if (!loading_values) {
                                    speedsScroll.has_changes = true
                                }
                            }
                        }

                        DoubleSpinBox {
                            id: six_speed
                            Layout.fillWidth: true
                            visible: no_speeds.realValue > 5
                            decimals: 0
                            prefix: "Speed 6: "
                            suffix: " %"
                            realFrom: 20
                            realTo: 100
                            realValue: 70
                            realStepSize: 1.0
                            onRealValueChanged: {
                                if (!loading_values) {
                                    speedsScroll.has_changes = true
                                }
                            }
                        }

                        DoubleSpinBox {
                            id: seven_speed
                            Layout.fillWidth: true
                            visible: no_speeds.realValue > 6
                            decimals: 0
                            prefix: "Speed 7: "
                            suffix: " %"
                            realFrom: 20
                            realTo: 100
                            realValue: 78
                            realStepSize: 1.0
                            onRealValueChanged: {
                                if (!loading_values) {
                                    speedsScroll.has_changes = true
                                }
                            }
                        }

                        DoubleSpinBox {
                            id: eight_speed
                            Layout.fillWidth: true
                            visible: no_speeds.realValue > 7
                            decimals: 0
                            prefix: "Speed 8: "
                            suffix: " %"
                            realFrom: 20
                            realTo: 100
                            realValue: 100
                            realStepSize: 1.0
                            onRealValueChanged: {
                                if (!loading_values) {
                                    speedsScroll.has_changes = true
                                }
                            }
                        }

                        RowLayout {
                            spacing: 10 // Space between the buttons

                            Button {
                                Layout.fillWidth: true
                                text: "Undo Changes"
                                enabled: speedsScroll.has_changes
                                onClicked: {
                                    read_settings()

                                    speedsScroll.has_changes = false
                                }
                            }

                            Button {
                                Layout.fillWidth: true
                                text: "Save"
                                enabled: speedsScroll.has_changes
                                onClicked: {
                                    write_settings()

                                    speedsScroll.has_changes = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // handshake timmer to initiate first transfer of values from lisp
    Timer {
        repeat: true
        interval: const_RELOAD_DELAY_MS
        running: true

        onTriggered: {

            if (readSettingsDone) {
                return
            }
            var buffer = new ArrayBuffer(1)
            var da = new DataView(buffer)
            da.setUint8(0, 255) // sends 255 as a handshake that data has not yet been recieved,
            mCommands.sendCustomAppData(buffer)
            console.log("Sent values request" )
        }
    }

    // get live values for RT data when on RT page
    Timer {
        id: rtTimer
        interval: 50
        running: true
        repeat: true

        onTriggered: {
            if (swipeView.currentIndex == 0) {
                mCommands.getValues()
                mCommands.getValuesSetup()
            }
        }
    }

    // get HW and firmware values
    function updateFwText() {
        var params = VescIf.getLastFwRxParams()

        var testFwStr = "";
        var fwNameStr = "";

        if (params.isTestFw > 0) {
            testFwStr = " BETA " +  params.isTestFw
        }

        if (params.fwName !== "") {
            fwNameStr = " (" + params.fwName + ")"
        }

        if (params.major >= 0) {
            firmwareVersion = params.major + "." + (1e5 + params.minor + '').slice(-2) + fwNameStr + testFwStr
        }

        detectedHardwareModel = params.hw

        if (detectedHardwareModel == "410") {
            possibleScooterModels = "\n- " + const_SCOOTER_MODELS[2]
        } else if (detectedHardwareModel == "60") {
            possibleScooterModels = "\n- " + const_SCOOTER_MODELS[1] + "\n- " + const_SCOOTER_MODELS[4] + "\nIf upgraded with Bluetooth adaptor:\n- " + const_SCOOTER_MODELS[0] + "\n- " + const_SCOOTER_MODELS[3]
        } else if (detectedHardwareModel == "60_MK5") {
            possibleScooterModels = "\n- " + const_SCOOTER_MODELS[0] + "\n- " + const_SCOOTER_MODELS[3]
        } else {
            possibleScooterModels = ""
        }
    }

    // delay timer
    Timer {
        id: timer
        onTriggered: {
            if (_delayCb) {
                var callback = _delayCb
                _delayCb = null
                callback()
            }
        }
    }

    function delay(delayTime, cb) {
        timer.stop();
        timer.interval = Math.max(0, Math.floor(delayTime));
        timer.repeat = false;
        dxrtData._delayCb = (typeof cb === "function") ? cb : null;
        timer.start();
    }

    function doReboot(delayTime) {
        delay(0, function () {
            rebootDialog.open()

            delay(delayTime, function () {
                console.log("Rebooting..." )

                mCommands.reboot()

                delay(const_RELOAD_DELAY_MS, function () {
                    read_settings()
                })
            })
        })
    }

    function read_settings() {
        readSettingsDone = false
    }

    function write_settings () {
        if (!readSettingsDone) {
            return
        }

        var buffer = new ArrayBuffer(30)
        var da = new DataView(buffer)

        da.setUint8(0, reverse_speed.realValue)
        da.setUint8(1, untangle_speed.realValue)
        da.setUint8(2, one_speed.realValue)
        da.setUint8(3, two_speed.realValue)
        da.setUint8(4, three_speed.realValue)
        da.setUint8(5, four_speed.realValue)
        da.setUint8(6, five_speed.realValue)
        da.setUint8(7, six_speed.realValue)
        da.setUint8(8, seven_speed.realValue)
        da.setUint8(9, eight_speed.realValue)
        da.setUint8(10, no_speeds.realValue + 1) // "+ 1" convert user speed values to actuall speed values
        da.setUint8(11, start_speed.realValue + 1)
        da.setUint8(12, jump_speed.realValue + 1)
        da.setUint8(13, safe_start.checked ? 1 : 0)
        da.setUint8(14, enable_reverse.checked ? 1 : 0)
        da.setUint8(15, enable_smart_cruise.checked ? 1 : 0)
        da.setUint8(16, smart_cruise_timeout.realValue)
        da.setUint8(17, (display_rotation.realValue == 0) ? 0 : Math.round(display_rotation.realValue / 90))
        da.setUint8(18, (display_brightness.realValue == 0) ? 0 : Math.round(display_brightness.realValue / 20))
        da.setUint8(19, hardware_configuration.currentIndex)
        da.setUint8(20, enable_beeps.checked ? 1 : 0)
        da.setUint8(21, beeps_volume.realValue)
        da.setUint8(22, cudaX_Flip.checked ? 1 : 0)
        da.setUint8(23, (display_rotation2.realValue == 0) ? 0 : Math.round(display_rotation2.realValue / 90))
        da.setUint8(24, enable_tbeeps.checked ? 1 : 0)
        da.setUint8(25, enable_smart_cruise_auto_engage.checked ? 1 : 0)
        da.setUint8(26, smart_cruise_auto_engage_delay.realValue)
        da.setUint8(27, enable_thirds_warning_startup.checked ? 1 : 0)
        da.setUint8(28, use_ah_battery_calculation.checked ? 1 : 0)
        da.setUint8(29, debug_enabled.checked ? 1 : 0)
        mCommands.sendCustomAppData(buffer)

        console.log("Sent values")
    }

    function reset_defaults_blacktip() {
        var buffer1 = new ArrayBuffer(30)
        var da1 = new DataView(buffer1)
        da1.setUint8(0, 45)
        da1.setUint8(1, 20)
        da1.setUint8(2, 30)
        da1.setUint8(3, 38)
        da1.setUint8(4, 46)
        da1.setUint8(5, 54)
        da1.setUint8(6, 62)
        da1.setUint8(7, 70)
        da1.setUint8(8, 78)
        da1.setUint8(9, 100)
        da1.setUint8(10, 9)
        da1.setUint8(11, 4)
        da1.setUint8(12, 7)
        da1.setUint8(13, 1)
        da1.setUint8(14, 0)
        da1.setUint8(15, 0)
        da1.setUint8(16, 60)
        da1.setUint8(17, 0)
        da1.setUint8(18, 5)
        da1.setUint8(19, 0)
        da1.setUint8(20, 0)
        da1.setUint8(21, 3)
        da1.setUint8(22, 0)
        da1.setUint8(23, 0)
        da1.setUint8(24, 0)
        da1.setUint8(25, 0) // Enable Auto-Engage default: off
        da1.setUint8(26, 10) // Auto-Engage Delay default: 10 seconds
        da1.setUint8(27, 0) // Enable Thirds Warning Startup default: off
        da1.setUint8(28, 0) // Battery calculation method default: voltage-based
        da1.setUint8(29, 0) // Debug enabled default: off
        mCommands.sendCustomAppData(buffer1)

        // All available settings here https://github.com/vedderb/bldc/blob/master/datatypes.h

        mMcConf.updateParamInt("si_motor_poles", 5, null)
        mMcConf.updateParamDouble("l_erpm_start", 0.9, null)
        mMcConf.updateParamDouble("l_in_current_map_start", 1, null) //6.05 only
        mMcConf.updateParamDouble("l_in_current_map_filter", 0.005, null) //6.05 only
        mMcConf.updateParamDouble("l_min_erpm", -6000, null)
        mMcConf.updateParamDouble("l_max_erpm", 6000, null)

        //Motor Temp Settings
        mMcConf.updateParamInt("l_temp_motor_start", 160, null)
        mMcConf.updateParamInt("l_temp_motor_end", 180, null)
        mMcConf.updateParamDouble("l_temp_accel_dec", 0, null)
        mMcConf.updateParamEnum("m_motor_temp_sens_type", 0, null)
        mMcConf.updateParamDouble("m_ntc_motor_beta", 3950, null)
        mMcConf.updateParamBool("foc_temp_comp", 1, null)
        mMcConf.updateParamDouble("foc_temp_comp_base_temp", 67.3, null)

        //FOC Blacktip motor settings
        mMcConf.updateParamDouble("foc_motor_r", 0.1225, null)
        mMcConf.updateParamDouble("foc_motor_l", 0.00023008, null) //245.97
        mMcConf.updateParamDouble("foc_motor_ld_lq_diff", 0.00005968, null)
        mMcConf.updateParamDouble("foc_motor_flux_linkage", 0.016608, null)
        mMcConf.updateParamDouble("foc_current_kp", 0.2301, null)
        mMcConf.updateParamDouble("foc_current_ki", 122.48, null)
        mMcConf.updateParamDouble("foc_observer_gain", 3.63e+06, null)
        mMcConf.updateParamDouble("foc_openloop_rpm", 500, null)

        mMcConf.updateParamDouble("foc_sl_openloop_hyst", 0.1, null)
        mMcConf.updateParamDouble("foc_sl_openloop_time_lock", 0, null)
        mMcConf.updateParamDouble("foc_sl_openloop_time_ramp", 0.1, null)
        mMcConf.updateParamDouble("foc_sl_openloop_time", 0.05, null)
        mMcConf.updateParamDouble("foc_sl_openloop_boost_q", 20, null)
        mMcConf.updateParamDouble("foc_sl_openloop_max_q", 30, null)

        //PID Settings
        mMcConf.updateParamDouble("s_pid_min_erpm", 5, null)
        mMcConf.updateParamBool("s_pid_allow_braking", 0, null)
        mMcConf.updateParamDouble("s_pid_ramp_erpms_s", 5000, null)

        //Battery Settings
        mMcConf.updateParamEnum("si_battery_type", 0, null)
        mMcConf.updateParamInt("si_battery_cells", 10, null)
        mMcConf.updateParamDouble("si_battery_ah", 9, null)

        //Current & Voltage Settings
        mMcConf.updateParamDouble("l_current_max", 45, null)
        mMcConf.updateParamDouble("l_current_min", -45, null)
        mMcConf.updateParamDouble("l_in_current_max", 23, null)
        mMcConf.updateParamDouble("l_in_current_min", -23, null)
        mMcConf.updateParamDouble("l_abs_current_max", 75, null)
        mMcConf.updateParamDouble("l_min_vin", 29, null)
        mMcConf.updateParamDouble("l_battery_cut_start", 32, null)
        mMcConf.updateParamDouble("l_battery_cut_end", 30, null)

        // App settings for UART/Bluetooth
        mAppConf.updateParamEnum("app_to_use", 3)
        mAppConf.updateParamInt("app_uart_baudrate", 115200)
        mAppConf.updateParamEnum("shutdown_mode", 9)

        mCommands.setMcconf(false) // Write Motor settings immediatly

        delay(2000, function() {
            mCommands.setAppConf()  // Write App settings 2 seconds later

            doReboot(2000)
        })

        console.log("Defaults Reset for Blacktip")
    }

    function reset_defaults_cudax() {
        var buffer1 = new ArrayBuffer(30)
        var da1 = new DataView(buffer1)
        da1.setUint8(0, 30)
        da1.setUint8(1, 10)
        da1.setUint8(2, 20)
        da1.setUint8(3, 30)
        da1.setUint8(4, 39)
        da1.setUint8(5, 49)
        da1.setUint8(6, 59)
        da1.setUint8(7, 68)
        da1.setUint8(8, 78)
        da1.setUint8(9, 100)
        da1.setUint8(10, 9)
        da1.setUint8(11, 4)
        da1.setUint8(12, 7)
        da1.setUint8(13, 1)
        da1.setUint8(14, 0)
        da1.setUint8(15, 0)
        da1.setUint8(16, 60)
        da1.setUint8(17, 2)
        da1.setUint8(18, 5)
        da1.setUint8(19, 3)
        da1.setUint8(20, 0)
        da1.setUint8(21, 3)
        da1.setUint8(22, 0)
        da1.setUint8(23, 2)
        da1.setUint8(24, 0)
        da1.setUint8(25, 0) // Enable Auto-Engage default: off
        da1.setUint8(26, 10) // Auto-Engage Delay default: 10 seconds
        da1.setUint8(27, 0) // Enable Thirds Warning Startup default: off
        da1.setUint8(28, 0) // Battery calculation method default: voltage-based
        da1.setUint8(29, 0) // Debug enabled default: off
        mCommands.sendCustomAppData(buffer1)

        // All available settings here https://github.com/vedderb/bldc/blob/f6b06bc9f8d02d2ba262166127c3f2ffaedbb17e/datatypes.h#L369

        mMcConf.updateParamInt("si_motor_poles", 7, null)
        mMcConf.updateParamDouble("l_erpm_start", 0.9, null)
        mMcConf.updateParamDouble("l_in_current_map_start", 1, null) //6.05 only
        mMcConf.updateParamDouble("l_in_current_map_filter", 0.005, null) //6.05 only
        mMcConf.updateParamDouble("l_min_erpm", -9000, null)
        mMcConf.updateParamDouble("l_max_erpm", 9000, null)


        //Motor Temp Settings
        mMcConf.updateParamInt("l_temp_motor_start", 160, null)
        mMcConf.updateParamInt("l_temp_motor_end", 180, null)
        mMcConf.updateParamDouble("l_temp_accel_dec", 0, null)
        mMcConf.updateParamEnum("m_motor_temp_sens_type", 0, null)
        mMcConf.updateParamDouble("m_ntc_motor_beta", 3950, null)
        mMcConf.updateParamBool("foc_temp_comp", 1, null)
        mMcConf.updateParamDouble("foc_temp_comp_base_temp", 67.7, null)

        //FOC CudaX motor settings
        mMcConf.updateParamDouble("foc_motor_r", 0.0253, null)
        mMcConf.updateParamDouble("foc_motor_l", 0.00013034, null)
        mMcConf.updateParamDouble("foc_motor_ld_lq_diff", 0.00001821, null)
        mMcConf.updateParamDouble("foc_motor_flux_linkage", 0.014246, null)
        mMcConf.updateParamDouble("foc_current_kp", 0.1303, null)
        mMcConf.updateParamDouble("foc_current_ki", 25.25, null)
        mMcConf.updateParamDouble("foc_observer_gain", 4.93e+06, null)
        mMcConf.updateParamDouble("foc_openloop_rpm", 500, null)

        mMcConf.updateParamDouble("foc_sl_openloop_hyst", 0.1, null)
        mMcConf.updateParamDouble("foc_sl_openloop_time_lock", 0, null)
        mMcConf.updateParamDouble("foc_sl_openloop_time_ramp", 0.1, null)
        mMcConf.updateParamDouble("foc_sl_openloop_time", 0.05, null)
        mMcConf.updateParamDouble("foc_sl_openloop_boost_q", 20, null)
        mMcConf.updateParamDouble("foc_sl_openloop_max_q", 30, null)

        //PID Settings
        mMcConf.updateParamDouble("s_pid_min_erpm", 5, null)
        mMcConf.updateParamBool("s_pid_allow_braking", 0, null)
        mMcConf.updateParamDouble("s_pid_ramp_erpms_s", 5000, null)

        //Battery Settings
        mMcConf.updateParamEnum("si_battery_type", 0, null)
        mMcConf.updateParamInt("si_battery_cells", 10, null)
        mMcConf.updateParamDouble("si_battery_ah", 9, null)

        //Current & Voltage Settings
        mMcConf.updateParamDouble("l_current_max", 100, null)
        mMcConf.updateParamDouble("l_current_min", -100, null)
        mMcConf.updateParamDouble("l_in_current_max", 46, null)
        mMcConf.updateParamDouble("l_in_current_min", -46, null)
        mMcConf.updateParamDouble("l_abs_current_max", 150, null)
        mMcConf.updateParamDouble("l_min_vin", 29, null)
        mMcConf.updateParamDouble("l_battery_cut_start", 32, null)
        mMcConf.updateParamDouble("l_battery_cut_end", 30, null)

        // App settings for UART/Bluetooth
        mAppConf.updateParamEnum("app_to_use", 3)
        mAppConf.updateParamInt("app_uart_baudrate", 115200)
        mAppConf.updateParamEnum("shutdown_mode", 9)

        mCommands.setMcconf(false) // Write Motor settings immediatly

        delay(2000, function() {
            mCommands.setAppConf()  // Write App settings 2 seconds later

            doReboot(2000)
        })

        console.log("Defaults Reset for CudaX")
    }

    function isBlacktip(hardware_type) {
        return hardware_type < 3
    }

    Connections {
        target: mCommands

        function onCustomAppDataReceived (data) {
            var dv = new DataView(data)
            loading_values = true;

            hardware_configuration.currentIndex =  dv.getUint8(19) // set first so U spinbox range is opened up for cuda x

            reverse_speed.realValue = dv.getUint8(0)
            untangle_speed.realValue = dv.getUint8(1)
            one_speed.realValue = dv.getUint8(2)
            two_speed.realValue = dv.getUint8(3)
            three_speed.realValue = dv.getUint8(4)
            four_speed.realValue = dv.getUint8(5)
            five_speed.realValue = dv.getUint8(6)
            six_speed.realValue = dv.getUint8(7)
            seven_speed.realValue = dv.getUint8(8)
            eight_speed.realValue = dv.getUint8(9)
            no_speeds.realValue = dv.getUint8(10) -1
            start_speed.realValue = dv.getUint8(11) -1
            jump_speed.realValue = dv.getUint8(12) -1
            safe_start.checked =  dv.getUint8(13) == 1
            enable_reverse.checked =  dv.getUint8(14) == 1
            enable_smart_cruise.checked =  dv.getUint8(15) == 1
            smart_cruise_timeout.realValue = dv.getUint8(16)
            display_rotation.realValue = (dv.getUint8(17) == 0) ? 0 : dv.getUint8(17) * 90
            display_brightness.realValue = (dv.getUint8(18) == 0) ? 0 : dv.getUint8(18) * 20
            enable_beeps.checked =  dv.getUint8(20) == 1
            beeps_volume.realValue = dv.getUint8(21)
            cudaX_Flip.checked =  dv.getUint8(22) == 1
            display_rotation2.realValue = (dv.getUint8(23) == 0) ? 0 : dv.getUint8(23) * 90
            enable_tbeeps.checked =  dv.getUint8(24) == 1
            enable_smart_cruise_auto_engage.checked =  dv.getUint8(25) == 1
            smart_cruise_auto_engage_delay.realValue = dv.getUint8(26)
            enable_thirds_warning_startup.checked =  dv.getUint8(27) == 1
            use_ah_battery_calculation.checked =  dv.getUint8(28) == 1
            debug_enabled.checked =  dv.getUint8(29) == 1

            ramp_rate.realValue = mMcConf.getParamDouble("s_pid_ramp_erpms_s")
            battery_ah.realValue = mMcConf.getParamDouble("si_battery_ah")

            loading_values = false
            readSettingsDone = true

            rebootDialog.close()

            console.log("Values received")
        }
    }

    Connections {
        id: commandsUpdate
        target: mCommands

        function onValuesSetupReceived(values, mask) {

           var soc = Math.max(0, Math.min(1, values.battery_level))
           var pct = 100 * (
              4.3867 * Math.pow(soc, 4)
              - 6.7072 * Math.pow(soc, 3)
              + 2.4021 * Math.pow(soc, 2)
              + 1.3619 * soc
           )
           batteryGauge.value = Math.max(0, Math.min(100, pct))

           speedGauge.value = values.rpm / mMcConf.getParamInt("si_motor_poles")
           escTempGauge.value = values.temp_mos
           escTempGauge.maximumValue = Math.ceil(mMcConf.getParamDouble("l_temp_fet_end") / 5) * 5
           escTempGauge.throttleStartValue = Math.ceil(mMcConf.getParamDouble("l_temp_fet_start") / 5) * 5
           escTempGauge.labelStep = Math.ceil(escTempGauge.maximumValue/ 50) * 5
           motTempGauge.value = values.temp_motor
           motTempGauge.labelStep = Math.ceil(motTempGauge.maximumValue/ 50) * 5
           motTempGauge.maximumValue = Math.ceil(mMcConf.getParamDouble("l_temp_motor_end") / 5) * 5
           motTempGauge.throttleStartValue = Math.ceil(mMcConf.getParamDouble("l_temp_motor_start") / 5) * 5
        }
    }

    Dialog {
        id: reverseDialog
        standardButtons: Dialog.Save | Dialog.Cancel
        modal: true
        focus: true
        width: big.width - 20
        closePolicy: Popup.CloseOnEscape
        title: "Untangle & Reverse"

        property bool has_changes: false

        onOpened: {
            standardButton(Dialog.Save).enabled = false
        }

	    onAccepted: {
            if (has_changes) {
                write_settings()

                has_changes = false
            }
	    }

	    onRejected: {
            if (has_changes) {
	            read_settings()

                has_changes = false
            }
	    }

        function valuesChanged() {
            has_changes = true
            standardButton(Dialog.Save).enabled = true
        }

        ScrollView {
            id: reverseScroll
            anchors.fill: parent
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Text {
                    color: "#ffffff"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap

                    text: "This adds two reverse gears, untangle and reverse. You can access these gears via a quadruple (4) click on the trigger."
                }

                Text {
                    color: "#ffffff"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    topPadding:15
                    text: "<b> This feature can be dangerous and requires training. By enabling this feature you acknowledge you fully understand how to use it safely. <b>"
                }

                CheckBox {
                    id: enable_reverse
                    Layout.fillWidth: true
                    text: "Enable Untangle & Reverse"
                    checked: false
                    onClicked: {
                        reverseDialog.valuesChanged()
                    }
                }
            }
        }
    }

    Dialog {
        id: smartCruiseDialog
        standardButtons: Dialog.Save | Dialog.Cancel
        modal: true
        focus: true
        width: big.width - 20
        closePolicy: Popup.CloseOnEscape
        title: "Smart Cruise"

        property bool has_changes: false

        onOpened: {
            standardButton(Dialog.Save).enabled = false
        }

	    onAccepted: {
            if (has_changes) {
                write_settings()

                has_changes = false
            }
	    }

	    onRejected: {
            if (has_changes) {
	            read_settings()

                has_changes = false
            }
	    }

        function valuesChanged() {
            has_changes = true
            standardButton(Dialog.Save).enabled = true
        }

        ScrollView {
            id: customScroll
            anchors.fill: parent
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Text {
                    color: "#ffffff"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap

                    text: "This gives you the option of Smart Cruise. While running, do a triple (3) click and the display will show \"C\" and Smart Cruise will be engaged."
                }

                Text {
                    color: "#ffffff"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    topPadding:10
                    text: "While Smart Cruise is active: short trigger taps reset the timeout timer. To adjust speed, hold the trigger for >1 second, release, then do 1 click (speed down) or 2 clicks (speed up). To disable Smart Cruise, do another triple (3) click after a long hold."
                }

                Text {
                    color: "#ffffff"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    topPadding:10
                    text: "Smart Cruise also times out after the duration set below. At the set time the display will show “C?” and reduce your rpm’s slightly. Another triple click will re-engage Smart Cruise, otherwise the scooter will stop."
                }

                Text {
                    color: "#ffffff"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    topPadding:15
                    text: "<b> By enabling this feature you acknowledge you fully understand how to use it safely.<b>"
                }

                CheckBox {
                    id: enable_smart_cruise
                    Layout.fillWidth: true
                    text: "Enable Smart Cruise"
                    checked: false
                    onClicked: {
                        smartCruiseDialog.valuesChanged()
                    }
                }

                DoubleSpinBox {
                    id: smart_cruise_timeout
                    Layout.fillWidth: true
                    visible: enable_smart_cruise.checked
                    decimals: 0
                    prefix: "Smart Cruise Timeout: "
                    suffix: " sec."
                    realFrom: 10
                    realTo: 240
                    realValue: 60
                    realStepSize: 10.0
                    onRealValueChanged: {
                        if (!loading_values) {
                            smartCruiseDialog.valuesChanged()
                        }
                    }
                }

                CheckBox {
                    id: enable_smart_cruise_auto_engage
                    visible: enable_smart_cruise.checked
                    Layout.fillWidth: true
                    text: "Enable Auto-Engage Smart Cruise"
                    checked: false
                    onClicked: {
                        smartCruiseDialog.valuesChanged()
                    }
                }

                DoubleSpinBox {
                    id: smart_cruise_auto_engage_delay
                    Layout.fillWidth: true
                    visible: enable_smart_cruise.checked && enable_smart_cruise_auto_engage.checked
                    decimals: 0
                    prefix: "Auto-Engage Delay: "
                    suffix: " sec."
                    realFrom: 5
                    realTo: 30
                    realValue: 10
                    realStepSize: 1.0
                    onRealValueChanged: {
                        if (!loading_values) {
                            smartCruiseDialog.valuesChanged()
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: batteryDialog
        standardButtons: Dialog.Save | Dialog.Cancel
        modal: true
        focus: true
        width: big.width - 20
        closePolicy: Popup.CloseOnEscape
        title: "Battery Configuration"

        property bool has_changes: false

        onOpened: {
            standardButton(Dialog.Save).enabled = false
        }

	    onAccepted: {
            if (has_changes) {
                mMcConf.updateParamDouble("si_battery_ah", battery_ah.realValue, null)
                mCommands.setMcconf(false)

                write_settings()

                has_changes = false
            }
	    }

	    onRejected: {
            if (has_changes) {
	            read_settings()

                has_changes = false
            }
	    }

        function valuesChanged() {
            has_changes = true
            standardButton(Dialog.Save).enabled = true
        }

        ScrollView {
            anchors.fill: parent
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                DoubleSpinBox {
                    id: battery_ah
                    Layout.fillWidth: true
                    decimals: 1
                    prefix: "Battery capacity: "
                    realFrom: 0.5
                    realTo: 20
                    realValue: 9
                    realStepSize: 0.5
                    onRealValueChanged: {
                        if (!loading_values) {
                            batteryDialog.valuesChanged()
                        }
                    }
                }

                CheckBox {
                    id: enable_thirds_warning_startup
                    Layout.fillWidth: true
                    text: "Thirds warning on from power-up"
                    checked: false
                    onClicked: {
                        batteryDialog.valuesChanged()
                    }
                }

                CheckBox {
                    id: use_ah_battery_calculation
                    Layout.fillWidth: true
                    text: "Use ampere-hour based battery calculation"
                    checked: false
                    onClicked: {
                        batteryDialog.valuesChanged()
                    }
                }
            }
        }
    }

    Dialog {
        id: beeperDisplayDialog
        standardButtons: Dialog.Save | Dialog.Cancel
        modal: true
        focus: true
        width: big.width - 20
        closePolicy: Popup.CloseOnEscape
        title: "Beeper & Display Configuration"

        property bool has_changes: false
        property bool reboot_required: false

        onOpened: {
            standardButton(Dialog.Save).enabled = false
        }

	    onAccepted: {
            if (has_changes) {
                write_settings()

                has_changes = false

                if (reboot_required) {
                    reboot_required = false

                    doReboot(2000)
                }
            }
	    }

	    onRejected: {
            if (has_changes) {
	            read_settings()

                has_changes = false
            }
	    }

        function valuesChanged() {
            has_changes = true
            standardButton(Dialog.Save).enabled = true
        }

        ScrollView {
            anchors.fill: parent
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                CheckBox {
                    id: enable_beeps
                    Layout.fillWidth: true
                    text: "Enable Battery Capacity Beeps"
                    checked: false
                    onClicked: {
                        beeperDisplayDialog.valuesChanged()
                    }
                }

                CheckBox {
                    id: enable_tbeeps
                    Layout.fillWidth: true
                    text: "Enable Trigger Beeps"
                    checked: false
                    onClicked: {
                        beeperDisplayDialog.valuesChanged()
                    }
                }

                DoubleSpinBox {
                    id: beeps_volume
                    Layout.fillWidth: true
                    decimals: 0
                    prefix: "Beep Volume: "
                    realFrom: 1
                    realTo:10
                    realValue: 1
                    realStepSize: 1
                    onRealValueChanged: {
                        if (!loading_values) {
                            beeperDisplayDialog.valuesChanged()
                        }
                    }
                }

                CheckBox {
                    id: cudaX_Flip
                    visible: !isBlacktip(hardware_configuration.currentIndex)
                    Layout.fillWidth: true
                    text: "Flip Screens on CudaX"
                    checked: false
                    onClicked: {
                        beeperDisplayDialog.valuesChanged()
                    }
                }

                DoubleSpinBox {
                    id: display_rotation
                    Layout.fillWidth: true
                    decimals: 0
                    prefix: "Display 1 Rotation: "
                    suffix: " Deg."
                    realFrom: 0
                    realTo: 270
                    realValue: 90
                    realStepSize: 90
                    onRealValueChanged: {
                        if (!loading_values) {
                            beeperDisplayDialog.valuesChanged()
                        }
                    }
                }

                DoubleSpinBox {
                    id: display_rotation2
                    Layout.fillWidth: true
                    visible: !isBlacktip(hardware_configuration.currentIndex)
                    decimals: 0
                    prefix: "Display 2 Rotation: "
                    suffix: " Deg."
                    realFrom: 0
                    realTo: 270
                    realValue: 90
                    realStepSize: 90
                    onRealValueChanged: {
                        if (!loading_values) {
                            beeperDisplayDialog.valuesChanged()
                        }
                    }
                }

                DoubleSpinBox {
                    id: display_brightness
                    Layout.fillWidth: true
                    decimals: 0
                    prefix: "Display Brightness*: "
                    suffix: " %"
                    realFrom: 0
                    realTo: 100
                    realValue: 100
                    realStepSize: 20
                    onRealValueChanged: {
                        if (!loading_values) {
                            beeperDisplayDialog.valuesChanged()
                            beeperDisplayDialog.reboot_required = true
                        }
                    }
                }

                Text {
                    topPadding:5
                    font.pixelSize: Qt.application.font.pixelSize * 0.8
                    color: Utility.getAppHexColor("lightText")
                    text: "* Will trigger a scooter reboot"
                }

                CheckBox {
                    id: debug_enabled
                    Layout.fillWidth: true
                    text: "Enable Debug Logging"
                    checked: false
                    onClicked: {
                        beeperDisplayDialog.valuesChanged()
                    }
                }
            }
        }
    }

    Dialog {
        id: hardwareDialog
        standardButtons: Dialog.Save | Dialog.Cancel
        modal: true
        focus: true
        width: big.width - 20
        closePolicy: Popup.CloseOnEscape
        title: "Scooter Hardware Configuration"

        property int original_hardware_configuration

        onOpened: {
            original_hardware_configuration = hardware_configuration.currentIndex
            standardButton(Dialog.Save).enabled = false
        }

	    onAccepted: {
            if (original_hardware_configuration != hardware_configuration.currentIndex) {
                if (isBlacktip(hardware_configuration.currentIndex) && !isBlacktip(original_hardware_configuration)) {
                    reset_defaults_blacktip()
                } else if (!isBlacktip(hardware_configuration.currentIndex) && isBlacktip(original_hardware_configuration)) {
                    reset_defaults_cudax()
                } else {
                    write_settings()

                    doReboot(2000)
                }
            }
	    }

	    onRejected: {
            if (original_hardware_configuration != hardware_configuration.currentIndex) {
	            read_settings()
            }
	    }

        ScrollView {
            id: hardwareScroll
            anchors.fill: parent
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Text {
                    color: "#ffffff"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    topPadding:15
                    text: "<b> Warning: If you are connected via Bluetooth and select a scooter without Bluetooth you will loose your connection.<b>"
                }

                Text {
                    color: "#ffffff"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    topPadding:15
                    text: "If you loose Bluetooth you will need to use the PC based VESC Tool and connect via USB to select the correct scooter."
                }

                Text {
                    Layout.fillWidth: true
                    font.pixelSize: Qt.application.font.pixelSize
                    topPadding:15
                    color: Utility.getAppHexColor("lightText")
                    text: "Detected motor controller model: " + detectedHardwareModel + "\nPossible scooter models for this hardware:" + possibleScooterModels
                }

                Text {
                    Layout.fillWidth: true
                    font.pixelSize: Qt.application.font.pixelSize
                    topPadding:15
                    color: Utility.getAppHexColor("lightText")
                    text: "Select your model and hardware version:*"
                }

                ComboBox {
                    id: hardware_configuration
                    Layout.fillWidth: true
                    currentIndex: -1
                    model: const_SCOOTER_MODELS

                    onCurrentIndexChanged: {
                        if (hardwareDialog.original_hardware_configuration != hardware_configuration.currentIndex) {
                            hardwareDialog.standardButton(Dialog.Save).enabled = true
                        } else {
                            hardwareDialog.standardButton(Dialog.Save).enabled = false
                        }
                    }
                }

                Rectangle {
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    color : "transparent"
                }

                Text {
                    color: "#ffffff"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    topPadding:15
                    text: "Use reset button to reset ALL the settings for the scooter. Must be used after a firmware update."
                }

                Button {
                    Layout.fillWidth: true
                    text: "Reset Defaults*"
                    enabled: hardwareDialog.original_hardware_configuration == hardware_configuration.currentIndex
                    onClicked: {
                        if (isBlacktip(hardware_configuration.currentIndex)) {
                            reset_defaults_blacktip()
                        } else {
                            reset_defaults_cudax()
                        }

                        hardwareDialog.close()
                    }
                }

                Text {
                    id: text3
                    topPadding:5
                    font.pixelSize: Qt.application.font.pixelSize * 0.8
                    color: Utility.getAppHexColor("lightText")
                    text: "* Will trigger a scooter reboot and potentially a reset to defaults"
                }
            }
        }
    }

    Dialog {
        id: rebootDialog
        standardButtons: Dialog.Cancel
        modal: true
        focus: true
        width: big.width - 20
        closePolicy: Popup.CloseOnEscape
        title: "Rebooting..."

        ScrollView {
            anchors.fill: parent
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Text {
                    color: "#ffffff"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap

                    text: "Please wait while the scooter is rebooting..."
                }
            }
        }
    }
}
