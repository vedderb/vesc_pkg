import "qrc:/mobile"
import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.3
import Vedder.vesc.commands 1.0
import Vedder.vesc.configparams 1.0
import Vedder.vesc.utility 1.0
import Vedder.vesc.vescinterface 1.0

Item {
    // Custom components
    Component {
        id: customValueSlider

        Slider {
            id: slider
            from: 0
            to: 100
            value: 50
            property bool asPercent: false
            property bool hideBubble: true
            property var formatValue: function(val) { 
                if (asPercent) {
                    let percentage = val * 100;
                    if (isNaN(percentage)) {
                        percentage = 0;
                    }
                    return percentage.toFixed(0) + "%";
                }
                return val + ""; 
            }

            Item {
                parent: slider.handle
                width: parent.width
                height: parent.height

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.top
                    anchors.bottomMargin: 8
                    width: valueText.width + 8
                    height: 20
                    radius: 4
                    color: palette.toolTipBase               
                    visible: true
                    opacity: slider.pressed || !hideBubble ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 150 } }

                    Text {
                        id: valueText
                        anchors.centerIn: parent
                        text: slider.formatValue(slider.value)
                        color: palette.toolTipText
                        font.pixelSize: 12
                        font.bold: true
                    }
                }
            }
        }
    }

    // Main app
    id: container
    anchors.fill: parent
    anchors.margins: 10
    property bool pairingTimeout: false
    property int remainingTime: 30  // Initialize with the full 30 seconds
    property Commands mCommands: VescIf.commands()
    property int floatAccessoriesMagic: 102
    property int lastStatusTime: 0
    property bool statusTimeout: false
    property bool readConfig: false
    property bool wasConnected: false
    property int floatPackageLastStatusTime: 0
    property int floatPackageConnected: 0
	property int uclEffectiveRole: 1          // 0 master, 1 slave
	property int refloatFwdConnected: 0       // 1 if forwarded frames are fresh
	property real refloatFwdAge: 9999         // seconds since last forwarded frame
    property real cfgLedBrightness: 0.6
    property real cfgLedBrightnessHighbeam: 0.5
    property real cfgLedBrightnessIdle: 0.3
    property real cfgLedBrightnessStatus: 0.6
    property int localCanId: -1
    property bool settingsScrollKeepBottom: false
    property int devBuildMagic: -1
    property var targetCanOptions: [ { text: "SELF (-1)", value: -1 } ]
    property int settingsRxCount: 0
    property int settingsParseErrorCount: 0
    property string lastSettingsParseError: ""
    property bool targetSelectionDirty: false

    Component.onCompleted: {
        if (VescIf.getLastFwRxParams().hwTypeStr() !== "Custom Module") {
            VescIf.emitMessageDialog("UnleashedCreativity Lights", "Warning: It doesn't look like this is installed on compatible hardware running VESC(R) software.", false, false)
        }

        refreshTargetCanOptions([])
        sendCode(String.fromCharCode(floatAccessoriesMagic) + String.fromCharCode(1) + "(send-config)")
    }

    Timer {
        id: statusCheckTimer
        interval: 1000 // Check status every second
        running: true
        repeat: true
        onTriggered: {
            sendCode(String.fromCharCode(floatAccessoriesMagic) + String.fromCharCode(1) + "(status)")
            lastStatusTime++
            floatPackageLastStatusTime++

            if (lastStatusTime > 5) { // 5 second timeout
                statusTimeout = true
            }
            if (lastStatusTime > 60) {
                wasConnected = false
            }
        }
    }

    Timer {
        id: settingsBottomStickTimerShort
        interval: 1
        repeat: false
        onTriggered: {
            if (settingsScrollKeepBottom) {
                scrollSettingsToBottom()
            }
        }
    }

    Timer {
        id: settingsBottomStickTimerLong
        interval: 120
        repeat: false
        onTriggered: {
            if (settingsScrollKeepBottom) {
                scrollSettingsToBottom()
                settingsScrollKeepBottom = false
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

    ColumnLayout {
        id: mainLayout
        anchors.fill: parent
        spacing: 10
        property string primaryTabLabel: ledEnabled.checked ? qsTr("Control") : qsTr("Status")
        property int enabledFeatureCount: 1
        property bool isSlaveUi: readConfig ? (nodeRole.value === 1) : (uclEffectiveRole === 1)

        onIsSlaveUiChanged: {
            if (isSlaveUi) {
                if (tabBar.currentIndex !== 3 && tabBar.currentIndex !== 4) {
                    tabBar.currentIndex = 3
                }
            } else {
                if (tabBar.currentIndex === 3) {
                    tabBar.currentIndex = 2
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            color: Utility.getAppHexColor("lightText")
            font.pointSize: 20
            text: "UnleashedCreativity Lights"
        }

        TabBar {
            id: tabBar
            Layout.fillWidth: true

            TabButton {
                text: mainLayout.primaryTabLabel
                visible: !mainLayout.isSlaveUi
                width: !mainLayout.isSlaveUi ? implicitWidth : 0
            }

            TabButton {
                text: qsTr("Config")
                enabled: true
                visible: !mainLayout.isSlaveUi
                width: !mainLayout.isSlaveUi ? implicitWidth : 0
            }

            TabButton {
                text: qsTr("Settings")
                visible: !mainLayout.isSlaveUi
                width: !mainLayout.isSlaveUi ? implicitWidth : 0
            }

            TabButton {
                text: qsTr("Node Slave")
                visible: mainLayout.isSlaveUi
                width: mainLayout.isSlaveUi ? implicitWidth : 0
            }

            TabButton {
                text: qsTr("About")
                width: implicitWidth
            }
        }

        TabBar {
            id: tabBar2
            Layout.fillWidth: true
            visible: tabBar.currentIndex === 1 && mainLayout.enabledFeatureCount > 1

            // Update enabled indices when checkboxes change
            Component.onCompleted: updateEnabledIndices()

            Connections {
                target: ledEnabled
                function onCheckedChanged() { updateEnabledIndices() }
            }


            TabButton {
                text: qsTr("LED")
                enabled: ledEnabled.checked
                visible: ledEnabled.checked
                width: ledEnabled.checked ? implicitWidth : 0
            }

        }

        // Stack Layout
        StackLayout {
            id: stackLayout
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

            // LED Control Tab
            ScrollView {
                id: statusScroll
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                contentWidth: availableWidth

                ColumnLayout {
                    width: statusScroll.availableWidth
                    spacing: 10

                    Timer {
                        id: debounceTimer
                        interval: 500  // Half a second (500ms)
                        repeat: false
                        onTriggered: {
                            applyControlChanges()
                        }
                    }

                    // Stack Layout
                    StackLayout {
                        id: stackLayout2
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        currentIndex: tabBar2.currentIndex
                    }

                    GroupBox {
                        title: "LED Control"
                        Layout.fillWidth: true
                        visible: ledEnabled.checked

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 10
                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: Utility.getAppHexColor("lightText")
                                font.bold: true
                                text: "LED output and highbeam state are controlled by refloat. Manual toggles are disabled here."
                            }

                            // Kept as hidden fields for protocol compatibility.
                            CheckBox {
                                id: ledOn
                                checked: true
                                visible: false
                                enabled: false
                            }

                            CheckBox {
                                id: ledHighbeamOn
                                checked: true
                                visible: false
                                enabled: false
                            }

                            ColumnLayout {
                                id: ledOnLayout
                                visible: true
                                spacing: 10

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Brightness"
                                }

                                Loader {
                                    id: ledBrightnessLoader
                                    sourceComponent: customValueSlider
                                    onLoaded: {
                                        item.from = 0.0
                                        item.to = getLedMaxBrightnessCap()
                                        item.value = cfgLedBrightness
                                        item.asPercent = true
                                        item.valueChanged.connect(function() {
                                                handleDebouncedChange()
                                        })
                                        applyLedControlBrightnessCap()
                                    }
                                }

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Idle Brightness"
                                }

                                Loader {
                                    id: ledBrightnessIdleLoader
                                    sourceComponent: customValueSlider
                                    onLoaded: {
                                        item.from = 0.0
                                        item.to = getLedMaxBrightnessCap()
                                        item.value = cfgLedBrightnessIdle
                                        item.asPercent = true
                                        item.valueChanged.connect(function() {
                                                handleDebouncedChange()
                                        })
                                        applyLedControlBrightnessCap()
                                    }
                                }

                                ColumnLayout {
                                    id: ledStatusBrightnessLayout
                                    visible: ledStatusStripType.currentValue > 0 || ledMallGrabEnabled.checked
                                    spacing: 10

                                    Text {
                                        color: Utility.getAppHexColor("lightText")
                                        text: ledMallGrabEnabled.checked && ledStatusStripType.currentValue > 0 ? "Status/Mall Grab Brightness" : ledMallGrabEnabled.checked ? "Mall Grab Brightness" : "Status Brightness"
                                    }

                                    Loader {
                                        id: ledBrightnessStatusLoader
                                        sourceComponent: customValueSlider
                                        onLoaded: {
                                            item.from = 0.0
                                            item.to = getLedMaxBrightnessCap()
                                            item.value = cfgLedBrightnessStatus
                                            item.asPercent = true
                                            item.valueChanged.connect(function() {
                                                    handleDebouncedChange()
                                            })
                                            applyLedControlBrightnessCap()
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                id: ledHighBeamBrightnessLayout
                                visible: (
                                    ledFrontStripType.currentIndex === 7
                                    || ledRearStripType.currentIndex === 7
                                )
                                spacing: 10

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Highbeam Brightness"
                                }

                                Loader {
                                    id: ledBrightnessHighbeamLoader
                                    sourceComponent: customValueSlider
                                    onLoaded: {
                                        item.from = 0.0
                                        item.to = getLedMaxBrightnessCap()
                                        item.value = cfgLedBrightnessHighbeam
                                        item.asPercent = true
                                        item.valueChanged.connect(function() {
                                                handleDebouncedChange()
                                        })
                                        applyLedControlBrightnessCap()
                                    }
                                }
                            }
                        }
                    }

                    GroupBox {
                        title: "Status"
                        Layout.fillWidth: true

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 10

                            // Status Texts Column
                            Text {
                                id: lastStatusText
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: !statusTimeout ? "green" : (lastStatusTime <= 60 ? "yellow" : "red")
                                text: !statusTimeout ? "Status: Connected" : (lastStatusTime <= 60 ? "Status: Connecting (" + lastStatusTime + "s)" : "Status: Disconnected (" + lastStatusTime + "s)")
                            }

                            Text {
                                id: floatPackageStatus
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                property int effectiveTime: Math.max(floatPackageLastStatusTime, lastStatusTime)
                                property bool slaveRoleActive: mainLayout.isSlaveUi
                                property bool showDirectRefloat: (!slaveRoleActive && floatPackageConnected === 1 && !statusTimeout)
                                color: showDirectRefloat
                                    ? "green"
                                    : (slaveRoleActive
                                        ? ((refloatFwdConnected === 1) ? "green" : ((refloatFwdAge >= 999.0 || refloatFwdAge <= 60.0) ? "yellow" : "red"))
                                        : ((floatPackageConnected === 1 && !statusTimeout) ? "green" : (effectiveTime <= 60 ? "yellow" : "red")))
                                text: showDirectRefloat
                                    ? ("Refloat: Connected")
                                    : (slaveRoleActive
                                        ? ((refloatFwdConnected === 1)
                                            ? ("Refloat (forwarded): Connected")
                                            : ((refloatFwdAge >= 999.0)
                                                ? ("Refloat (forwarded): Waiting for master")
                                                : ("Refloat (forwarded): Connecting (" + Math.floor(refloatFwdAge) + "s)")))
                                        : ((floatPackageConnected === 1 && !statusTimeout)
                                            ? ("Refloat: Connected")
                                            : ("Refloat: Connecting (" + effectiveTime + "s)")))
                            }

                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: "#ffcc66"
                                visible: targetSelectionDirty
                                text: "Diagnostics: target CAN-ID changes are pending Save Config."
                            }

                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                visible: (!readConfig || settingsParseErrorCount > 0 || statusTimeout)
                                color: Utility.getAppHexColor("lightText")
                                text: (!readConfig
                                       ? "Diagnostics: waiting for settings sync. Save Config will stay hidden until settings load completes."
                                       : (mainLayout.isSlaveUi
                                          ? "Diagnostics: this node is in Slave mode, so Save Config is intentionally hidden."
                                          : "Diagnostics: settings loaded and Master UI active."))
                            }

                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                visible: (settingsParseErrorCount > 0)
                                color: "#ffcc66"
                                text: "Diagnostics: settings parse issues=" + settingsParseErrorCount
                                      + ", last=\"" + lastSettingsParseError + "\""
                            }

                        }
                    }

                }
            }

            // LED Configuration Tab
            ScrollView {
                id: configScroll
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                ColumnLayout {
                    width: stackLayout.width

                    ColumnLayout {
                        id: ledEnabledLayout
                        visible: ledEnabled.checked && tabBar2.currentIndex === 0
                        spacing: 10

                        GroupBox {
                            title: "LED General Config"
                            Layout.fillWidth: true

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 10

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "LED Frequency (Hz) "
                                    visible: ledEnabled.checked
                                }

                                SpinBox {
                                    id: ledLoopDelay
                                    from: 1
                                    to: 1000
                                    value: 20
                                    stepSize: 1
                                    visible: ledEnabled.checked
                                    editable: true
                                }

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Max Blend Count"
                                }

                                SpinBox {
                                    id: ledMaxBlendCount
                                    from: 1
                                    to: 100
                                    value: 4
                                    editable: true
                                }

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "LED Fix"
                                }

                                SpinBox {
                                    id: ledFix
                                    from: 1
                                    to: 1000000
                                    value: 100
                                    editable: true
                                }

                                CheckBox {
                                    id: ledUpdateNotRunning
                                    text: "Don't update LEDs while running"
                                    checked: false
                                }

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "LED Max Brightness (80% by default)"
                                }

                                Loader {
                                    id: ledMaxBrightnessLoader
                                    sourceComponent: customValueSlider
                                    onLoaded: {
                                        item.from = 0.0
                                        item.to = 1.0
                                        item.value = 0.8
                                        item.stepSize = 0.01
                                        item.asPercent = true
                                        item.valueChanged.connect(function() {
                                            applyLedControlBrightnessCap()
                                        })
                                        applyLedControlBrightnessCap()
                                    }
                                }

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Dim RGB on Highbeam (% of main brightness)"
                                }

                                Loader {
                                    id: ledDimOnHighbeamRatioLoader
                                    sourceComponent: customValueSlider
                                    onLoaded: {
                                        item.from = 0.0
                                        item.to = 1.0
                                        item.value = 0.0
                                        item.stepSize = 0.1
                                        item.asPercent = true
                                    }
                                }

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Mode"
                                }

                                ComboBox {
                                    id: ledMode
                                    Layout.fillWidth: true
                                    model: [
                                        {text: "White/Red", value: 0},
                                        {text: "Battery Meter", value: 1},
                                        {text: "Cylon", value: 2},
                                        {text: "Rainbow Chase", value: 3}
                                    ]
                                    textRole: "text"
                                    valueRole: "value"
                                    onCurrentIndexChanged: {
                                        value = model[currentIndex].value
                                    }
                                    property int value: 0
                                }

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Idle Mode"
                                }

                                ComboBox {
                                    id: ledModeIdle
                                    Layout.fillWidth: true
                                    model: ledMode.model
                                    textRole: "text"
                                    valueRole: "value"
                                    onCurrentIndexChanged: {
                                        value = model[currentIndex].value
                                    }
                                    property int value: 5
                                }

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Status Mode"
                                }

                                ComboBox {
                                    id: ledModeStatus
                                    Layout.fillWidth: true
                                    model: [
                                        {text: "Green->Red Voltage, Blue Sensor, Yellow->Red Duty", value: 0},
                                        {text: "Swap ADC1/ADC2", value: 1},
                                    ]
                                    textRole: "text"
                                    valueRole: "value"
                                    onCurrentIndexChanged: {
                                        value = model[currentIndex].value
                                    }
                                    property int value: 0
                                }

                                CheckBox {
                                    id: ledMallGrabEnabled
                                    text: "Mall Grab"
                                    checked: true
                                }

                                CheckBox {
                                    id: ledBrakeLightEnabled
                                    text: "Brake Light"
                                    checked: true
                                }

                                CheckBox {
                                    id: ledShowBatteryCharging
                                    text: "Show battery % while charging"
                                    checked: false
                                    visible: false
                                }

                                ColumnLayout {
                                    id: ledBrakeLightLayout
                                    visible: ledBrakeLightEnabled.checked
                                    spacing: 10

                                    Text {
                                        color: Utility.getAppHexColor("lightText")
                                        text: "Brake Light Min Amps"
                                    }

                                    SpinBox {
                                        id: ledBrakeLightMinAmps
                                        from: -40.0
                                        to: -1.0
                                        value: -4.0
                                        editable: true
                                    }
                                }

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Idle Timeout (sec)"
                                }

                                SpinBox {
                                    id: idleTimeout
                                    from: 1
                                    to: 100
                                    value: 1
                                    editable: true
                                }

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Idle Timeout Shutoff (sec)"
                                }

                                SpinBox {
                                    id: idleTimeoutShutoff
                                    from: 0
                                    to: 1000
                                    value: 600
                                    editable: true
                                }

                            }
                        }

                        GroupBox {
                            title: "Status Config"
                            Layout.fillWidth: true

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 10

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Status Strip"
                                }

                                ComboBox {
                                    id: ledStatusStripType
                                    Layout.fillWidth: true
                                    model: [
                                        {text: "None", value: 0},
                                        {text: "Custom", value: 1},
                                    ]
                                    textRole: "text"
                                    valueRole: "value"
                                    onCurrentIndexChanged: {
                                        value = model[currentIndex].value
                                        updateStatusLEDSettings()
                                    }
                                    property int value: 1
                                }

                                ColumnLayout {
                                    id: ledStatusPinLayout
                                    visible: ledStatusStripType.currentValue > 0
                                    spacing: 10

                                    Text {
                                        color: Utility.getAppHexColor("lightText")
                                        text: "Status Target CAN-ID"
                                    }

                                    ComboBox {
                                        id: statusTargetID
                                        Layout.fillWidth: true
                                        model: targetCanOptions
                                        textRole: "text"
                                        valueRole: "value"
                                        property int value: -1

                                        function syncIndexFromValue() {
                                            for (var i = 0; i < model.length; i++) {
                                                if (model[i].value === value) {
                                                    if (currentIndex !== i) currentIndex = i
                                                    return
                                                }
                                            }
                                            currentIndex = -1
                                        }

                                        onCurrentIndexChanged: {
                                            if (currentIndex >= 0 && currentIndex < model.length) {
                                                value = model[currentIndex].value
                                            }
                                        }
                                        onActivated: {
                                            targetSelectionDirty = true
                                        }
                                        onValueChanged: syncIndexFromValue()
                                        onModelChanged: syncIndexFromValue()
                                        Component.onCompleted: syncIndexFromValue()
                                    }

                                    Text {
                                        color: Utility.getAppHexColor("lightText")
                                        text: "Status Pin"
                                    }

                                    SpinBox {
                                        id: ledStatusPin
                                        from: -1
                                        to: 100
                                        value: 7
                                        editable: true
                                    }

                                    Text {
                                        color: Utility.getAppHexColor("lightText")
                                        text: "Status Num"
                                    }

                                    SpinBox {
                                        id: ledStatusNum
                                        from: 0
                                        to: 100
                                        value: 10
                                        editable: true
                                    }

                                    Text {
                                        color: Utility.getAppHexColor("lightText")
                                        text: "Status Type"
                                    }

                                    ComboBox {
                                        id: ledStatusType
                                        Layout.fillWidth: true
                                        model: [
                                            {text: "GRB", value: 0},
                                            {text: "RGB", value: 1},
                                            {text: "GRBW", value: 2},
                                            {text: "RGBW", value: 3},
                                            {text: "WRGB", value: 4},
                                        ]
                                        textRole: "text"
                                        valueRole: "value"
                                        onCurrentIndexChanged: {
                                            value = model[currentIndex].value
                                        }
                                        property int value: 0
                                    }

                                    CheckBox {
                                        id: ledStatusReversed
                                        text: "Status Reversed"
                                        checked: false
                                    }
                                }
                            }
                        }

                        GroupBox {
                            title: "LED Front Config"
                            Layout.fillWidth: true

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 10

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Front Strip"
                                }

                                ComboBox {
                                    id: ledFrontStripType
                                    Layout.fillWidth: true
                                    model: [
                                        {text: "None", value: 0},
                                        {text: "Custom", value: 1},
                                        {text: "Avaspark Laserbeam", value: 2},
                                        {text: "Avaspark Laserbeam Pint", value: 3},
                                        {text: "JetFleet H4", value: 4},
                                        {text: "JetFleet H4 (no limit DCDC)", value: 5},
                                        {text: "JetFleet GT", value: 6},
                                        {text: "Stock GT", value: 7},
                                        {text: "Avaspark Laserbeam V2", value: 8},
                                        {text: "Avaspark Laserbeam V2 Pint", value: 9},
                                        {text: "Light-shutka Flashfires", value: 10},
                                        {text: "Fungineers GTFO", value: 11},
                                    ]
                                    textRole: "text"
                                    valueRole: "value"
                                    onCurrentIndexChanged: {
                                        preserveSettingsBottomIfNeeded()
                                        value = model[currentIndex].value
                                        updateFrontLEDSettings()
                                    }
                                    property int value: 2
                                }

                                ColumnLayout {
                                    id: ledFrontPinLayout
                                    visible: ledFrontStripType.currentValue > 0
                                    spacing: 10
                                    
                                    Text {
                                        color: Utility.getAppHexColor("lightText")
                                        text: "Front Target CAN-ID"
                                    }

                                    ComboBox {
                                        id: frontTargetID
                                        Layout.fillWidth: true
                                        model: targetCanOptions
                                        textRole: "text"
                                        valueRole: "value"
                                        property int value: -1

                                        function syncIndexFromValue() {
                                            for (var i = 0; i < model.length; i++) {
                                                if (model[i].value === value) {
                                                    if (currentIndex !== i) currentIndex = i
                                                    return
                                                }
                                            }
                                            currentIndex = -1
                                        }

                                        onCurrentIndexChanged: {
                                            if (currentIndex >= 0 && currentIndex < model.length) {
                                                value = model[currentIndex].value
                                            }
                                        }
                                        onActivated: {
                                            targetSelectionDirty = true
                                        }
                                        onValueChanged: syncIndexFromValue()
                                        onModelChanged: syncIndexFromValue()
                                        Component.onCompleted: syncIndexFromValue()
                                    }

                                    Text {
                                        color: Utility.getAppHexColor("lightText")
                                        text: "Front Pin"
                                    }

                                    SpinBox {
                                        id: ledFrontPin
                                        from: -1
                                        to: 100
                                        value: 8
                                        editable: true
                                    }
                                }

                                ColumnLayout {
                                    id: ledFrontHighbeamPinLayout
                                    visible: ledFrontStripType.currentValue === 7
                                    spacing: 10

                                    Text {
                                        color: Utility.getAppHexColor("lightText")
                                        text: "Front Highbeam Pin"
                                    }

                                    SpinBox {
                                        id: ledFrontHighbeamPin
                                        from: -1
                                        to: 100
                                        value: -1
                                        editable: true
                                    }
                                }

                                ColumnLayout {
                                    id: ledFrontCustomSettings
                                    visible: ledFrontStripType.currentValue === 1
                                    spacing: 10

                                    Text {
                                        color: Utility.getAppHexColor("lightText")
                                        text: "Front Num"
                                    }

                                    SpinBox {
                                        id: ledFrontNum
                                        from: 0
                                        to: 100
                                        value: 18
                                        editable: true
                                    }

                                    Text {
                                        color: Utility.getAppHexColor("lightText")
                                        text: "Front Type"
                                    }

                                    ComboBox {
                                        id: ledFrontType
                                        Layout.fillWidth: true
                                        model: [
                                            {text: "GRB", value: 0},
                                            {text: "RGB", value: 1},
                                            {text: "GRBW", value: 2},
                                            {text: "RGBW", value: 3},
                                            {text: "WRGB", value: 4},
                                        ]
                                        textRole: "text"
                                        valueRole: "value"
                                        onCurrentIndexChanged: {
                                            value = model[currentIndex].value
                                        }
                                        property int value: 0
                                    }
                                }

                                ColumnLayout {
                                    id: ledFrontReversedLayout
                                    visible: ledFrontStripType.currentValue > 0
                                    spacing: 10

                                    CheckBox {
                                        id: ledFrontReversed
                                        text: "Front Reversed"
                                        checked: false
                                    }
                                }
                            }
                        }

                        GroupBox {
                            title: "LED Rear Config"
                            Layout.fillWidth: true

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 10

                                Text {
                                    color: Utility.getAppHexColor("lightText")
                                    text: "Rear Strip"
                                }

                                ComboBox {
                                    id: ledRearStripType
                                    Layout.fillWidth: true
                                    model: [
                                        {text: "None", value: 0},
                                        {text: "Custom", value: 1},
                                        {text: "Avaspark Laserbeam", value: 2},
                                        {text: "Avaspark Laserbeam Pint", value: 3},
                                        {text: "JetFleet H4", value: 4},
                                        {text: "JetFleet H4 (no limit DCDC)", value: 5},
                                        {text: "JetFleet GT", value: 6},
                                        {text: "Stock GT", value: 7},
                                        {text: "Avaspark Laserbeam V2", value: 8},
                                        {text: "Avaspark Laserbeam V2 Pint", value: 9},
                                        {text: "Light-shutka Flashfires", value: 10},
                                        {text: "Fungineers GTFO", value: 11},
                                    ]
                                    textRole: "text"
                                    valueRole: "value"
                                    onCurrentIndexChanged: {
                                        preserveSettingsBottomIfNeeded()
                                        value = model[currentIndex].value
                                        updateRearLEDSettings()
                                    }
                                    property int value: 2
                                }

                                ColumnLayout {
                                    id: ledRearPinLayout
                                    visible: ledRearStripType.currentValue > 0
                                    spacing: 10

                                    Text {
                                        color: Utility.getAppHexColor("lightText")
                                        text: "Rear Target CAN-ID"
                                    }

                                    ComboBox {
                                        id: rearTargetID
                                        Layout.fillWidth: true
                                        model: targetCanOptions
                                        textRole: "text"
                                        valueRole: "value"
                                        property int value: -1

                                        function syncIndexFromValue() {
                                            for (var i = 0; i < model.length; i++) {
                                                if (model[i].value === value) {
                                                    if (currentIndex !== i) currentIndex = i
                                                    return
                                                }
                                            }
                                            currentIndex = -1
                                        }

                                        onCurrentIndexChanged: {
                                            if (currentIndex >= 0 && currentIndex < model.length) {
                                                value = model[currentIndex].value
                                            }
                                        }
                                        onActivated: {
                                            targetSelectionDirty = true
                                        }
                                        onValueChanged: syncIndexFromValue()
                                        onModelChanged: syncIndexFromValue()
                                        Component.onCompleted: syncIndexFromValue()
                                    }

                                    Text {
                                        color: Utility.getAppHexColor("lightText")
                                        text: "Rear Pin"
                                    }

                                    SpinBox {
                                        id: ledRearPin
                                        from: -1
                                        to: 100
                                        value: 9
                                        editable: true
                                    }
                                }

                                ColumnLayout {
                                    id: ledRearHighbeamPinLayout
                                    visible: ledRearStripType.currentValue === 7
                                    spacing: 10

                                    Text {
                                        color: Utility.getAppHexColor("lightText")
                                        text: "Rear Highbeam Pin"
                                    }

                                    SpinBox {
                                        id: ledRearHighbeamPin
                                        from: -1
                                        to: 100
                                        value: -1
                                        editable: true
                                    }
                                }

                                ColumnLayout {
                                    id: ledRearCustomSettings
                                    visible: ledRearStripType.currentValue === 1
                                    spacing: 10

                                    Text {
                                        color: Utility.getAppHexColor("lightText")
                                        text: "Rear Num"
                                    }

                                    SpinBox {
                                        id: ledRearNum
                                        from: 0
                                        to: 100
                                        value: 18
                                        editable: true
                                    }

                                    Text {
                                        color: Utility.getAppHexColor("lightText")
                                        text: "Rear Type"
                                    }

                                    ComboBox {
                                        id: ledRearType
                                        Layout.fillWidth: true
                                        model: [
                                            {text: "GRB", value: 0},
                                            {text: "RGB", value: 1},
                                            {text: "GRBW", value: 2},
                                            {text: "RGBW", value: 3},
                                            {text: "WRGB", value: 4},
                                        ]
                                        textRole: "text"
                                        valueRole: "value"
                                        onCurrentIndexChanged: {
                                            value = model[currentIndex].value
                                        }
                                        property int value: 0
                                    }
                                }

                                ColumnLayout {
                                    id: ledRearReversedLayout
                                    visible: ledRearStripType.currentValue > 0
                                    spacing: 10

                                    CheckBox {
                                        id: ledRearReversed
                                        text: "Rear Reversed"
                                        checked: false
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.preferredWidth: stackLayout.width
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        color: Utility.getAppHexColor("lightText")
                        font.bold: true
                        font.pointSize: 21
                        text: "Daisy-chain tip: shared data pins are supported.\nWire LEDs in configured order and use matching Target CAN-ID assignments."
                    }
                }
            }

            // Settings tab
            ScrollView {
                id: settingsScroll
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                contentWidth: availableWidth

                Connections {
                    target: settingsScroll.contentItem
                    function onContentHeightChanged() {
                        if (settingsScrollKeepBottom) {
                            scrollSettingsToBottom()
                        }
                    }
                }

                ColumnLayout {
                    width: settingsScroll.availableWidth
                    spacing: 10

                    CheckBox {
                        id: ledEnabled
                        checked: true
                        visible: false
                        enabled: false
                    }
                    
						GroupBox {
							title: "Node Role"
							Layout.fillWidth: true
							visible: false
					
						ColumnLayout {
							anchors.fill: parent
							spacing: 10
					
							Text {
								color: Utility.getAppHexColor("lightText")
								text: "Node Role"
							}
					
							ComboBox {
								id: nodeRole
								Layout.fillWidth: true
								model: [
									{ text: "Master", value: 0 },
									{ text: "Slave",  value: 1 }
								]
								textRole: "text"
								valueRole: "value"
							
								property int value: 2
							
								function syncIndexFromValue() {
									for (var i = 0; i < model.length; i++) {
										if (model[i].value === value) {
											if (currentIndex !== i) currentIndex = i
											return
										}
									}
								}
							
								onCurrentIndexChanged: {
									value = model[currentIndex].value
								}
							
								onValueChanged: {
									syncIndexFromValue()
								}
							
								Component.onCompleted: {
									syncIndexFromValue()
								}
							}
					
							Text {
								color: Utility.getAppHexColor("lightText")
								text: "Master CAN-ID (slave only)"
								visible: nodeRole.value === 1
							}
					
							SpinBox {
								id: masterCanID
								from: -1
								to: 254
								value: -1
								editable: true
								visible: nodeRole.value === 1
							}
					
							// Hidden/internal, but defined so parser can assign it safely
							SpinBox {
								id: peersCache
								from: 0
								to: 255
								value: 0
								visible: false
							}
						}
					}

                    GroupBox {
                        title: "Discharge Curve"
                        Layout.fillWidth: true

                        ColumnLayout {
                            anchors.fill: parent
                            width: parent.width
                            spacing: 10

                            Text {
                                color: Utility.getAppHexColor("lightText")
                                wrapMode: Text.WordWrap
                                text: "State of charge now uses pack voltage with the selected discharge curve."
                            }

                            Text {
                                color: Utility.getAppHexColor("lightText")
                                text: "Cell Type"
                                                            }

                            ComboBox {
                                id: cellType
                                                                Layout.fillWidth: true
                                    model: [
                                        {text: "Linear", value: 0},
                                        {text: "P28A", value: 1},
                                        {text: "P30B", value: 2},
                                        {text: "P42A", value: 3},
                                        {text: "P45B", value: 4},
                                        {text: "P50B", value: 5},
                                        {text: "DG40", value: 6},
                                        {text: "50S", value: 7},
                                        {text: "VTC6", value: 8},
                                    ]
                                textRole: "text"
                                valueRole: "value"
                                onCurrentIndexChanged: {
                                   value = model[currentIndex].value
                                }
                                property int value: 4
                            }

                            Text {
                                color: Utility.getAppHexColor("lightText")
                                text: "Series Cells"
                            }

                            SpinBox {
                                id: seriesCells
                                from: -1
                                to: 64
                                value: -1
                                editable: true
                            }
                        }
                    }

                    GroupBox {
                        title: "Loop Settings"
                        Layout.fillWidth: true

                        ColumnLayout {
                            width: parent.width
                            spacing: 10

                            Text {
                                color: Utility.getAppHexColor("lightText")
                                text: "CAN Frequency (Hz)"
                            }

                            SpinBox {
                                id: canLoopDelay
                                from: 1
                                to: 1000
                                value: 2
                                stepSize: 1
                                editable: true
                            }
                        }
                    }


                    Text {
                        Layout.fillWidth: true
                        Layout.preferredWidth: settingsScroll.availableWidth
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        color: Utility.getAppHexColor("lightText")
                        font.bold: true
                        font.pointSize: 21
                        text: "Want this device back in default slave mode?\nUse \"Restore Default Config\" from the menu below."
                    }
                }
            }

            // Node Slave Tab
            ScrollView {
                id: nodeSlaveScroll
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                contentWidth: availableWidth

                ColumnLayout {
                    width: nodeSlaveScroll.availableWidth
                    spacing: 20

                    Item { Layout.fillHeight: true }

                    GroupBox {
                        title: "Node Slave"
                        Layout.fillWidth: true

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 10

                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: Utility.getAppHexColor("lightText")
                                font.bold: true
                                font.pointSize: 20
                                text: "This node is configured as a slave. It follows the master and receives configuration from the Master CAN-ID."
                            }

                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: Utility.getAppHexColor("lightText")
                                font.bold: true
                                font.pointSize: 20
                                text: "Master CAN-ID: " + masterCanID.value
                            }

                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: Utility.getAppHexColor("lightText")
                                font.bold: true
                                font.pointSize: 18
                                visible: isSlaveOutputEnabledForNode(ledFrontStripType.currentIndex, frontTargetID.value)
                                text: slaveOutputLine("Front", ledFrontPin.value, ledFrontReversed.checked, stripTypeLabel(ledFrontStripType.currentIndex))
                            }

                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: Utility.getAppHexColor("lightText")
                                font.bold: true
                                font.pointSize: 18
                                visible: isSlaveOutputEnabledForNode(ledRearStripType.currentIndex, rearTargetID.value)
                                text: slaveOutputLine("Rear", ledRearPin.value, ledRearReversed.checked, stripTypeLabel(ledRearStripType.currentIndex))
                            }

                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: Utility.getAppHexColor("lightText")
                                font.bold: true
                                font.pointSize: 18
                                visible: isSlaveOutputEnabledForNode(ledStatusStripType.currentIndex, statusTargetID.value)
                                text: slaveOutputLine("Status", ledStatusPin.value, ledStatusReversed.checked, statusStripTypeLabel(ledStatusStripType.currentIndex))
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // About Tab
            ScrollView {
                id: aboutScroll
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                contentWidth: availableWidth

                ColumnLayout {
                    width: aboutScroll.availableWidth
                    spacing: 16

                    Image {
                        id: aboutLogo
                        source: "https://i0.wp.com/unleashedcreativity.com.au/wp-content/uploads/2024/06/cropped-UC-Logo-no-background.png?fit=501%2C395&ssl=1"
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: Math.min(stackLayout.width * 0.6, 260)
                        Layout.preferredHeight: 150
                    }

                    TextArea {
                        id: aboutText
                        textFormat: Text.RichText
                        font.pointSize: 13
                        text: "<p><b>Unleashed Creativity Lights PACKAGE</b></p>" +
                            "<p>A package for ESP32-C3 lighting hardware running VESC(R) software over CAN bus, integrated with the Refloat package.</p>" +
                            "<p><b>Major Features</b></p>" +
                            "<ul>" +
                            "<li>New Refloat RT API integration.</li>" +
                            "<li>Lighting control now from Refloat.</li>" +
                            "<li>Master-only Refloat discovery and polling, with forwarded state for peers/slaves.</li>" +
                            "<li>Two-role node model only: Master and Slave (default is Slave).</li>" +
                            "<li>Master is the sole source of configuration.</li>" +
                            "<li>Slave stores pushed configuration with CRC-checked persistence.</li>" +
                            "<li>Targeted LED outputs using SELF (-1) or peer CAN-ID for daisy-chain layouts.</li>" +
                            "<li>Slave diagnostics tab with per-output details for node-targeted channels.</li>" +
                            "<li>Runtime config refresh improvements for UI (Read Config and status-driven target updates).</li>" +
                            "<li>Reduced CAN chatter defaults for better app link stability.</li>" +
                            "<li>Advanced lighting behavior and patterns: status, run/reverse white-red, battery, Cylon, rainbow, brake and highbeam.</li>" +
                            "<li>Optimized for minimal CAN traffic during normal operation.</li>" +
                            "</ul>" +
                            "<p><b>What's Changed Since 2026.041</b></p>" +
                            "<ul>" +
                            "<li>Release V2026.042.</li>" +
                            "<li>Retains target CAN-ID selector stability while user edits are pending Save Config.</li>" +
                            "<li>Retains the explicit diagnostics line when target CAN-ID changes are unsaved.</li>" +
                            "</ul>" +
                            "<p>Website: <a href='https://www.UnleashedCreativity.com.au'>https://www.UnleashedCreativity.com.au</a></p>" +
                            "<p><b>Trademark Notice:</b> VESC is a registered trademark of Benjamin Vedder. Unleashed Creativity hardware is sold for use with VESC(R) software and VESC(R) Tool. No affiliation with or endorsement by Benjamin Vedder or the VESC Project is claimed.</p>" +
                            "<p><b>Thanks:</b> Built on the original Float Accessories work by Relys: <a href='https://github.com/Relys/vesc_pkg/tree/float-accessories'>https://github.com/Relys/vesc_pkg/tree/float-accessories</a></p>" +
                            "<p><b>BUILD INFO</b><br/>Version 2026.042<br/></p>"
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Utility.getAppHexColor("lightText")
                        onLinkActivated: function(url) {
                            Qt.openUrlExternally(url)
                        }
                    }
                }
            }
        }

	        // Save and Restore Buttons
	        RowLayout {
	            Layout.fillWidth: true
	            spacing: 10
	            visible: !mainLayout.isSlaveUi && (
                (tabBar.currentIndex === 0)
                || tabBar.currentIndex === 1
                || tabBar.currentIndex === 2
            )

            Item { Layout.fillWidth: true }

            Button {
                id: saveConfigButton
                text: "Save Config"
                enabled: readConfig && lastStatusTime < 2
                visible: !mainLayout.isSlaveUi
                onClicked: {
                    console.log(makeArgStr())
                    sendCode(String.fromCharCode(floatAccessoriesMagic) + String.fromCharCode(1) + "(recv-config " + makeArgStr() + " )")
                    targetSelectionDirty = false
                }
            }

	            ToolButton {
                id: optionsButton
                text: "⋮"
                font.pixelSize: 24
                visible: !mainLayout.isSlaveUi
                onClicked: optionsMenu.open()

                Menu {
                    id: optionsMenu
                    y: optionsButton.height

                    MenuItem {
                        text: "Read Config"
                        onClicked: {
                            sendCode(String.fromCharCode(floatAccessoriesMagic) + String.fromCharCode(1) + "(send-config)")
                        }
                    }

                    MenuItem {
                        text: "Restore Default Config"
                        onClicked: {
                            sendCode(String.fromCharCode(floatAccessoriesMagic) + String.fromCharCode(1) + "(restore-config)")
                            sendCode(String.fromCharCode(floatAccessoriesMagic) + String.fromCharCode(1) + "(send-config)")
                        }
                    }
	                }
	            }
	        }

	        RowLayout {
	            Layout.fillWidth: true
	            spacing: 10
	            visible: mainLayout.isSlaveUi && tabBar.currentIndex === 3

	            Item { Layout.fillWidth: true }

	            ColumnLayout {
	                spacing: 8
                    Layout.alignment: Qt.AlignHCenter

	                Button {
	                    text: "Become Master"
                        Layout.alignment: Qt.AlignHCenter
                        visible: masterCanID.value === -1
	                    onClicked: {
                        nodeRole.value = 0
                        nodeRole.currentIndex = 0
                        masterCanID.value = -1
                        uclEffectiveRole = 0
                        tabBar.currentIndex = 2
                        sendCode(
                            String.fromCharCode(floatAccessoriesMagic)
                            + String.fromCharCode(1)
                            + "(progn (set-config 'node-role 0) (set-config 'reserved-slot-5 3) (set-config 'master-can-id -1) (save-config) (send-config))"
                        )
	                    }
	                }

	                Button {
	                    text: "Restore Settings"
                        Layout.alignment: Qt.AlignHCenter
	                    onClicked: {
	                        sendCode(String.fromCharCode(floatAccessoriesMagic) + String.fromCharCode(1) + "(restore-config)")
	                        sendCode(String.fromCharCode(floatAccessoriesMagic) + String.fromCharCode(1) + "(send-config)")
	                    }
	                }
	            }

	            Item { Layout.fillWidth: true }
	        }
	    }

    function updateStatusLEDSettings() {
        switch(ledStatusStripType.value) {
            case 0: // None
                break
            case 1: // Custom
                break
            default:
                // Do nothing, keep user-defined values
        }
    }

    function updateFrontLEDSettings() {
        switch(ledFrontStripType.value) {
            case 0: // None
                break
            case 1: // Custom
                break
            case 2: // Avaspark Laserbeam
                ledFrontNum.value = 18
                ledFrontType.currentIndex = 0
                break
            case 3: // Avaspark Laserbeam Pint
                ledFrontNum.value = 16
                ledFrontType.currentIndex = 0
                break
            case 4: // JetFleet H4
                ledFrontNum.value = 17
                ledFrontType.currentIndex = 0
                break
            case 5: // JetFleet H4 (no limit)
                ledFrontNum.value = 17
                ledFrontType.currentIndex = 0
                break
            case 6: // JetFleet GT
                ledFrontNum.value = 11
                ledFrontType.currentIndex = 0
                break
            case 7: // Stock GT
                ledFrontNum.value = 11
                ledFrontType.currentIndex = 2
                break
            case 8: // Avaspark Laserbeam V3
                ledFrontNum.value = 13
                ledFrontType.currentIndex = 0
                break
            case 9: // Avaspark Laserbeam V3 Pint
                ledFrontNum.value = 10
                ledFrontType.currentIndex = 0
                break
            case 10: // Light-shutka Flashfires
                ledFrontNum.value = 20;
                ledFrontType.currentIndex = 0
                break
            case 11: // Fungineers GTFO
                ledFrontNum.value = 10
                ledFrontType.currentIndex = 0
                break
            default:
                // Do nothing, keep user-defined values
        }
    }

    function updateRearLEDSettings() {
        switch(ledRearStripType.value) {
            case 0: // None
                break
            case 1: // Custom
                break
            case 2: // Avaspark Laserbeam
                ledRearNum.value = 18
                ledRearType.currentIndex = 0
                break
            case 3: // Avaspark Laserbeam Pint
                ledRearNum.value = 16
                ledRearType.currentIndex = 0
                break
            case 4: // JetFleet H4
                ledRearNum.value = 17
                ledRearType.currentIndex = 0
                break
            case 5: // JetFleet H4 (no limit)
                ledRearNum.value = 17
                ledRearType.currentIndex = 0
                break
            case 6: // JetFleet GT
                ledRearNum.value = 11
                ledRearType.currentIndex = 0
                break
            case 7: // Stock GT
                ledRearNum.value = 11
                ledRearType.currentIndex = 2
                break
            case 8: // Avaspark Laserbeam V2
                ledRearNum.value = 13
                ledRearType.currentIndex = 0
                break
            case 9: // Avaspark Laserbeam V2 Pint
                ledRearNum.value = 10
                ledRearType.currentIndex = 0
                break
            case 10: // Light-shutka Flashfires
                ledRearNum.value = 20
                ledRearType.currentIndex = 0
                break
            case 11: // Fungineers GTFO
                ledRearNum.value = 10
                ledRearType.currentIndex = 0
                break
            default:
                // Do nothing, keep user-defined values
        }
    }

    function refreshTargetCanOptions(peerIds) {
        var ids = []
        var seen = {}

        function addId(id) {
            var n = Number(id)
            if (isNaN(n) || n < -1 || n > 254) {
                return
            }
            var key = String(n)
            if (seen[key]) {
                return
            }
            seen[key] = true
            ids.push(n)
        }

        addId(-1)
        if (peerIds && peerIds.length) {
            for (var i = 0; i < peerIds.length; i++) {
                addId(peerIds[i])
            }
        }

        if (frontTargetID) { addId(frontTargetID.value) }
        if (rearTargetID) { addId(rearTargetID.value) }
        if (statusTargetID) { addId(statusTargetID.value) }

        ids.sort(function(a, b) {
            if (a === -1) return -1
            if (b === -1) return 1
            return a - b
        })

        var opts = []
        for (var j = 0; j < ids.length; j++) {
            var idVal = ids[j]
            opts.push({
                text: (idVal === -1) ? "SELF (-1)" : ("CAN-ID " + idVal),
                value: idVal
            })
        }

        targetCanOptions = opts
    }

    function getLedMaxBrightnessCap() {
        var cap = 1.0
        if (ledMaxBrightnessLoader && ledMaxBrightnessLoader.item) {
            cap = Number(ledMaxBrightnessLoader.item.value)
        }
        if (isNaN(cap)) {
            cap = 1.0
        }
        return Math.max(0.0, Math.min(1.0, cap))
    }

    function isSettingsScrollAtBottom() {
        if (!configScroll || !configScroll.contentItem) {
            return false
        }
        var flick = configScroll.contentItem
        return (flick.contentY + flick.height) >= (flick.contentHeight - 6)
    }

    function scrollSettingsToBottom() {
        if (!configScroll || !configScroll.contentItem) {
            return
        }
        var flick = configScroll.contentItem
        flick.contentY = Math.max(0, flick.contentHeight - flick.height)
    }

    function preserveSettingsBottomIfNeeded() {
        settingsScrollKeepBottom = isSettingsScrollAtBottom()
        if (settingsScrollKeepBottom) {
            Qt.callLater(scrollSettingsToBottom)
            settingsBottomStickTimerShort.restart()
            settingsBottomStickTimerLong.restart()
        }
    }

    function yesNo(v) {
        return v ? "Yes" : "No"
    }

    function slaveOutputLine(name, pin, reversed, typeLabel) {
        return name + ", Pin:" + pin + "  Rev:" + yesNo(reversed) + "  Type:" + typeLabel
    }

    function isSlaveOutputEnabledForNode(stripType, targetId) {
        var t = Number(targetId)
        return Number(stripType) > 0
            && (
                (localCanId >= 0 && t === Number(localCanId))
                || (localCanId < 0 && t >= 0)
            )
    }

    function statusStripTypeLabel(stripType) {
        var t = Number(stripType)
        switch (t) {
        case 1: return "Custom"
        default: return "Off"
        }
    }

    function stripTypeLabel(stripType) {
        var t = Number(stripType)
        switch (t) {
        case 1: return "Custom"
        case 2: return "Avaspark Laserbeam"
        case 3: return "Avaspark Laserbeam Pint"
        case 4: return "JetFleet H4"
        case 5: return "JetFleet H4 (no limit)"
        case 6: return "JetFleet GT"
        case 7: return "Stock GT"
        case 8: return "Avaspark Laserbeam V3"
        case 9: return "Avaspark Laserbeam V3 Pint"
        case 10: return "Light-shutka Flashfires"
        case 11: return "Fungineers GTFO"
        default: return "Off"
        }
    }

    function applyLedControlBrightnessCap() {
        var cap = getLedMaxBrightnessCap()
        var sliders = [
            ledBrightnessLoader,
            ledBrightnessIdleLoader,
            ledBrightnessStatusLoader,
            ledBrightnessHighbeamLoader
        ]

        for (var i = 0; i < sliders.length; i++) {
            var loader = sliders[i]
            if (loader && loader.item) {
                loader.item.to = cap
                if (loader.item.value > cap) {
                    loader.item.value = cap
                }
                if (loader.item.value < loader.item.from) {
                    loader.item.value = loader.item.from
                }
            }
        }
    }

    function makeControlArgStr() {
        return [
            1,
            1,
            parseFloat(getSliderValue(ledBrightnessLoader, cfgLedBrightness)).toFixed(2),
            parseFloat(getSliderValue(ledBrightnessHighbeamLoader, cfgLedBrightnessHighbeam)).toFixed(2),
            parseFloat(getSliderValue(ledBrightnessIdleLoader, cfgLedBrightnessIdle)).toFixed(2),
            parseFloat(getSliderValue(ledBrightnessStatusLoader, cfgLedBrightnessStatus)).toFixed(2),
            0
        ].join(" ");
    }

    function handleDebouncedChange() {
        debounceTimer.restart()  // Reset the timer on any change
    }

    function applyControlChanges() {
        //console.log("Applying LED control settings after debounce")
        sendCode(String.fromCharCode(floatAccessoriesMagic) + String.fromCharCode(1) + "(recv-control " + makeControlArgStr() + " )")
    }

    function makeArgStr() {
        return [
            1,
            0,
            1,
            1,
            ledMode.currentIndex,
            ledModeIdle.currentIndex,
            ledModeStatus.currentIndex,
            ledMallGrabEnabled.checked * 1,
            ledBrakeLightEnabled.checked * 1,
            parseFloat(ledBrakeLightMinAmps.value).toFixed(2),
            idleTimeout.value,
            idleTimeoutShutoff.value,
            parseFloat(getSliderValue(ledBrightnessLoader, cfgLedBrightness)).toFixed(2),
            parseFloat(getSliderValue(ledBrightnessHighbeamLoader, cfgLedBrightnessHighbeam)).toFixed(2),
            parseFloat(getSliderValue(ledBrightnessIdleLoader, cfgLedBrightnessIdle)).toFixed(2),
            parseFloat(getSliderValue(ledBrightnessStatusLoader, cfgLedBrightnessStatus)).toFixed(2),
            ledStatusPin.value,
            ledStatusNum.value,
            ledStatusType.currentIndex,
            ledStatusReversed.checked * 1,
            ledFrontPin.value,
            ledFrontNum.value,
            ledFrontType.currentIndex,
            ledFrontReversed.checked * 1,
            ledFrontStripType.currentIndex,
            ledRearPin.value,
            ledRearNum.value,
            ledRearType.currentIndex,
            ledRearReversed.checked * 1,
            ledRearStripType.currentIndex,
            -1,
            -1,
            -1,
            -1,
            0,
            0,
            ledLoopDelay.value,
            8,
            canLoopDelay.value,
            ledMaxBlendCount.value,
            parseFloat(ledDimOnHighbeamRatioLoader.item.value).toFixed(2),
            0,
            ledStatusStripType.currentIndex,
            0,
            ledFix.value,
            0,
            ledFrontHighbeamPin.value,
            ledRearHighbeamPin.value,
            128,
            parseFloat(getSliderValue(ledMaxBrightnessLoader, 0.8)).toFixed(2),
            1,
            cellType.value,
            ledUpdateNotRunning.checked * 1,
            0,
            seriesCells.value,
            -1,
            frontTargetID.value,
            rearTargetID.value,
            statusTargetID.value,
            nodeRole.value,
            masterCanID.value,
            peersCache.value
        ].join(" ");
    }

    // Property to track enabled tabs
    property var enabledIndices: []

    // Update enabled indices whenever checkbox states change
    onEnabledIndicesChanged: {
        // If current tab is disabled, switch to first enabled tab
        if (!enabledIndices.includes(tabBar2.currentIndex)) {
            const firstEnabled = enabledIndices[0]
            if (firstEnabled !== undefined) {
                tabBar2.currentIndex = firstEnabled
            }
        }
    }

    function updateEnabledIndices() {
        const newIndices = []
        if (ledEnabled.checked) newIndices.push(0)

        enabledIndices = newIndices
    }

    function sendCode(str) {
        mCommands.sendCustomAppData(str + '\0')
    }

    function getSliderValue(loader, fallbackValue) {
        if (loader && loader.item) {
            return loader.item.value
        }
        return fallbackValue
    }

    function setLoaderValue(loader, value) {
        if (loader && loader.item) {
            loader.item.value = value
        }
    }

    function syncBrightnessSliders() {
        if (ledBrightnessLoader && ledBrightnessLoader.item) {
            ledBrightnessLoader.item.value = cfgLedBrightness
        }
        if (ledBrightnessHighbeamLoader && ledBrightnessHighbeamLoader.item) {
            ledBrightnessHighbeamLoader.item.value = cfgLedBrightnessHighbeam
        }
        if (ledBrightnessIdleLoader && ledBrightnessIdleLoader.item) {
            ledBrightnessIdleLoader.item.value = cfgLedBrightnessIdle
        }
        if (ledBrightnessStatusLoader && ledBrightnessStatusLoader.item) {
            ledBrightnessStatusLoader.item.value = cfgLedBrightnessStatus
        }
    }

    function parseConfigToken(tokens, idx) {
        if (idx < tokens.length && tokens[idx] !== "") {
            return Number(tokens[idx])
        }
        return 0
    }


    Connections {
        target: mCommands

        function onCustomAppDataReceived(data) {
            var str = data.toString()

            if (!wasConnected) {
                // Read settings on initial message
                wasConnected = true
                if (!readConfig) {
                    sendCode(String.fromCharCode(floatAccessoriesMagic) + String.fromCharCode(1) + "(send-config)")
                }
            }

            if (str.startsWith("settings")) {
                try {
                    settingsRxCount++
                    var firstConfigLoad = !readConfig
                    var tokens = str.split(" ")
                    var i = 1
                    devBuildMagic = parseConfigToken(tokens, i); i++
                    ledEnabled.checked = parseConfigToken(tokens, i) > 0; i++
                    ledOn.checked = parseConfigToken(tokens, i) > 0; i++
                    ledHighbeamOn.checked = parseConfigToken(tokens, i) > 0; i++
                    ledMode.currentIndex = parseConfigToken(tokens, i); i++
                    ledModeIdle.currentIndex = parseConfigToken(tokens, i); i++
                    ledModeStatus.currentIndex = parseConfigToken(tokens, i); i++
                    ledMallGrabEnabled.checked = parseConfigToken(tokens, i) > 0; i++
                    ledBrakeLightEnabled.checked = parseConfigToken(tokens, i) > 0; i++
                    ledBrakeLightMinAmps.value = parseConfigToken(tokens, i); i++
                    idleTimeout.value = parseConfigToken(tokens, i); i++
                    idleTimeoutShutoff.value = parseConfigToken(tokens, i); i++
                    cfgLedBrightness = parseConfigToken(tokens, i); i++
                    cfgLedBrightnessHighbeam = parseConfigToken(tokens, i); i++
                    cfgLedBrightnessIdle = parseConfigToken(tokens, i); i++
                    cfgLedBrightnessStatus = parseConfigToken(tokens, i); i++
                    ledStatusPin.value = parseConfigToken(tokens, i); i++
                    ledStatusNum.value = parseConfigToken(tokens, i); i++
                    ledStatusType.currentIndex = parseConfigToken(tokens, i); i++
                    ledStatusReversed.checked = parseConfigToken(tokens, i) > 0; i++
                    ledFrontPin.value = parseConfigToken(tokens, i); i++
                    ledFrontNum.value = parseConfigToken(tokens, i); i++
                    ledFrontType.currentIndex = parseConfigToken(tokens, i); i++
                    ledFrontReversed.checked = parseConfigToken(tokens, i) > 0; i++
                    ledFrontStripType.currentIndex = parseConfigToken(tokens, i); i++
                    ledRearPin.value = parseConfigToken(tokens, i); i++
                    ledRearNum.value = parseConfigToken(tokens, i); i++
                    ledRearType.currentIndex = parseConfigToken(tokens, i); i++
                    ledRearReversed.checked = parseConfigToken(tokens, i) > 0; i++
                    ledRearStripType.currentIndex = parseConfigToken(tokens, i); i++
                    ledLoopDelay.value = parseConfigToken(tokens, i); i++
                    canLoopDelay.value = parseConfigToken(tokens, i); i++
                    ledMaxBlendCount.value = parseConfigToken(tokens, i); i++
                    setLoaderValue(ledDimOnHighbeamRatioLoader, parseConfigToken(tokens, i)); i++
                    ledStatusStripType.currentIndex = parseConfigToken(tokens, i); i++
                    ledFix.value = parseConfigToken(tokens, i); i++
                    ledFrontHighbeamPin.value = parseConfigToken(tokens, i); i++
                    ledRearHighbeamPin.value = parseConfigToken(tokens, i); i++
                    setLoaderValue(ledMaxBrightnessLoader, parseConfigToken(tokens, i)); i++
                    applyLedControlBrightnessCap()
                    cellType.currentIndex = parseConfigToken(tokens, i); i++
                    ledUpdateNotRunning.checked = parseConfigToken(tokens, i) > 0; i++
                    seriesCells.value = parseConfigToken(tokens, i); i++
                    frontTargetID.value = parseConfigToken(tokens, i); i++
                    rearTargetID.value = parseConfigToken(tokens, i); i++
                    statusTargetID.value = parseConfigToken(tokens, i); i++
                    targetSelectionDirty = false
                    nodeRole.value = parseConfigToken(tokens, i); i++
                    uclEffectiveRole = nodeRole.value
                    masterCanID.value = parseConfigToken(tokens, i); i++
                    peersCache.value = parseConfigToken(tokens, i); i++
                    if (i < tokens.length) {
                        localCanId = parseConfigToken(tokens, i)
                    }
                    syncBrightnessSliders()
                    refreshTargetCanOptions([frontTargetID.value, rearTargetID.value, statusTargetID.value])

                    readConfig = true;
                    if (firstConfigLoad) {
                        tabBar.currentIndex = (nodeRole.value === 1) ? 3 : 0
                    }
                } catch (e) {
                    settingsParseErrorCount++
                    lastSettingsParseError = e
                    console.log("settings parse failed:", e)
                }
            } else if (str.startsWith("msg")) {
                var msg = str.substring(4)
                VescIf.emitMessageDialog("UnleashedCreativity Lights", msg, false, false)
            } else if (str.startsWith("float-stats")) {
                var tokens = str.split(" ")

                // Cutdown status payload: legacy reserved fields are fixed placeholders.
                floatPackageConnected = Number(tokens[1])
                if (floatPackageConnected === 1) {
                    floatPackageLastStatusTime = 0
                }

                // Support both status payload formats:
                // New: local, role, fwdConnected, fwdAge, peerCount, peerIds..., buildMagic
                // Old: role, fwdConnected, fwdAge, peerCount, peerIds..., buildMagic
                var peerCountNew = (tokens.length > 15) ? Number(tokens[15]) : NaN
                var buildIxNew = 16 + (isNaN(peerCountNew) ? 0 : peerCountNew)
                var hasNewFormat = (!isNaN(peerCountNew)
                                    && peerCountNew >= 0
                                    && buildIxNew < tokens.length
                                    && Number(tokens[buildIxNew]) === devBuildMagic)

                var peerIds = []
                if (hasNewFormat) {
                    if (tokens.length > 11) {
                        localCanId = Number(tokens[11])
                    }
                    if (tokens.length > 12) {
                        uclEffectiveRole = Number(tokens[12])
                    }
                    if (tokens.length > 13) {
                        refloatFwdConnected = Number(tokens[13])
                    }
                    if (tokens.length > 14) {
                        refloatFwdAge = parseFloat(tokens[14])
                    }
                    for (var pn = 0; pn < peerCountNew; pn++) {
                        var peerIxNew = 16 + pn
                        if (peerIxNew < tokens.length) {
                            peerIds.push(Number(tokens[peerIxNew]))
                        }
                    }
                    if (buildIxNew < tokens.length && tokens[buildIxNew] !== "") {
                        devBuildMagic = Number(tokens[buildIxNew])
                    }
                    var tailIxNew = buildIxNew + 1
                    if (!targetSelectionDirty && tailIxNew + 2 < tokens.length) {
                        frontTargetID.value = Number(tokens[tailIxNew])
                        rearTargetID.value = Number(tokens[tailIxNew + 1])
                        statusTargetID.value = Number(tokens[tailIxNew + 2])
                    }
                } else {
                    if (tokens.length > 11) {
                        uclEffectiveRole = Number(tokens[11])
                    }
                    if (tokens.length > 12) {
                        refloatFwdConnected = Number(tokens[12])
                    }
                    if (tokens.length > 13) {
                        refloatFwdAge = parseFloat(tokens[13])
                    }
                    if (tokens.length > 14) {
                        var peerCountOld = Number(tokens[14])
                        for (var po = 0; po < peerCountOld; po++) {
                            var peerIxOld = 15 + po
                            if (peerIxOld < tokens.length) {
                                peerIds.push(Number(tokens[peerIxOld]))
                            }
                        }
                        var buildIxOld = 15 + peerCountOld
                        if (buildIxOld < tokens.length && tokens[buildIxOld] !== "") {
                            devBuildMagic = Number(tokens[buildIxOld])
                        }
                        var tailIxOld = buildIxOld + 1
                        if (!targetSelectionDirty && tailIxOld + 2 < tokens.length) {
                            frontTargetID.value = Number(tokens[tailIxOld])
                            rearTargetID.value = Number(tokens[tailIxOld + 1])
                            statusTargetID.value = Number(tokens[tailIxOld + 2])
                        }
                    }
                }
                refreshTargetCanOptions(peerIds)

                // Update status flags
                lastStatusTime = 0  // Reset the timer when status is received
                if (floatPackageConnected === 1) {
                    floatPackageLastStatusTime = 0
                } else {
                    floatPackageLastStatusTime = floatPackageLastStatusTime // Trigger binding re-evaluation
                }

                statusTimeout = false
            } else if (str.startsWith("control")) {
                var tokens = str.split(" ")
                ledOn.checked = Number(tokens[1])
                ledHighbeamOn.checked = Number(tokens[2])
                cfgLedBrightness = Number(tokens[3])
                cfgLedBrightnessHighbeam = parseFloat(Number(tokens[4]))
                cfgLedBrightnessIdle = Number(tokens[5])
                cfgLedBrightnessStatus = Number(tokens[6])
                syncBrightnessSliders()
                applyLedControlBrightnessCap()
            } else if (str.startsWith("status Settings Read")) {
                sendCode(String.fromCharCode(floatAccessoriesMagic) + String.fromCharCode(1) + "(send-control)")
                var msg = str.substring(7)
                VescIf.emitStatusMessage(msg, true)
            } else if (str.startsWith("status")) {
                var msg = str.substring(7)
                VescIf.emitStatusMessage(msg, true)
            }
        }
    }
}
