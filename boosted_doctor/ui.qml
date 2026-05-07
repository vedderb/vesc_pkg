import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.3
import Vedder.vesc.commands 1.0
import Vedder.vesc.utility 1.0

Rectangle {
    id: container
    anchors.fill: parent
    color: colorBg

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
    property int valBtnState: 0
    property var cellVoltages: []

    readonly property color colorRed: "#FF5252"
    readonly property color colorGreen: "#66BB6A"
    readonly property color colorAmber: "#FFC107"
    readonly property color colorBoostedOrange: "#F0401E"
    readonly property color colorBg: "#1D1D1D"
    readonly property color colorPanel: "#2D2D2D"
    readonly property color colorWhite: "#ffffff"
    readonly property color colorText: "#ffffff"
    readonly property color colorLightText: "#aaaaaa"

    
    property var lastUpdateTime: new Date()
    property string timeSinceUpdate: "0"
    property string statusText: "Status: connecting..."
    property color statusColor: colorRed

    function getBatTypeString(type) {
        if (type === 1) return "SRB"
        if (type === 2) return "XRB"
        if (type === 3) return "Rev"
        return "Unknown"
    }

    function getBtnStateString(s) {
        if (s === 0x00) return "none"
        if (s === 0x01) return "1x press"
        if (s === 0x02) return "2x press"
        if (s === 0x03) return "3x press"
        if (s === 0x04) return "4x press"
        if (s === 0x05) return "5x press"
        if (s === 0x06) return "pressed"
        if (s === 0x07) return "held <1s"
        if (s === 0x08) return "held <2s"
        if (s === 0x09) return "held >2s"
        if (s === 0x0A) return "was held <1.5s"
        if (s === 0x0B) return "was held <2s"
        if (s === 0x0C) return "was held >2s"
        return "0x" + s.toString(16).toUpperCase()
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
        interval: 200
        running: true
        repeat: true
        onTriggered: {
            var diff = (new Date() - lastUpdateTime) / 1000.0;
            timeSinceUpdate = diff.toFixed(0);

            if (valBtnState > 0) {
                statusText = "Button: " + getBtnStateString(valBtnState);
                statusColor = colorWhite;
            } else if (diff < 1.5) {
                if (connected) {
                    statusText = "Status: connected";
                    statusColor = colorWhite;
                } else {
                    statusText = "Status: disconnected";
                    statusColor = colorRed;
                }
            } else {
                statusText = "Status: connecting... (" + diff.toFixed(0) + "s)";
                statusColor = colorAmber;
            }
        }
    }

    Timer {
        interval: 250
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
        anchors.margins: 10
        height: 60

        RowLayout {
            anchors.centerIn: parent
            spacing: 15

            Image {
                source: "data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTMyLjYxMSIgaGVpZ2h0PSIxMzEiIHZpZXdCb3g9IjAgMCAxMzIuNjExIDEzMSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48cGF0aCBzdHlsZT0iZmlsbDojZjA0MDFlIiBkPSJNNjUuNzQxIDM5MC45MThjLTMuNDEtMi4wNjMtNi4yNjQtNC4yLTYuMzQtNC43NS0uMTQxLTEuMDExIDEyLjY0LTguOTU2IDIzLjY4LTE0LjcyIDUuMDE0LTIuNjE4IDcuNDE3LTMuMjA1IDE0LjYzMS0zLjU3MyA1LjQwMi0uMjc2IDEwLjA3OS4wMyAxMi41LjgxNSAzLjA1Mi45OTEgMjEuMTY1IDEwLjg0MyAyMy4zNTQgMTIuNzAyLjg2My43MzMtNC4zNSA0LjE1NC05LjYxMyA2LjMxbC01LjEyNyAyLjA5OC00Ljg5My0zLjAxYy02LjU2LTQuMDM4LTEzLjI0NC01LjQ5LTE4LjY3Mi00LjA2LTIuMy42MDUtOC4zNjggMy41NC0xMy40ODcgNi41MnMtOS40MjQgNS40MTgtOS41NjkgNS40MThjLS4xNDQgMC0zLjA1My0xLjY4OC02LjQ2NC0zLjc1bTcyLjg0LTE0Ljk0NWMtMzMuMzQzLTIwLjIzMy00Mi45NjItMjAuOTU4LTY5LjkwNy01LjI3NGwtMTAuNDA3IDYuMDU3LTMuMTEtMy4wMTRjLTEuNzEtMS42NTgtMy44NzEtNC4zMDQtNC44MDItNS44OGwtMS42OTItMi44NjQgMTIuMDIyLTYuODA3YzE1LjEyMy04LjU2MyAyMS42NTctMTEuMjAzIDMxLjI2NC0xMi42MzEgOC44Ny0xLjMyIDE5LjEzMi0uMTc0IDI3LjkzMiAzLjExOSA2LjI1NiAyLjM0IDM1LjcgMTkuNjA1IDM1LjcgMjAuOTMzIDAgMS4yMS03Ljg3NyAxMS4wNzItOC43NzQgMTAuOTg0LS40LS4wNC00LjEwMS0yLjEyLTguMjI2LTQuNjIzTTM2Ljg0IDM1Ny45N2MtMy44OTEtOS4xOTktNC43NDUtNy45MDQgMTEuNDA4LTE3LjMwMSAxNy43NDgtMTAuMzI2IDIyLjkyNy0xNC43NzggMjcuNTgtMjMuNzE1IDQuNjQ2LTguOTI1IDUuNzUyLTE0Ljc0NCA1Ljc1Mi0zMC4yODh2LTEyLjkwM2wzLjc1LTEuMDQyYzIuMDYyLS41NzMgNS40OTQtMS4wNDQgNy42MjYtMS4wNDdsMy44NzUtLjAwNi0uNTEyIDE3LjI1Yy0uNTcgMTkuMTQ2LTEuNTM3IDIzLjY0OC03LjU3NiAzNS4yNS01LjcgMTAuOTUyLTEzLjk1NyAxOC40MDgtMzEuODI3IDI4Ljc0LTguMzE0IDQuODA2LTE1Ljc3NiA4Ljk5MS0xNi41ODEgOS4zLTEuMDMuMzk1LTIuMDctLjg2Ni0zLjQ5Ni00LjIzOXptMTAxLjcwNC03LjI4Yy0xOS4xODItMTEuMzY1LTI3LjMtMjAuNDU3LTMzLjA1Ni0zNy4wMjEtMi4wMDYtNS43NzEtMi4zMDgtOC45NC0yLjY5NC0yOC4yNWwtLjQzNS0yMS43NSAyLjM2LjA5NmMxLjI5OS4wNTIgNC42MS42MTcgNy4zNiAxLjI1NGw1IDEuMTYuNjA0IDE5LjQ5NGMuMzMyIDEwLjcyMyAxLjA4MiAyMC45MzggMS42NjcgMjIuNyAyLjA2MiA2LjIxMyA3LjM5NiAxNS4wNDMgMTEuNTUgMTkuMTE5IDMuNDA2IDMuMzQzIDIzLjM4IDE2LjI0MyAyNy4wMzggMTcuNDYzIDEuMzE5LjQ0LTMuMjU2IDEzLjcxNC00LjcyNiAxMy43MTQtLjY2MiAwLTcuMjYzLTMuNTktMTQuNjY4LTcuOTc4bTE0LjAzNi0xNy41MzhjLTE0LjctOC43MDctMjEuNzMtMTUuNDczLTI0LjkxLTIzLjk3LTEuNzI2LTQuNjE0LTIuMDktNy44NDktMi4wOS0xOC41NTEgMC03LjEzLjM5OC0xMi45NjIuODg2LTEyLjk2Mi40ODcgMCAzLjYzNyAxLjgzNyA3IDQuMDgyIDYuMDg4IDQuMDY2IDYuMTE0IDQuMTAzIDYuMTE0IDguOTUxIDAgMTMuNzU3IDMuOTIgMTkuNzQ2IDE4LjUgMjguMjY2bDkgNS4yNTl2Ny44ODdjMCA0LjQwNy0uNDQyIDguMDEtMSA4LjE2NS0uNTUuMTUyLTYuNjI1LTMuMDU1LTEzLjUtNy4xMjdtLTExMy0zLjkzMnYtOC4zOGw3LjI1LTQuODM2YzEwLjIxLTYuODEgMTEuOTQyLTEwLjUxOCAxMi42OS0yNy4xNjNsLjU2LTEyLjQ4IDYtMy4zMzVjMy4zLTEuODMzIDYuMzM3LTMuMzM5IDYuNzUtMy4zNDYuNDEyLS4wMDcuNzUgNy42MjIuNzUgMTYuOTUxIDAgMTQuNzA3LS4yNzYgMTcuNjk4LTIuMDcxIDIyLjQ5Ny0yLjk0OSA3Ljg4MS05Ljg5IDE0Ljk2OC0yMS44MjIgMjIuMjhMMzkuNTgxIDMzNy42eiIgdHJhbnNmb3JtPSJ0cmFuc2xhdGUoLTM0LjQ3IC0yNjMuNjY4KSIvPjwvc3ZnPg=="
                sourceSize.width: 40
                sourceSize.height: 40
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
            }

            Text {
                color: colorText
                font.pointSize: 22
                font.bold: true
                text: "Boosted Doctor"
            }
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
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.horizontal.interactive: false
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        ColumnLayout {
            width: scrollView.availableWidth - 20
            x: 10
            spacing: 20

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                color: {
                    var base = connected ? colorPanel : colorPanel; // Always panel color
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
                Layout.maximumWidth: parent.width // Force wrap
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
                                var p = (v - 3.0) / (3.95 - 3.0);
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
        anchors.margins: 10
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
                if (tokens.length > 11) {
                    valBtnState = Number(tokens[11]);
                }
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
