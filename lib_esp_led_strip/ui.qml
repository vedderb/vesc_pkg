/*
Copyright 2026 VESC project

This file is part of the VESC firmware.

The VESC firmware is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

The VESC firmware is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

// Example UI for lib_esp_led_strip. Each strip is one segment on its own pin;
// the firmware pools RMT channels behind the pins, so several strips run at
// once. Strips are managed as tabs that can be added and removed at runtime.
//
// The QML is the source of truth: ext-esp_led-seg-def resets a segment's
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

    // Segment defaults set by ext-esp_led-seg-def. Replays skip values equal
    // to these, keeping the burst after a rebuild small. fx 2 = solid (0 =
    // off, 1 = custom), matching the firmware effect enum.
    readonly property int fxSolid: 2
        readonly property int defFx: fxSolid
            // Palette 0 is the (empty) custom palette; 1 = Spectrum is the default.
            readonly property int defPal: 1
                readonly property int defSpeed: 32
                    readonly property int defSize: 8
                        readonly property int defFxVal: 255
                            readonly property int defBri: 255
                            readonly property bool defAutoWhite: false
                            readonly property bool defReverse: false

                                // One object per strip; array index == segment index on the device.
                                property var strips: []

                                // ---- Comms -----------------------------------------------------------

                                // The esp_led_strip.lisp script evaluates expressions sent as custom app
                                // data. Each call is one lisp form beginning with '(' (the script only
                                // evaluates data that starts with a parenthesis).
                                function sendCode(str)
                                {
                                    mCommands.sendCustomAppData(str + "\0")
                                }

                                // Throttled sends for live slider dragging: the first change goes out
                                // immediately, further changes are coalesced per control key at 20 Hz and
                                // the final value flushed on release. The strip smooths brightness itself.
                                property var txPending: ({})

                                function flushTx()
                                {
                                    for (var k in txPending) {
                                        sendCode(txPending[k])
                                    }
                                    txPending = ({})
                                }

                                function queueSend(key, str)
                                {
                                    txPending[key] = str
                                    if (!txTimer.running)
                                    {
                                        flushTx()
                                        txTimer.start()
                                    }
                                }

                                Timer {
                                    id: txTimer
                                    interval: 50
                                    repeat: true
                                    onTriggered: {
                                        if (Object.keys(txPending).length > 0)
                                        {
                                            flushTx()
                                        } else {
                                        stop()
                                    }
                                }
                            }

                            // Packed 0xWWRRGGBB, as the lib expects. Forced unsigned with
                            // >>> 0 because a white byte of 0x80 or more makes the 32-bit
                            // result negative in JS, which would be sent as a negative
                            // literal.
                            function packColor(w, r, g, b)
                            {
                                return (((Math.round(w) << 24) | (Math.round(r) << 16) |
                                (Math.round(g) << 8) | Math.round(b)) >>> 0)
                            }

                            // ---- Strip management ------------------------------------------------

                            function makeStrip(pin, len, type, timing, offset)
                            {
                                return {
                                    pin: pin, len: len, ledType: type, timing: timing, offset: offset,
                                    fx: defFx, pal: defPal,
                                    w: 0, r: 255, g: 0, b: 0,
                                    speed: defSpeed, size: defSize, fxVal: defFxVal, bri: defBri,
                                    autoWhite: defAutoWhite, reverse: defReverse
                                }
                            }

                            // Called from the Add dialog once pin / length / type / timing / offset are
                            // chosen, so a strip is only created (and init'd) on the pin the user
                            // picked - never on a placeholder pin.
                            function addStripFrom(pin, len, type, timing, offset)
                            {
                                var arr = strips.slice()
                                arr.push(makeStrip(pin, len, type, timing, offset))
                                strips = arr            // reassign -> tab delegates rebuild
                                applyStructure()
                                tabBar.currentIndex = strips.length - 1
                            }

                            // Next free offset on a pin: the end of the furthest strip already on it,
                            // so chained strips (0-20, 21-40, ...) can be placed with one fewer thing
                            // to compute. 0 when the pin is unused.
                            function nextOffsetForPin(pin)
                            {
                                var end = 0
                                for (var i = 0; i < strips.length; i++) {
                                    if (strips[i].pin === pin)
                                    {
                                        var e = strips[i].offset + strips[i].len
                                        if (e > end) end = e
                                    }
                                }
                                return end
                            }

                            function removeStrip(idx)
                            {
                                if (idx < 0 || idx >= strips.length)
                                {
                                    return
                                }
                                var arr = strips.slice()
                                arr.splice(idx, 1)
                                strips = arr
                                if (tabBar.currentIndex > strips.length)
                                {
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
                            function applyStructure()
                            {
                                if (strips.length === 0)
                                {
                                    sendCode("(ext-esp_led-deinit)")
                                    return
                                }
                                var c = ["(ext-esp_led-deinit)"]
                                for (var i = 0; i < strips.length; i++) {
                                    var s = strips[i]
                                    c.push("(ext-esp_led-seg-def " + i + " " + s.pin + " " +
                                    s.ledType + " " + s.len + " " + s.offset + " " + s.timing + ")")
                                }
                                c.push("(ext-esp_led-init " + strips.length + ")")
                                sendCode("(progn " + c.join(" ") + ")")

                                for (var j = 0; j < strips.length; j++) {
                                    sendStripSettings(j)
                                }
                            }

                            // Send a strip's settings that differ from the seg-def defaults, as one
                            // atomic progn (skipped entirely when everything is default).
                            function sendStripSettings(i)
                            {
                                var s = strips[i]
                                var c = []
                                if (s.fx !== defFx) c.push("(ext-esp_led-seg-fx " + i + " " + s.fx + ")")
                                    if (s.pal !== defPal) c.push("(ext-esp_led-seg-pal " + i + " " + s.pal + ")")
                                if (s.speed !== defSpeed) c.push("(ext-esp_led-seg-spd " + i + " " + s.speed + ")")
                                    if (s.size !== defSize) c.push("(ext-esp_led-seg-size " + i + " " + s.size + ")")
                                if (s.fxVal !== defFxVal) c.push("(ext-esp_led-seg-fx-val " + i + " " + s.fxVal + ")")
                                    if (s.bri !== defBri) c.push("(ext-esp_led-seg-bri " + i + " " + s.bri + ")")
                                if (s.autoWhite !== defAutoWhite)
                                    c.push("(ext-esp_led-seg-auto-white " + i + " " + (s.autoWhite ? 1 : 0) + ")")
                                if (s.reverse !== defReverse)
                                    c.push("(ext-esp_led-seg-reverse " + i + " " + (s.reverse ? 1 : 0) + ")")
                                var col = packColor(s.w, s.r, s.g, s.b)
                                if (col !== 0) c.push("(ext-esp_led-seg-col " + i + " " + col + ")")
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
                                            if (!pressed)
                                            {
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
                                            // The live element of `strips`, NOT modelData: a JS array
                                            // model hands the delegate a *copy* of the element, so
                                            // every edit written through modelData was lost to
                                            // `strips` - and applyStructure(), which replays from
                                            // `strips`, then pushed each strip's creation values
                                            // (solid red) back over the user's settings. Re-binds on
                                            // add / remove, when indices shift.
                                            property var d: index >= 0 && index < strips.length
                                                ? strips[index] : makeStrip(0, 1, 0, 0, 0)
                                                // d is a plain JS object, so QML cannot see fields
                                                // being mutated inside it and bindings on d.<field>
                                                // never re-evaluate. Anything the UI has to react to
                                                // live needs a real property like these, kept in step
                                                // with d by whatever control owns the value.
                                                property int ledType: d.ledType
                                                property int fx: d.fx
                                                contentWidth: availableWidth
                                                clip: true

                                                // The white die is a separate emitter, so it cannot be shown
                                                // exactly on screen - approximate it by lifting RGB towards
                                                // white, which is close enough to tell the channels apart.
                                                function refreshPreview()
                                                {
                                                    colorPreview.color = Qt.rgba(Math.min(255, d.r + d.w) / 255,
                                                    Math.min(255, d.g + d.w) / 255,
                                                    Math.min(255, d.b + d.w) / 255, 1)
                                                }
                                                function pushColor()
                                                {
                                                    queueSend("col" + seg,
                                                    "(ext-esp_led-seg-col " + seg + " " + packColor(d.w, d.r, d.g, d.b) + ")")
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

                                                            // Pixel offset within the pin's chain. Strips sharing a
                                                            // pin must have non-overlapping [offset, offset+LEDs)
                                                            // ranges (e.g. 0-20 then 21-40 on the same data line).
                                                            Label { text: "Offset" }
                                                            SpinBox {
                                                                from: 0; to: 1024; editable: true
                                                                Layout.fillWidth: true
                                                                value: page.d.offset
                                                                onValueModified: { page.d.offset = value; applyStructure() }
                                                            }

                                                            Label { text: "Type" }
                                                            ComboBox {
                                                                model: ["GRB (WS2812)", "RGB", "GRBW (SK6812 RGBW)", "RGBW", "WRGB (WS2814)"]
                                                                Layout.fillWidth: true
                                                                currentIndex: page.ledType
                                                                onActivated: {
                                                                    page.d.ledType = currentIndex // model, read by applyStructure
                                                                    page.ledType = currentIndex   // notifies the W / auto-white rows
                                                                    applyStructure()
                                                                }
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
                                                                model: ["Off", "Custom", "Solid", "Breathe", "Chase", "Rainbow", "Sparkle", "Comet", "Gauge", "Strobe", "Larson", "Felony", "Theater", "Wipe", "Waves", "Candle", "Heartbeat", "Turn signal"]
                                                                Layout.fillWidth: true
                                                                currentIndex: page.fx
                                                                onActivated: {
                                                                    page.d.fx = currentIndex // model, replayed by applyStructure
                                                                    page.fx = currentIndex   // notifies this combo's binding
                                                                    sendCode("(ext-esp_led-seg-fx " + page.seg + " " + currentIndex + ")")
                                                                }
                                                            }

                                                            Label { text: "Palette" }
                                                            ComboBox {
                                                                model: ["Custom", "Spectrum", "Fire", "Ocean", "Neon", "Ember", "Traffic", "B&W Flash", "Police Blue", "Sunset", "Lava", "Aurora", "Forest", "Party", "Ice", "Halloween", "Christmas", "Pastel", "Sakura"]
                                                                Layout.fillWidth: true
                                                                currentIndex: page.d.pal
                                                                // Colour 0 means "take colour from the palette", so
                                                                // clear the colour when a palette is picked.
                                                                onActivated: {
                                                                    page.d.pal = currentIndex
                                                                    page.d.r = 0; page.d.g = 0; page.d.b = 0
                                                                    page.refreshPreview()
                                                                    sendCode("(ext-esp_led-seg-pal " + page.seg + " " + currentIndex + ")")
                                                                    sendCode("(ext-esp_led-seg-col " + page.seg + " 0)")
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
                                                                    "(ext-esp_led-seg-spd " + page.seg + " " + item.value.toFixed(0) + ")")
                                                                })
                                                                item.interactionReleased.connect(function() {
                                                                queueSend("spd" + page.seg,
                                                                "(ext-esp_led-seg-spd " + page.seg + " " + item.value.toFixed(0) + ")")
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
                                                            "(ext-esp_led-seg-size " + page.seg + " " + item.value.toFixed(0) + ")")
                                                        })
                                                        item.interactionReleased.connect(function() {
                                                        queueSend("size" + page.seg,
                                                        "(ext-esp_led-seg-size " + page.seg + " " + item.value.toFixed(0) + ")")
                                                    })
                                                }
                                            }

                                            Label { text: "Effect value" }
                                            Loader {
                                                sourceComponent: customValueSlider
                                                Layout.fillWidth: true
                                                onLoaded: {
                                                    item.from = 0; item.to = 255; item.value = page.d.fxVal
                                                    item.valueChanged.connect(function() {
                                                    page.d.fxVal = Math.round(item.value)
                                                    queueSend("fxval" + page.seg,
                                                    "(ext-esp_led-seg-fx-val " + page.seg + " " + item.value.toFixed(0) + ")")
                                                })
                                                item.interactionReleased.connect(function() {
                                                queueSend("fxval" + page.seg,
                                                "(ext-esp_led-seg-fx-val " + page.seg + " " + item.value.toFixed(0) + ")")
                                            })
                                        }
                                    }

                                    // One slider whose meaning comes from the effect, so
                                    // the label cannot say what it does on its own.
                                    Label { text: "" }
                                    Label {
                                        text: "What this does depends on the effect: the fill on Gauge, the mode on Turn signal (0 off, then left / right / hazard x solid / blink / sweep, 1-9). Other effects ignore it."
                                        font.italic: true
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
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
                                            "(ext-esp_led-seg-bri " + page.seg + " " + item.value.toFixed(0) + ")")
                                        })
                                        item.interactionReleased.connect(function() {
                                        queueSend("bri" + page.seg,
                                        "(ext-esp_led-seg-bri " + page.seg + " " + item.value.toFixed(0) + ")")
                                    })
                                }
                            }

                            // Mirrors the effect pixels as they are packed for the
                            // wire, so moving effects run the other way - for strips
                            // mounted with the data-in end at the far side.
                            Label { text: "Reverse" }
                            Switch {
                                checked: page.d.reverse
                                onToggled: {
                                    page.d.reverse = checked
                                    sendCode("(ext-esp_led-seg-reverse " + page.seg + " " + (checked ? 1 : 0) + ")")
                                }
                            }

                            // Only meaningful on strips with a white channel, so both
                            // rows are hidden on the others. Layouts skip invisible
                            // items, so the label and the switch must hide together
                            // or the two-column grid shifts.
                            Label {
                                text: "Auto white"
                                visible: page.ledType >= 2
                            }
                            Switch {
                                visible: page.ledType >= 2
                                checked: page.d.autoWhite
                                onToggled: {
                                    page.d.autoWhite = checked
                                    // Auto-white only acts on pixels whose white byte is 0,
                                    // so clear any manual W - otherwise enabling this would
                                    // appear to do nothing.
                                    if (checked && page.d.w !== 0) {
                                        page.d.w = 0
                                        if (wSlider.item) wSlider.item.value = 0
                                        page.refreshPreview()
                                        page.pushColor()
                                    }
                                    sendCode("(ext-esp_led-seg-auto-white " + page.seg + " " + (checked ? 1 : 0) + ")")
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

                    // Hidden on strips with no white die (label and slider together,
                    // so the grid does not shift). Greyed rather than hidden while
                    // auto-white is on, since that is a toggle right above: auto-white
                    // derives the white byte and only acts when it is 0, so the two
                    // are mutually exclusive.
                    Label {
                        text: "W"
                        visible: page.ledType >= 2
                        enabled: !page.d.autoWhite
                    }
                    Loader {
                        id: wSlider
                        sourceComponent: customValueSlider
                        Layout.fillWidth: true
                        visible: page.ledType >= 2
                        enabled: !page.d.autoWhite
                        onLoaded: {
                            item.from = 0; item.to = 255; item.value = page.d.w
                            item.valueChanged.connect(function() {
                            page.d.w = Math.round(item.value)
                            page.refreshPreview(); page.pushColor()
                        })
                        item.interactionReleased.connect(page.pushColor)
                    }
                }
                }

                RowLayout {
                    Layout.fillWidth: true

                    // Presets set a solid colour and switch to the solid
                    // effect. ext-esp_led-seg-col only sets the colour - it is
                    // ext-esp_led-col-rgb, the all-segment variant, that also
                    // forces the effect - so the effect is sent explicitly.
                    Repeater {
                        model: [
                        { name: "Red", cr: 255, cg: 0, cb: 0 },
                        { name: "Green", cr: 0, cg: 255, cb: 0 },
                        { name: "Blue", cr: 0, cg: 0, cb: 255 },
                        { name: "White", cr: 255, cg: 255, cb: 255 }
                        ]
                        Button {
                            text: modelData.name
                            Layout.fillWidth: true
                            onClicked: {
                                page.d.r = modelData.cr
                                page.d.g = modelData.cg
                                page.d.b = modelData.cb
                                page.d.w = 0 // the presets are RGB
                                page.d.fx = fxSolid
                                page.fx = fxSolid // moves the combo via its binding
                                page.refreshPreview()
                                sendCode("(ext-esp_led-seg-col " + page.seg + " " +
                                packColor(0, modelData.cr, modelData.cg, modelData.cb) + ")")
                                sendCode("(ext-esp_led-seg-fx " + page.seg + " " + fxSolid + ")")
                            }
                        }
                    }
                    Button {
                        text: "Off"
                        Layout.fillWidth: true
                        // FX_OFF (0) blanks the strip whatever the
                        // effect, without disturbing its colour.
                        onClicked: {
                            page.d.fx = 0
                            page.fx = 0
                            sendCode("(ext-esp_led-seg-fx " + page.seg + " 0)")
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
                            queueSend("bri", "(ext-esp_led-bri " + item.value.toFixed(0) + ")")
                        })
                        item.interactionReleased.connect(function() {
                        queueSend("bri", "(ext-esp_led-bri " + item.value.toFixed(0) + ")")
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
                    queueSend("fade", "(ext-esp_led-fade " + item.value.toFixed(0) + ")")
                })
                item.interactionReleased.connect(function() {
                queueSend("fade", "(ext-esp_led-fade " + item.value.toFixed(0) + ")")
            })
        }
    }

    // Smoothness / CPU trade only: the firmware advances animations by
    // elapsed real time, so effects run at the same speed whatever this
    // is set to. Long strips may not reach a high setting - the loop
    // paces itself against the work it actually did.
    Label { text: "Frame rate" }
    Loader {
        sourceComponent: customValueSlider
        Layout.fillWidth: true
        onLoaded: {
            item.from = 5; item.to = 120; item.value = 30
            item.formatValue = function(val) { return val.toFixed(0) + " fps" }
            item.valueChanged.connect(function() {
            queueSend("fps", "(ext-esp_led-fps " + item.value.toFixed(0) + ")")
        })
        item.interactionReleased.connect(function() {
        queueSend("fps", "(ext-esp_led-fps " + item.value.toFixed(0) + ")")
    })
}
    }

}
}

// Restarts every strip's animation from phase 0 in one call, so effects
// set up at different times line up. Nothing else about the strips
// changes; strips running different speeds drift apart again from here.
Button {
    text: "Sync animations"
    Layout.fillWidth: true
    onClicked: {
        // Flush first: a queued slider value landing after the sync
        // would not disturb the phase, but the strips should be at the
        // speed the user sees before they are lined up.
        flushTx()
        sendCode("(ext-esp_led-sync)")
    }
}

Button {
    text: "Stop all (deinit)"
    Layout.fillWidth: true
    onClicked: {
        strips = []
        tabBar.currentIndex = 0
        sendCode("(ext-esp_led-deinit)")
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
    dlgType.currentIndex, dlgTiming.currentIndex,
    dlgOffset.value)

    GridLayout {
        anchors.fill: parent
        columns: 2

        Label { text: "Pin" }
        SpinBox {
            id: dlgPin
            from: 0; to: 48; value: 20; editable: true
            Layout.fillWidth: true
            // Chained strips share a pin: suggest the next free offset when
            // the chosen pin already has strips on it.
            onValueModified: dlgOffset.value = nextOffsetForPin(value)
        }

        Label { text: "LEDs" }
        SpinBox {
            id: dlgLen
            from: 1; to: 512; value: 30; editable: true
            Layout.fillWidth: true
        }

        Label { text: "Offset" }
        SpinBox {
            id: dlgOffset
            from: 0; to: 1024; value: 0; editable: true
            Layout.fillWidth: true
        }

        Label { text: "Type" }
        ComboBox {
            id: dlgType
            model: ["GRB (WS2812)", "RGB", "GRBW (SK6812 RGBW)", "RGBW", "WRGB (WS2814)"]
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
                dlgOffset.value = nextOffsetForPin(dlgPin.value)
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
