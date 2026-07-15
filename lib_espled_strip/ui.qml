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

// Example UI for lib_espled_strip. Each strip is one segment on its own pin;
// the firmware pools RMT channels behind the pins, so several strips run at
// once. Strips are managed as tabs that can be added and removed at runtime.
//
// The QML is the source of truth: ext-espled-seg-def resets a segment's
// runtime state, so any structural change (add / remove / re-define) rebuilds
// every segment and then replays each strip's non-default settings. Effect
// and colour tweaks on an existing strip are sent live as single commands.
//
// Strips are held in the `strips` JS array. Add/remove reassign the array so
// the tab delegates fully rebuild (correct indices and values); live edits
// mutate the array in place, so sliders stay responsive without a rebuild.

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

    // Segment defaults set by ext-espled-seg-def. Replays skip values equal
    // to these, keeping the burst after a rebuild small.
    readonly property int defFx: 0
    readonly property int defPal: 0
    readonly property int defSpeed: 32
    readonly property int defSize: 8
    readonly property int defLevel: 255
    readonly property int defBri: 255

    // One object per strip; array index == segment index on the device.
    property var strips: []

    // ---- Comms -----------------------------------------------------------

    // The espled_strip.lisp script evaluates expressions sent as custom app
    // data. Each call is one lisp form beginning with '(' (the script only
    // evaluates data that starts with a parenthesis).
    function sendCode(str) {
        mCommands.sendCustomAppData(str + "\0")
    }

    // Throttled sends for live slider dragging: the first change goes out
    // immediately, further changes are coalesced per control key at 20 Hz and
    // the final value flushed on release. The strip smooths brightness itself.
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

    function packColor(r, g, b) {
        return (Math.round(r) << 16) | (Math.round(g) << 8) | Math.round(b)
    }

    // ---- Strip management ------------------------------------------------

    function makeStrip(pin, len, type, timing) {
        return {
            pin: pin, len: len, ledType: type, timing: timing,
            fx: defFx, pal: defPal,
            r: 255, g: 0, b: 0,
            speed: defSpeed, size: defSize, level: defLevel, bri: defBri
        }
    }

    // Called from the Add dialog once pin / length / type / timing are chosen,
    // so a strip is only created (and init'd) on the pin the user picked -
    // never on a placeholder pin.
    function addStripFrom(pin, len, type, timing) {
        var arr = strips.slice()
        arr.push(makeStrip(pin, len, type, timing))
        strips = arr            // reassign -> tab delegates rebuild
        applyStructure()
        tabBar.currentIndex = strips.length - 1
    }

    function removeStrip(idx) {
        if (idx < 0 || idx >= strips.length) {
            return
        }
        var arr = strips.slice()
        arr.splice(idx, 1)
        strips = arr
        if (tabBar.currentIndex > strips.length) {
            tabBar.currentIndex = strips.length // land on Global
        }
        applyStructure()
    }

    // Rebuild the strips. The structure (deinit + every seg-def + init) goes
    // in ONE (progn ...) form so it is evaluated atomically on the device -
    // sending those as separate app-data packets risks drops/reordering that
    // run init before a segment is defined, leaving the strip un-started.
    // Each strip's non-default settings then follow as their own progn.
    // Called on add / remove and on setup-field edits.
    function applyStructure() {
        if (strips.length === 0) {
            sendCode("(ext-espled-deinit)")
            return
        }
        var c = ["(ext-espled-deinit)"]
        for (var i = 0; i < strips.length; i++) {
            var s = strips[i]
            c.push("(ext-espled-seg-def " + i + " " + s.pin + " " +
                   s.ledType + " " + s.len + " 0 " + s.timing + ")")
        }
        c.push("(ext-espled-init " + strips.length + ")")
        sendCode("(progn " + c.join(" ") + ")")

        for (var j = 0; j < strips.length; j++) {
            sendStripSettings(j)
        }
    }

    // Send a strip's settings that differ from the seg-def defaults, as one
    // atomic progn (skipped entirely when everything is default).
    function sendStripSettings(i) {
        var s = strips[i]
        var c = []
        if (s.fx !== defFx)       c.push("(ext-espled-seg-fx " + i + " " + s.fx + ")")
        if (s.pal !== defPal)     c.push("(ext-espled-seg-pal " + i + " " + s.pal + ")")
        if (s.speed !== defSpeed) c.push("(ext-espled-seg-spd " + i + " " + s.speed + ")")
        if (s.size !== defSize)   c.push("(ext-espled-seg-size " + i + " " + s.size + ")")
        if (s.level !== defLevel) c.push("(ext-espled-seg-level " + i + " " + s.level + ")")
        if (s.bri !== defBri)     c.push("(ext-espled-seg-bri " + i + " " + s.bri + ")")
        var col = packColor(s.r, s.g, s.b)
        if (col !== 0)            c.push("(ext-espled-seg-col " + i + " " + col + ")")
        if (c.length > 0) {
            sendCode("(progn " + c.join(" ") + ")")
        }
    }

    // ---- Reusable slider with a value bubble -----------------------------

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

    // ---- Per-strip control page ------------------------------------------

    Component {
        id: stripPage

        ScrollView {
            id: page
            // index / modelData come from the Repeater delegate context and
            // are valid at creation (before the child controls initialize).
            property int seg: index
            property var d: modelData
            contentWidth: availableWidth
            clip: true

            function refreshPreview() {
                colorPreview.color = Qt.rgba(d.r / 255, d.g / 255, d.b / 255, 1)
            }
            function pushColor() {
                queueSend("col" + seg,
                    "(ext-espled-seg-col " + seg + " " + packColor(d.r, d.g, d.b) + ")")
            }

            ColumnLayout {
                width: page.availableWidth
                spacing: 8

                GroupBox {
                    title: "Setup (rebuilds strips on change)"
                    Layout.fillWidth: true

                    GridLayout {
                        anchors.fill: parent
                        columns: 2

                        Label { text: "Pin" }
                        SpinBox {
                            from: 0; to: 48; editable: true
                            Layout.fillWidth: true
                            value: page.d.pin
                            onValueModified: { page.d.pin = value; applyStructure() }
                        }

                        Label { text: "LEDs" }
                        SpinBox {
                            from: 1; to: 512; editable: true
                            Layout.fillWidth: true
                            value: page.d.len
                            onValueModified: { page.d.len = value; applyStructure() }
                        }

                        Label { text: "Type" }
                        ComboBox {
                            model: ["GRB (WS2812)", "RGB", "GRBW (SK6812 RGBW)", "RGBW"]
                            Layout.fillWidth: true
                            currentIndex: page.d.ledType
                            onActivated: { page.d.ledType = currentIndex; applyStructure() }
                        }

                        Label { text: "Timing" }
                        ComboBox {
                            model: ["Universal", "WS2812B", "WS2815", "SK6812", "SK6815"]
                            Layout.fillWidth: true
                            currentIndex: page.d.timing
                            onActivated: { page.d.timing = currentIndex; applyStructure() }
                        }

                        Button {
                            text: "Remove this strip"
                            Layout.columnSpan: 2
                            Layout.fillWidth: true
                            onClicked: removeStrip(page.seg)
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
                            id: fxCombo
                            model: ["Solid", "Breathe", "Chase", "Rainbow", "Sparkle", "Comet", "Gauge", "Strobe", "Larson", "Felony", "Theater", "Wipe", "Waves", "Candle", "Heartbeat"]
                            Layout.fillWidth: true
                            currentIndex: page.d.fx
                            onActivated: {
                                page.d.fx = currentIndex
                                sendCode("(ext-espled-seg-fx " + page.seg + " " + currentIndex + ")")
                            }
                        }

                        Label { text: "Palette" }
                        ComboBox {
                            model: ["Spectrum", "Fire", "Ocean", "Neon", "Ember", "Traffic", "B&W Flash", "Police Blue", "Sunset", "Lava", "Aurora", "Forest", "Party", "Ice", "Halloween", "Christmas", "Pastel", "Sakura"]
                            Layout.fillWidth: true
                            currentIndex: page.d.pal
                            // Colour 0 means "take colour from the palette", so
                            // clear the colour when a palette is picked.
                            onActivated: {
                                page.d.pal = currentIndex
                                page.d.r = 0; page.d.g = 0; page.d.b = 0
                                page.refreshPreview()
                                sendCode("(ext-espled-seg-pal " + page.seg + " " + currentIndex + ")")
                                sendCode("(ext-espled-seg-col " + page.seg + " 0)")
                            }
                        }

                        Label { text: "" }
                        Label {
                            text: "Palettes colour the effect while no colour is set; picking a colour overrides them. Rainbow always draws the palette."
                            font.italic: true
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        Label { text: "Speed" }
                        Loader {
                            sourceComponent: customValueSlider
                            Layout.fillWidth: true
                            onLoaded: {
                                item.from = 1; item.to = 255; item.value = page.d.speed
                                item.valueChanged.connect(function() {
                                    page.d.speed = Math.round(item.value)
                                    queueSend("spd" + page.seg,
                                        "(ext-espled-seg-spd " + page.seg + " " + item.value.toFixed(0) + ")")
                                })
                                item.interactionReleased.connect(function() {
                                    queueSend("spd" + page.seg,
                                        "(ext-espled-seg-spd " + page.seg + " " + item.value.toFixed(0) + ")")
                                })
                            }
                        }

                        Label { text: "Size" }
                        Loader {
                            sourceComponent: customValueSlider
                            Layout.fillWidth: true
                            onLoaded: {
                                item.from = 1; item.to = 64; item.value = page.d.size
                                item.valueChanged.connect(function() {
                                    page.d.size = Math.round(item.value)
                                    queueSend("size" + page.seg,
                                        "(ext-espled-seg-size " + page.seg + " " + item.value.toFixed(0) + ")")
                                })
                                item.interactionReleased.connect(function() {
                                    queueSend("size" + page.seg,
                                        "(ext-espled-seg-size " + page.seg + " " + item.value.toFixed(0) + ")")
                                })
                            }
                        }

                        Label { text: "Level" }
                        Loader {
                            sourceComponent: customValueSlider
                            Layout.fillWidth: true
                            onLoaded: {
                                item.from = 0; item.to = 255; item.value = page.d.level
                                item.valueChanged.connect(function() {
                                    page.d.level = Math.round(item.value)
                                    queueSend("lvl" + page.seg,
                                        "(ext-espled-seg-level " + page.seg + " " + item.value.toFixed(0) + ")")
                                })
                                item.interactionReleased.connect(function() {
                                    queueSend("lvl" + page.seg,
                                        "(ext-espled-seg-level " + page.seg + " " + item.value.toFixed(0) + ")")
                                })
                            }
                        }

                        // Per-strip brightness. The firmware multiplies this by
                        // the Global brightness slider, so the strip's output is
                        // (strip brightness / 255) * (global brightness / 255).
                        Label { text: "Brightness" }
                        Loader {
                            sourceComponent: customValueSlider
                            Layout.fillWidth: true
                            onLoaded: {
                                item.from = 0; item.to = 255; item.value = page.d.bri
                                item.valueChanged.connect(function() {
                                    page.d.bri = Math.round(item.value)
                                    queueSend("bri" + page.seg,
                                        "(ext-espled-seg-bri " + page.seg + " " + item.value.toFixed(0) + ")")
                                })
                                item.interactionReleased.connect(function() {
                                    queueSend("bri" + page.seg,
                                        "(ext-espled-seg-bri " + page.seg + " " + item.value.toFixed(0) + ")")
                                })
                            }
                        }
                    }
                }

                GroupBox {
                    title: "Colour"
                    Layout.fillWidth: true

                    ColumnLayout {
                        anchors.fill: parent

                        Rectangle {
                            id: colorPreview
                            Layout.fillWidth: true
                            height: 24
                            radius: 4
                            color: Qt.rgba(page.d.r / 255, page.d.g / 255, page.d.b / 255, 1)
                            border.color: "#808080"
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2

                            Label { text: "R" }
                            Loader {
                                sourceComponent: customValueSlider
                                Layout.fillWidth: true
                                onLoaded: {
                                    item.from = 0; item.to = 255; item.value = page.d.r
                                    item.valueChanged.connect(function() {
                                        page.d.r = Math.round(item.value)
                                        page.refreshPreview(); page.pushColor()
                                    })
                                    item.interactionReleased.connect(page.pushColor)
                                }
                            }

                            Label { text: "G" }
                            Loader {
                                sourceComponent: customValueSlider
                                Layout.fillWidth: true
                                onLoaded: {
                                    item.from = 0; item.to = 255; item.value = page.d.g
                                    item.valueChanged.connect(function() {
                                        page.d.g = Math.round(item.value)
                                        page.refreshPreview(); page.pushColor()
                                    })
                                    item.interactionReleased.connect(page.pushColor)
                                }
                            }

                            Label { text: "B" }
                            Loader {
                                sourceComponent: customValueSlider
                                Layout.fillWidth: true
                                onLoaded: {
                                    item.from = 0; item.to = 255; item.value = page.d.b
                                    item.valueChanged.connect(function() {
                                        page.d.b = Math.round(item.value)
                                        page.refreshPreview(); page.pushColor()
                                    })
                                    item.interactionReleased.connect(page.pushColor)
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            // Presets set a solid colour; the firmware ext also
                            // forces the solid effect, so keep fx in sync.
                            Repeater {
                                model: [
                                    { name: "Red",   cr: 255, cg: 0,   cb: 0 },
                                    { name: "Green", cr: 0,   cg: 255, cb: 0 },
                                    { name: "Blue",  cr: 0,   cg: 0,   cb: 255 },
                                    { name: "White", cr: 255, cg: 255, cb: 255 }
                                ]
                                Button {
                                    text: modelData.name
                                    Layout.fillWidth: true
                                    onClicked: {
                                        page.d.r = modelData.cr
                                        page.d.g = modelData.cg
                                        page.d.b = modelData.cb
                                        page.d.fx = 0
                                        fxCombo.currentIndex = 0
                                        page.refreshPreview()
                                        sendCode("(ext-espled-seg-col " + page.seg + " " +
                                                 packColor(modelData.cr, modelData.cg, modelData.cb) + ")")
                                        sendCode("(ext-espled-seg-fx " + page.seg + " 0)")
                                    }
                                }
                            }
                            Button {
                                text: "Off"
                                Layout.fillWidth: true
                                onClicked: {
                                    page.d.r = 0; page.d.g = 0; page.d.b = 0
                                    page.refreshPreview()
                                    sendCode("(ext-espled-seg-col " + page.seg + " 0)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- Global control page ---------------------------------------------

    Component {
        id: globalPage

        ScrollView {
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: 8

                GroupBox {
                    title: "Global (all strips)"
                    Layout.fillWidth: true

                    GridLayout {
                        anchors.fill: parent
                        columns: 2

                        Label { text: "Brightness" }
                        Loader {
                            sourceComponent: customValueSlider
                            Layout.fillWidth: true
                            onLoaded: {
                                item.from = 0; item.to = 255; item.value = 255
                                item.valueChanged.connect(function() {
                                    queueSend("bri", "(ext-espled-bri " + item.value.toFixed(0) + ")")
                                })
                                item.interactionReleased.connect(function() {
                                    queueSend("bri", "(ext-espled-bri " + item.value.toFixed(0) + ")")
                                })
                            }
                        }

                        Label { text: "Fade" }
                        Loader {
                            sourceComponent: customValueSlider
                            Layout.fillWidth: true
                            onLoaded: {
                                item.from = 0; item.to = 32; item.value = 15
                                item.valueChanged.connect(function() {
                                    queueSend("fade", "(ext-espled-fade " + item.value.toFixed(0) + ")")
                                })
                                item.interactionReleased.connect(function() {
                                    queueSend("fade", "(ext-espled-fade " + item.value.toFixed(0) + ")")
                                })
                            }
                        }

                        Label { text: "Auto white" }
                        Switch {
                            onToggled: sendCode("(ext-espled-auto-white " + (checked ? 1 : 0) + ")")
                        }

                        Label { text: "Current limit (mA)" }
                        SpinBox {
                            from: 0; to: 20000; value: 0
                            stepSize: 100
                            editable: true
                            Layout.fillWidth: true
                            onValueModified: sendCode("(ext-espled-ablimit " + value + ")")
                        }
                    }
                }

                Button {
                    text: "Stop all (deinit)"
                    Layout.fillWidth: true
                    onClicked: {
                        strips = []
                        tabBar.currentIndex = 0
                        sendCode("(ext-espled-deinit)")
                    }
                }
            }
        }
    }

    // ---- Add-strip dialog: capture pin/length/type/timing up front ------

    Dialog {
        id: addDialog
        title: "Add LED strip"
        modal: true
        anchors.centerIn: parent
        width: Math.min(container.width - 20, 340)
        standardButtons: Dialog.Ok | Dialog.Cancel

        // A strip is only created once these are chosen, so init never runs
        // on a placeholder pin.
        onAccepted: addStripFrom(dlgPin.value, dlgLen.value,
                                 dlgType.currentIndex, dlgTiming.currentIndex)

        GridLayout {
            anchors.fill: parent
            columns: 2

            Label { text: "Pin" }
            SpinBox {
                id: dlgPin
                from: 0; to: 48; value: 20; editable: true
                Layout.fillWidth: true
            }

            Label { text: "LEDs" }
            SpinBox {
                id: dlgLen
                from: 1; to: 512; value: 30; editable: true
                Layout.fillWidth: true
            }

            Label { text: "Type" }
            ComboBox {
                id: dlgType
                model: ["GRB (WS2812)", "RGB", "GRBW (SK6812 RGBW)", "RGBW"]
                Layout.fillWidth: true
            }

            Label { text: "Timing" }
            ComboBox {
                id: dlgTiming
                model: ["Universal", "WS2812B", "WS2815", "SK6812", "SK6815"]
                Layout.fillWidth: true
            }
        }
    }

    // ---- Layout: tab bar + stacked pages ---------------------------------

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            Layout.fillWidth: true

            TabBar {
                id: tabBar
                Layout.fillWidth: true
                clip: true

                Repeater {
                    model: strips
                    TabButton { text: "Strip " + (index + 1) }
                }
                TabButton { text: "Global" }
            }

            Button {
                text: "+ Add"
                onClicked: {
                    // Reset the dialog to sensible defaults each open.
                    dlgPin.value = 20
                    dlgLen.value = 30
                    dlgType.currentIndex = 0
                    dlgTiming.currentIndex = 0
                    addDialog.open()
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

            Repeater {
                model: strips
                delegate: stripPage
            }

            Loader { sourceComponent: globalPage }
        }
    }

    // Opens with no strips; the device keeps whatever it was running until
    // the user adds a strip (+ Add) or presses Stop all.
}
