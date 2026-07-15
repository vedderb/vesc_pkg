/*
    Copyright 2026 VESC project

    This file is part of the VESC firmware.

    The VESC firmware is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    The VESC firmware is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

import Vedder.vesc.commands 1.0
import Vedder.vesc.utility 1.0

Item {
    id: container
    anchors.fill: parent
    anchors.margins: 10

    property Commands mCommands: VescIf.commands()

    // The espled_strip.lisp script evaluates expressions sent as custom app data.
    function sendCode(str) {
        mCommands.sendCustomAppData(str + "\0")
    }

    // Throttled sends for live slider dragging: the first change goes out
    // immediately, further changes are coalesced per control at 20 Hz and
    // the final value is flushed on release. The strip itself smooths
    // brightness changes (ext-espled-fade).
    property var txPending: ({})

    function flushTx() {
        for (var k in txPending) {
            sendCode(txPending[k])
        }
        txPending = ({})
    }

    function queueSend(key, str) {
        txPending[key] = str
        if (!txTimer.running) {
            flushTx()
            txTimer.start()
        }
    }

    Timer {
        id: txTimer
        interval: 50
        repeat: true
        onTriggered: {
            if (Object.keys(txPending).length > 0) {
                flushTx()
            } else {
                stop()
            }
        }
    }

    // Slider with a value bubble over the handle while dragging, updating
    // the UI immediately and emitting through the throttle.
    Component {
        id: customValueSlider

        Slider {
            id: slider
            from: 0
            to: 100
            value: 50
            stepSize: 1
            property bool hideBubble: true
            signal interactionReleased()

            onPressedChanged: {
                if (!pressed) {
                    interactionReleased()
                }
            }
            property var formatValue: function(val) {
                return val.toFixed(0)
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

    function packedColor() {
        var r = rLoader.item ? rLoader.item.value : 0
        var g = gLoader.item ? gLoader.item.value : 0
        var b = bLoader.item ? bLoader.item.value : 0
        return (Math.round(r) << 16) | (Math.round(g) << 8) | Math.round(b)
    }

    function sendColor() {
        queueSend("color", "(ext-espled-seg-col 0 " + packedColor() + ")")
    }

    // Wire a loaded customValueSlider to the throttle: live queued sends on
    // any change and a flush on release.
    function hookSlider(item, key, makeCmd) {
        item.valueChanged.connect(function() {
            queueSend(key, makeCmd(item.value))
        })
        item.interactionReleased.connect(function() {
            queueSend(key, makeCmd(item.value))
        })
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: parent.width
            spacing: 8

            GroupBox {
                title: "Strip Setup"
                Layout.fillWidth: true

                GridLayout {
                    anchors.fill: parent
                    columns: 2

                    Label { text: "Pin" }
                    SpinBox {
                        id: pinBox
                        from: 0; to: 48; value: 20
                        editable: true
                        Layout.fillWidth: true
                    }

                    Label { text: "LEDs" }
                    SpinBox {
                        id: lenBox
                        from: 1; to: 512; value: 30
                        editable: true
                        Layout.fillWidth: true
                    }

                    Label { text: "Type" }
                    ComboBox {
                        id: typeBox
                        model: ["GRB (WS2812)", "RGB", "GRBW (SK6812 RGBW)", "RGBW"]
                        Layout.fillWidth: true
                    }

                    Label { text: "Timing" }
                    ComboBox {
                        id: timingBox
                        model: ["Universal", "WS2812B", "WS2815", "SK6812", "SK6815"]
                        Layout.fillWidth: true
                    }

                    Button {
                        text: "Start"
                        Layout.fillWidth: true
                        onClicked: sendCode("(espled-setup " + pinBox.value + " " +
                                            lenBox.value + " " + typeBox.currentIndex + " " +
                                            timingBox.currentIndex + ")")
                    }
                    Button {
                        text: "Stop"
                        Layout.fillWidth: true
                        onClicked: sendCode("(ext-espled-deinit)")
                    }
                }
            }

            GroupBox {
                title: "Effect"
                Layout.fillWidth: true

                GridLayout {
                    anchors.fill: parent
                    columns: 2

                    Label { text: "Effect" }
                    ComboBox {
                        id: fxBox
                        model: ["Solid", "Breathe", "Chase", "Rainbow", "Sparkle", "Comet", "Gauge", "Strobe", "Larson", "Felony", "Theater", "Wipe", "Waves", "Candle", "Heartbeat"]
                        Layout.fillWidth: true
                        onActivated: sendCode("(ext-espled-seg-fx 0 " + currentIndex + ")")
                    }

                    Label { text: "Palette" }
                    ComboBox {
                        id: palBox
                        model: ["Spectrum", "Fire", "Ocean", "Neon", "Ember", "Traffic", "B&W Flash", "Police Blue", "Sunset", "Lava", "Aurora", "Forest", "Party", "Ice", "Halloween", "Christmas", "Pastel", "Sakura"]
                        Layout.fillWidth: true
                        // Color 0 = "take color from the palette", so clear
                        // the color when a palette is picked.
                        onActivated: {
                            sendCode("(ext-espled-seg-pal 0 " + currentIndex + ")")
                            sendCode("(ext-espled-seg-col 0 0)")
                        }
                    }

                    Label { text: "" }
                    Label {
                        text: "Palettes color the effect while no color is set; picking a color overrides them. Rainbow always draws the palette."
                        font.italic: true
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Label { text: "Speed" }
                    Loader {
                        id: spdLoader
                        sourceComponent: customValueSlider
                        Layout.fillWidth: true
                        onLoaded: {
                            item.from = 1; item.to = 255; item.value = 32
                            hookSlider(item, "spd", function(v) {
                                return "(ext-espled-seg-spd 0 " + v.toFixed(0) + ")"
                            })
                        }
                    }

                    Label { text: "Size" }
                    Loader {
                        id: sizeLoader
                        sourceComponent: customValueSlider
                        Layout.fillWidth: true
                        onLoaded: {
                            item.from = 1; item.to = 64; item.value = 8
                            hookSlider(item, "size", function(v) {
                                return "(ext-espled-seg-size 0 " + v.toFixed(0) + ")"
                            })
                        }
                    }

                    Label { text: "Level" }
                    Loader {
                        id: lvlLoader
                        sourceComponent: customValueSlider
                        Layout.fillWidth: true
                        onLoaded: {
                            item.from = 0; item.to = 255; item.value = 255
                            hookSlider(item, "level", function(v) {
                                return "(ext-espled-seg-level 0 " + v.toFixed(0) + ")"
                            })
                        }
                    }
                }
            }

            GroupBox {
                title: "Color"
                Layout.fillWidth: true

                ColumnLayout {
                    anchors.fill: parent

                    Rectangle {
                        Layout.fillWidth: true
                        height: 24
                        radius: 4
                        color: {
                            var r = rLoader.item ? rLoader.item.value : 0
                            var g = gLoader.item ? gLoader.item.value : 0
                            var b = bLoader.item ? bLoader.item.value : 0
                            return Qt.rgba(r / 255, g / 255, b / 255, 1)
                        }
                        border.color: "#808080"
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2

                        Label { text: "R" }
                        Loader {
                            id: rLoader
                            sourceComponent: customValueSlider
                            Layout.fillWidth: true
                            onLoaded: {
                                item.from = 0; item.to = 255; item.value = 255
                                item.valueChanged.connect(sendColor)
                                item.interactionReleased.connect(sendColor)
                            }
                        }

                        Label { text: "G" }
                        Loader {
                            id: gLoader
                            sourceComponent: customValueSlider
                            Layout.fillWidth: true
                            onLoaded: {
                                item.from = 0; item.to = 255; item.value = 0
                                item.valueChanged.connect(sendColor)
                                item.interactionReleased.connect(sendColor)
                            }
                        }

                        Label { text: "B" }
                        Loader {
                            id: bLoader
                            sourceComponent: customValueSlider
                            Layout.fillWidth: true
                            onLoaded: {
                                item.from = 0; item.to = 255; item.value = 0
                                item.valueChanged.connect(sendColor)
                                item.interactionReleased.connect(sendColor)
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        // These switch every segment to a solid color
                        // (ext-espled-col-rgb sets the effect too), so sync
                        // the effect combo to match.
                        Button {
                            text: "Red"
                            Layout.fillWidth: true
                            onClicked: {
                                sendCode("(ext-espled-col-rgb 255 0 0)")
                                fxBox.currentIndex = 0
                            }
                        }
                        Button {
                            text: "Green"
                            Layout.fillWidth: true
                            onClicked: {
                                sendCode("(ext-espled-col-rgb 0 255 0)")
                                fxBox.currentIndex = 0
                            }
                        }
                        Button {
                            text: "Blue"
                            Layout.fillWidth: true
                            onClicked: {
                                sendCode("(ext-espled-col-rgb 0 0 255)")
                                fxBox.currentIndex = 0
                            }
                        }
                        Button {
                            text: "White"
                            Layout.fillWidth: true
                            onClicked: {
                                sendCode("(ext-espled-col-rgb 255 255 255)")
                                fxBox.currentIndex = 0
                            }
                        }
                        Button {
                            text: "Off"
                            Layout.fillWidth: true
                            onClicked: sendCode("(ext-espled-col 0)")
                        }
                    }
                }
            }

            GroupBox {
                title: "Global"
                Layout.fillWidth: true

                GridLayout {
                    anchors.fill: parent
                    columns: 2

                    Label { text: "Brightness" }
                    Loader {
                        id: briLoader
                        sourceComponent: customValueSlider
                        Layout.fillWidth: true
                        onLoaded: {
                            item.from = 0; item.to = 255; item.value = 255
                            hookSlider(item, "bri", function(v) {
                                return "(ext-espled-bri " + v.toFixed(0) + ")"
                            })
                        }
                    }

                    Label { text: "Fade" }
                    Loader {
                        id: fadeLoader
                        sourceComponent: customValueSlider
                        Layout.fillWidth: true
                        onLoaded: {
                            item.from = 0; item.to = 32; item.value = 15
                            hookSlider(item, "fade", function(v) {
                                return "(ext-espled-fade " + v.toFixed(0) + ")"
                            })
                        }
                    }

                    Label { text: "Auto white" }
                    Switch {
                        id: awSwitch
                        onToggled: sendCode("(ext-espled-auto-white " + (checked ? 1 : 0) + ")")
                    }

                    Label { text: "Current limit (mA)" }
                    SpinBox {
                        id: abBox
                        from: 0; to: 20000; value: 0
                        stepSize: 100
                        editable: true
                        Layout.fillWidth: true
                        onValueModified: sendCode("(ext-espled-ablimit " + value + ")")
                    }
                }
            }
        }
    }
}
