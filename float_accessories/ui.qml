import "qrc:/mobile"
import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.3
import QtQuick.Controls.Material 2.2
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
            signal interactionReleased()

            onPressedChanged: {
                if (!pressed) {
                    interactionReleased()
                }
            }
            property var formatValue: function(val) { 
                if (asPercent) {
                    let percentage = ((val - from) / (to - from)) * 100;
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

    // Shared card styling values
    QtObject {
        id: cardStyle
        property int topPadding: 42
        property int sidePadding: 12
        property int bottomPadding: 12
        property int contentSpacing: 6
        property int titleHeight: 40
        property int radius: 15
        // Spacing constants
        property int betweenCards: 20   // gap between GroupBox cards
        property int fieldSpacing: 10   // gap between label+control pairs in a card
        property int labelSpacing: 2    // gap between a label and its control
        // ScrollView padding
        property int scrollHPadding: 12  // left/right padding inside scrollviews
        property int scrollTopPadding: 16
        property int scrollBottomPadding: 16
        // ScrollView background
        property color scrollViewBg: Utility.getAppHexColor("darkBackground")
    }

    // Shared field label styling (used for labels that sit above a control)
    QtObject {
        id: fieldLabelStyle
        property color color: Qt.rgba(1, 1, 1, 0.75)
        property int pixelSize: 13
        property bool bold: false
    }

    Component {
        id: cardBg
        Rectangle {
            color: Qt.rgba(1, 1, 1, 0.06)
            radius: cardStyle.radius
        }
    }

    // Reusable card component with title and optional titleRight content
    // Usage: Loader { sourceComponent: card; onLoaded: { item.title = "Title"; item.titleRight = someComponent } }
    Component {
        id: card
        Rectangle {
            property string title: ""
            property Component titleRight: null
            default property alias content: contentColumn.children

            Layout.fillWidth: true
            radius: 15
            color: Qt.rgba(1, 1, 1, 0.06)
            implicitHeight: cardInner.implicitHeight + 24

            ColumnLayout {
                id: cardInner
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 12
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 2
                    visible: title !== ""

                    Text {
                        text: title
                        color: "white"
                        font.pixelSize: 15
                        font.bold: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    Loader {
                        id: titleRightLoader
                        sourceComponent: titleRight
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        visible: titleRight !== null
                    }
                }

                ColumnLayout {
                    id: contentColumn
                    Layout.fillWidth: true
                    spacing: 10
                }
            }
        }
    }

    // Card title for GroupBox label
    Component {
        id: cardTitleLabel
        Item {
            property string title: ""
            implicitHeight: 40
            implicitWidth: parent ? parent.width : 200

            Text {
                id: titleText
                text: parent.title
                color: "white"
                font.bold: true
                font.pixelSize: 15
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Card title with right content for GroupBox label
    Component {
        id: cardTitleWithRight
        Item {
            property string title: ""
            default property alias titleRight: titleRightRow.children
            implicitHeight: 40
            implicitWidth: parent ? parent.width : 200

            Text {
                text: parent.title
                color: "white"
                font.bold: true
                font.pixelSize: 15
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
            }
            Row {
                id: titleRightRow
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
            }
        }
    }

    Component {
        id: customSwitch
        Switch {
            id: control
            padding: 0
            indicator: Rectangle {
                implicitWidth: 48
                implicitHeight: 26
                x: control.leftPadding
                y: parent.height / 2 - height / 2
                radius: 13
                color: control.checked ? Material.accent : palette.button
                border.color: control.checked ? Material.accent : palette.button
                
                Rectangle {
                    x: control.checked ? parent.width - width - 2 : 2
                    y: 2
                    width: 22
                    height: 22
                    radius: 11
                    color: "white"
                    Behavior on x {
                        NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                    }
                }
            }
        }
    }

    // Main app
    id: container
    property string tabTitle: "Float Accessories"  
    anchors.fill: parent
    property int pubmotePairCode: -1  // Initialize with a default invalid value
    property int pubmotePairingState: 0
    property bool pairingTimeout: false
    property int remainingTime: 60  // Initialize with the full 60 seconds
    property int bmsConnected: 0
    property Commands mCommands: VescIf.commands()
    property int floatAccessoriesMagic: 102
    property bool acceptTOS: false
    property int lastStatusTime: 0
    property bool statusTimeout: true
    property bool readConfig: false
    property bool wasConnected: false
    property int floatPackageLastStatusTime: 0
    property int pubmoteLastStatusTime: 0
    property bool floatPackageConnected: false
    property bool pubmoteConnected: false
    property bool gnssFix: false
    property real gnssAge: 9999
    property real gnssHdop: 99
    property real gnssSpeed: 0
    property int pubmoteWifiChannel: 0
    property bool isPubmoteBle: false
    property bool isPubmotePaired: false
    property int bmsStatusTemp: 0
    property int bmsBatteryTypeVal: 0
    property int bmsBatteryCyclesVal: 0
    property real lcmHum: 0
    property real lcmHumTemp: 0
    property real bmsHum: 0
    property real bmsHumTemp: 0
    property int loggerRunning: 0
    property string pubmoteVersionStr: "Unknown"

    // Live remote input preview state
    property bool pubmoteInputConnected: false
    property real pubmoteInputJsy: 0
    property real pubmoteInputJsx: 0
    property bool pubmoteInputBtC: false
    property bool pubmoteInputBtZ: false
    property bool pubmoteInputRev: false

    // ---- LED strips add/remove -----------------------------------------
    // The per-role strip config cards below (status / front / rear / footpad
    // / button) are each still backed by their own ledXxxStripType / pin /
    // num controls and the positional config protocol. A role's Strip Type
    // combo doubles as its enable: index 0 = "None" hides the card (removes
    // the strip), any preset shows it. The "+ Add Strip" button at the end
    // of the list adds a not-yet-used role. The firmware chains strips that
    // share a pin automatically, so no per-strip offset is configured here.
    // This binding tracks the five currentValue props directly so it
    // re-evaluates whenever a strip is added or removed.
    property var addedRoles: {
        var a = []
        if (ledStatusStripType.currentValue > 0)  a.push("Status")
        if (ledFrontStripType.currentValue > 0)   a.push("Front")
        if (ledRearStripType.currentValue > 0)    a.push("Rear")
        if (ledFootpadStripType.currentValue > 0) a.push("Footpad")
        if (ledButtonStripType.currentValue > 0)  a.push("Button")
        return a
    }

    // Enable (on = true, set the Strip Type to its first real preset) or
    // remove (on = false, back to "None") a role. Setting currentIndex fires
    // the combo's existing onCurrentIndexChanged, which pushes live settings.
    function setRole(name, on) {
        var idx = on ? 1 : 0
        switch (name) {
        case "Status":  ledStatusStripType.currentIndex = idx;  break
        case "Front":   ledFrontStripType.currentIndex = idx;   break
        case "Rear":    ledRearStripType.currentIndex = idx;    break
        case "Footpad": ledFootpadStripType.currentIndex = idx; break
        case "Button":  ledButtonStripType.currentIndex = idx;  break
        }
    }

    Component.onCompleted: {
        if (VescIf.getLastFwRxParams().hwTypeStr() !== "Custom Module") {
            VescIf.emitMessageDialog("Float Accessories", "Warning: It doesn't look like this is installed on a VESC Express.", false, false)
        }

        sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(send-config)")
    }

    Timer {
        id: statusCheckTimer
        interval: 1000 // Check status every second
        running: true
        repeat: true
        onTriggered: {
            sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(status)")
            lastStatusTime++
            floatPackageLastStatusTime++
            pubmoteLastStatusTime++

            if (lastStatusTime > 2) { // 2 second timeout
                statusTimeout = true
            }
            if (lastStatusTime > 60) {
                wasConnected = false
            }
        }
    }

    // Polls the remote's input state while the preview section is visible and toggled on
    Timer {
        id: inputPreviewTimer
        interval: 100 // 10 Hz
        repeat: true
        running: inputPreviewSection.visible && inputPreviewEnabled.checked
        onTriggered: {
            sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(input-state)")
        }
    }

    // Timer for 60-second timeout
    Timer {
        id: pairingTimeoutTimer
        interval: 1000  // 1 second
        running: false
        repeat: true

        onTriggered: {
            remainingTime--;  // Decrease the remaining time by 1 second

            if (remainingTime <= 0) {
                pairingTimeout = true;
                sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(pair-pubmote -2)");  // Automatically reject if time runs out
                sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(send-config)");
                pubmotePairPopup.close();
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

    // Pubmote pairing confirmation, styled like the espled_strip Add dialog:
    // a modal Dialog with a title header and framework background rather than
    // a hand-rolled black Popup.
    Dialog {
        id: pubmotePairPopup
        modal: true
        focus: true
        anchors.centerIn: parent
        width: Math.min(container.width - 20, 340)

        // Match the rounding of the standard cards elsewhere in the UI.
        background: Rectangle {
            color: Utility.getAppHexColor("darkBackground")
            radius: cardStyle.radius
            border.color: Qt.rgba(1, 1, 1, 0.1)
            border.width: 1
        }

        onVisibleChanged: {
            if (visible) {
                pubmotePairingState = 1;
                // Generate code only when the popup is shown
                pubmotePairCode = Math.floor(1000 + Math.random() * 9000);  // Generates a number between 1000 and 9999
                pairingTimeout = false;  // Reset timeout flag
                remainingTime = 60;  // Reset the timer to 60 seconds
                pairingTimeoutTimer.start();  // Start the 1-second timer to count down

                // Send the pairing request with the generated code
                sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(pair-pubmote " + pubmotePairCode + ")");
            } else {
                pairingTimeoutTimer.stop();  // Stop timer if the popup is closed
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            Text {
                text: "Pairing Code: " + pubmotePairCode
                color: Utility.getAppHexColor("lightText")
                font.pointSize: 20
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: "Time remaining: " + remainingTime + " s"
                color: Utility.getAppHexColor("lightText")
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: pubmotePairingState === 1 ? "Searching for remote..." :
                      pubmotePairingState === 2 ? "Remote found! Confirm code and Accept." :
                      "Pairing..."
                color: Material.accent
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 10

                Button {
                    text: "Reject"
                    Layout.fillWidth: true
                    onClicked: {
                        sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(pair-pubmote -2)");  // Reject pairing manually
                        sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(send-config)");
                        pubmotePairPopup.close();
                    }
                }

                Button {
                    text: "Accept"
                    Layout.fillWidth: true
                    highlighted: true
                    enabled: !pairingTimeout
                    onClicked: {
                        if (!pairingTimeout) {
                            sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(pair-pubmote -1)");  // Accept pairing
                            sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(send-config)");
                            pubmotePairPopup.close();
                        }
                    }
                }
            }
        }
    }

    Popup {
        id: keySettingPopup
        modal: true
        focus: true
        visible: false
        width: parent.width * 0.8
        height: parent.height * 0.3
        anchors.centerIn: parent

        background: Rectangle {
            color: "black"
            radius: 10
        }

        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 10

            Text {
                text: "Set Keys"
                color: "white"
                font.pointSize: 16
                Layout.alignment: Qt.AlignHCenter
            }

            TextField {
                id: keyInput
                placeholderText: "Enter Key (16 hex bytes, e.g., FFAABBCC...)"
                Layout.fillWidth: true
            }

            TextField {
                id: counterInput
                placeholderText: "Enter Counter (16 hex bytes, e.g., FFAABBCC...)"
                Layout.fillWidth: true
            }

            Button {
                id: submitButton
                text: "Submit"
                Layout.alignment: Qt.AlignHCenter
                onClicked: {
                    var keyHex = keyInput.text.replace(/[^0-9A-Fa-f]/g, '');
                    var counterHex = counterInput.text.replace(/[^0-9A-Fa-f]/g, '');

                    if (keyHex.length === 32 && counterHex.length === 32) {
                        console.log("Key: " + keyHex);
                        console.log("Counter: " + counterHex);

                        var keyList = hexStringToLispList(keyHex);
                        var counterList = hexStringToLispList(counterHex);

                        var sendKeysString = "(send-keys " + keyList + " " + counterList + ")";
                        console.log("Sending: " + sendKeysString);
                        sendCode(String.fromCharCode(102) + String.fromCharCode(1) + sendKeysString);

                        keySettingPopup.close();
                    } else {
                        console.error("Invalid input: Both key and counter must result in 4 uint32 values each")
                    }
                }
            }
        }
    }

    // BMS terms of service, styled like the pubmote pairing dialog.
    Dialog {
        id: termsPopup
        modal: true
        focus: true
        anchors.centerIn: parent
        width: Math.min(container.width - 20, 400)
        height: Math.min(container.height - 40, 560)

        // Match the rounding of the standard cards elsewhere in the UI.
        background: Rectangle {
            color: Utility.getAppHexColor("darkBackground")
            radius: cardStyle.radius
            border.color: Qt.rgba(1, 1, 1, 0.1)
            border.width: 1
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            Text {
                text: "Terms of Service"
                color: "white"
                font.bold: true
                font.pixelSize: 15
                Layout.alignment: Qt.AlignHCenter
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                background: Rectangle { color: cardStyle.scrollViewBg; radius: 8 }

                TextArea {
                    id: termsText
                    textFormat: Text.RichText
                    text: "<p>WARNING NOTICE:</p>" +
                        "<p>This code is released as part of legitimate security research and is intended to enable interoperability between a specific Battery Management System (BMS) and aftermarket Electronic Speed Controllers (ESCs) for a widely used motorized land vehicle. This vehicle is often utilized as a mobility aid for individuals with disabilities, such as those with Hidradenitis Suppurativa, which prevents the use of traditional mobility devices.</p>" +
                        "<p>The publication of this code is an exercise of the right to free speech and expression, protected under the First Amendment of the U.S. Constitution. Furthermore, this code is released in accordance with both the security research exception under DMCA Section 1201(g) and the exemption for motorized land vehicles, which allows the circumvention of technological protection measures (TPMs) for the purposes of repair, modification, and interoperability under the Librarian of Congress's 2015 ruling and subsequent triennial exemptions. This exemption applies specifically to vehicle software, including Battery Management Systems, and permits this work for diagnostic and modification purposes.</p>" +
                        "<p>This system lacks manufacturer-provided documentation or tools for repair. Currently, consumers are forced to replace the entire battery, enclosure, and BMS at significant cost, rather than repairing individual components. We are providing the necessary documentation and tools to facilitate the repair of these systems, enabling consumers to extend the life of their devices.</p>" +
                        "<p>This publication is further supported by the California Right to Repair Act (SB 244), which took full effect on July 1, 2024. Under this law, consumers and independent repair providers are entitled to access the tools, parts, and documentation necessary to perform repairs on electronics and appliances sold or used in California, reinforcing the legality and public interest of this code publication. Although some exceptions apply, this law affirms the right to repair motorized vehicles, aligning with the purpose of this research and promoting repairability and consumer choice.</p>" +
                        "<p>Additionally, this publication is protected under Washington's Revised Code of Washington (RCW) § 4.24.525 and California Code of Civil Procedure § 425.16, which are anti-SLAPP laws designed to prevent lawsuits aimed at intimidating or silencing lawful speech on matters of public interest. Any attempt to interfere with or litigate against the publication of this code may result in the dismissal of such legal actions, with the imposition of attorney's fees and statutory damages.</p>" +
                        "<p>Furthermore, the motor land vehicle this BMS resides in had its advertised speed reduced during a software update for the haptic buzz feature. This change constitutes a violation of Article 6(1)(a) of the EU Directive 2005/29/EC on Unfair Commercial Practices, which prohibits misleading actions that affect the consumer's decision to purchase or retain a product. Reducing the performance of previously purchased products, is deemed unfair under EU law, particularly as consumers were not informed or compensated for this loss of functionality.</p>" +
                        "<p>Moreover, the haptic feedback feature remains insufficiently implemented. On uneven terrains such as trails, the vibration cannot be felt effectively, and the audio feedback is may sometimes be too quiet to be useful, especially for individuals with disabilities like hearing impairments. This code addresses these deficiencies by allowing use with ESCs that allow real-time interoperability with third-party phone applications that provide customizable alerts through speakers, or headphones, improving accessibility, safety, and overall user experience."
                    color: Utility.getAppHexColor("lightText")
                    wrapMode: Text.Wrap
                    readOnly: true
                    background: null
                    onLinkActivated: function(url) {
                        Qt.openUrlExternally(url)
                    }
                }
            }

            CheckBox {
                id: acceptCheckBox
                text: "I have read and accept the Terms of Service."
                checked: false
                onCheckedChanged: {
                    acceptButton.enabled = checked
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Button {
                    text: "Cancel"
                    Layout.fillWidth: true
                    onClicked: {
                        termsPopup.close()
                        bmsEnabled.checked = false
                        VescIf.emitMessageDialog("Float Accessories", "You must accept the Terms of Service to continue with BMS features.", false, false)
                    }
                }

                Button {
                    id: acceptButton
                    text: "Accept"
                    Layout.fillWidth: true
                    highlighted: true
                    enabled: acceptCheckBox.checked
                    onClicked: {
                        acceptTOS = true
                        termsPopup.close()
                        sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(accept-tos)")
                    }
                }
            }
        }
    }

    // About dialog, opened from the (i) button in the title bar (was a tab).
    Dialog {
        id: aboutDialog
        modal: true
        focus: true
        anchors.centerIn: parent
        width: Math.min(container.width - 20, 400)
        height: Math.min(container.height - 40, 520)
        background: Rectangle {
            color: Utility.getAppHexColor("darkBackground")
            radius: cardStyle.radius
            border.color: Qt.rgba(1, 1, 1, 0.1)
            border.width: 1
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            TextArea {
                textFormat: Text.RichText
                text: "<p><b>FLOAT ACCESSORIES PACKAGE</b></p>" +
                    "<p>A VESC Express package for controlling LEDs, BMS and Pubmote.</p>" +

                    "<p><b>Support Future Work</b></p>" +
                    "<p>Buy me a Coffee: <a href='https://venmo.com/sylerclayton'>https://venmo.com/sylerclayton</a></p>" +
                    "<p>Support me on Patreon: <a href='https://patreon.com/SylerTheCreator'>https://patreon.com/SylerTheCreator</a></p>" +

                    "<p><b>CREDITS</b></p>" +
                    "<p>Special Thanks: Benjamin Vedder, surfdado, Mitch (NuRxG), Siwoz, lolwheel (OWIE), ThankTheMaker (rESCue), 4_fools (avaspark), auden_builds (pubmote)</p>" +
                    "<p>gr33tz: outlandnish, exphat, datboig42069</p>" +
                    "<p>Beta Testers: Pickles</p>" +

                    "<p>My Blog: <a href='https://sylerclayton.com'>https://sylerclayton.com</a></p>" +

                    "<p><b>BUILD INFO</b></p>" +
                    "<p>Version 4.0.0</p>" +
                    "<p>Source code can be found here: <a href='https://github.com/relys/vesc_pkg'>https://github.com/relys/vesc_pkg</a></p>"
                wrapMode: Text.WordWrap
                readOnly: true
                color: Utility.getAppHexColor("lightText")
                background: null
                onLinkActivated: function(url) {
                    Qt.openUrlExternally(url)
                }
            }
            }

            Button {
                text: "Close"
                Layout.fillWidth: true
                highlighted: true
                onClicked: aboutDialog.close()
            }
        }
    }

    ColumnLayout {
        id: mainLayout
        anchors.fill: parent
        spacing: 10
        property string primaryTabLabel: ledEnabled.checked || bmsEnabled.checked || logEnabled.checked ? qsTr("Control") : qsTr("Status")
        property int enabledFeatureCount: ledEnabled.checked + pubmoteEnabled.checked + bmsEnabled.checked + logEnabled.checked + gnssEnabled.checked + mqttEnabled.checked

        onEnabledFeatureCountChanged: {
            if (enabledFeatureCount === 0 && tabBar.currentIndex === 1) {
                tabBar.currentIndex = 0
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.topMargin: 10
            implicitHeight: appTitleText.implicitHeight

            Text {
                id: appTitleText
                anchors.centerIn: parent
                color: Utility.getAppHexColor("lightText")
                font.pointSize: 20
                font.bold: true
                text: "Float Accessories"
            }

            // Opens the About dialog (replaces the old About tab).
            RoundButton {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 30
                implicitHeight: 30
                padding: 0
                text: "i"
                font.pointSize: 13
                font.bold: true
                onClicked: aboutDialog.open()
            }
        }

        // Config menu for selecting which config to show
        Menu {
            id: configMenu

            MenuItem {
                text: qsTr("Lights")
                visible: ledEnabled.checked
                height: visible ? implicitHeight : 0
                onTriggered: {
                    tabBar2.currentIndex = 0
                    tabBar.currentIndex = 1
                }
            }
            MenuItem {
                text: qsTr("Pubmote")
                visible: pubmoteEnabled.checked
                height: visible ? implicitHeight : 0
                onTriggered: {
                    tabBar2.currentIndex = 1
                    tabBar.currentIndex = 1
                }
            }
            MenuItem {
                text: qsTr("BMS")
                visible: bmsEnabled.checked
                height: visible ? implicitHeight : 0
                onTriggered: {
                    tabBar2.currentIndex = 2
                    tabBar.currentIndex = 1
                }
            }
            MenuItem {
                text: qsTr("Logging")
                visible: logEnabled.checked
                height: visible ? implicitHeight : 0
                onTriggered: {
                    tabBar2.currentIndex = 3
                    tabBar.currentIndex = 1
                }
            }
            MenuItem {
                text: qsTr("GNSS")
                visible: gnssEnabled.checked
                height: visible ? implicitHeight : 0
                onTriggered: {
                    tabBar2.currentIndex = 4
                    tabBar.currentIndex = 1
                }
            }
            MenuItem {
                text: qsTr("MQTT")
                visible: mqttEnabled.checked
                height: visible ? implicitHeight : 0
                onTriggered: {
                    tabBar2.currentIndex = 5
                    tabBar.currentIndex = 1
                }
            }
        }

        TabBar {
            id: tabBar
            Layout.fillWidth: true

            TabButton {
                id: primaryTabButton
                text: mainLayout.primaryTabLabel
                font.capitalization: Font.MixedCase
                Layout.fillWidth: true
                contentItem: Text {
                    text: primaryTabButton.text
                    font: primaryTabButton.font
                    color: primaryTabButton.checked ? "white" : Qt.rgba(1, 1, 1, 0.54)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            TabButton {
                id: configTabButton
                text: qsTr("Config")
                font.capitalization: Font.MixedCase
                enabled: mainLayout.enabledFeatureCount > 0
                visible: mainLayout.enabledFeatureCount > 0
                Layout.fillWidth: true
                Layout.maximumWidth: mainLayout.enabledFeatureCount > 0 ? Number.POSITIVE_INFINITY : 0
                width: mainLayout.enabledFeatureCount > 0 ? undefined : 0

                contentItem: Item {
                    implicitWidth: labelText.implicitWidth + (chevronCanvas.visible ? chevronCanvas.width + 4 : 0)
                    implicitHeight: labelText.implicitHeight

                    property color textColor: configTabButton.checked ? "white" : Qt.rgba(1, 1, 1, 0.54)

                    Text {
                        id: labelText
                        text: qsTr("Config")
                        font: configTabButton.font
                        color: parent.textColor
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: chevronCanvas.visible ? -(chevronCanvas.width + 4) / 2 : 0
                    }

                    Canvas {
                        id: chevronCanvas
                        width: 14
                        height: 14
                        visible: mainLayout.enabledFeatureCount > 1
                        anchors.left: labelText.right
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter

                        property color strokeColor: parent.textColor
                        onStrokeColorChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = strokeColor
                            ctx.lineWidth = 1.5
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"
                            var s = 14 / 24
                            ctx.beginPath()
                            ctx.moveTo(6 * s, 9 * s)
                            ctx.lineTo(12 * s, 15 * s)
                            ctx.lineTo(18 * s, 9 * s)
                            ctx.stroke()
                        }
                    }
                }

                onClicked: {
                    if (mainLayout.enabledFeatureCount > 1) {
                        configMenu.popup(configTabButton, 0, configTabButton.height)
                    } else {
                        if (ledEnabled.checked) tabBar2.currentIndex = 0
                        else if (pubmoteEnabled.checked) tabBar2.currentIndex = 1
                        else if (bmsEnabled.checked) tabBar2.currentIndex = 2
                        else if (logEnabled.checked) tabBar2.currentIndex = 3
                        else if (gnssEnabled.checked) tabBar2.currentIndex = 4
                        else if (mqttEnabled.checked) tabBar2.currentIndex = 5
                    }
                }
            }

            TabButton {
                id: settingsTabButton
                text: qsTr("Settings")
                font.capitalization: Font.MixedCase
                Layout.fillWidth: true
                contentItem: Text {
                    text: settingsTabButton.text
                    font: settingsTabButton.font
                    color: settingsTabButton.checked ? "white" : Qt.rgba(1, 1, 1, 0.54)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

        }

        TabBar {
            id: tabBar2
            Layout.fillWidth: true
            visible: false  // Hidden - using menu instead

            // Update enabled indices when checkboxes change
            Component.onCompleted: updateEnabledIndices()

            Connections {
                target: ledEnabled
                function onCheckedChanged() { updateEnabledIndices() }
            }

            Connections {
                target: pubmoteEnabled
                function onCheckedChanged() { updateEnabledIndices() }
            }

            Connections {
                target: bmsEnabled
                function onCheckedChanged() { updateEnabledIndices() }
            }

            Connections {
                target: logEnabled
                function onCheckedChanged() { updateEnabledIndices() }
            }

            Connections {
                target: gnssEnabled
                function onCheckedChanged() { updateEnabledIndices() }
            }

            Connections {
                target: mqttEnabled
                function onCheckedChanged() { updateEnabledIndices() }
            }

            TabButton {
                text: qsTr("Lights")
                enabled: ledEnabled.checked
                visible: ledEnabled.checked
                width: ledEnabled.checked ? implicitWidth : 0
            }

            TabButton {
                text: qsTr("Pubmote")
                enabled: pubmoteEnabled.checked
                visible: pubmoteEnabled.checked
                width: pubmoteEnabled.checked ? implicitWidth : 0
            }

            TabButton {
                text: qsTr("BMS")
                enabled: bmsEnabled.checked
                visible: bmsEnabled.checked
                width: bmsEnabled.checked ? implicitWidth : 0
            }
            TabButton {
                text: qsTr("Logging")
                enabled: logEnabled.checked
                visible: logEnabled.checked
                width: logEnabled.checked ? implicitWidth : 0
            }
            TabButton {
                text: qsTr("GNSS")
                enabled: gnssEnabled.checked
                visible: gnssEnabled.checked
                width: gnssEnabled.checked ? implicitWidth : 0
            }
            TabButton {
                text: qsTr("MQTT")
                enabled: mqttEnabled.checked
                visible: mqttEnabled.checked
                width: mqttEnabled.checked ? implicitWidth : 0
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
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                background: Rectangle { color: cardStyle.scrollViewBg }

                Item {
                    width: stackLayout.width
                    implicitHeight: scrollContent1.implicitHeight + cardStyle.scrollTopPadding + cardStyle.scrollBottomPadding

                    ColumnLayout {
                        id: scrollContent1
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: cardStyle.scrollTopPadding
                        anchors.leftMargin: cardStyle.scrollHPadding
                        anchors.rightMargin: cardStyle.scrollHPadding
                        spacing: 20

                    Timer {
                        id: throttleTimer
                        interval: 50  // 50ms throttle timer
                        repeat: false
                        property bool controlPending: false
                        onTriggered: {
                            if (controlPending) {
                                applyControlChanges()
                                controlPending = false
                            }
                        }
                    }

                    GroupBox {
                        title: "Light Control"
                        Layout.fillWidth: true
                        visible: ledEnabled.checked
                        background: Loader { sourceComponent: cardBg }
                        label: Item {
                            implicitHeight: 40
                            width: parent ? parent.width : 200

                            Text {
                                text: "Light Control"
                                color: "white"
                                font.bold: true
                                font.pixelSize: 15
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Loader {
                                id: ledOn
                                sourceComponent: customSwitch
                                anchors.right: parent.right
                                anchors.rightMargin: cardStyle.sidePadding
                                anchors.verticalCenter: parent.verticalCenter
                                property bool checked: item ? item.checked : false

                                onLoaded: {
                                    item.checked = true
                                    item.checkedChanged.connect(function() {
                                        ledOn.checked = item.checked
                                        handleDebouncedChange()
                                    })
                                }

                                onCheckedChanged: {
                                    if (item) item.checked = checked
                                }
                            }
                        }
                        topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 6

                            ColumnLayout {
                                id: ledHighBeamLayout
                                visible: (
                                    ledOn.checked
                                    && (
                                        frontHbMode === 2
                                        || (frontHbMode === 1 && ledFrontHighbeamPin.value >= 0)
                                        || rearHbMode === 2
                                        || (rearHbMode === 1 && ledRearHighbeamPin.value >= 0)
                                    )
                                )
                                spacing: 10

                                CheckBox {
                                    id: ledHighbeamOn
                                    text: "LED Highbeam On"
                                    checked: true
                                    onCheckedChanged: {
                                        handleDebouncedChange()
                                    }
                                }
                            }

                            ColumnLayout {
                                id: ledOnLayout
                                visible: true
                                spacing: 10

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Brightness"
                                        opacity: ledOn.checked ? 1.0 : 0.4
                                    }
                                    Loader {
                                        id: ledBrightnessLoader
                                        enabled: ledOn.checked
                                        opacity: ledOn.checked ? 1.0 : 0.4
                                        sourceComponent: customValueSlider
                                        onLoaded: {
                                            item.from = 0.0
                                            item.to = 1.0
                                            item.value = 0.6
                                            item.asPercent = true
                                            item.valueChanged.connect(function() {
                                                    handleDebouncedChange()
                                            })
                                            item.interactionReleased.connect(function() {
                                                    flushControlChanges()
                                            })
                                        }
                                    }
                                }

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Idle Brightness"
                                        opacity: ledOn.checked ? 1.0 : 0.4
                                    }
                                    Loader {
                                        id: ledBrightnessIdleLoader
                                        enabled: ledOn.checked
                                        opacity: ledOn.checked ? 1.0 : 0.4
                                        sourceComponent: customValueSlider
                                        onLoaded: {
                                            item.from = 0.0
                                            item.to = 1.0
                                            item.value = 0.3
                                            item.asPercent = true
                                            item.valueChanged.connect(function() {
                                                    handleDebouncedChange()
                                            })
                                            item.interactionReleased.connect(function() {
                                                    flushControlChanges()
                                            })
                                        }
                                    }
                                }

                                ColumnLayout {
                                    id: ledStatusBrightnessLayout
                                    visible: ledStatusStripType.currentValue > 0 || ledMallGrabEnabled.checked
                                    spacing: cardStyle.labelSpacing

                                    Text {
                                        opacity: ledOn.checked ? 1.0 : 0.4
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: ledMallGrabEnabled.checked && ledStatusStripType.currentValue > 0 ? "Status/Mall Grab Brightness" : ledMallGrabEnabled.checked ? "Mall Grab Brightness" : "Status Brightness"
                                    }

                                    Loader {
                                        id: ledBrightnessStatusLoader
                                        enabled: ledOn.checked
                                        opacity: ledOn.checked ? 1.0 : 0.4
                                        sourceComponent: customValueSlider
                                        onLoaded: {
                                            item.from = 0.0
                                            item.to = 1.0
                                            item.value = 0.6
                                            item.asPercent = true
                                            item.valueChanged.connect(function() {
                                                    handleDebouncedChange()
                                            })
                                            item.interactionReleased.connect(function() {
                                                    flushControlChanges()
                                            })
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                id: ledHighBeamBrightnessLayout
                                visible: (
                                    ledOn.checked
                                    && ledHighbeamOn.checked
                                    && (frontHbMode > 0 || rearHbMode > 0)
                                )
                                spacing: 2

                                Text {
                                    color: fieldLabelStyle.color
                                    font.pixelSize: fieldLabelStyle.pixelSize
                                    font.bold: fieldLabelStyle.bold
                                    text: "Highbeam Brightness"
                                }

                                Loader {
                                    id: ledBrightnessHighbeamLoader
                                    Layout.topMargin: -9
                                    sourceComponent: customValueSlider
                                    onLoaded: {
                                        item.from = 0.0
                                        item.to = 1.0
                                        item.value = 0.5
                                        item.asPercent = true
                                        item.valueChanged.connect(function() {
                                                handleDebouncedChange()
                                        })
                                        item.interactionReleased.connect(function() {
                                                flushControlChanges()
                                        })
                                    }
                                }
                            }
                        }
                    }

                    GroupBox {
                        title: "Logging Control"
                        Layout.fillWidth: true
                        visible: logEnabled.checked
                        background: Loader { sourceComponent: cardBg }
                        label: Loader { sourceComponent: cardTitleLabel; onLoaded: item.title = "Logging Control" }
                        topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 6

                            Text {
                                id: loggerStatus
                                Layout.fillWidth: true
                                color: statusTimeout ? "grey" : (loggerRunning ? "green" : Utility.getAppHexColor("lightText"))
                                text: statusTimeout ? "Logger Status: Unknown" : "Logger Status: " + (loggerRunning ? "Running" : "Not Running")
                            }

                            Button {
                                id: logStartButton
                                Layout.fillWidth: true
                                Layout.preferredWidth: 500
                                visible: !statusTimeout && !loggerRunning
                                text: "Start Logging"

                                onClicked: {
                                    sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(start-log (get-config 'log-append-gnss) (get-config 'log-rate))");
                                }
                            }
                            Button {
                                id: logStopButton
                                Layout.fillWidth: true
                                Layout.preferredWidth: 500
                                visible: !statusTimeout && loggerRunning
                                text: "Stop Logging"

                                onClicked: {
                                    sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(stop-log)");
                                }
                            }
                        }
                    }

                    GroupBox {
                        title: "BMS Control"
                        Layout.fillWidth: true
                        visible: bmsEnabled.checked && bmsType.currentIndex > 1
                        background: Loader { sourceComponent: cardBg }
                        label: Loader { sourceComponent: cardTitleLabel; onLoaded: item.title = "BMS Control" }
                        topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 6

                            Switch {
                                id: bmsChargeState
                                text: "Charge BMS 90%"
                                checked: true
                                enabled: bmsConnected === 1
                                onCheckedChanged: {
                                    handleDebouncedChange()
                                }
                            }
                        }
                    }

                    GroupBox {
                        title: "Status"
                        Layout.fillWidth: true
                        background: Loader { sourceComponent: cardBg }
                        label: Loader { sourceComponent: cardTitleLabel; onLoaded: item.title = "Status" }
                        topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 6

                            // Status Texts Column
                            Text {
                                id: lastStatusText
                                Layout.fillWidth: true
                                color: !statusTimeout ? "green" : (lastStatusTime <= 60 ? "yellow" : "red")
                                text: !statusTimeout ? "Status: Connected" : (lastStatusTime <= 60 ? "Status: Connecting (" + lastStatusTime + "s)" : "Status: Disconnected (" + lastStatusTime + "s)")
                            }

                            Text {
                                id: floatPackageStatus
                                Layout.fillWidth: true
                                property int effectiveTime: Math.max(floatPackageLastStatusTime, lastStatusTime)
                                color: (floatPackageConnected && !statusTimeout) ? "green" : (effectiveTime <= 60 ? "yellow" : "red")
                                text: (floatPackageConnected && !statusTimeout) ? "Float Package: Connected" : (effectiveTime <= 60 ? "Float Package: Connecting (" + effectiveTime + "s)" : "Float Package: Disconnected (" + effectiveTime + "s)")
                            }

                            Text {
                                id: pubmoteStatus
                                Layout.fillWidth: true
                                visible: pubmoteEnabled.checked
                                property int effectiveTime: Math.max(pubmoteLastStatusTime, lastStatusTime)
                                color: !isPubmotePaired ? Utility.getAppHexColor("lightText") : ((pubmoteConnected && !statusTimeout) ? "green" : (effectiveTime <= 60 ? "yellow" : "red"))
                                text: !isPubmotePaired ? "Pubmote: Not Paired" : ("Pubmote : " + ((pubmoteConnected && !statusTimeout) ? (isPubmoteBle ? "Connected (BLE)" : "Connected (WiFi Channel " + (pubmoteWifiChannel ? pubmoteWifiChannel : "?") + ")") : (effectiveTime <= 60 ? "Connecting (" + effectiveTime + "s)" : "Disconnected (" + effectiveTime + "s)")))
                            }

                            Text {
                                id: gnssStatus
                                Layout.fillWidth: true
                                visible: gnssEnabled.checked
                                color: statusTimeout ? "grey" : (gnssFix ? "green" : (gnssAge <= 10 ? "yellow" : "red"))
                                text: statusTimeout ? "GNSS: Unknown"
                                    : (gnssFix ? "GNSS: Fix (HDOP " + gnssHdop.toFixed(1) + ", " + (gnssSpeed * 3.6).toFixed(1) + " km/h)"
                                    : (gnssAge <= 10 ? "GNSS: Searching (no fix)" : "GNSS: No Signal"))
                            }

                            Text {
                                id: bmsStatus
                                Layout.fillWidth: true
                                color: (!statusTimeout && bmsConnected) ? "green" : "red"
                                text: statusTimeout ? "BMS: Unknown" : "BMS: " + (bmsConnected ? "Connected" : "Not Connected")
                                visible: bmsEnabled.checked
                            }
                            Text {
                                id: bmsHumStatus
                                Layout.fillWidth: true
                                color: (!statusTimeout && bmsHum > 0) ? (bmsHum < 65 ? "green" : bmsHum < 80 ? "orange" : "red") : "grey"
                                text: "BMS Humidity: " + ((!statusTimeout && bmsHum > 0) ? bmsHum + "%" : "Unknown")
                                visible: bmsEnabled.checked && humidityEnabled.checked
                            }
                            Text {
                                id: bmsHumTempStatus
                                Layout.fillWidth: true
                                color: (!statusTimeout && bmsHum > 0) ? "green" : "grey"
                                text: "BMS Temp: " + ((!statusTimeout && bmsHum > 0) ? Math.floor((bmsHumTemp * 1.8 + 32) * 100)/100 +"F " + bmsHumTemp + "C" : "Unknown")
                                visible: bmsEnabled.checked
                            }
                            Text {
                                id: humidityStatus
                                Layout.fillWidth: true
                                color: (!statusTimeout && lcmHum > 0) ? (lcmHum < 65 ? "green" : lcmHum < 80 ? "orange" : "red") : "grey"
                                text: "LCM Humidity: " + ((!statusTimeout && lcmHum > 0) ? lcmHum + "%" : "Unknown")
                                visible: humidityEnabled.checked
                            }
                            Text {
                                id: humidityTempStatus
                                Layout.fillWidth: true
                                color: (!statusTimeout && lcmHum > 0) ? "green" : "grey"
                                text: "LCM Temp: " + ((!statusTimeout && lcmHum > 0) ? Math.floor((lcmHumTemp * 1.8 + 32) * 100)/100 +"F " + lcmHumTemp + "C" : "Unknown")
                                visible: humidityEnabled.checked
                            }
                        }
                    }

                    GroupBox {
                        title: "BMS Info"
                        Layout.fillWidth: true
                        visible: bmsEnabled.checked && bmsConnected === 1
                        background: Loader { sourceComponent: cardBg }
                        label: Loader { sourceComponent: cardTitleLabel; onLoaded: item.title = "BMS Info" }
                        topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 6

                            Text {
                                id: bmsError
                                Layout.fillWidth: true
                                color: Utility.getAppHexColor("lightText")
                                text: statusTimeout ? "BMS Error: Unknown" : "BMS Error: " + bmsStatusTemp + "\nCharging: " + ((bmsStatusTemp & 0x20)>0) + "\nEmpty: " + ((bmsStatusTemp & 0x04)>0) + "\nTemp: " + ((bmsStatusTemp & 0x03)>0) + "\nOvercharge: " + ((bmsStatusTemp & 0x08)>0) + "\nSoC Calibration: " + ((bmsStatusTemp & 0x40)>0)
                            }
                            Text {
                                id: bmsBatteryType
                                Layout.fillWidth: true
                                color: Utility.getAppHexColor("lightText")
                                text: statusTimeout ? "Battery Type: Unknown" : "Battery Type: " + bmsBatteryTypeVal
                            }
                            Text {
                                id: bmsBatteryCycles
                                Layout.fillWidth: true
                                color: Utility.getAppHexColor("lightText")
                                text: statusTimeout ? "Battery Cycles: Unknown" : "Battery Cycles: " + bmsBatteryCyclesVal
                            }
                        }
                    }
                    }
                }
            }

            // LED Configuration Tab
            ScrollView {
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                background: Rectangle { color: cardStyle.scrollViewBg }

                Item {
                    width: stackLayout.width
                    implicitHeight: scrollContent2.implicitHeight + cardStyle.scrollTopPadding + cardStyle.scrollBottomPadding

                    ColumnLayout {
                        id: scrollContent2
                        x: cardStyle.scrollHPadding
                        y: cardStyle.scrollTopPadding
                        width: stackLayout.width - 2 * cardStyle.scrollHPadding
                        spacing: 20

                        ColumnLayout {
                            id: ledEnabledLayout
                            Layout.fillWidth: true
                            visible: ledEnabled.checked && tabBar2.currentIndex === 0
                            spacing: 20

                        GroupBox {
                            title: "LED General Config"
                            Layout.fillWidth: true
                            background: Loader { sourceComponent: cardBg }
                            label: Loader { sourceComponent: cardTitleLabel; onLoaded: item.title = "LED General Config" }
                            topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 10

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
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
                                }

                                // Max Blend Count and LED Fix were rgbled-era
                                // workarounds; the espled render thread makes
                                // them unnecessary. Their wire-protocol slots
                                // are kept as constants.

                                CheckBox {
                                    id: ledUpdateNotRunning
                                    text: "Don't update LEDs while running"
                                    checked: false
                                }

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
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
                                        }
                                    }
                                }

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
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
                                }

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Mode"
                                    }
                                    ComboBox {
                                        id: ledMode
                                        Layout.fillWidth: true
                                        model: [
                                            {text: "White/Red", value: 0},
                                            {text: "Battery Meter", value: 1},
                                            {text: "Cyan/Magenta", value: 2},
                                            {text: "Blue/Green", value: 3},
                                            {text: "Yellow/Green", value: 4},
                                            {text: "Rainbow Chase", value: 5},
                                            {text: "Strobe", value: 6},
                                            {text: "Rave", value: 7},
                                            {text: "Mullet", value: 8},
                                            {text: "Knight Rider", value: 9},
                                            {text: "Felony", value: 10},
                                            {text: "Trans Pride", value: 11}
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
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
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
                                }

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Startup Mode"
                                    }
                                    ComboBox {
                                        id: ledModeStartup
                                        Layout.fillWidth: true
                                        model: ledMode.model
                                        textRole: "text"
                                        valueRole: "value"
                                        onCurrentIndexChanged: {
                                            value = model[currentIndex].value
                                        }
                                        property int value: 5
                                    }
                                }

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
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
                                }

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Button Mode"
                                    }
                                    ComboBox {
                                        id: ledModeButton
                                        Layout.fillWidth: true
                                        model: [
                                            {text: "Rainbow Chase", value: 0},
                                            {text: "Battery Meter", value: 1},
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
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Footpad Mode"
                                    }
                                    ComboBox {
                                        id: ledModeFootpad
                                        Layout.fillWidth: true
                                        model: [
                                            {text: "Rainbow Chase", value: 0}
                                        ]
                                        textRole: "text"
                                        valueRole: "value"
                                        onCurrentIndexChanged: {
                                            value = model[currentIndex].value
                                        }
                                        property int value: 0
                                    }
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
                                }

                                ColumnLayout {
                                    id: ledBrakeLightLayout
                                    visible: ledBrakeLightEnabled.checked
                                    spacing: cardStyle.labelSpacing

                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
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

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Idle Timeout (sec)"
                                    }
                                    SpinBox {
                                        id: idleTimeout
                                        from: 1
                                        to: 100
                                        value: 1
                                        editable: true
                                    }
                                }

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
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

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Startup Timeout (s)"
                                    }
                                    SpinBox {
                                        id: ledStartupTimeout
                                        from: 10
                                        to: 60
                                        value: 20
                                        editable: true
                                    }
                                }
                            }
                        }

                        GroupBox {
                            title: "Status Config"
                            Layout.fillWidth: true
                            visible: ledStatusStripType.currentValue > 0
                            background: Loader { sourceComponent: cardBg }
                            label: Loader { sourceComponent: cardTitleLabel; onLoaded: item.title = "Status Config" }
                            topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 10

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
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
                                }

                                ColumnLayout {
                                    id: ledStatusPinLayout
                                    visible: ledStatusStripType.currentValue > 0
                                    spacing: cardStyle.fieldSpacing

                                    ColumnLayout {
                                        spacing: cardStyle.labelSpacing
                                        Text {
                                            color: fieldLabelStyle.color
                                            font.pixelSize: fieldLabelStyle.pixelSize
                                            font.bold: fieldLabelStyle.bold
                                            text: "Status Pin"
                                        }
                                        SpinBox {
                                            id: ledStatusPin
                                            from: -1
                                            to: 100
                                            value: 7
                                            editable: true
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: cardStyle.labelSpacing
                                        Text {
                                            color: fieldLabelStyle.color
                                            font.pixelSize: fieldLabelStyle.pixelSize
                                            font.bold: fieldLabelStyle.bold
                                            text: "Status Num"
                                        }
                                        SpinBox {
                                            id: ledStatusNum
                                            from: 0
                                            to: 100
                                            value: 10
                                            editable: true
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: cardStyle.labelSpacing
                                        Layout.fillWidth: true
                                        Text {
                                            color: fieldLabelStyle.color
                                            font.pixelSize: fieldLabelStyle.pixelSize
                                            font.bold: fieldLabelStyle.bold
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
                                    }

                                    CheckBox {
                                        id: ledStatusReversed
                                        text: "Status Reversed"
                                        checked: false
                                    }

                                    ColumnLayout {
                                        spacing: cardStyle.labelSpacing
                                        Layout.fillWidth: true
                                        Text {
                                            color: fieldLabelStyle.color
                                            font.pixelSize: fieldLabelStyle.pixelSize
                                            font.bold: fieldLabelStyle.bold
                                            text: "Status Timing"
                                        }
                                        ComboBox {
                                            id: ledStatusTiming
                                            Layout.fillWidth: true
                                            model: ["Universal", "WS2812B", "WS2815", "SK6812", "SK6815"]
                                        }
                                    }
                                }
                            }
                        }

                        GroupBox {
                            title: "LED Front Config"
                            Layout.fillWidth: true
                            visible: ledFrontStripType.currentValue > 0
                            background: Loader { sourceComponent: cardBg }
                            label: Loader { sourceComponent: cardTitleLabel; onLoaded: item.title = "LED Front Config" }
                            topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 10

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
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
                                            value = model[currentIndex].value
                                            updateFrontLEDSettings()
                                        }
                                        property int value: 2
                                    }
                                }

                                ColumnLayout {
                                    id: ledFrontPinLayout
                                    visible: ledFrontStripType.currentValue > 0
                                    spacing: 10

                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
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
                                    visible: frontHbMode === 1
                                    spacing: 10

                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
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

                                    ColumnLayout {
                                        spacing: cardStyle.labelSpacing
                                        Text {
                                            color: fieldLabelStyle.color
                                            font.pixelSize: fieldLabelStyle.pixelSize
                                            font.bold: fieldLabelStyle.bold
                                            text: "Front Num"
                                        }
                                        SpinBox {
                                            id: ledFrontNum
                                            from: 0
                                            to: 100
                                            value: 18
                                            editable: true
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: cardStyle.labelSpacing
                                        Layout.fillWidth: true
                                        Text {
                                            color: fieldLabelStyle.color
                                            font.pixelSize: fieldLabelStyle.pixelSize
                                            font.bold: fieldLabelStyle.bold
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

                                ColumnLayout {
                                    visible: ledFrontStripType.currentValue > 0
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true

                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Front Timing"
                                    }
                                    ComboBox {
                                        id: ledFrontTiming
                                        Layout.fillWidth: true
                                        model: ["Universal", "WS2812B", "WS2815", "SK6812", "SK6815"]
                                    }
                                }
                            }
                        }

                        GroupBox {
                            title: "LED Rear Config"
                            Layout.fillWidth: true
                            visible: ledRearStripType.currentValue > 0
                            background: Loader { sourceComponent: cardBg }
                            label: Loader { sourceComponent: cardTitleLabel; onLoaded: item.title = "LED Rear Config" }
                            topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 10

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
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
                                            value = model[currentIndex].value
                                            updateRearLEDSettings()
                                        }
                                        property int value: 2
                                    }
                                }

                                ColumnLayout {
                                    id: ledRearPinLayout
                                    visible: ledRearStripType.currentValue > 0
                                    spacing: cardStyle.labelSpacing

                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
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
                                    visible: rearHbMode === 1
                                    spacing: cardStyle.labelSpacing

                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
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
                                    spacing: cardStyle.fieldSpacing

                                    ColumnLayout {
                                        spacing: cardStyle.labelSpacing
                                        Text {
                                            color: fieldLabelStyle.color
                                            font.pixelSize: fieldLabelStyle.pixelSize
                                            font.bold: fieldLabelStyle.bold
                                            text: "Rear Num"
                                        }
                                        SpinBox {
                                            id: ledRearNum
                                            from: 0
                                            to: 100
                                            value: 18
                                            editable: true
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: cardStyle.labelSpacing
                                        Layout.fillWidth: true
                                        Text {
                                            color: fieldLabelStyle.color
                                            font.pixelSize: fieldLabelStyle.pixelSize
                                            font.bold: fieldLabelStyle.bold
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

                                ColumnLayout {
                                    visible: ledRearStripType.currentValue > 0
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true

                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Rear Timing"
                                    }
                                    ComboBox {
                                        id: ledRearTiming
                                        Layout.fillWidth: true
                                        model: ["Universal", "WS2812B", "WS2815", "SK6812", "SK6815"]
                                    }
                                }
                            }
                        }

                        GroupBox {
                            title: "LED Button Config"
                            Layout.fillWidth: true
                            visible: ledButtonStripType.currentValue > 0
                            background: Loader { sourceComponent: cardBg }
                            label: Loader { sourceComponent: cardTitleLabel; onLoaded: item.title = "LED Button Config" }
                            topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 10

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Button"
                                    }
                                    ComboBox {
                                        id: ledButtonStripType
                                        Layout.fillWidth: true
                                        model: [
                                            {text: "None", value: 0},
                                            {text: "NeoPixel RGB", value: 1},
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
                                    id: ledButtonPinLayout
                                    visible: ledButtonStripType.currentValue > 0
                                    spacing: cardStyle.labelSpacing

                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Button Pin"
                                    }

                                    SpinBox {
                                        id: ledButtonPin
                                        from: -1
                                        to: 100
                                        value: -1
                                        editable: true
                                    }
                                }

                                ColumnLayout {
                                    id: ledButtonCustomSettings
                                    visible: ledButtonStripType.currentValue === 1
                                    spacing: 10
                                }
                            }
                        }

                        GroupBox {
                            title: "LED Footpad Config"
                            Layout.fillWidth: true
                            visible: ledFootpadStripType.currentValue > 0
                            background: Loader { sourceComponent: cardBg }
                            label: Loader { sourceComponent: cardTitleLabel; onLoaded: item.title = "LED Footpad Config" }
                            topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 10

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Footpad Strip"
                                    }
                                    ComboBox {
                                        id: ledFootpadStripType
                                        Layout.fillWidth: true
                                        model: [
                                            {text: "None", value: 0},
                                            {text: "Custom", value: 1}
                                        ]
                                        textRole: "text"
                                        valueRole: "value"
                                        onCurrentIndexChanged: {
                                            value = model[currentIndex].value
                                            updateFootpadLEDSettings()
                                        }
                                        property int value: 0
                                    }
                                }

                                ColumnLayout {
                                    id: ledFootpadPinLayout
                                    visible: ledFootpadStripType.currentValue > 0
                                    spacing: cardStyle.labelSpacing

                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Footpad Pin"
                                    }

                                    SpinBox {
                                        id: ledFootpadPin
                                        from: -1
                                        to: 100
                                        value: -1
                                        editable: true
                                    }
                                }

                                ColumnLayout {
                                    id: ledFootpadCustomSettings
                                    visible: ledFootpadStripType.currentValue === 1
                                    spacing: cardStyle.fieldSpacing

                                    ColumnLayout {
                                        spacing: cardStyle.labelSpacing
                                        Text {
                                            color: fieldLabelStyle.color
                                            font.pixelSize: fieldLabelStyle.pixelSize
                                            font.bold: fieldLabelStyle.bold
                                            text: "Footpad Num"
                                        }
                                        SpinBox {
                                            id: ledFootpadNum
                                            from: 0
                                            to: 100
                                            value: 13
                                            editable: true
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: cardStyle.labelSpacing
                                        Layout.fillWidth: true
                                        Text {
                                            color: fieldLabelStyle.color
                                            font.pixelSize: fieldLabelStyle.pixelSize
                                            font.bold: fieldLabelStyle.bold
                                            text: "Footpad Type"
                                        }
                                        ComboBox {
                                            id: ledFootpadType
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
                                }

                                ColumnLayout {
                                    id: ledFootpadReversedLayout
                                    visible: ledFootpadStripType.currentValue > 0
                                    spacing: 10

                                    CheckBox {
                                        id: ledFootpadReversed
                                        text: "Footpad Reversed"
                                        checked: false
                                    }
                                }

                                ColumnLayout {
                                    visible: ledFootpadStripType.currentValue > 0
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true

                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Footpad Timing"
                                    }
                                    ComboBox {
                                        id: ledFootpadTiming
                                        Layout.fillWidth: true
                                        model: ["Universal", "WS2812B", "WS2815", "SK6812", "SK6815"]
                                    }
                                }
                            }
                        }

                        // Adds a not-yet-used role to the list above; each
                        // role's own Strip Type = "None" removes it again.
                        Button {
                            text: "+ Add Strip"
                            Layout.fillWidth: true
                            enabled: container.addedRoles.length < 5
                            onClicked: addStripMenu.popup()

                            Menu {
                                id: addStripMenu

                                MenuItem {
                                    text: "Status bar"
                                    visible: ledStatusStripType.currentValue === 0
                                    height: visible ? implicitHeight : 0
                                    onTriggered: container.setRole("Status", true)
                                }
                                MenuItem {
                                    text: "Front"
                                    visible: ledFrontStripType.currentValue === 0
                                    height: visible ? implicitHeight : 0
                                    onTriggered: container.setRole("Front", true)
                                }
                                MenuItem {
                                    text: "Rear"
                                    visible: ledRearStripType.currentValue === 0
                                    height: visible ? implicitHeight : 0
                                    onTriggered: container.setRole("Rear", true)
                                }
                                MenuItem {
                                    text: "Footpad"
                                    visible: ledFootpadStripType.currentValue === 0
                                    height: visible ? implicitHeight : 0
                                    onTriggered: container.setRole("Footpad", true)
                                }
                                MenuItem {
                                    text: "Button LED"
                                    visible: ledButtonStripType.currentValue === 0
                                    height: visible ? implicitHeight : 0
                                    onTriggered: container.setRole("Button", true)
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 20
                        visible: pubmoteEnabled.checked && tabBar2.currentIndex === 1
                        GroupBox {
                            title: "Pubmote Config"
                            Layout.fillWidth: true
                            background: Loader { sourceComponent: cardBg }
                            label: Loader { sourceComponent: cardTitleLabel; onLoaded: item.title = "Pubmote Config" }
                            topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 10

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    visible: pubmoteEnabled.checked
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Frequency (Hz)"
                                    }
                                    SpinBox {
                                        id: pubmoteLoopDelay
                                        from: 1
                                        to: 1000
                                        value: 8
                                        stepSize: 1
                                        editable: true
                                    }
                                }

                                Text {
                                    id: pubmoteMacAddress
                                    color: Utility.getAppHexColor("lightText")
                                    text: "MAC: Unknown"
                                }

                                Text {
                                    id: pubmoteVersion
                                    color: Utility.getAppHexColor("lightText")
                                    text: statusTimeout ? "Version: Unknown" : "Version: " + pubmoteVersionStr
                                }

                                Button {
                                    text: isPubmotePaired ? "Unpair Pubmote" : "Pair Pubmote"
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 500
                                    onClicked: {
                                        if (isPubmotePaired) {
                                            sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(pair-pubmote -2)");
                                            sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(send-config)");
                                        } else {
                                            pubmotePairPopup.open();  // Open the confirmation popup with the random code
                                        }
                                    }
                                }

                            }
                        }

                        GroupBox {
                            id: inputPreviewSection
                            title: "Input Preview"
                            Layout.fillWidth: true
                            background: Loader { sourceComponent: cardBg }
                            label: Item {
                                implicitHeight: 40
                                width: parent ? parent.width : 200

                                Text {
                                    text: "Input Preview"
                                    color: "white"
                                    font.bold: true
                                    font.pixelSize: 15
                                    anchors.left: parent.left
                                    anchors.leftMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Loader {
                                    id: inputPreviewEnabled
                                    sourceComponent: customSwitch
                                    anchors.right: parent.right
                                    anchors.rightMargin: cardStyle.sidePadding
                                    anchors.verticalCenter: parent.verticalCenter
                                    property bool checked: item ? item.checked : false

                                    onLoaded: {
                                        item.checked = false
                                        item.checkedChanged.connect(function() {
                                            inputPreviewEnabled.checked = item.checked
                                        })
                                    }

                                    onCheckedChanged: {
                                        if (item) item.checked = checked
                                    }
                                }
                            }
                            topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 10

                                Text {
                                    visible: inputPreviewEnabled.checked
                                    text: pubmoteInputConnected ? "Pubmote connected" : "Pubmote not connected"
                                    color: pubmoteInputConnected ? "cyan" : Utility.getAppHexColor("lightText")
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                ColumnLayout {
                                    visible: inputPreviewEnabled.checked
                                    spacing: 10
                                    Layout.alignment: Qt.AlignHCenter

                                    Rectangle {
                                        id: joystickPad
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.preferredWidth: 160
                                        Layout.preferredHeight: 160
                                        color: "transparent"
                                        border.color: Qt.rgba(1, 1, 1, 0.3)
                                        border.width: 1
                                        radius: 8

                                        Rectangle {
                                            width: 1
                                            height: parent.height - 2
                                            anchors.centerIn: parent
                                            color: Qt.rgba(1, 1, 1, 0.15)
                                        }
                                        Rectangle {
                                            width: parent.width - 2
                                            height: 1
                                            anchors.centerIn: parent
                                            color: Qt.rgba(1, 1, 1, 0.15)
                                        }

                                        Rectangle {
                                            width: 14
                                            height: 14
                                            radius: 7
                                            color: pubmoteInputConnected ? "cyan" : "gray"
                                            x: (parent.width - width) / 2 + Math.max(-1, Math.min(1, pubmoteInputJsx)) * (parent.width - width) / 2
                                            y: (parent.height - height) / 2 - Math.max(-1, Math.min(1, pubmoteInputJsy)) * (parent.height - height) / 2
                                        }
                                    }

                                    Text {
                                        text: "Y: " + pubmoteInputJsy.toFixed(3) + "    X: " + pubmoteInputJsx.toFixed(3)
                                        color: Utility.getAppHexColor("lightText")
                                        Layout.alignment: Qt.AlignHCenter
                                    }

                                    RowLayout {
                                        spacing: 10
                                        Layout.alignment: Qt.AlignHCenter

                                        Rectangle {
                                            Layout.preferredWidth: 70
                                            Layout.preferredHeight: 32
                                            radius: 6
                                            color: pubmoteInputBtC ? "cyan" : Qt.rgba(1, 1, 1, 0.1)
                                            Text {
                                                anchors.centerIn: parent
                                                text: "C"
                                                color: pubmoteInputBtC ? "black" : "white"
                                            }
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: 70
                                            Layout.preferredHeight: 32
                                            radius: 6
                                            color: pubmoteInputBtZ ? "cyan" : Qt.rgba(1, 1, 1, 0.1)
                                            Text {
                                                anchors.centerIn: parent
                                                text: "Z"
                                                color: pubmoteInputBtZ ? "black" : "white"
                                            }
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: 70
                                            Layout.preferredHeight: 32
                                            radius: 6
                                            color: pubmoteInputRev ? "cyan" : Qt.rgba(1, 1, 1, 0.1)
                                            Text {
                                                anchors.centerIn: parent
                                                text: "REV"
                                                color: pubmoteInputRev ? "black" : "white"
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 20
                        visible: bmsEnabled.checked && tabBar2.currentIndex === 2
                        GroupBox {
                            title: "BMS Config"
                            Layout.fillWidth: true
                            background: Loader { sourceComponent: cardBg }
                            label: Loader { sourceComponent: cardTitleLabel; onLoaded: item.title = "BMS Config" }
                            topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding
                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 10

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    visible: bmsEnabled.checked
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "BMS Frequency (Hz)"
                                    }
                                    SpinBox {
                                        id: bmsLoopDelay
                                        from: 1
                                        to: 1000
                                        value: 8
                                        stepSize: 1
                                        editable: true
                                    }
                                }

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "BMS Type"
                                    }
                                    ComboBox {
                                        id: bmsType
                                        Layout.fillWidth: true
                                        model: [
                                            {text: "None", value: 0},
                                            {text: "Unencrypted", value: 1},
                                            {text: "Encrypted", value: 2},
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
                                    id: bmsSettings
                                    visible: bmsType.currentIndex > 0
                                    spacing: cardStyle.fieldSpacing

                                    ColumnLayout {
                                        id: bmsCryptoSettingsLayout
                                        visible: bmsType.currentIndex > 1
                                        spacing: cardStyle.fieldSpacing

                                        Button {
                                            text: "Set Keys"
                                            onClicked: {
                                                keyInput.text = ""
                                                counterInput.text = ""
                                                keySettingPopup.open()
                                            }
                                        }
                                    }

                                    CheckBox {
                                        id: bmsRS485Chip
                                        text: "RS485 Chip (Required for encrypted BMS charger level without Owie RS485 bypass)"
                                        checked: false
                                    }

                                    ColumnLayout {
                                        spacing: cardStyle.labelSpacing
                                        Text {
                                            color: fieldLabelStyle.color
                                            font.pixelSize: fieldLabelStyle.pixelSize
                                            font.bold: fieldLabelStyle.bold
                                            text: "RS485 RO/A Pin"
                                        }
                                        SpinBox {
                                            id: bmsRs485ROPin
                                            from: -1
                                            to: 100
                                            value: -1
                                            editable: true
                                        }
                                    }

                                    ColumnLayout {
                                        id: bmsRS485chipLayout
                                        visible: bmsRS485Chip.checked
                                        spacing: cardStyle.fieldSpacing

                                        ColumnLayout {
                                            spacing: cardStyle.labelSpacing
                                            Text {
                                                color: fieldLabelStyle.color
                                                font.pixelSize: fieldLabelStyle.pixelSize
                                                font.bold: fieldLabelStyle.bold
                                                text: "RS485 DI Pin"
                                            }
                                            SpinBox {
                                                id: bmsRs485DIPin
                                                from: -1
                                                to: 100
                                                value: -1
                                                editable: true
                                            }
                                        }

                                        ColumnLayout {
                                            spacing: cardStyle.labelSpacing
                                            Text {
                                                color: fieldLabelStyle.color
                                                font.pixelSize: fieldLabelStyle.pixelSize
                                                font.bold: fieldLabelStyle.bold
                                                text: "RS485 DE/RE Pin"
                                            }
                                            SpinBox {
                                                id: bmsRs485DEREPin
                                                from: -1
                                                to: 100
                                                value: -1
                                                editable: true
                                            }
                                        }

                                        Button {
                                            text: "Factory Init"
                                            //enabled: bmsConnected === 1
                                            onClicked: {
                                                bmsFactoryInit()
                                            }
                                        }
                                    }

                                    CheckBox {
                                        id: bmsChargeOnly
                                        text: "Charge only (Mosfet toggle wakeup to keep alive)"
                                        checked: false
                                    }

                                    ColumnLayout {
                                        id: bmsChargeOnlyLayout
                                        visible: bmsChargeOnly.checked
                                        spacing: cardStyle.labelSpacing

                                        Text {
                                            color: fieldLabelStyle.color
                                            font.pixelSize: fieldLabelStyle.pixelSize
                                            font.bold: fieldLabelStyle.bold
                                            text: "Wakeup Pin"
                                        }

                                        SpinBox {
                                            id: bmsWakeupPin
                                            from: -1
                                            to: 100
                                            value: -1
                                            editable: true
                                        }
                                    }

                                    CheckBox {
                                        id: bmsOverrideSOC
                                        text: "Override SOC (Choose cell type in Settings)"
                                        checked: false
                                    }

                                    ColumnLayout {
                                        spacing: cardStyle.labelSpacing
                                        Text {
                                            color: fieldLabelStyle.color
                                            font.pixelSize: fieldLabelStyle.pixelSize
                                            font.bold: fieldLabelStyle.bold
                                            text: "BMS Buffer Size"
                                        }
                                        SpinBox {
                                            id: bmsBuffSize
                                            from: 16
                                            to: 256
                                            value: 128
                                            editable: true
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 20
                        visible: logEnabled.checked && tabBar2.currentIndex === 3
                        GroupBox {
                            title: "Logging Config"
                            Layout.fillWidth: true
                            background: Loader { sourceComponent: cardBg }
                            label: Loader { sourceComponent: cardTitleLabel; onLoaded: item.title = "Logging Config" }
                            topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 10
                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Logging Frequency (Hz)"
                                    }
                                    SpinBox {
                                        id: logRate
                                        from: 1
                                        to: 1000
                                        value: 2
                                        stepSize: 1
                                        editable: true
                                    }
                                }

                                CheckBox {
                                    id: logAppendGnss
                                    text: "GNSS Logging Enabled"
                                    checked: false
                                }

                                Button {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 500
                                    text: "Test SD-card"
                                    visible: logEnabled.checked

                                    onClicked: {
                                        commDialog.open()
                                        var ok = mCommands.fileBlockWrite("test.txt", "TestTxt")
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
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 20
                        visible: gnssEnabled.checked && tabBar2.currentIndex === 4
                        GroupBox {
                            title: "GNSS Config"
                            Layout.fillWidth: true
                            background: Loader { sourceComponent: cardBg }
                            label: Loader { sourceComponent: cardTitleLabel; onLoaded: item.title = "GNSS Config" }
                            topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 10

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Type"
                                    }
                                    ComboBox {
                                        id: gnssType
                                        Layout.fillWidth: true
                                        model: ["u-blox (UBX)", "NMEA (UART)"]
                                    }
                                }

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "RX Pin (module TX)"
                                    }
                                    SpinBox {
                                        id: gnssRxPin
                                        from: -1
                                        to: 100
                                        value: -1
                                        editable: true
                                    }
                                }

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: gnssType.currentIndex === 0 ? "TX Pin (module RX)" : "TX Pin (module RX, optional)"
                                    }
                                    SpinBox {
                                        id: gnssTxPin
                                        from: -1
                                        to: 100
                                        value: -1
                                        editable: true
                                    }
                                }

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "UART"
                                    }
                                    SpinBox {
                                        id: gnssUartNum
                                        from: 0
                                        to: 2
                                        value: 1
                                        editable: true
                                    }
                                }

                                ColumnLayout {
                                    visible: gnssType.currentIndex === 0
                                    spacing: cardStyle.labelSpacing
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Nav Rate (ms)"
                                    }
                                    SpinBox {
                                        id: gnssRateMs
                                        from: 100
                                        to: 5000
                                        value: 500
                                        stepSize: 100
                                        editable: true
                                    }
                                }

                                ColumnLayout {
                                    visible: gnssType.currentIndex === 1
                                    spacing: cardStyle.labelSpacing
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Baud Rate"
                                    }
                                    SpinBox {
                                        id: gnssBaud
                                        from: 4800
                                        to: 921600
                                        value: 9600
                                        stepSize: 4800
                                        editable: true
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 20
                        visible: mqttEnabled.checked && tabBar2.currentIndex === 5
                        GroupBox {
                            title: "MQTT Config"
                            Layout.fillWidth: true
                            background: Loader { sourceComponent: cardBg }
                            label: Loader { sourceComponent: cardTitleLabel; onLoaded: item.title = "MQTT Config" }
                            topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 10

                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    color: fieldLabelStyle.color
                                    font.pixelSize: fieldLabelStyle.pixelSize
                                    text: "Wi-Fi must be configured separately in the VESC Express Wi-Fi settings; MQTT connects over that link."
                                }

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Broker URI"
                                    }
                                    TextField {
                                        id: mqttUri
                                        Layout.fillWidth: true
                                        placeholderText: "mqtt://host:1883"
                                    }
                                }

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Client ID"
                                    }
                                    TextField {
                                        id: mqttClientId
                                        Layout.fillWidth: true
                                        placeholderText: "Client ID (blank = auto)"
                                    }
                                }

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Username"
                                    }
                                    TextField {
                                        id: mqttUser
                                        Layout.fillWidth: true
                                        placeholderText: "Username (blank = none)"
                                    }
                                }

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Password"
                                    }
                                    TextField {
                                        id: mqttPassword
                                        Layout.fillWidth: true
                                        echoMode: TextInput.Password
                                        placeholderText: "Password"
                                    }
                                }

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Layout.fillWidth: true
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Topic Prefix"
                                    }
                                    TextField {
                                        id: mqttTopicPrefix
                                        Layout.fillWidth: true
                                        text: "vesc/float"
                                        placeholderText: "vesc/float"
                                    }
                                }

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "QoS"
                                    }
                                    SpinBox {
                                        id: mqttQos
                                        from: 0
                                        to: 2
                                        value: 0
                                        editable: true
                                    }
                                }

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Keepalive (s)"
                                    }
                                    SpinBox {
                                        id: mqttKeepalive
                                        from: 5
                                        to: 600
                                        value: 60
                                        editable: true
                                    }
                                }

                                ColumnLayout {
                                    spacing: cardStyle.labelSpacing
                                    Text {
                                        color: fieldLabelStyle.color
                                        font.pixelSize: fieldLabelStyle.pixelSize
                                        font.bold: fieldLabelStyle.bold
                                        text: "Publish Rate (Hz)"
                                    }
                                    SpinBox {
                                        id: mqttPublishRate
                                        from: 1
                                        to: 30
                                        value: 1
                                        editable: true
                                    }
                                }
                            }
                        }
                    }
                    }
                }
            }

            // Settings tab
            ScrollView {
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                background: Rectangle { color: cardStyle.scrollViewBg }

                Item {
                    width: stackLayout.width
                    implicitHeight: scrollContent3.implicitHeight + cardStyle.scrollTopPadding + cardStyle.scrollBottomPadding

                    ColumnLayout {
                        id: scrollContent3
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: cardStyle.scrollTopPadding
                        anchors.leftMargin: cardStyle.scrollHPadding
                        anchors.rightMargin: cardStyle.scrollHPadding
                        spacing: 20

                    GroupBox {
                        title: "Features"
                        Layout.fillWidth: true
                        background: Loader { sourceComponent: cardBg }
                        label: Loader { sourceComponent: cardTitleLabel; onLoaded: item.title = "Features" }
                        topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 6
                            CheckBox {
                                id: ledEnabled
                                text: "Lighting Enabled"
                                checked: false
                            }

                            CheckBox {
                                id: pubmoteEnabled
                                text: "Pubmote Enabled"
                                checked: false
                                enabled: true
                            }

                            CheckBox {
                                id: bmsEnabled
                                text: "BMS Enabled"
                                checked: false
                                enabled: true
                            }

                            CheckBox {
                                id: logEnabled
                                text: "SD Card Logging Enabled"
                                checked: false
                                enabled: true
                            }

                            CheckBox {
                                id: humidityEnabled
                                text: "Humidity Sensor Enabled"
                                checked: false
                                enabled: true
                            }

                            CheckBox {
                                id: gnssEnabled
                                text: "GNSS Enabled"
                                checked: false
                                enabled: true
                            }

                            CheckBox {
                                id: mqttEnabled
                                text: "MQTT Enabled"
                                checked: false
                                enabled: true
                            }
                        }
                    }

                    GroupBox {
                        title: "Node Role"
                        Layout.fillWidth: true
                        background: Loader { sourceComponent: cardBg }
                        label: Loader { sourceComponent: cardTitleLabel; onLoaded: item.title = "Node Role" }
                        topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: cardStyle.labelSpacing

                            Text {
                                color: fieldLabelStyle.color
                                font.pixelSize: fieldLabelStyle.pixelSize
                                font.bold: fieldLabelStyle.bold
                                text: "CAN Role"
                            }
                            ComboBox {
                                id: nodeRole
                                Layout.fillWidth: true
                                model: ["Master", "Slave"]
                                // onActivated only fires on user interaction, not
                                // when the loaded value is applied below, so this
                                // never echoes the role straight back on connect.
                                onActivated: {
                                    sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(set-node-role " + currentIndex + ")")
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: fieldLabelStyle.color
                                font.pixelSize: fieldLabelStyle.pixelSize - 2
                                text: "Master polls the VESC and broadcasts telemetry plus the shared lighting settings over CAN. Slaves render their own strips from the master's broadcast and do not poll the VESC. Pins, LED counts and strip timing stay local to each node. Reboot after changing the role."
                            }
                        }
                    }

                    GroupBox {
                        title: "State of Charge Reporting"
                        Layout.fillWidth: true
                        background: Loader { sourceComponent: cardBg }
                        label: Loader { sourceComponent: cardTitleLabel; onLoaded: item.title = "State of Charge Reporting" }
                        topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding

                        ColumnLayout {
                            anchors.fill: parent
                            width: stackLayout.width
                            spacing: 10

                            RadioButton {
                                id: floatPkgSoc
                                checked: true
                                text: qsTr("Float Package (from VESC firmware)")
                            }
                            RadioButton {
                                id: voltageCurveSoc
                                text: qsTr("Voltage Curve Based")
                            }

                            ColumnLayout {
                                spacing: cardStyle.labelSpacing
                                visible: voltageCurveSoc.checked
                                Layout.fillWidth: true
                                Text {
                                    color: fieldLabelStyle.color
                                    font.pixelSize: fieldLabelStyle.pixelSize
                                    font.bold: fieldLabelStyle.bold
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
                                    property int value: 0
                                }
                            }
                        }
                    }

                    GroupBox {
                        title: "Loop Settings"
                        Layout.fillWidth: true
                        background: Loader { sourceComponent: cardBg }
                        label: Loader { sourceComponent: cardTitleLabel; onLoaded: item.title = "Loop Settings" }
                        topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding

                        ColumnLayout {
                            width: stackLayout.width
                            spacing: 10

                            ColumnLayout {
                                spacing: cardStyle.labelSpacing
                                Text {
                                    color: fieldLabelStyle.color
                                    font.pixelSize: fieldLabelStyle.pixelSize
                                    font.bold: fieldLabelStyle.bold
                                    text: "CAN Frequency (Hz)"
                                }
                                SpinBox {
                                    id: canLoopDelay
                                    from: 1
                                    to: 1000
                                    value: 8
                                    stepSize: 1
                                    editable: true
                                }
                            }
                        }
                    }

                    GroupBox {
                        title: "Humidity Sensor"
                        Layout.fillWidth: true
                        visible: humidityEnabled.checked
                        background: Loader { sourceComponent: cardBg }
                        label: Loader { sourceComponent: cardTitleLabel; onLoaded: item.title = "Humidity Sensor" }
                        topPadding: cardStyle.topPadding; leftPadding: cardStyle.sidePadding; rightPadding: cardStyle.sidePadding; bottomPadding: cardStyle.bottomPadding

                        ColumnLayout {
                            anchors.fill: parent
                            width: stackLayout.width
                            spacing: 10
                            ColumnLayout {
                                spacing: cardStyle.labelSpacing
                                Text {
                                    color: fieldLabelStyle.color
                                    font.pixelSize: fieldLabelStyle.pixelSize
                                    font.bold: fieldLabelStyle.bold
                                    text: "SDA Pin"
                                }
                                SpinBox {
                                    id: humiditySdaPin
                                    from: -1
                                    to: 100
                                    value: 7
                                    editable: true
                                }
                            }

                            ColumnLayout {
                                spacing: cardStyle.labelSpacing
                                Text {
                                    color: fieldLabelStyle.color
                                    font.pixelSize: fieldLabelStyle.pixelSize
                                    font.bold: fieldLabelStyle.bold
                                    text: "SLC Pin"
                                }
                                SpinBox {
                                    id: humiditySlcPin
                                    from: -1
                                    to: 100
                                    value: 7
                                    editable: true
                                }
                            }
                        }
                    }

                    }
                }
            }

        }

        // Save and Restore Buttons
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            visible: tabBar.currentIndex === 1 || tabBar.currentIndex === 2

            Item { Layout.fillWidth: true }

            Button {
                text: statusTimeout ? "Not connected" : "Save Config"
                enabled: readConfig && !statusTimeout
                onClicked: {
                    if (bmsEnabled.checked && !acceptTOS) {
                        termsPopup.visible = true
                    }

                    console.log(makeArgStr())
                    sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(recv-config " + makeArgStr() + " )")

                    // MQTT config is sent as its own command: its string fields
                    // (URI, credentials, prefix) can't ride the space-split
                    // recv-config token vector. Strings are escaped and quoted
                    // so the (eval (read ...)) command path parses them intact.
                    var mqttEsc = function(s) {
                        return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + '"'
                    }
                    var mqttCmd = "(recv-mqtt-cfg " +
                        (mqttEnabled.checked * 1) + " " +
                        mqttQos.value + " " +
                        mqttKeepalive.value + " " +
                        mqttPublishRate.value + " " +
                        mqttEsc(mqttUri.text) + " " +
                        mqttEsc(mqttClientId.text) + " " +
                        mqttEsc(mqttUser.text) + " " +
                        mqttEsc(mqttPassword.text) + " " +
                        mqttEsc(mqttTopicPrefix.text) + ")"
                    sendCode(String.fromCharCode(102) + String.fromCharCode(1) + mqttCmd)
                    //sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(save-config)")
                    //sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(send-config)")
                }
            }

            ToolButton {
                id: optionsButton
                text: "⋮"
                font.pixelSize: 24
                enabled: !statusTimeout
                onClicked: optionsMenu.open()

                Menu {
                    id: optionsMenu
                    y: optionsButton.height

                    MenuItem {
                        text: "Read Config"
                        onClicked: {
                            sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(send-config)")
                        }
                    }

                    MenuItem {
                        text: "Restore Default Config"
                        onClicked: {
                            sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(restore-config)")
                            sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(send-config)")
                        }
                    }
                }
            }
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

    // Front/rear board presets. Selecting one just fills the concrete
    // hardware description below - only those values are stored in the
    // config, the preset itself is not. hbPos holds embedded highbeam LED
    // positions; hbMin/hbMax the drive range those LEDs expect.
    property var stripPresets: [
        { },                                                                        // 0 None
        { },                                                                        // 1 Custom
        { num: 18, type: 0, hbMode: 2, hbPos: [0], hbMin: 0.0, hbMax: 1.0 },        // 2 Avaspark Laserbeam
        { num: 16, type: 0, hbMode: 2, hbPos: [0], hbMin: 0.0, hbMax: 1.0 },        // 3 Avaspark Laserbeam Pint
        { num: 17, type: 0, hbMode: 2, hbPos: [3,8,14,19], hbMin: 0.6, hbMax: 0.8 },// 4 JetFleet H4
        { num: 17, type: 0, hbMode: 2, hbPos: [3,8,14,19], hbMin: 0.6, hbMax: 1.0 },// 5 JetFleet H4 (no limit)
        { num: 11, type: 0, hbMode: 2, hbPos: [1,4,10,13], hbMin: 0.6, hbMax: 1.0 },// 6 JetFleet GT
        { num: 11, type: 2, hbMode: 1, hbPos: [], hbMin: 0.0, hbMax: 1.0 },         // 7 Stock GT (PWM highbeam)
        { num: 13, type: 0, hbMode: 2, hbPos: [0], hbMin: 0.0, hbMax: 1.0 },        // 8 Avaspark Laserbeam V2
        { num: 10, type: 0, hbMode: 2, hbPos: [0], hbMin: 0.0, hbMax: 1.0 },        // 9 Avaspark Laserbeam V2 Pint
        { num: 20, type: 0, hbMode: 2, hbPos: [0], hbMin: 0.0, hbMax: 1.0 },        // 10 Light-shutka Flashfires
        { num: 10, type: 0, hbMode: 2, hbPos: [3,6,9,13], hbMin: 0.4, hbMax: 1.0 }, // 11 Fungineers GTFO
    ]

    // Highbeam hardware description per strip (0 none, 1 PWM pin,
    // 2 embedded LEDs). Filled by the presets, kept as-is for Custom.
    property int frontHbMode: 0
    property var frontHbPos: []
    property real frontHbMin: 0.0
    property real frontHbMax: 1.0
    property int rearHbMode: 0
    property var rearHbPos: []
    property real rearHbMin: 0.0
    property real rearHbMax: 1.0

    // Positions pack one per byte from the lowest, 255 = unused.
    function packHbPos(arr) {
        var v = 0
        for (var i = 0; i < 4; i++) {
            v |= (i < arr.length ? (arr[i] & 0xFF) : 0xFF) << (8 * i)
        }
        return v
    }

    function unpackHbPos(v) {
        var arr = []
        for (var i = 0; i < 4; i++) {
            var b = (v >> (8 * i)) & 0xFF
            if (b !== 0xFF) arr.push(b)
        }
        return arr
    }

    // Find the preset matching a loaded config, 1 (Custom) when none does.
    function matchStripPreset(num, type, hbMode, hbPos, hbMin, hbMax) {
        for (var i = 2; i < stripPresets.length; i++) {
            var p = stripPresets[i]
            if (p.num === num && p.type === type && p.hbMode === hbMode
                && Math.abs(p.hbMin - hbMin) < 0.01
                && Math.abs(p.hbMax - hbMax) < 0.01
                && JSON.stringify(p.hbPos) === JSON.stringify(hbPos)) {
                return i
            }
        }
        return 1
    }

    function updateFrontLEDSettings() {
        var p = stripPresets[ledFrontStripType.value]
        if (!p || p.num === undefined) {
            return // None / Custom keep the user-defined values
        }
        ledFrontNum.value = p.num
        ledFrontType.currentIndex = p.type
        frontHbMode = p.hbMode
        frontHbPos = p.hbPos
        frontHbMin = p.hbMin
        frontHbMax = p.hbMax
    }

    function updateRearLEDSettings() {
        var p = stripPresets[ledRearStripType.value]
        if (!p || p.num === undefined) {
            return // None / Custom keep the user-defined values
        }
        ledRearNum.value = p.num
        ledRearType.currentIndex = p.type
        rearHbMode = p.hbMode
        rearHbPos = p.hbPos
        rearHbMin = p.hbMin
        rearHbMax = p.hbMax
    }

    function updateFootpadLEDSettings() {
        switch(ledFootpadStripType.value) {
            case 0: // None
                break
            case 1: // Custom
                break
            default:
                // Do nothing, keep user-defined values
        }
    }

    function bmsFactoryInit(str) {
        sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(bms-trigger-factory-init)")
    }

    function makeControlArgStr() {
        return [
            ledOn.checked * 1,
            ledHighbeamOn.checked * 1,
            parseFloat(ledBrightnessLoader.item.value).toFixed(2),
            parseFloat(ledBrightnessHighbeamLoader.item.value).toFixed(2),
            parseFloat(ledBrightnessIdleLoader.item.value).toFixed(2),
            parseFloat(ledBrightnessStatusLoader.item.value).toFixed(2),
            bmsChargeState.checked * 1
        ].join(" ");
    }

    function handleDebouncedChange() {
        if (!throttleTimer.running) {
            applyControlChanges()
            throttleTimer.start()
        } else {
            throttleTimer.controlPending = true
        }
    }

    function flushControlChanges() {
        if (throttleTimer.controlPending) {
            applyControlChanges()
            throttleTimer.controlPending = false
        }
        throttleTimer.stop()
    }

    function applyControlChanges() {
        //console.log("Applying LED control settings after debounce")
        sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(recv-control " + makeControlArgStr() + " )")
    }

    function makeArgStr() {
        return [
            ledEnabled.checked * 1,
            bmsEnabled.checked * 1,
            pubmoteEnabled.checked * 1,
            ledOn.checked * 1,
            ledHighbeamOn.checked * 1,
            ledMode.currentIndex,
            ledModeIdle.currentIndex,
            ledModeStatus.currentIndex,
            ledModeStartup.currentIndex,
            ledModeButton.currentIndex,
            ledModeFootpad.currentIndex,
            ledMallGrabEnabled.checked * 1,
            ledBrakeLightEnabled.checked * 1,
            parseFloat(ledBrakeLightMinAmps.value).toFixed(2),
            idleTimeout.value,
            idleTimeoutShutoff.value,
            parseFloat(ledBrightnessLoader.item.value).toFixed(2),
            parseFloat(ledBrightnessHighbeamLoader.item.value).toFixed(2),
            parseFloat(ledBrightnessIdleLoader.item.value).toFixed(2),
            parseFloat(ledBrightnessStatusLoader.item.value).toFixed(2),
            ledStatusPin.value,
            ledStatusNum.value,
            ledStatusType.currentIndex,
            ledStatusReversed.checked * 1,
            ledFrontPin.value,
            ledFrontNum.value,
            ledFrontType.currentIndex,
            ledFrontReversed.checked * 1,
            ledFrontStripType.currentIndex > 0 ? ledFrontTiming.currentIndex + 1 : 0,
            ledRearPin.value,
            ledRearNum.value,
            ledRearType.currentIndex,
            ledRearReversed.checked * 1,
            ledRearStripType.currentIndex > 0 ? ledRearTiming.currentIndex + 1 : 0,
            ledButtonPin.value,
            ledButtonStripType.currentIndex > 0 ? 1 : 0,
            ledFootpadPin.value,
            ledFootpadNum.value,
            ledFootpadType.currentIndex,
            ledFootpadReversed.checked * 1,
            ledFootpadStripType.currentIndex > 0 ? ledFootpadTiming.currentIndex + 1 : 0,
            bmsRs485DIPin.value,
            bmsRs485ROPin.value,
            bmsRs485DEREPin.value,
            bmsWakeupPin.value,
            bmsOverrideSOC.checked * 1,
            bmsRS485Chip.checked * 1,
            ledLoopDelay.value,
            bmsLoopDelay.value,
            pubmoteLoopDelay.value,
            canLoopDelay.value,
            ledStartupTimeout.value,
            parseFloat(ledDimOnHighbeamRatioLoader.item.value).toFixed(2),
            bmsType.currentIndex,
            ledStatusStripType.currentIndex > 0 ? ledStatusTiming.currentIndex + 1 : 0,
            bmsChargeOnly.checked * 1,
            ledShowBatteryCharging.checked * 1,
            ledFrontHighbeamPin.value,
            ledRearHighbeamPin.value,
            bmsBuffSize.value,
            parseFloat(ledMaxBrightnessLoader.item.value).toFixed(2),
            voltageCurveSoc.checked * 1,
            cellType.value,
            ledUpdateNotRunning.checked * 1,
            logEnabled.checked * 1,
            logRate.value,
            logAppendGnss.checked * 1,
            humidityEnabled.checked * 1,
            humiditySdaPin.value,
            humiditySlcPin.value,
            frontHbMode,
            packHbPos(frontHbPos),
            frontHbMin.toFixed(2),
            frontHbMax.toFixed(2),
            rearHbMode,
            packHbPos(rearHbPos),
            rearHbMin.toFixed(2),
            rearHbMax.toFixed(2),
            gnssEnabled.checked * 1,
            gnssType.currentIndex,
            gnssRxPin.value,
            gnssTxPin.value,
            gnssUartNum.value,
            gnssRateMs.value,
            gnssBaud.value
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
        if (pubmoteEnabled.checked) newIndices.push(1)
        if (bmsEnabled.checked) newIndices.push(2)
        if (logEnabled.checked) newIndices.push(3)
        if (gnssEnabled.checked) newIndices.push(4)
        if (mqttEnabled.checked) newIndices.push(5)
        enabledIndices = newIndices
    }

    function sendCode(str) {
        mCommands.sendCustomAppData(str + '\0')
    }

    function hexStringToLispList(hexString) {
        var result = "'(";
        for (var i = 0; i < hexString.length; i += 2) {
            var byteHex = hexString.substr(i, 2);
            result += "0x" + byteHex.toUpperCase() + (i < 30 ? " " : "");
        }
        result += ")";
        return result;
    }

    function unpackUint32ToBytes(packedValue) {
        return [
            (packedValue >> 24) & 0xFF,
            (packedValue >> 16) & 0xFF,
            (packedValue >> 8) & 0xFF,
            packedValue & 0xFF
        ];
    }

    Connections {
        target: mCommands

        function onCustomAppDataReceived(data) {
            var str = data.toString()

            if (!wasConnected) {
                // Read settings on initial message
                wasConnected = true
                if (!readConfig) {
                    sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(send-config)")
                }
            }

            if (str.startsWith("settings")) {
                var tokens = str.split(" ")
                acceptTOS = (Number(tokens[4])) ? true : false
                ledEnabled.checked = Number(tokens[5])
                bmsEnabled.checked = Number(tokens[6])
                pubmoteEnabled.checked = Number(tokens[7])
                ledOn.checked = Number(tokens[8])
                ledHighbeamOn.checked = Number(tokens[9])
                ledMode.currentIndex = Number(tokens[10])
                ledModeIdle.currentIndex = Number(tokens[11])
                ledModeStatus.currentIndex = Number(tokens[12])
                ledModeStartup.currentIndex = Number(tokens[13])
                ledModeButton.currentIndex = Number(tokens[14])
                ledModeFootpad.currentIndex = Number(tokens[15])
                ledMallGrabEnabled.checked = Number(tokens[16])
                ledBrakeLightEnabled.checked = Number(tokens[17])
                ledBrakeLightMinAmps.value = Number(tokens[18])
                idleTimeout.value = Number(tokens[19])
                idleTimeoutShutoff.value = Number(tokens[20])
                ledBrightnessLoader.item.value = Number(tokens[21])
                ledBrightnessHighbeamLoader.item.value = Number(tokens[22])
                ledBrightnessIdleLoader.item.value = Number(tokens[23])
                ledBrightnessStatusLoader.item.value = Number(tokens[24])
                ledStatusPin.value = Number(tokens[25])
                ledStatusNum.value = Number(tokens[26])
                ledStatusType.currentIndex = Number(tokens[27])
                ledStatusReversed.checked = Number(tokens[28])
                ledFrontPin.value = Number(tokens[29])
                ledFrontNum.value = Number(tokens[30])
                ledFrontType.currentIndex = Number(tokens[31])
                ledFrontReversed.checked = Number(tokens[32])
                var frontTiming = Number(tokens[33])
                if (frontTiming > 0) {
                    ledFrontTiming.currentIndex = frontTiming - 1
                }
                ledRearPin.value = Number(tokens[34])
                ledRearNum.value = Number(tokens[35])
                ledRearType.currentIndex = Number(tokens[36])
                ledRearReversed.checked = Number(tokens[37])
                var rearTiming = Number(tokens[38])
                if (rearTiming > 0) {
                    ledRearTiming.currentIndex = rearTiming - 1
                }
                ledButtonPin.value = Number(tokens[39])
                ledButtonStripType.currentIndex = Number(tokens[40]) > 0 ? 1 : 0
                ledFootpadPin.value = Number(tokens[41])
                ledFootpadNum.value = Number(tokens[42])
                ledFootpadType.currentIndex = Number(tokens[43])
                ledFootpadReversed.checked = Number(tokens[44])
                var footpadTiming = Number(tokens[45])
                ledFootpadStripType.currentIndex = footpadTiming > 0 ? 1 : 0
                if (footpadTiming > 0) {
                    ledFootpadTiming.currentIndex = footpadTiming - 1
                }
                // Format and display MAC address... need to unpack
                var unpack = unpackUint32ToBytes(Number(tokens[46])).concat(unpackUint32ToBytes(Number(tokens[47]))).slice(0,-2)
                var macAddress = unpack.map(function(token) {
                    return ("0" + Number(token).toString(16)).slice(-2);
                }).join(":");
                // pubmote-secret-code 48
                bmsRs485DIPin.value = Number(tokens[49])
                bmsRs485ROPin.value = Number(tokens[50])
                bmsRs485DEREPin.value = Number(tokens[51])
                bmsWakeupPin.value = Number(tokens[52])
                bmsOverrideSOC.checked = Number(tokens[53])
                bmsRS485Chip.checked = Number(tokens[54])
                //Need to read and unpack. To set this is also going to be handled in seperate button like tos, pair-pubmote etc.
                //bmsKeyA.value = Number(tokens[55])
                //bmsKeyB.value = Number(tokens[56])
                //bmsKeyC.value = Number(tokens[57])
                //bmsKeyD.value = Number(tokens[58])
                //bmsCounterA.value = Number(tokens[59])
                //bmsCounterB.value = Number(tokens[60])
                //bmsCounterC.value = Number(tokens[61])
                //bmsCounterD.value = Number(tokens[62])
                ledLoopDelay.value = Number(tokens[63])
                bmsLoopDelay.value = Number(tokens[64])
                pubmoteLoopDelay.value = Number(tokens[65])
                canLoopDelay.value = Number(tokens[66])
                ledStartupTimeout.value = Number(tokens[67])
                ledDimOnHighbeamRatioLoader.item.value = Number(tokens[68])
                bmsType.currentIndex = Number(tokens[69])
                var statusTiming = Number(tokens[70])
                ledStatusStripType.currentIndex = statusTiming > 0 ? 1 : 0
                if (statusTiming > 0) {
                    ledStatusTiming.currentIndex = statusTiming - 1
                }
                bmsChargeOnly.checked = Number(tokens[71])
                ledShowBatteryCharging.checked = Number(tokens[72])
                ledFrontHighbeamPin.value = Number(tokens[73])
                ledRearHighbeamPin.value = Number(tokens[74])
                bmsBuffSize.value = Number(tokens[75])
                ledMaxBrightnessLoader.item.value = Number(tokens[76])
                floatPkgSoc.checked = Number(tokens[77]) == 0
                voltageCurveSoc.checked = Number(tokens[77]) == 1
                cellType.currentIndex = Number(tokens[78])
                ledUpdateNotRunning.checked = Number(tokens[79])
                logEnabled.checked = Number(tokens[80])
                logRate.value = Number(tokens[81])
                logAppendGnss.checked = Number(tokens[82])
                humidityEnabled.checked = Number(tokens[83])
                humiditySdaPin.value = Number(tokens[84])
                humiditySlcPin.value = Number(tokens[85])
                frontHbMode = Number(tokens[86])
                frontHbPos = unpackHbPos(Number(tokens[87]))
                frontHbMin = Number(tokens[88])
                frontHbMax = Number(tokens[89])
                rearHbMode = Number(tokens[90])
                rearHbPos = unpackHbPos(Number(tokens[91]))
                rearHbMin = Number(tokens[92])
                rearHbMax = Number(tokens[93])
                gnssEnabled.checked = Number(tokens[94])
                gnssType.currentIndex = Number(tokens[95])
                gnssRxPin.value = Number(tokens[96])
                gnssTxPin.value = Number(tokens[97])
                gnssUartNum.value = Number(tokens[98])
                gnssRateMs.value = Number(tokens[99])
                gnssBaud.value = Number(tokens[100])

                // The preset itself is not stored - recognize it from the
                // loaded values, falling back to Custom.
                ledFrontStripType.currentIndex = frontTiming > 0
                    ? matchStripPreset(ledFrontNum.value, ledFrontType.currentIndex,
                                       frontHbMode, frontHbPos, frontHbMin, frontHbMax)
                    : 0
                ledRearStripType.currentIndex = rearTiming > 0
                    ? matchStripPreset(ledRearNum.value, ledRearType.currentIndex,
                                       rearHbMode, rearHbPos, rearHbMin, rearHbMax)
                    : 0

                isPubmoteBle = (macAddress === "00:00:00:00:00:00");
                isPubmotePaired = (Number(tokens[46]) != -1);
                pubmoteMacAddress.text = !isPubmotePaired ? "MAC: Not Paired" : (isPubmoteBle ? "Connection: BLE" : "MAC: " + macAddress.toUpperCase());
                readConfig = true;
            } else if (str.startsWith("node-role ")) {
                nodeRole.currentIndex = Number(str.split(" ")[1])
            } else if (str.startsWith("msg")) {
                var msg = str.substring(4)
                VescIf.emitMessageDialog("Float Accessories", msg, false, false)
            } else if (str.startsWith("mqtt-cfg ")) {
                // Numeric MQTT fields (space-split). String fields arrive on
                // their own mqtt-* lines below so values with spaces survive.
                var mtok = str.split(" ")
                mqttEnabled.checked = Number(mtok[1])
                mqttQos.value = Number(mtok[2])
                mqttKeepalive.value = Number(mtok[3])
                mqttPublishRate.value = Number(mtok[4])
            } else if (str.startsWith("mqtt-uri ")) {
                mqttUri.text = str.substring(9)
            } else if (str.startsWith("mqtt-cid ")) {
                mqttClientId.text = str.substring(9)
            } else if (str.startsWith("mqtt-user ")) {
                mqttUser.text = str.substring(10)
            } else if (str.startsWith("mqtt-pass ")) {
                mqttPassword.text = str.substring(10)
            } else if (str.startsWith("mqtt-prefix ")) {
                mqttTopicPrefix.text = str.substring(12)
            } else if (str.startsWith("float-stats")) {
                var tokens = str.split(" ")

                // Float Package connection status
                floatPackageConnected = !!Number(tokens[1])
                if (floatPackageConnected) {
                    floatPackageLastStatusTime = 0
                }

                // Pubmote connection status
                pubmoteConnected = !!Number(tokens[2])
                pubmoteWifiChannel = Number(tokens[7])
                if (pubmoteConnected) {
                    pubmoteLastStatusTime = 0
                }

                if (!pubmoteConnected) {
                    pubmoteVersionStr = "Unknown";
                }

                // BMS connection status
                bmsConnected = Number(tokens[3])
                bmsStatusTemp = Number(tokens[4])
                bmsBatteryTypeVal = Number(tokens[5])
                bmsBatteryCyclesVal = Number(tokens[6])

                // Humidity Sensor Status
                lcmHum = parseFloat(tokens[8])
                lcmHumTemp = parseFloat(tokens[9])

                bmsHum = parseFloat(tokens[10])
                bmsHumTemp = parseFloat(tokens[11])

                loggerRunning = parseFloat(tokens[12])

                // GNSS status
                if (tokens.length > 16) {
                    gnssFix = !!Number(tokens[13])
                    gnssAge = parseFloat(tokens[14])
                    gnssHdop = parseFloat(tokens[15])
                    gnssSpeed = parseFloat(tokens[16])
                }

                // Update status flags
                lastStatusTime = 0  // Reset the timer when status is received
                if (floatPackageConnected) {
                    floatPackageLastStatusTime = 0
                } else {
                    floatPackageLastStatusTime = floatPackageLastStatusTime // Trigger binding re-evaluation
                }
                
                if (pubmoteConnected) {
                    pubmoteLastStatusTime = 0
                } else {
                    pubmoteLastStatusTime = pubmoteLastStatusTime // Trigger binding re-evaluation
                }

                statusTimeout = false
            } else if (str.startsWith("control")) {
                var tokens = str.split(" ")
                ledOn.checked = Number(tokens[1])
                ledHighbeamOn.checked = Number(tokens[2])
                ledBrightnessLoader.item.value = Number(tokens[3])
                ledBrightnessHighbeamLoader.item.value = parseFloat(Number(tokens[4]))
                ledBrightnessIdleLoader.item.value = Number(tokens[5])
                ledBrightnessStatusLoader.item.value = Number(tokens[6])
                bmsChargeState.checked = Number(tokens[7])
            } else if (str.startsWith("status Settings Read")) {
                sendCode(String.fromCharCode(102) + String.fromCharCode(1) + "(send-control)")
                var msg = str.substring(7)
                VescIf.emitStatusMessage(msg, true)
            } else if (str.startsWith("status")) {
                var msg = str.substring(7)
                VescIf.emitStatusMessage(msg, true)
            } else if (str.startsWith("pubmote-info")) {
                var tokens = str.split(" ");
                var newVersion = "unknown";
                if (tokens.length >= 2) {
                   var version = tokens[1].split(".");
                    if (version.length >= 3 && (version[0] || version[1] || version[2])) {
                        newVersion = tokens[1];
                    }
                }
                pubmoteVersionStr = newVersion;
            } else if (str.startsWith("pairing-status")) {
                var tokens = str.split(" ");
                pubmotePairingState = Number(tokens[1]);
            } else if (str.startsWith("input-state")) {
                var tokens = str.split(" ");
                pubmoteInputConnected = !!Number(tokens[1]);
                pubmoteInputJsy = parseFloat(tokens[2]);
                pubmoteInputJsx = parseFloat(tokens[3]);
                pubmoteInputBtC = !!Number(tokens[4]);
                pubmoteInputBtZ = !!Number(tokens[5]);
                pubmoteInputRev = !!Number(tokens[6]);
            }
        }
    }
}