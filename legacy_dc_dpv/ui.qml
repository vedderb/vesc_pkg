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

    property string firmwareVersion: "<Unknown>"
    property string detectedHardwareModel: "<Unknown>"

    property double ahUsed: 0
    property double powerAvg: 0
    property double powerMax: 0
    property double fetTempAvg: 0
    property double fetTempMax: 0
    property int uptimeSec: 0

    property string battery_type_text: "<Unknown>"
    property double battery_voltage: 0
    property int battery_type: 255
    property int battery_cells: 0


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

            property int buttons: 5
            property int buttonWidth: 60

            TabButton {
                id: tab
                text: qsTr("Home")
                width: implicitWidth
                //width: Math.max(tabBar.buttonWidth, tabBar.width / tabBar.buttons)
            }
            TabButton {
                text: qsTr("Info")
                width: implicitWidth
                //width: Math.max(tabBar.buttonWidth, tabBar.width / tabBar.buttons)
            }
            TabButton {
                text: qsTr("Settings")
                width: implicitWidth
                //width: Math.max(tabBar.buttonWidth, tabBar.width / tabBar.buttons)
            }
            TabButton {
                text: qsTr("Features")
                width: implicitWidth
                //width: Math.max(tabBar.buttonWidth, tabBar.width / tabBar.buttons)
            }
            TabButton {
                text: qsTr("Speeds")
                width: implicitWidth
                //width: Math.max(tabBar.buttonWidth, tabBar.width / tabBar.buttons)
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
                                minimumValue: 0
                                maximumValue: 100
                                minAngle: -250
                                maxAngle: 0
                                labelStep: 10
                                value: 0
                                typeText: "Duty cycle"

                                CustomGauge {
                                    id: batteryGauge
                                    width: gaugeSize2*1.1
                                    height: gaugeSize2*1.1
                                    anchors.centerIn: parent
                                    anchors.horizontalCenterOffset: 0.45 * gaugeSize
                                    anchors.verticalCenterOffset: -0.45 * gaugeSize
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

                                    Text {
                                        id: battTypeLabel
                                        color: Utility.getAppHexColor("lightText")
                                        text: battery_type_text
                                        font.pixelSize: gaugeSize2/18.0
                                        verticalAlignment: Text.AlignVCenter
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: gaugeSize2*0.12
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
                                id: ampGauge
                                width:gaugeSize2
                                height:gaugeSize2
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.horizontalCenterOffset: -0.25 *big.width
                                anchors.verticalCenter: big.top
                                anchors.verticalCenterOffset: (1.05 * big.width) + tab.height

                                minimumValue: 0
                                maximumValue: 100
                                value: 0
                                precision: 2
                                labelStep: 20
                                property real throttleStartValue: 60
                                property color blueColor: Utility.getAppHexColor("tertiary2")
                                property color orangeColor: Utility.getAppHexColor("orange")
                                property color redColor: "red"
                                nibColor: value > throttleStartValue ? redColor : (value > 30 ? orangeColor: blueColor)
                                Behavior on nibColor {
                                    ColorAnimation {
                                        duration: 1000;
                                        easing.type: Easing.InOutSine
                                        easing.overshoot: 3
                                    }
                                }
                                unitText: "A"
                                typeText: "Battery\nAmperage"
                                minAngle: -160
                                maxAngle: 160
                            }
                            CustomGauge {
                                id: escTempGauge
                                width:gaugeSize2
                                height:gaugeSize2
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.horizontalCenterOffset: 0.25 *big.width
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
                        }
                   }
              }
            }
            // Info page settings.
            Page {
                ScrollView {
                    id: infoScroll
                    anchors.fill: parent
                    clip: true
                    contentWidth: availableWidth
                   ColumnLayout {

                        Rectangle {
                            id: infoView
                            Layout.fillWidth: true

                            Grid {
                                columns: 2
                                rows: 9
                                rowSpacing: 8
                                columnSpacing: 10
                            Layout.fillWidth: true
                                property real labelWidth: 250
                                property real valueWidth: 75

                                Text {
                                    width: parent.labelWidth
                                    color: "#ffffff"
                                    text: "Hardware Detected"
                                }
                                Text {
                                    width: parent.valueWidth
                                    color: "#ffffff"
                                    text: detectedHardwareModel
                                    horizontalAlignment: Text.AlignRight
                                }

                                Text {
                                    width: parent.labelWidth
                                    color: "#ffffff"
                                    text: "Firmware Detected"
                                }
                                Text {
                                    width: parent.valueWidth
                                    color: "#ffffff"
                                    text: firmwareVersion
                                    horizontalAlignment: Text.AlignRight
                                }

                                Text {
                                    width: parent.labelWidth
                                    color: "#ffffff"
                                    text: "Uptime"
                                }
                                Text {
                                    width: parent.valueWidth
                                    color: "#ffffff"
                                    text: formatTime(uptimeSec)
                                    horizontalAlignment: Text.AlignRight
                                }

                                Text {
                                    width: parent.labelWidth
                                    color: "#ffffff"
                                    text: "Battery"
                                }
                                Text {
                                    width: parent.valueWidth
                                    color: "#ffffff"
                                    text: battery_voltage + " V"
                                    horizontalAlignment: Text.AlignRight
                                }

                                Text {
                                    width: parent.labelWidth
                                    color: "#ffffff"
                                    text: "Battery Ah Used"
                                }
                                Text {
                                    width: parent.valueWidth
                                    color: "#ffffff"
                                    horizontalAlignment: Text.AlignRight
                                    text: ahUsed.toFixed(2) + " Ah"
                                }

                                Text {
                                    width: parent.labelWidth
                                    color: "#ffffff"
                                    text: "Average Watts"
                                }
                                Text {
                                    width: parent.valueWidth
                                    color: "#ffffff"
                                    horizontalAlignment: Text.AlignRight
                                    text: powerAvg.toFixed(1) + " W"
                                }

                                Text {
                                    width: parent.labelWidth
                                    color: "#ffffff"
                                    text: "Maximum Watts"
                                }
                                Text {
                                    width: parent.valueWidth
                                    color: "#ffffff"
                                    horizontalAlignment: Text.AlignRight
                                    text: powerMax.toFixed(1) + " W"
                                }

                                Text {
                                    width: parent.labelWidth
                                    color: "#ffffff"
                                    text: "Average MOSFET Temp"
                                }
                                Text {
                                    width: parent.valueWidth
                                    color: "#ffffff"
                                    horizontalAlignment: Text.AlignRight
                                    text: fetTempAvg.toFixed(1) + " C"
                                }

                                Text {
                                    width: parent.labelWidth
                                    color: "#ffffff"
                                    text: "Maximum  MOSFET Temp"
                                }
                                Text {
                                    width: parent.valueWidth
                                    color: "#ffffff"
                                    horizontalAlignment: Text.AlignRight
                                    text: fetTempMax.toFixed(1) + " C"
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

                        RowLayout {
                            DoubleSpinBox {
                                id: no_speeds
                                Layout.fillWidth: true
                                decimals: 0
                                prefix: "No. Speeds: "
                                realFrom: 1
                                realTo: 8
                                realValue: 8
                                realStepSize: 1.0
                                property string helpTitle: "Number of Speeds"
                                property var helpText: [ "This is how many speeds you'll have access to while driving the DPV (not including reverse and untangle speeds)." ]
                                onRealValueChanged: {
                                   if (!loading_values) {
                                       settingsScroll.has_changes = true
                                   }
                                }
                            }
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = no_speeds.helpTitle
                                   helpDialog.helpText = no_speeds.helpText
                                   helpDialog.open()
                               }
                            }
                        }

                        RowLayout {
                            DoubleSpinBox {
                                id: start_speed
                                Layout.fillWidth: true
                                decimals: 0
                                prefix: "Start Speed: "
                                realFrom: 1
                                realTo: no_speeds.realValue
                                realValue: 3
                                realStepSize: 1.0
                                property string helpTitle: "Start Speed"
                                property var helpText: [ "This is the speed to set when starting the DPV for the first time. On subsequent starts, the DPV will start in the same speed as when it last stopped" ]
                                onRealValueChanged: {
                                   if (!loading_values) {
                                       settingsScroll.has_changes = true
                                   }
                                }
                            }
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = start_speed.helpTitle
                                   helpDialog.helpText = start_speed.helpText
                                   helpDialog.open()
                               }
                            }
                        }

                        RowLayout {
                            DoubleSpinBox {
                                id: start_speed_timeout
                                Layout.fillWidth: true
                                decimals: 0
                                prefix: "Re-Start Timeout: "
                                realFrom: 0
                                realTo: 240
                                realValue: 15
                                realStepSize: 1.0
                                property string helpTitle: "Re-Start Speed Timeout"
                                property var helpText: [ "When re-starting the DPV it will start at the same speed you last used unless this number of seconds have passed.", "Set this to '0' to disable starting in the previous speed." ]
                                onRealValueChanged: {
                                   if (!loading_values) {
                                       settingsScroll.has_changes = true
                                   }
                                }
                            }
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = start_speed_timeout.helpTitle
                                   helpDialog.helpText = start_speed_timeout.helpText
                                   helpDialog.open()
                               }
                            }
                        }


                        RowLayout {
                            DoubleSpinBox {
                                id: jump_speed
                                Layout.fillWidth: true
                                decimals: 0
                                prefix: "Jump Speed: "
                                realFrom: 1
                                realTo: no_speeds.realValue
                                realValue: 6
                                realStepSize: 1.0
                                property string helpTitle: "Jump Speed"
                                property var helpText: [ "This is the speed to set when you start the DPV with 3 clicks." ]
                                onRealValueChanged: {
                                   if (!loading_values) {
                                       settingsScroll.has_changes = true
                                   }
                                }
                            }
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = jump_speed.helpTitle
                                   helpDialog.helpText = jump_speed.helpText
                                   helpDialog.open()
                               }
                            }
                        }
                    }
                }
            }
            // Features page
            Page {
                background: Rectangle {
                    opacity: 0.0
                }

                ScrollView {
                    id: featuresScroll
                    anchors.fill: parent
                    clip: true
                    contentWidth: availableWidth

                    property bool has_changes: false

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        RowLayout {
                            CheckBox {
                                id: safe_start
                                Layout.fillWidth: true
                                text: "Enable Safe Start"
                                checked: false
                                property string helpTitle: "Enable Safe Start"
                                property var helpText: [ "The <b>Safe Start</b> feature initially runs the propeller at low speeds to see if there is resistance. If there is little resistance, like in air, the propeller won't go to full speed. If water resistance is detected, the propeller will increase to the starting speed.",
                                     "This resistance is detected by the amount of current the motor draws: more resistance means more current.",
                                     "<b>Safe Start Current</b> needs to be set to a suitable value for your DPV. To find a suitable value: <ul><li>turn <b>Safe Start</b> off, then</li> <li>Watch the <b>Battery Amperage</b> dial on the <b>Home</b> page, then</li><li>Start the DPV in air, and</li><li>Note the amperage on the dial, then</li><li>Turn <b>Safe Start</b> back on and</li><li>Set <b>Safe Start Current</b> to a value a little higher (perhaps double).</li></ul>" ]
                                onClicked: {
                                   if (!loading_values) {
                                       featuresScroll.has_changes = true
                                   }
                                }
                            }
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = safe_start.helpTitle
                                   helpDialog.helpText = safe_start.helpText
                                   helpDialog.open()
                               }
                            }
                        }

                        RowLayout {
                            DoubleSpinBox {
                                id: min_current
                                Layout.fillWidth: true
                                enabled: safe_start.checked
                                decimals: 1
                                prefix: "Safe Start Current: "

                                realFrom: 0
                                realTo: 10
                                realValue: 0
                                realStepSize: 0.1
                                property string helpTitle: "Safe Start Current"
                                property var helpText: [ "<b>Safe Start Current</b> needs to be set to a suitable value for your DPV. To find a suitable value: <ul><li>turn <b>Safe Start</b> off, then</li> <li>Watch the <b>Battery Amperage</b> dial on the <b>Home</b> page, then</li><li>Start the DPV in air, and</li><li>Note the amperage on the dial, then</li><li>Turn <b>Safe Start</b> back on and</li><li>Set <b>Safe Start Current</b> to a value a little higher (perhaps double).</li></ul>",
                                    "<b>Warning:</b> if this is set too low the DPV will go to full speed on land. If set too high it will not go to full speed in water." ]
                                onRealValueChanged: {
                                    if (!loading_values) {
                                        featuresScroll.has_changes = true
                                    }
                                }
                            }
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = min_current.helpTitle
                                   helpDialog.helpText = min_current.helpText
                                   helpDialog.open()
                               }
                            }
                        }

                        RowLayout {
                            CheckBox {
                                id: enable_reverse
                                Layout.fillWidth: true
                                text: "Enable Untangle & Reverse (4 Clicks while stopped)"
                                property string helpTitle: "Enable Reverse"
                                property var helpText: [ "This feature enables Reverse and Untangle modes. Untangle is a slow reverse meant to assist in untangling weeds or line from the propeller.", "Once enabled you can start Untangle mode by clicking 4 times on the trigger and holding while in an off state. Double-click and hold to enter Reverse, or single-click and hold to return to Untangle mode. To end either mode, release the trigger", "Make sure you set a suitable Reverse and Untangle speeds in the <b>Speeds</b> tab." ]
                                onClicked: {
                                    if (enable_reverse.checked) {
                                        reverseDialog.open()
                                    } else {
                                        featuresScroll.has_changes = true
                                    }
                                }
                            }
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = enable_reverse.helpTitle
                                   helpDialog.helpText = enable_reverse.helpText
                                   helpDialog.open()
                               }
                            }
                        }
                        RowLayout {
                            CheckBox {
                                id: enable_smart_cruise
                                Layout.fillWidth: true
                                text: "Enable Smart Cruise (3 clicks while running)"
                                property string helpTitle: " Enable Smart Cruise"
                                property var helpText: [ "This features puts the DPV in cruise mode, where the trigger can be released. Click the trigger 3 times while running to enter Smart Cruise.", "For safety reasons, Smart Cruise will only last a short time, up to 240 seconds as set by the <b>Smart Cruise Timeout</b>.",
                                   "While running in Smart Cruise you can:<ul><li>Click 3 times to end Smart Cruise</li><li>Short click (no hold) to reset the timeout</li><li>Long hold (1/2 second) and release to decrease speed</li><li>Long hold (1/2 second), release then double-click to increase speed.</li></ul>",
                                   "This feature is handy for changing hands on the trigger without losing speed, or giving your hand a rest on a long dive." ]
                                onClicked: {
                                    if (enable_smart_cruise.checked) {
                                        smartCruiseDialog.open()
                                    } else {
                                        featuresScroll.has_changes = true
                                    }
                                }
                            }
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = enable_smart_cruise.helpTitle
                                   helpDialog.helpText = enable_smart_cruise.helpText
                                   helpDialog.open()
                               }
                            }
                        }

                        RowLayout {
                            DoubleSpinBox {
                                id: smart_cruise_timeout
                                Layout.fillWidth: true
                                enabled: enable_smart_cruise.checked
                                decimals: 0
                                prefix: "Smart Cruise Timeout: "
                                suffix: " sec."
                                realFrom: 10
                                realTo: 240
                                realValue: 60
                                realStepSize: 10.0
                                property string helpTitle: "Smart Cruise Timeout"
                                property var helpText: [ "This defines how long Smart Cruise will last. After this many seconds, Smart Cruise will stop.", "Smart Cruise can be extended by clicking 4 times before the timeout elapses." ]
                                onRealValueChanged: {
                                    if (!loading_values) {
                                        featuresScroll.has_changes = true
                                    }
                                }
                            }
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = smart_cruise_timeout.helpTitle
                                   helpDialog.helpText = smart_cruise_timeout.helpText
                                   helpDialog.open()
                               }
                            }
                        }

                        RowLayout {
                            CheckBox {
                                id: enable_smart_cruise_auto_engage
                                enabled: enable_smart_cruise.checked
                                Layout.fillWidth: true
                                text: "Enable Auto-Engage Smart Cruise"
                                checked: false
                                property string helpTitle: "Smart Cruise Auto-Engage"
                                property var helpText: [ "This feature automatically engages Smart Cruise if you have been in the same speed for the duration set in <b>Auto-Engage Delay</b>.", "This feature can be very troublesome if you forget it's enabled and expect your DPV to stop when you release the trigger.", "Use this with extreme caution." ]
                                onClicked: {
                                    featuresScroll.has_changes = true
                                }
                            }
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = enable_smart_cruise_auto_engage.helpTitle
                                   helpDialog.helpText = enable_smart_cruise_auto_engage.helpText
                                   helpDialog.open()
                               }
                            }
                        }

                        RowLayout {
                            DoubleSpinBox {
                                id: smart_cruise_auto_engage_delay
                                Layout.fillWidth: true
                                enabled: enable_smart_cruise.checked && enable_smart_cruise_auto_engage.checked
                                decimals: 0
                                prefix: "Auto-Engage Delay: "
                                suffix: " sec."
                                realFrom: 5
                                realTo: 30
                                realValue: 10
                                realStepSize: 1.0
                                property string helpTitle: "Smart Cruise Auto-Engage Delay"
                                property var helpText: [ "This is the time after which Smart Cruise will automatically engage after being in the same speed." ]
                                onRealValueChanged: {
                                    if (!loading_values) {
                                        featuresScroll.has_changes = true
                                    }
                                }
                            }
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = smart_cruise_auto_engage_delay.helpTitle
                                   helpDialog.helpText = smart_cruise_auto_engage_delay.helpText
                                   helpDialog.open()
                               }
                            }
                        }

                        RowLayout {
                            CheckBox {
                                id: debug_enabled
                                Layout.fillWidth: true
                                text: "Enable Debug"
                                checked: false
                                property string helpTitle: "Enable Debug"
                                property var helpText: [ "Debug is useful to see what the controller is doing. It will show the number of clicks it sees and the speeds it is setting.", "To see debug information you need to use vesc-tool and use the LispBM menu option from the left menu.", "Leave this feature off unless you are trying to diagnose a problem." ]
                                onClicked: {
                                   if (!loading_values) {
                                       featuresScroll.has_changes = true
                                   }
                                }
                            }
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = debug_enabled.helpTitle
                                   helpDialog.helpText = debug_enabled.helpText
                                   helpDialog.open()
                               }
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

                        // Reverse Speed
                        RowLayout {
                            DoubleSpinBox {
                                id: reverse_speed
                                Layout.fillWidth: true
                                enabled: enable_reverse.checked
                                decimals: 0
                                prefix: "Reverse Speed: "
                                suffix: " %"
                                realFrom: 20
                                realTo: 50
                                realValue: 45
                                realStepSize: 1.0
                                property string helpTitle: "Reverse Speed Duty Cycle"
                                property var helpText: [ "Choose the Duty Cycle (which is the percentage of your battery's voltage) to use when in reverse.", "Enable <b>Untangle & Reverse</b> in Features to set this value." ]
                                onRealValueChanged: {
                                   if (!loading_values) {
                                       speedsScroll.has_changes = true
                                   }
                                }
                            }
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = reverse_speed.helpTitle
                                   helpDialog.helpText = reverse_speed.helpText
                                   helpDialog.open()
                               }
                            }
                        }

                        RowLayout {
                            DoubleSpinBox {
                                id: untangle_speed
                                Layout.fillWidth: true
                                enabled: enable_reverse.checked
                                decimals: 0
                                prefix: "Untangle Speed: "
                                suffix: " %"
                                realFrom: 20
                                realTo: 30
                                realValue: 20
                                realStepSize: 1.0
                                property string helpTitle: "Untangle Speed Duty Cycle"
                                property var helpText: [ "Choose the Duty Cycle (the percentage of your battery's voltage) to use when in untangle mode.", "Enter Untangle mode by first clicking 4 times while off to engage reverse, then click once to reduce speed to tangle mode.", "Enable <b>Untangle & Reverse</b> in Features to set this value." ]
                                onRealValueChanged: {
                                    if (!loading_values) {
                                        speedsScroll.has_changes = true
                                    }
                                }
                            }
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = untangle_speed.helpTitle
                                   helpDialog.helpText = untangle_speed.helpText
                                   helpDialog.open()
                               }
                            }
                        }


                        // First speed
                        RowLayout {
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
                                property string helpTitle: "Speed Duty Cycle"
                                property var helpText: [ "Choose the Duty Cycle (the percentage of your battery's voltage) to use when in this speed. A higher percentage results in a faster speed.",
                                    "<b>Warning:</b> If you have a battery of a higher voltage than your DPV's motor is rated for, then choose percentages carefully. For example: if you installed a 40V battery in a DPV meant for 24V, you should never use a Duty Cycle greater than 24/40 or 60%. Going higher could risk damaging your motor or propeller." ]
                                onRealValueChanged: {
                                    if (!loading_values) {
                                        speedsScroll.has_changes = true
                                    }
                                }
                            }
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = one_speed.helpTitle
                                   helpDialog.helpText = one_speed.helpText
                                   helpDialog.open()
                               }
                            }
                        }


                        RowLayout {
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
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = one_speed.helpTitle
                                   helpDialog.helpText = one_speed.helpText
                                   helpDialog.open()
                               }
                            }
                        }

                        RowLayout {
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
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = one_speed.helpTitle
                                   helpDialog.helpText = one_speed.helpText
                                   helpDialog.open()
                               }
                            }
                        }

                        RowLayout {
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
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = one_speed.helpTitle
                                   helpDialog.helpText = one_speed.helpText
                                   helpDialog.open()
                               }
                            }
                        }

                        RowLayout {
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
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = one_speed.helpTitle
                                   helpDialog.helpText = one_speed.helpText
                                   helpDialog.open()
                               }
                            }
                        }

                        RowLayout {
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
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = one_speed.helpTitle
                                   helpDialog.helpText = one_speed.helpText
                                   helpDialog.open()
                               }
                            }
                        }

                        RowLayout {
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
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = one_speed.helpTitle
                                   helpDialog.helpText = one_speed.helpText
                                   helpDialog.open()
                               }
                            }
                        }

                        RowLayout {
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
                            Button {
                               icon.source: "qrc:res/icons/Help-96.png"
                               Layout.rightMargin: 25
                               implicitWidth: implicitContentWidth + leftPadding + rightPadding
                               hoverEnabled: true
                               ToolTip.text: "Help"
                               ToolTip.visible: hovered
                               onClicked: {
                                   helpDialog.title = one_speed.helpTitle
                                   helpDialog.helpText = one_speed.helpText
                                   helpDialog.open()
                               }
                            }
                        }
                    }
                }
            }
        }

        // Save/Restore buttons
        RowLayout {
            spacing: 10 // Space between the buttons

            Button {
                Layout.fillWidth: true
                text: "Undo Changes"
                enabled: speedsScroll.has_changes || settingsScroll.has_changes || featuresScroll.has_changes
                onClicked: {
                    read_settings()
                    speedsScroll.has_changes = false
                    settingsScroll.has_changes = false
                    featuresScroll.has_changes = false
                }
            }

            Button {
                Layout.fillWidth: true
                text: "Save"
                enabled: speedsScroll.has_changes || settingsScroll.has_changes || featuresScroll.has_changes
                onClicked: {
                    write_settings()
                    speedsScroll.has_changes = false
                    settingsScroll.has_changes = false
                    featuresScroll.has_changes = false
                }
            }
        }
    }

    // handshake timer to initiate first transfer of values from lisp
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
                mCommands.getStats(0xFFFFFFFF)
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
        if (detectedHardwareModel == "") {
            detectedHardwareModel = "<Unknown>"
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

        var buffer = new ArrayBuffer(22)
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
        da.setUint8(10, no_speeds.realValue + 1) // "+ 1" convert user speed values to actual speed values
        da.setUint8(11, start_speed.realValue + 1)
        da.setUint8(12, jump_speed.realValue + 1)
        da.setUint8(13, safe_start.checked ? 1 : 0)
        da.setUint8(14, enable_reverse.checked ? 1 : 0)
        da.setUint8(15, enable_smart_cruise.checked ? 1 : 0)
        da.setUint8(16, smart_cruise_timeout.realValue)
        da.setUint8(17, min_current.realValue * 10)
        da.setUint8(18, enable_smart_cruise_auto_engage.checked ? 1 : 0)
        da.setUint8(19, smart_cruise_auto_engage_delay.realValue)
        da.setUint8(20, debug_enabled.checked ? 1 : 0)
        da.setUint8(21, start_speed_timeout.realValue)
        mCommands.sendCustomAppData(buffer)

        console.log("Sent values")
    }

    function reset_defaults() {
        var buffer1 = new ArrayBuffer(22)
        var da1 = new DataView(buffer1)
        da1.setUint8(0, 45) // Reverse speed
        da1.setUint8(1, 20) // Untangle speed
        da1.setUint8(2, 30) // speed 1
        da1.setUint8(3, 38) // speed 2
        da1.setUint8(4, 46) // speed 3
        da1.setUint8(5, 54) // speed 4
        da1.setUint8(6, 62) // speed 5
        da1.setUint8(7, 70) // speed 6
        da1.setUint8(8, 78) // speed 7
        da1.setUint8(9, 100) // speed 8
        da1.setUint8(10, 9) // num speeds
        da1.setUint8(11, 4) // start speed
        da1.setUint8(12, 7) // jump speed
        da1.setUint8(13, 1) // Safe start
        da1.setUint8(14, 0) // Enable reverse
        da1.setUint8(15, 0) // Enabled smart cruise
        da1.setUint8(16, 60) // smart cruise timeout seconds
        da1.setUint8(17, 1) // min current for safe start
        da1.setUint8(18, 1) // enable smart cruise
        da1.setUint8(19, 10) // smart cruise auto engage delay
        da1.setUint8(20, 0) // debug enable
        da1.setUnit8(21, 15) // re-start_speed_timeout
        mCommands.sendCustomAppData(buffer1)
    }

    // Format time into a more readable format
    function formatTime(totalSeconds) {
        var days = Math.floor(totalSeconds / 86400);
        var hours = Math.floor((totalSeconds % 86400) / 3600)
        var minutes = Math.floor((totalSeconds % 3600) / 60);
        var seconds = totalSeconds % 60;

        // Add leading zeros if numbers are less than 10
        var pad = function(val) {
            return (val < 10 ? "0" : "") + val;
        };

        if (days > 0) {
            return days + "d " + pad(hours) + "h" + pad(minutes) + "m" + pad(seconds) + "s";
        } else if (hours > 0) {
            return pad(hours) + ":" + pad(minutes) + ":" + pad(seconds);
        } else {
            return pad(minutes) + "m" + pad(seconds) + "s"; // Optional: omit hours if zero
        }
    }


    Connections {
        target: mCommands

        function onCustomAppDataReceived (data) {
            var dv = new DataView(data)
            if (dv.byteLength < 22) {
                console.warn("Settings payload too short:", dv.byteLength)
                return
            }
            loading_values = true;

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
            min_current.realValue = dv.getUint8(17) / 10
            enable_smart_cruise_auto_engage.checked =  dv.getUint8(18) == 1
            smart_cruise_auto_engage_delay.realValue = dv.getUint8(19)
            debug_enabled.checked =  dv.getUint8(20) == 1
            start_speed_timeout.realValue = dv.getUint8(21)

            //battery_ah.realValue = mMcConf.getParamDouble("si_battery_ah")
            battery_type = mMcConf.getParamEnum("si_battery_type")
            battery_cells = mMcConf.getParamInt("si_battery_cells")

            loading_values = false
            readSettingsDone = true

            rebootDialog.close()

            console.log("Values received")
        }
    }


    // Calculate state of charge
    function calculateSoC() {
        var table = [ ]
        switch (battery_type) {
        case 0:    // BATTERY_TYPE_LIION_3_0__4_2
            battery_type_text = "LI-ION"
            table = [
                { v: 4.20, soc: 100 }, { v: 4.11, soc: 90 }, { v: 4.02, soc: 80 },
                { v: 3.93, soc: 70 },  { v: 3.85, soc: 60 }, { v: 3.79, soc: 50 },
                { v: 3.74, soc: 40 },  { v: 3.69, soc: 30 }, { v: 3.63, soc: 20 },
                { v: 3.53, soc: 10 },  { v: 3.30, soc: 5 },  { v: 3.00, soc: 0 }
            ]
            break;
        case 1:    // BATTERY_TYPE_LIIRON_2_6__3_6
            battery_type_text = "Li-IRON"
            table = [
                { v: 3.65, soc: 100 }, { v: 3.61, soc: 99 }, { v: 3.46, soc: 95 },
                { v: 3.32, soc: 90 },  { v: 3.31, soc: 80 }, { v: 3.30, soc: 70 },
                { v: 3.29, soc: 60 },  { v: 3.28, soc: 50 }, { v: 3.27, soc: 40 },
                { v: 3.25, soc: 30 },  { v: 3.22, soc: 20 }, { v: 3.12, soc: 14 },
                { v: 3.00, soc: 9 },   { v: 2.80, soc: 4 },  { v: 2.50, soc: 0 }
            ]
            break;
        case 2:    // BATTERY_TYPE_LEAD_ACID
            battery_type_text = "LEAD ACID"
            table = [
                { v: 2.15, soc: 100 }, { v: 2.11, soc: 90 }, { v: 2.08, soc: 80 },
                { v: 2.05, soc: 70 },  { v: 2.03, soc: 60 }, { v: 2.01, soc: 50 },
                { v: 1.99, soc: 40 },  { v: 1.97, soc: 30 }, { v: 1.94, soc: 20 },
                { v: 1.90, soc: 10 },  { v: 1.75, soc: 0 }
            ]
            break;
        default:
            console.warn("Unsupported battery chemistry");
            return 0;
            break;
        }

        var cellVoltage = battery_voltage / battery_cells;

        // Boundary evaluation
        if (cellVoltage >= table[0].v) return 100;
        if (cellVoltage <= table[table.length - 1].v) return 0;

        // Piecewise linear interpolation between lookup points
        for (var i = 0; i < table.length - 1; i++) {
            var upper = table[i];
            var lower = table[i + 1];

            if (cellVoltage <= upper.v && cellVoltage >= lower.v) {
                var vRange = upper.v - lower.v;
                var socRange = upper.soc - lower.soc;
                var progress = (cellVoltage - lower.v) / vRange;

                var calculatedSoC = lower.soc + (progress * socRange);
                return Math.round(calculatedSoC);
            }
        }

        return 0;
    }

    Connections {
        id: commandsUpdate
        target: mCommands

        function onValuesSetupReceived(values, mask) {

           /*console.log("------- Listing Values Received --------")
           for (var prop in values) {
               if (typeof values[prop] !== "function") {
                   console.log(prop + ": " + values[prop])
               }
           }*/

           /*
               Values returned:

               temp_mos: 28.4
               temp_motor: 0
               current_motor: 0.08
               current_in: 0
               duty_now: 0
               rpm: 0
               speed: 0
               v_in: 39.6
               battery_level: 0.674
               amp_hours: 0.2865
               amp_hours_charged: 0
               watt_hours: 11.0899
               watt_hours_charged: 0.0005
               tachometer: 0
               tachometer_abs: 0
               position: 0
               fault_code: undefined
               vesc_id: 5
               num_vescs: 1
               battery_wh: 466.026
               fault_str: FAULT_CODE_NONE
               odometer: 31
               uptime_ms: 82099116
           */

           // Apply a factor to battery_level for accurate %
           battery_voltage = values.v_in
           batteryGauge.value = calculateSoC()
           speedGauge.value = values.duty_now * 100

           ampGauge.value = values.current_motor
           escTempGauge.value = values.temp_mos
           escTempGauge.maximumValue = Math.ceil(mMcConf.getParamDouble("l_temp_fet_end") / 5) * 5
           escTempGauge.throttleStartValue = Math.ceil(mMcConf.getParamDouble("l_temp_fet_start") / 5) * 5
           escTempGauge.labelStep = Math.ceil(escTempGauge.maximumValue/ 50) * 5
           ahUsed = values.amp_hours;
        }

        function onStatsRx(values, mask) {

           /*console.log("------- Listing Properties --------")
           console.log("mask: " + mask)
           for (var prop in values) {
               if (typeof values[prop] !== "function") {
                   console.log(prop + ": " + values[prop])
               }
           }*/

           fetTempAvg = values.temp_mos_avg
           fetTempMax = values.temp_mos_max
           powerAvg = values.power_avg
           powerMax = values.power_max
           uptimeSec = values.count_time
        }

    }

    Dialog {
        id: reverseDialog
        standardButtons: Dialog.Yes | Dialog.Cancel
        modal: true
        focus: true
        width: big.width - 20
        height: parent.height
        closePolicy: Popup.CloseOnEscape
        title: "Confirmation"

        onAccepted: {
            enable_reverse.checked = true
            featuresScroll.has_changes = true
        }

        onRejected: {
            enable_reverse.checked = false
        }

        ScrollView {
            id: reverseScroll
            anchors.fill: parent
            clip: true
            contentWidth: availableWidth
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Text {
                    color: "#ffffff"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    height: contentHeight

                    text: "This adds two reverse gears, untangle and reverse. You can access these gears via a quadruple (4) click on the trigger."
                }

                Text {
                    color: "#ffffff"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    topPadding:15
                    height: contentHeight
                    text: "<b>This feature can be dangerous and requires training. By enabling this feature you acknowledge you fully understand how to use it safely. </b>"
                }

                Text {
                    color: "#ffffff"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    topPadding:15
                    text: "Enable Untangle & Reverse"
                }
            }
        }
    }

    Dialog {
        id: smartCruiseDialog
        standardButtons: Dialog.Yes | Dialog.Cancel
        modal: true
        focus: true
        width: big.width - 20
        height: parent.height
        closePolicy: Popup.CloseOnEscape
        title: "Confirmation"

        onAccepted: {
            enable_smart_cruise.checked = true
            featuresScroll.has_changes = true
        }

        onRejected: {
            enable_smart_cruise.checked = false
        }

        ScrollView {
            id: customScroll
            anchors.fill: parent
            clip: true
            contentWidth: availableWidth
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Text {
                    color: "#ffffff"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    height: contentHeight

                    text: "This gives you the option of Smart Cruise. While running, do a triple (3) click and Smart Cruise will be engaged."
                }

                Text {
                    color: "#ffffff"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    topPadding:10
                    height: contentHeight

                    text: "While Smart Cruise is active: short trigger taps reset the timeout timer. To adjust speed, hold the trigger for >0.5 second, release, then do 1 click (speed down) or 2 clicks (speed up). To disable Smart Cruise, do another triple (3) click after a long hold."
                }

                Text {
                    color: "#ffffff"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    topPadding: 10
                    height: contentHeight

                    text: "Smart Cruise also times out after the duration set below. At the set time power will reduce slightly. Another triple click will re-engage Smart Cruise, otherwise the scooter will stop."
                }

                Text {
                    color: "#ffffff"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    topPadding: 15
                    height: contentHeight
                    text: "<b> By enabling this feature you acknowledge you fully understand how to use it safely.</b>"
                }

                Text {
                    color: "#ffffff"
                    Layout.fillWidth: true
                    topPadding: 15
                    text: "Enable Smart Cruise?"
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
        height: parent.height
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


    // Generic help dialog
    Dialog {
        id: helpDialog
        modal: true
        standardButtons: Dialog.Close
        width: parent.width - 10

        property string helpTitle: "Help"
        property var helpText: [ "Help has not be added for this topic." ]

        onRejected: {
            title =  "Help"
            helpText =  [ "Help has not be added for this topic." ]
        }
        ScrollView {
            id: helpScroll
            anchors.fill: parent
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: parent.width
                Repeater {
                    model: helpDialog.helpText

                    Text {
                        color: "#ffffff"
                        Layout.fillWidth: true
                        topPadding: 15
                        wrapMode: Text.WordWrap

                        text: modelData
                    }
                }
            }
        }
    }
}
