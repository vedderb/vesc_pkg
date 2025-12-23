import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.3
import Vedder.vesc.commands 1.0
import Vedder.vesc.utility 1.0

Item {
    id: container
    anchors.fill: parent
    anchors.margins: 10

    property Commands mCommands: VescIf.commands()
    property bool connected: false
    property int soc: 0
    property double packVolt: 0.0
    property int batType: 0
    property double minCellVolt: 0.0
    property double maxCellVolt: 0.0
    property int verMajor: 0
    property int verMinor: 0
    property int verPatch: 0
    property string fwVersion: verMajor + "." + verMinor + "." + verPatch
    readonly property int commGetStatus: 1
    readonly property int commGetCells: 2
    readonly property int commPfailReset: 3
    property double amps: 0.0
    property var cellVoltages: []

    readonly property color colorRed: "#F44336"
    readonly property color colorGreen: "#4CAF50"
    readonly property color colorAmber: "#FFC107"
    readonly property color colorWhite: "#ffffff"
    readonly property color colorText: "#ffffff"
    readonly property color colorLightText: "#aaaaaa"
    
    property var lastUpdateTime: new Date()
    property string timeSinceUpdate: "0"
    property string statusText: "Status: Connecting..."
    property color statusColor: colorRed

    function getBatTypeString(type) {
        if (type === 1) return "SRB"
        if (type === 2) return "XRB"
        if (type === 3) return "Rev"
        return "Unknown"
    }

    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            var buffer = new ArrayBuffer(1);
            var dv = new DataView(buffer);
            var ind = 0;
            dv.setUint8(ind, commGetStatus);
            ind += 1;
            mCommands.sendCustomAppData(buffer);
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            var diff = (new Date() - lastUpdateTime) / 1000.0;
            timeSinceUpdate = diff.toFixed(0);

            if (diff < 1.0) {
                statusText = "Status: connected";
                statusColor = colorWhite;
            } else {
                statusText = "Status: connecting (" + diff.toFixed(0) + "s)";
                statusColor = colorAmber;
            }
        }
    }

    Timer {
        interval: 500
        running: connected
        repeat: true
        onTriggered: {
            var buffer = new ArrayBuffer(1);
            var dv = new DataView(buffer);
            dv.setUint8(0, commGetCells);
            mCommands.sendCustomAppData(buffer);
        }
    }

    // --- Header ---
    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 60

        Text {
            anchors.centerIn: parent
            color: colorText
            font.pointSize: 20
            font.bold: true
            text: "Boosted Battery Doctor"
        }
    }

    // --- Content ---
    ScrollView {
        id: scrollView
        anchors.top: header.bottom
        anchors.bottom: footer.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 0
        clip: true

        // Ensure the content fills the width
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        ColumnLayout {
            width: scrollView.availableWidth
            spacing: 20

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                color: {
                    var base = connected ? colorGreen : colorRed;
                    return statusMouseArea.pressed ? Qt.darker(base, 1.2) : base;
                }
                radius: 5
                
                Text {
                    anchors.centerIn: parent
                    color: colorWhite
                    font.pointSize: 18
                    text: connected ? (getBatTypeString(batType) + " " + fwVersion) : "No battery detected"
                }

                Text {
                    text: "▼"
                    visible: connected
                    color: "#FFFFFF"
                    font.pixelSize: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 15
                    anchors.verticalCenter: parent.verticalCenter
                }

                MouseArea {
                    id: statusMouseArea
                    anchors.fill: parent
                    enabled: connected
                    onClicked: statusMenu.visible ? statusMenu.close() : statusMenu.open()
                }

                Menu {
                    id: statusMenu
                    y: parent.height
                    width: parent.width // Match width of status bar
                    
                    MenuItem {
                        text: "Clear RLOD"
                        onTriggered: {
                            var buffer = new ArrayBuffer(1);
                            var dv = new DataView(buffer);
                            var ind = 0;
                            dv.setUint8(ind, commPfailReset);
                            ind += 1;
                            mCommands.sendCustomAppData(buffer);
                        }
                    }
                }
            }

            Text {
                visible: !connected
                Layout.fillWidth: true
                text: "Battery is either disconnected or in deep sleep. Press the power button to wake and connect automatically.\n\nPlease ensure the baud rate of all VESC devices are set to 250k."
                color: colorLightText
                font.pointSize: 14
                horizontalAlignment: Text.AlignHLeft
                wrapMode: Text.WordWrap
            }

            Text {
                visible: connected
                text: `State of Charge: ${soc}%`
                color: soc < 20 ? colorRed : (soc < 50 ? colorAmber : colorGreen)
                font.pointSize: 16
                Layout.alignment: Qt.AlignHCenter
            }

            GridLayout {
                visible: connected
                columns: 2
                Layout.fillWidth: true
                rowSpacing: 10
                columnSpacing: 10

                Text {
                    text: "Voltage:"
                    color: colorLightText
                    font.pointSize: 16
                }
                Text {
                    text: packVolt.toFixed(2) + "V"
                    color: colorText
                    font.pointSize: 16
                }
                Text {
                    text: "Cells:"
                    color: colorLightText
                    font.pointSize: 16
                }
                Text {
                    text: minCellVolt.toFixed(3) + "V - " + maxCellVolt.toFixed(3) + "V  |  " + ((maxCellVolt - minCellVolt) * 1000).toFixed(0) + "ΔmV"
                    color: (maxCellVolt - minCellVolt) > 0.2 ? colorRed : ((maxCellVolt - minCellVolt) > 0.1 ? colorAmber : colorText)
                    font.pointSize: 16
                }


                Text {
                    text: "State:"
                    color: colorLightText
                    font.pointSize: 16
                }
                Text {
                    text: (amps > 0.1 ? "Charging" : (amps < -0.1 ? "Discharging" : "Idle")) + 
                          "  |  " + Math.abs(amps).toFixed(2) + "A"
                    color: colorText 
                    font.pointSize: 16
                }
            }

            GridLayout {
                visible: connected
                columns: 2
                Layout.fillWidth: true
                rowSpacing: 10
                columnSpacing: 10

                Repeater {
                    model: cellVoltages
                    delegate: ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        
                        Text {
                            text: "Cell " + (index + 1)
                            color: colorLightText
                            font.pointSize: 12
                        }

                        ProgressBar {
                            Layout.fillWidth: true
                            from: 0.0
                            to: 1.0
                            value: {
                                var v = modelData;
                                var p = (v - 2.7) / (4.2 - 2.7);
                                return Math.max(0.0, Math.min(1.0, p));
                            }
                            
                            background: Rectangle {
                                implicitWidth: 200
                                implicitHeight: 20
                                color: "#444"
                                radius: 3
                            }

                            contentItem: Item {
                                implicitWidth: 200
                                implicitHeight: 10

                                Rectangle {
                                    width: parent.parent.visualPosition * parent.width
                                    height: parent.height
                                    radius: 2
                                    color: {
                                        var v = modelData;
                                        if (v < 3.0) return colorRed;
                                        if (v < 3.6) return colorAmber;
                                        return colorGreen;
                                    }
                                }
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.toFixed(3) + "V"
                                    color: colorText
                                    font.pixelSize: 12
                                    font.bold: true
                                    style: Text.Outline
                                    styleColor: "#000"
                                }
                            }
                        }
                    }
                }
            }

            // Spacer to ensure content isn't flush with bottom if short
            Item { height: 20 }
        }
    }

    // --- Footer ---
    Item {
        id: footer
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 30 // Increased height for better spacing

        Text {
            anchors.centerIn: parent
            text: statusText
            color: statusColor
            font.pointSize: 12
        }
    }

    Connections {
        target: mCommands
        
        function onCustomAppDataReceived(data) {
            var str = data.toString();
            if (str.startsWith("data:status ")) {
                lastUpdateTime = new Date();
                var tokens = str.split(" ");
                // Order: <connected> <type> <vMaj> <vMin> <vPatch> <volt> <soc> <min> <max> <amps>
                connected = Number(tokens[1]) > 0;
                batType = Number(tokens[2]);
                verMajor = Number(tokens[3]);
                verMinor = Number(tokens[4]);
                verPatch = Number(tokens[5]);
                packVolt = Number(tokens[6]);
                soc = Number(tokens[7]);
                minCellVolt = Number(tokens[8]);
                maxCellVolt = Number(tokens[9]);
                maxCellVolt = Number(tokens[9]);
                amps = Number(tokens[10]);
            }
            else if (str.startsWith("data:cells ")) {
                var tokens = str.split(" ");
                // data:cells v1 v2 ...
                // Slice off the first token ("data:cells")
                var newCells = [];
                for (var i = 1; i < tokens.length; i++) {
                    if (tokens[i].length > 0) {
                        // incoming is mV integer, convert to Volts
                        newCells.push(Number(tokens[i]) / 1000.0);
                    }
                }
                cellVoltages = newCells;
            }
        }
    }
}
