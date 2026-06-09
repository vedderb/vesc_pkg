import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.3

import Vedder.vesc.commands 1.0
import Vedder.vesc.utility 1.0

Item {
    id: root
    anchors.fill: parent
    anchors.margins: 8

    property Commands mCommands: VescIf.commands()
    property bool confLoaded: false

    // Live telemetry (from "rt" frames)
    property real rtPitch: 0.0
    property real rtRate: 0.0
    property bool armed: false
    property real rtOut: 0.0
    property real rtRider: 0.0
    property string statusText: "Connecting to script..."
    readonly property color brandColor: "#FF7A18"

    // ---- Reusable labeled slider ----
    component ParamSlider: ColumnLayout {
        property string name: ""
        property string units: ""
        property int decimals: 2
        property alias value: slider.value
        property alias from: slider.from
        property alias to: slider.to
        property alias stepSize: slider.stepSize
        Layout.fillWidth: true
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: name
                color: Utility.getAppHexColor("lightText")
                font.pixelSize: 14
                Layout.fillWidth: true
            }
            Text {
                text: slider.value.toFixed(decimals) + units
                color: Utility.getAppHexColor("lightText")
                font.pixelSize: 14
                font.bold: true
            }
        }
        Slider {
            id: slider
            Layout.fillWidth: true
        }
    }

    // ---- Comm helpers ----
    function sendCmd(c) {
        var buffer = new ArrayBuffer(1)
        var dv = new DataView(buffer)
        dv.setUint8(0, c)
        mCommands.sendCustomAppData(buffer)
    }

    function writeConfig() {
        var buffer = new ArrayBuffer(25)
        var dv = new DataView(buffer)
        var i = 0
        dv.setUint8(i, 2); i += 1
        dv.setFloat32(i, pStart.value); i += 4
        dv.setFloat32(i, pEnd.value); i += 4
        dv.setFloat32(i, pDamp.value); i += 4
        dv.setFloat32(i, pPull.value); i += 4
        dv.setFloat32(i, pLpf.value); i += 4
        dv.setFloat32(i, cbInvert.checked ? -1.0 : 1.0); i += 4
        mCommands.sendCustomAppData(buffer)
        statusText = "Written + saved to device"
    }

    Component.onCompleted: sendCmd(1)

    // Keep asking for the config until the script answers.
    Timer {
        interval: 1000
        running: !confLoaded
        repeat: true
        onTriggered: sendCmd(1)
    }

    Connections {
        target: mCommands
        function onCustomAppDataReceived(data) {
            var str = data.toString()
            var t = str.split(" ")
            if (t[0] === "conf") {
                pStart.value = Number(t[1])
                pEnd.value = Number(t[2])
                pDamp.value = Number(t[3])
                pPull.value = Number(t[4])
                pLpf.value = Number(t[5])
                cbInvert.checked = Number(t[6]) < 0
                armed = Number(t[7]) === 1
                confLoaded = true
                statusText = "Config loaded from device"
            } else if (t[0] === "rt") {
                rtPitch = Number(t[1])
                rtRate = Number(t[2])
                armed = Number(t[3]) === 1
                rtOut = Number(t[4])
                rtRider = Number(t[5])
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                text: "<a href='https://3shulmotors.com' style='text-decoration:none;'>3ShulMotors</a>"
                textFormat: Text.RichText
                linkColor: brandColor
                font.pixelSize: 13
                font.bold: true
                onLinkActivated: function(url) { Qt.openUrlExternally(url) }
            }
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Wheelie Assist"
                    color: Utility.getAppHexColor("lightText")
                    font.pixelSize: 22
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "v1.0.0"
                    color: Utility.getAppHexColor("lightText")
                    font.pixelSize: 12
                    Layout.alignment: Qt.AlignBottom
                }
            }
        }

        // ---- Live telemetry panel ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: telemCol.implicitHeight + 16
            radius: 6
            color: "#2b2b2b"
            border.width: 1
            border.color: armed ? "#66BB6A" : "#FF5252"

            ColumnLayout {
                id: telemCol
                anchors.fill: parent
                anchors.margins: 8
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Live"
                        color: Utility.getAppHexColor("lightText")
                        font.pixelSize: 14
                        font.bold: true
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        radius: 4
                        color: armed ? "#66BB6A" : "#FF5252"
                        Layout.preferredWidth: lblArm.implicitWidth + 16
                        Layout.preferredHeight: lblArm.implicitHeight + 6
                        Text {
                            id: lblArm
                            anchors.centerIn: parent
                            text: armed ? "ARMED" : "DISARMED"
                            color: "#ffffff"
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }
                }
                Text {
                    color: Utility.getAppHexColor("lightText")
                    font.family: "DejaVu Sans Mono"
                    font.pixelSize: 14
                    text: "pitch  : " + rtPitch.toFixed(1) + "°   rate: " + rtRate.toFixed(1) + "°/s"
                }
                Text {
                    color: Utility.getAppHexColor("lightText")
                    font.family: "DejaVu Sans Mono"
                    font.pixelSize: 14
                    text: "output : " + (rtOut * 100).toFixed(1) + "%   throttle: " + (rtRider * 100).toFixed(0) + "%"
                }
            }
        }

        // ---- Tunables ----
        ScrollView {
            id: tuneScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: tuneScroll.availableWidth
                spacing: 12

                ParamSlider {
                    id: pStart
                    name: "Throttle fade start"
                    units: "°"; decimals: 1
                    from: 0; to: 60; stepSize: 0.5; value: 25
                }
                ParamSlider {
                    id: pEnd
                    name: "Balance ceiling (hard cap)"
                    units: "°"; decimals: 1
                    from: 10; to: 75; stepSize: 0.5; value: 45
                }
                ParamSlider {
                    id: pDamp
                    name: "Pitch-rate damping"
                    decimals: 4
                    from: 0; to: 0.1; stepSize: 0.001; value: 0.01
                }
                ParamSlider {
                    id: pPull
                    name: "Max pull-down current"
                    decimals: 2
                    from: 0; to: 1.0; stepSize: 0.01; value: 0.6
                }
                ParamSlider {
                    id: pLpf
                    name: "Gyro low-pass (alpha)"
                    decimals: 2
                    from: 0.02; to: 1.0; stepSize: 0.01; value: 0.2
                }
                CheckBox {
                    id: cbInvert
                    text: "Invert pitch sign (IMU mounted reversed)"
                    contentItem: Text {
                        text: cbInvert.text
                        color: Utility.getAppHexColor("lightText")
                        font.pixelSize: 14
                        leftPadding: cbInvert.indicator.width + 6
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: "#FFC107"
                    font.pixelSize: 12
                    text: "Test on a stand first. Reverse pull-down needs l_min_erpm < 0 in the motor config."
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Utility.getAppHexColor("lightText")
                    font.pixelSize: 11
                    text: "Tip: adjust these on the fly with a 3ShulMotors smart display, or right here in the app."
                }
            }
        }

        // ---- Actions ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Button {
                text: "Read"
                Layout.fillWidth: true
                onClicked: sendCmd(1)
            }
            Button {
                text: "Toggle Arm"
                Layout.fillWidth: true
                onClicked: sendCmd(3)
            }
            Button {
                text: "Write && Save"
                Layout.fillWidth: true
                onClicked: writeConfig()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: statusText
                color: Utility.getAppHexColor("lightText")
                font.pixelSize: 12
            }
            Text {
                text: "Developed by 3ShulMotors"
                color: brandColor
                font.pixelSize: 12
                font.bold: true
            }
        }
    }
}
