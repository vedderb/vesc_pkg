import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15
import QtQuick.Layouts 1.15
import Vedder.vesc.commands 1.0
import Vedder.vesc.utility 1.0

Item {
    id: root
    anchors.fill: parent

    property Commands mCommands: VescIf.commands()
    // Theme. VESC Tool resolves its palette at start-up and emits nothing when the
    // theme changes, so these are read when the page is built - switching theme
    // needs the tab reopened, the same as the rest of the app. Dark keeps the exact
    // colours this UI was drawn in; light borrows the app's own so the cards stop
    // being dark slabs under light-mode text. The light values are set here rather
    // than taken from the app's palette: its names describe the dark theme, so
    // darkBackground is white in light mode and the deepest surfaces came out the
    // lightest. Light works the other way round from dark - the panels are white
    // and sit above a grey page rather than below it, with a hairline edge so the
    // white still reads, and every control is a clear step down from them. Anything that carries
    // meaning by its colour - the mode pills, LOCK, SECRET, CRUISE, the battery
    // bar - is left alone, and so is the white text sitting on top of those.
    readonly property bool  darkUi:    Utility.isDarkMode()
    readonly property color cDeep:     darkUi ? "#26262b" : "#ffffff"
    readonly property color cWell:     darkUi ? "#26262b" : "#d9dee4"
    readonly property color cCard:     darkUi ? "#2b2b31" : "#ffffff"
    readonly property color cCtl:      darkUi ? "#33333a" : "#e2e6eb"
    readonly property color cCtlHi:    darkUi ? "#3a3a44" : "#dce0e6"
    readonly property color cEdge:     darkUi ? "#43434c" : "#ccd2d9"
    readonly property color cTrack:    darkUi ? "#43434c" : "#e2e6eb"
    readonly property color cInk:      darkUi ? "#ffffff" : "#16181c"
    readonly property color cDim:      darkUi ? "#a0a0aa" : "#5a626b"
    readonly property color cAccent:   darkUi ? "#f29c65" : "#9a4d08"
    readonly property color cAccentBg: darkUi ? "#613c26" : "#f2c79a"
    readonly property color cAccentBg2:darkUi ? "#583827" : "#f6d9bb"
    readonly property color cDialog:   darkUi ? "#3a3a42" : "#ffffff"
    readonly property color cOff:      darkUi ? "#6e6e76" : "#9aa2ab"
    readonly property color cDim2:     darkUi ? "#8e8e98" : "#79818a"
    readonly property color cWarnBg:   darkUi ? "#3a1416" : "#fde8e6"
    readonly property color cWarnInk:  darkUi ? "#ff8a80" : "#a3201a"
    readonly property color cWarnTint: darkUi ? "#8e3b3b" : "#e8a9a5"

    property int loadedModel: -1
    // Read straight off the controller with getDecodedAdc, so the pin voltages
    // cost the script nothing - it is already near the const-heap ceiling.
    property real adcV1: 0.0
    property real adcV2: 0.0
    property bool isSlave: modelBox.currentIndex === 2
    // Load is only complete once every settings message has arrived. Saving
    // before that would write empty fields as 0 and wipe modes/general, so
    // Save stays disabled and the UI keeps re-requesting until all are in.
    property var settingsSeen: ({})
    property int settingsSeenCount: 0
    property bool settingsLoaded: false
    property bool saving: false
    // Edits the controller has not been told about yet. textEdited, toggled and
    // activated only fire for a real touch, so the fields a settings message
    // fills in on load never count as changes.
    property bool cfgDirty: false

    function markDirty() { if (settingsLoaded) cfgDirty = true }

    // Anything that throws here runs inside Component.onCompleted and takes
    // getSettings() down with it, leaving the UI on "Loading..." for good - so
    // a page SwipeView has not built yet, or a child that is not an Item, has
    // to be stepped over rather than trusted.
    function watchEdits(item) {
        if (!item || !item.children) return
        for (var i = 0; i < item.children.length; i++) {
            var c = item.children[i]
            if (!c) continue
            if (c.textEdited) c.textEdited.connect(root.markDirty)
            else if (c.toggled) c.toggled.connect(root.markDirty)
            else if (c.activated) c.activated.connect(root.markDirty)
            watchEdits(c)
        }
    }

    property bool statePending: false
    property double statePendingSince: 0
    readonly property var settingsMsgs: ["model", "general", "temps", "modes",
        "secret", "apply", "gesture", "misc", "rear", "cruise", "alarm"]

    function markSettingsSeen(key) {
        if (settingsMsgs.indexOf(key) < 0 || settingsSeen[key])
            return
        settingsSeen[key] = true
        settingsSeenCount += 1
        if (settingsSeenCount >= settingsMsgs.length) {
            settingsLoaded = true
            // whatever is on screen is now exactly what the controller holds
            cfgDirty = false
        }
    }

    function resetSettingsLoad() {
        settingsSeen = ({})
        settingsSeenCount = 0
        settingsLoaded = false
    }
    property real titleSize: Qt.application.font.pointSize > 0 ? Qt.application.font.pointSize + 3 : 14

    // The figure cards are laid out from real glyph widths, not from titleSize -
    // that is a point size, while an anchor margin is in pixels, and the two are
    // only the same number on a desktop. Widest case for each slot, so the four
    // cards hold a column whatever they happen to be showing.
    FontMetrics { id: chipUnitFm; font.bold: true; font.pointSize: root.titleSize * 0.96 }

    // Digits and caps carry no descender, so they do not sit in the middle of a
    // box that reserves room for one - centring the box leaves the ink off centre
    // by an amount that depends entirely on the font the device happens to use.
    // Measure it there rather than bake in a pixel measured somewhere else.
    FontMetrics { id: inkFm; font.bold: true; font.pointSize: root.titleSize }
    readonly property real inkOffset: {
        var t = inkFm.tightBoundingRect("0")
        if (!t || t.height <= 0) return 0
        return inkFm.height / 2 - (inkFm.ascent + t.y + t.height / 2)
    }
    function inkNudge(scale) { return Math.round(root.inkOffset * scale * 10) / 10 }
    // The unit pane is as wide as the widest unit plus a little air. The
    // reading is right-aligned against it, so nothing is centred and there is
    // no per-card offset left to get wrong.
    readonly property real chipUnitW: Math.round(chipUnitFm.advanceWidth("km")
                                                 + chipUnitFm.height * 0.35)

    // The four readouts under the battery bar. Every one of these already
    // arrives in the state line, so choosing between them costs the script
    // nothing. Caps are one letter each: the tile reserves a column the width
    // of an M and the digits line up across all four from it.
    readonly property var statOpts: [
        { key: "vin",   name: "Voltage" },
        { key: "amps",  name: "Battery Current" },
        { key: "mamps", name: "Motor Current" },
        { key: "fet",   name: "ESC Temperature" },
        { key: "mot",   name: "Motor Temperature" },
        { key: "bmst",  name: "Battery Temperature" },
        { key: "batt",  name: "Battery Percentage" },
        { key: "up",    name: "Uptime" },
        { key: "trip",  name: "Trip Distance" }
    ]
    // Offered whenever the BMS is switched on, not once it has answered - the
    // reading only arrives while a pack is actually reporting, and waiting for
    // it hides the choice from anyone setting the scooter up beforehand. The
    // tile itself shows "-" until there is something to show.
    readonly property var statOptsShown: statOpts.filter(function (o) {
        return o.key !== "bmst" || bmsSoc.checked
    })
    property var statSel: ["vin", "amps", "fet", "mot"]

    // Uptime carries its unit in the cap slot, so the letter beside the
    // number says what the number counts - seconds, minutes, hours or days.
    function fmtUptime(sec) {
        if (sec < 60)    return { v: String(Math.floor(sec)), u: "s" }
        if (sec < 3600)  return { v: String(Math.floor(sec / 60)), u: "m" }
        if (sec < 86400) return { v: String(Math.floor(sec / 3600)), u: "h" }
        return { v: String(Math.floor(sec / 86400)), u: "d" }
    }

    function statTile(key) {
        switch (key) {
        case "amps":  return { unit: "A", val: String(Math.round(stAmps)) }
        case "mamps": return { unit: "A", val: String(Math.round(stMotAmps)) }
        case "fet":   return { icon: "temp", val: String(Math.round(toShownTemp(stFet))),
                               warn: stFet > tempLimitC(tempWarningFet, 999) }
        case "mot":   return { icon: "temp", val: String(Math.round(toShownTemp(stMot))),
                               warn: stMot > tempLimitC(tempWarningMotor, 999) }
        case "bmst":  return stBmsTemp > -99
                             ? { icon: "temp", val: String(Math.round(toShownTemp(stBmsTemp))),
                                 warn: stBmsTemp > tempLimitC(bmsTempHi, 50)
                                       || stBmsTemp < tempLimitC(bmsTempLo, 0) }
                             : { icon: "temp", val: "-" }
        case "batt":  return { icon: "batt", val: String(Math.round(stBatt)) }
        case "up":    var u = fmtUptime(stUptime)
                      return { unit: u.u, val: u.v }
        case "trip":  return { icon: "dist", val: useMph.checked
                                  ? String(Math.round(stTrip * 0.621371))
                                  : String(Math.round(stTrip)) }
        default:      return { unit: "V", val: String(Math.round(stVin)) }
        }
    }

    function setStat(slot, key) {
        var n = statSel.slice()
        n[slot] = key
        statSel = n
        if (uiPrefs) uiPrefs.statSlots = n.join(",")
    }

    // Qt.labs.settings is not guaranteed to be deployed in every VESC Tool
    // build, and a failed file-level import takes the whole page down with it.
    // Built at run time instead: if neither module is there the tiles simply
    // stop being remembered between sessions.
    property var uiPrefs: null

    function initPrefs() {
        var decl = ' Settings { category: "scooter_dashboard_support"; property string statSlots: "" }'
        var mods = ["import Qt.labs.settings 1.0;", "import QtCore 6.5;"]
        for (var i = 0; i < mods.length; i++) {
            try {
                uiPrefs = Qt.createQmlObject(mods[i] + decl, root, "uiPrefs")
                break
            } catch (e) { uiPrefs = null }
        }
        if (uiPrefs && uiPrefs.statSlots !== "") {
            var v = String(uiPrefs.statSlots).split(",")
            if (v.length === 4) {
                for (var k = 0; k < 4; k++)
                    if (!statOpts.some(function (o) { return o.key === v[k] })) return
                statSel = v
            }
        }
    }

    // Live scooter state for the Control tab
    property bool stOff: false
    property bool stLock: false
    property bool stLight: false
    property bool stSecret: false
    property int stMode: 4
    property real stBatt: 0
    property real stVin: 0
    property real stSpeed: 0
    property real stWatts: 0
    property real stWhkm: 0
    property real stRange: 0
    property real stAmps: 0
    property real stMax: 60
    property bool stCruise: false
    property bool stCruiseEn: false
    property bool stCruiseAllow: false
    property bool stSecretAllow: false
    property int stMotors: 1
    property int stFault: 0
    property int stSlip: 0
    property real stMotAmps: 0
    property real stBmsTemp: -100
    property real stUptime: 0
    property real stTrip: 0
    // above half, the fill reaches past the middle - so the centred figure
    // and the range parked on the left are both sitting on colour
    readonly property bool battOnFill: stBatt > 50
    property bool stImgOk: true
    property real stFet: 0
    property real stMot: 0
    // The three colours everything coloured is drawn from, so the battery bar
    // reads as part of the same set as the buttons rather than its own scheme.
    readonly property color palRed: "#dc2e28"
    readonly property color palAmber: "#e49e26"
    readonly property color palGreen: "#25af32"
    // text sitting on the charge fill: the fill is bright in either theme
    readonly property color palOnFill: "#16181c"

    function mixColor(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, 1)
    }

    // The two warning lamps, traced off the real icons by tools/svg_to_canvas.py:
    // closed rings in a unit box, the cut outs wound the other way so the plain
    // fill leaves them open. A package carries no image files, and the modules
    // that would take an SVG are not in VESC Tool's own QML, so Canvas draws them.
    readonly property var iconEngine: [
        [0.2269, 0.1531, 0.6508, 0.1531, 0.6508, 0.204, 0.5356, 0.204, 0.5356, 0.2385, 0.6507, 0.2384, 0.6714, 0.2457,
         0.6817, 0.265, 0.6824, 0.3045, 0.7329, 0.3051, 0.7536, 0.318, 0.7853, 0.4285, 0.8151, 0.4285, 0.848, 0.3245,
         0.861, 0.3089, 0.9473, 0.3044, 0.9709, 0.3141, 0.9816, 0.343, 0.996, 0.4617, 0.9979, 0.6667, 0.9797, 0.8237,
         0.9673, 0.8413, 0.9414, 0.8469, 0.8747, 0.8465, 0.8563, 0.8386, 0.8157, 0.7232, 0.7859, 0.7226, 0.7564, 0.8281,
         0.7351, 0.8456, 0.3117, 0.8453, 0.214, 0.7226, 0.1199, 0.7221, 0.0968, 0.711, 0.0895, 0.688, 0.0895, 0.5449,
         0.0631, 0.5449, 0.0631, 0.6905, 0, 0.6905, 0, 0.3361, 0.0631, 0.3361, 0.0631, 0.4817, 0.0895, 0.4817,
         0.0894, 0.3393, 0.0982, 0.3139, 0.1192, 0.3046, 0.1953, 0.3045, 0.197, 0.2603, 0.217, 0.2398, 0.3555, 0.2385,
         0.3555, 0.204, 0.2269, 0.204],
        [0.3245, 0.3016, 0.259, 0.3016, 0.2565, 0.347, 0.2368, 0.3661, 0.1532, 0.3677, 0.1532, 0.6589, 0.2481, 0.665,
         0.3425, 0.7829, 0.7028, 0.7828, 0.7345, 0.6755, 0.7474, 0.6627, 0.7681, 0.6591, 0.8414, 0.6595, 0.8601, 0.6672,
         0.9011, 0.7828, 0.9215, 0.7828, 0.9336, 0.6608, 0.9359, 0.5308, 0.9204, 0.3683, 0.9011, 0.3683, 0.8679, 0.4702,
         0.8562, 0.4864, 0.7601, 0.4915, 0.7336, 0.4754, 0.7028, 0.3677, 0.6484, 0.3671, 0.6298, 0.3599, 0.6192, 0.3408,
         0.6186, 0.3016]]
    readonly property var iconSlip: [
        [0.6165, 0.0133, 0.7215, 0.0522, 0.8187, 0.1172, 0.899, 0.2057, 0.9507, 0.3002, 0.9836, 0.421, 0.9848, 0.5382,
         0.9619, 0.6443, 0.9099, 0.7513, 0.8347, 0.8418, 0.7234, 0.9201, 0.6693, 0.9435, 0.6474, 0.9387, 0.6371, 0.9207,
         0.6438, 0.9003, 0.7392, 0.8479, 0.8053, 0.7943, 0.8619, 0.7252, 0.9045, 0.6438, 0.9287, 0.5537, 0.9331, 0.4826,
         0.9273, 0.4122, 0.9026, 0.3246, 0.8579, 0.2411, 0.8044, 0.1779, 0.7387, 0.1247, 0.6628, 0.0853, 0.5929, 0.0634,
         0.4931, 0.0537, 0.4052, 0.0646, 0.324, 0.0913, 0.2128, 0.1624, 0.1642, 0.2134, 0.1262, 0.2674, 0.0797, 0.3802,
         0.0679, 0.4503, 0.0676, 0.5183, 0.0831, 0.6066, 0.1138, 0.6839, 0.1633, 0.7606, 0.2255, 0.8225, 0.2481, 0.8378,
         0.3132, 0.746, 0.3225, 0.7388, 0.3314, 0.743, 0.3897, 0.9593, 0.3737, 0.9711, 0.1672, 1, 0.1573, 0.9954,
         0.1564, 0.982, 0.2178, 0.8861, 0.1102, 0.781, 0.0684, 0.7147, 0.0384, 0.6462, 0.0184, 0.5666, 0.013, 0.484,
         0.019, 0.4046, 0.0387, 0.3266, 0.0701, 0.2565, 0.1117, 0.1917, 0.2123, 0.0932, 0.2888, 0.0477, 0.3607, 0.0193,
         0.4448, 0.0023, 0.5025, 0],
        [0.5147, 0.1391, 0.8135, 0.6731, 0.8126, 0.6895, 0.7995, 0.7033, 0.6561, 0.7068, 0.1833, 0.706, 0.1676, 0.6874,
         0.1816, 0.6437, 0.4511, 0.1651, 0.4742, 0.1273, 0.4896, 0.1182],
        [0.4644, 0.2842, 0.4548, 0.3073, 0.4679, 0.5415, 0.5124, 0.5398, 0.5229, 0.2979, 0.5056, 0.2793, 0.488, 0.275],
        [0.4607, 0.5703, 0.4487, 0.5998, 0.4589, 0.6275, 0.4872, 0.6404, 0.516, 0.6305, 0.5298, 0.6, 0.5178, 0.5716,
         0.4888, 0.5592]]

    // The two units that read better as a picture than a letter. Drawn rather
    // than set in text for the same reason the warning lamps are: a package
    // ships no image files, and a font glyph for either one cannot be relied on.
    // Both use the full box rather than its shortest side - the pane is taller
    // than it is wide, and both shapes stand up.
    function paintUnitIcon(ctx, kind, w, h, col) {
        ctx.reset()
        ctx.fillStyle = col
        ctx.strokeStyle = col
        ctx.lineJoin = "round"
        ctx.lineCap = "round"

        // The canvas fills the pane, so centring here is exact - sizing the
        // canvas instead left a rounded width that anchors could not halve
        // evenly, and the glyph sat a pixel off. Work inset from it.
        var iw = w * 0.58
        var ih = h * 0.48
        ctx.translate((w - iw) / 2, (h - ih) / 2)
        w = iw
        h = ih

        if (kind === "temp") {
            // Traced off temperature-low (SVG Repo) on its own 24 grid: bulb of
            // r4 at 8,17 and a 6-wide tube capped at 8,6. Stroke included that
            // spans x 3.25..12.75 and y 2.25..21.75, which is what gets fitted.
            var k = Math.min(w / 9.5, h / 19.5)
            ctx.save()
            ctx.translate((w - 9.5 * k) / 2 - 3.25 * k, (h - 19.5 * k) / 2 - 2.25 * k)
            ctx.scale(k, k)
            ctx.lineWidth = 1.5
            ctx.lineCap = "round"
            ctx.lineJoin = "round"

            // body: round the bulb, up the left wall, over the cap, back down
            ctx.beginPath()
            ctx.arc(8, 17, 4, -0.7227, 3.8643)
            ctx.lineTo(5, 6)
            ctx.arc(8, 6, 3, Math.PI, 0)
            ctx.lineTo(11, 14.354)
            ctx.closePath()
            ctx.stroke()

            // the column, and the bulb it stands in
            ctx.beginPath()
            ctx.moveTo(8, 16)
            ctx.lineTo(8, 12)
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(8, 17, 1 + ctx.lineWidth / 2, 0, Math.PI * 2)
            ctx.fill()

            ctx.restore()
            return
        }

        if (kind === "dist") {
            // A pin beside the road it sits on, redrawn simply from location-on-road
            // (SVG Repo): its winding ribbon and dashes turn to mush at this size,
            // so the road is one stroke. Grid is 20 wide to match the battery.
            var kd = Math.min(w / 20, h / 20)
            ctx.save()
            ctx.translate((w - 20 * kd) / 2, (h - 20 * kd) / 2)
            ctx.scale(kd, kd)
            ctx.lineWidth = 1.6

            ctx.beginPath()
            ctx.arc(6.6, 7.4, 4.4, Math.PI * 0.78, Math.PI * 0.22)
            ctx.lineTo(6.6, 18.6)
            ctx.closePath()
            ctx.stroke()

            ctx.beginPath()
            ctx.arc(6.6, 7.4, 1.7, 0, Math.PI * 2)
            ctx.stroke()

            ctx.beginPath()
            ctx.moveTo(6.6, 18.6)
            ctx.bezierCurveTo(17.2, 20.4, 11.2, 11.4, 17.4, 4.6)
            ctx.stroke()

            ctx.restore()
            return
        }

        // battery stood on end - the pane has height to spare and no width
        var bw = w * 0.56
        var bh = h * 0.74
        var x0 = (w - bw) / 2
        var lw2 = Math.max(1.2, w * 0.10)
        var r = w * 0.13
        ctx.lineWidth = lw2

        // The terminal is part of the shape, so the body alone is not what gets
        // centred - measure the pair, stroke included, and place from that.
        var termH = h * 0.10
        var termGap = h * 0.012
        var top = (h - (termH + termGap + bh + lw2)) / 2
        var y0 = top + termH + termGap + lw2 / 2

        ctx.beginPath()
        ctx.rect(x0 + bw * 0.29, top, bw * 0.42, termH)
        ctx.fill()

        ctx.beginPath()
        ctx.moveTo(x0 + r, y0)
        ctx.lineTo(x0 + bw - r, y0)
        ctx.quadraticCurveTo(x0 + bw, y0, x0 + bw, y0 + r)
        ctx.lineTo(x0 + bw, y0 + bh - r)
        ctx.quadraticCurveTo(x0 + bw, y0 + bh, x0 + bw - r, y0 + bh)
        ctx.lineTo(x0 + r, y0 + bh)
        ctx.quadraticCurveTo(x0, y0 + bh, x0, y0 + bh - r)
        ctx.lineTo(x0, y0 + r)
        ctx.quadraticCurveTo(x0, y0, x0 + r, y0)
        ctx.closePath()
        ctx.stroke()

        // charge, filled from the foot up
        var ix = x0 + lw2 * 1.5
        var iy = y0 + lw2 * 1.5
        var iw = bw - lw2 * 3
        var ih = bh - lw2 * 3
        ctx.beginPath()
        ctx.rect(ix, iy + ih * 0.38, iw, ih * 0.62)
        ctx.fill()
    }

    // dx/dy are fractions of the badge: a shape is centred on its bounding box,
    // which is not where the eye puts it once something sticks out of one corner.
    // grow re-strokes the first ring in place - every stroke here is traced as a
    // closed outline, so the only way to fatten one is to lay a line back down
    // along its own edge, and only the ring that leads carries it.
    function paintIcon(ctx, rings, size, frac, dx, dy, col, grow) {
        ctx.reset()
        var e = size * frac
        var ox = (size - e) / 2 + dx * size
        var oy = (size - e) / 2 + dy * size
        ctx.beginPath()
        for (var s = 0; s < rings.length; s++) {
            var r = rings[s]
            ctx.moveTo(ox + r[0] * e, oy + r[1] * e)
            for (var i = 2; i < r.length; i += 2)
                ctx.lineTo(ox + r[i] * e, oy + r[i + 1] * e)
            ctx.closePath()
        }
        ctx.fillStyle = col
        ctx.fill()
        if (grow > 0) {
            var f = rings[0]
            ctx.beginPath()
            ctx.moveTo(ox + f[0] * e, oy + f[1] * e)
            for (var k = 2; k < f.length; k += 2)
                ctx.lineTo(ox + f[k] * e, oy + f[k + 1] * e)
            ctx.closePath()
            ctx.lineWidth = e * grow
            ctx.lineJoin = "round"
            ctx.strokeStyle = col
            ctx.stroke()
        }
    }

    // Highest draw seen this session, the fallback when nothing caps watts.
    property real stWattPeak: 500
    // The sub-dial scales to the watt limit set for the mode that is running, so
    // a given sweep means the same thing every session instead of rescaling
    // itself the first time you pull hard.
    readonly property real stWattMax: {
        var on = applyWatts.checked
        if (!on)
            return stWattPeak
        var f = stSecret ? (stMode === 2 ? secretEcoWatts : (stMode === 1 ? secretDriveWatts : secretSportWatts))
                         : (stMode === 2 ? ecoWatts : (stMode === 1 ? driveWatts : sportWatts))
        var v = Number.parseFloat(f.text)
        // the field is per motor; setup-current-in already combines every one
        return v > 0 ? v * stMotors : stWattPeak
    }

    function applyStateLine(line) {
        var p = line.split(" ")
        stOff = parseBoolToken(p[1])
        stLock = parseBoolToken(p[2])
        stLight = parseBoolToken(p[3])
        stSecret = parseBoolToken(p[4])
        stMode = Number.parseInt(p[5]) || 4
        stBatt = Number.parseFloat(p[6]) || 0
        stVin = Number.parseFloat(p[7]) || 0
        stSpeed = Number.parseFloat(p[8]) || 0
        stWatts = Number.parseFloat(p[9]) || 0
        stWhkm = Number.parseFloat(p[10]) || 0
        stRange = Number.parseFloat(p[11]) || 0
        stAmps = Number.parseFloat(p[12]) || 0
        stMax = Number.parseFloat(p[13]) || 60
        stCruise = parseBoolToken(p[14])
        stCruiseEn = parseBoolToken(p[15])
        stCruiseAllow = parseBoolToken(p[16])
        stImgOk = parseBoolToken(p[17])
        stFet = Number.parseFloat(p[18]) || 0
        stMot = Number.parseFloat(p[19]) || 0
        stSecretAllow = parseBoolToken(p[20])
        stMotors = Math.max(1, Number.parseInt(p[21]) || 1)
        stFault = Number.parseInt(p[22]) || 0
        stSlip = Number.parseInt(p[23]) || 0
        stBmsTemp = Number.parseFloat(p[24])
        if (isNaN(stBmsTemp)) stBmsTemp = -100
        stUptime = Number.parseFloat(p[25]) || 0
        if (Math.abs(stWatts) > stWattPeak)
            stWattPeak = Math.abs(stWatts)
    }

    function ctrlCode(str) {
        sendCode(str)
        sendCode("(send-state)")
    }

    function sendCode(str) {
        mCommands.sendCustomAppData(str + "\0")
    }

    // Saving fires a dozen commands and each one blocks the script for as long
    // as its EEPROM writes take, so a fixed gap between them is a guess that a
    // full group can outrun - and the dropped one is the last, which is what
    // reloads the saved values into the running script. Wait for the script to
    // answer instead. A step is idempotent, so a lost answer can be retried.
    property var sendQueue: []
    property string sendCur: ""
    property int sendTries: 0
    property bool sendBusy: false

    function queueCode(str) {
        root.sendQueue.push(str)
        if (!root.sendBusy) sendStep()
    }

    function sendStep() {
        if (root.sendCur === "") {
            if (root.sendQueue.length === 0) {
                root.sendBusy = false
                ackTimer.stop()
                return
            }
            root.sendCur = root.sendQueue.shift()
            root.sendTries = 0
        }
        root.sendBusy = true
        root.sendTries += 1
        mCommands.sendCustomAppData(root.sendCur + "\0")
        ackTimer.restart()
    }

    function stepDone() {
        if (!root.sendBusy) return
        ackTimer.stop()
        root.sendCur = ""
        sendStep()
    }

    // Long enough to clear the slowest step by a wide margin. finish-settings-save
    // reloads, re-applies the mode - which can spend half a second per parameter
    // on a CAN device that does not answer - and then sends all eleven groups
    // back with a 50ms gap between them. Firing early there is worse than not
    // firing at all: the retry re-sends every setting from EEPROM and overwrites
    // whatever is on screen, which reads as a control that refuses to change.
    Timer {
        id: ackTimer
        interval: 6000
        onTriggered: {
            if (root.sendTries >= 2) root.sendCur = ""  // give up, never stall
            root.sendStep()
        }
    }

    // The script looks the names up itself, so a group travels as its name plus
    // its values in the order scooter_support.lisp's setting-groups lists them.
    function saveGroup(name, vals) {
        queueCode("(save-group '" + name + " (list " + vals.join(" ") + "))")
    }

    function boolAtom(box) {
        return box.checked ? "true" : "false"
    }

    function parseBoolToken(token) {
        return token === "true" || token === "1"
    }

    // Wh/km: "0" when zero, one decimal below 10, no decimals from 10 up
    function fmtWhkm(v) {
        if (v < 0.05)
            return "0"
        if (v >= 10)
            return Math.round(v).toString()
        return v.toFixed(1)
    }

    // Lever combo codes: 0=brake+throttle, 1=brake only, 2=throttle only, 3=none
    function comboFromBoxes(brakeBox, throttleBox) {
        if (brakeBox.checked && throttleBox.checked) return 0
        if (brakeBox.checked) return 1
        if (throttleBox.checked) return 2
        return 3
    }

    function setBoxesFromCombo(combo, brakeBox, throttleBox) {
        brakeBox.checked = (combo === 0 || combo === 1)
        throttleBox.checked = (combo === 0 || combo === 2)
    }

    // Boot mode dropdown index <-> speed mode value (2=eco, 1=drive, 4=sport)
    function bootModeValue() {
        return [2, 1, 4][bootMode.currentIndex]
    }

    function setBootMode(value) {
        bootMode.currentIndex = value === 2 ? 0 : (value === 1 ? 1 : 2)
    }

    function pressesIndex(box, token, fallback) {
        var n = Number.parseInt(token)
        box.currentIndex = Number.isNaN(n) ? fallback : n
    }

    function readReal(field, decimals) {
        var number = Number.parseFloat(field.text.replace(",", "."))
        if (!Number.isFinite(number)) {
            number = 0
        }
        return number.toFixed(decimals)
    }

    function setReal(field, value, decimals) {
        var number = Number(value)
        if (Number.isFinite(number)) {
            field.text = (number % 1 === 0) ? number.toString() : number.toFixed(decimals)
        }
    }

    // Current is shown as a percentage in the UI but stored/sent as a 0-1
    // scale (VESC's l_current_max_scale). Convert at the UI boundary, and
    // HARD-CAP at 100% - this is a multiplier of Motor Current Max, so a value
    // above 100 would over-drive the motor. Never let the save path exceed 1.0.
    function readPct(field) {
        var n = Number.parseFloat(field.text.replace(",", "."))
        if (!Number.isFinite(n)) n = 0
        if (n < 0) n = 0
        if (n > 100) n = 100
        return (n / 100).toFixed(3)
    }

    function setPct(field, value) {
        var n = Number(value) * 100
        if (!Number.isFinite(n)) n = 0
        if (n < 0) n = 0
        if (n > 100) n = 100
        field.text = (Math.abs(n - Math.round(n)) < 0.05) ? Math.round(n).toString() : n.toFixed(1)
    }

    // Clamp a current field to 0-100 as soon as the user leaves it (feedback)
    function clampPct(field) {
        setPct(field, readPct(field))
    }

    // Overmodulation: VESC's floor is 1.0 (no overmod). Never save below 1.0 -
    // an empty field or a mistaken 0 would be an invalid/harmful factor.
    function setOm(field, value) {
        var n = Number(value)
        if (Number.isFinite(n)) field.text = (n < 1.0 ? 1.0 : n).toFixed(3)
    }

    function readOm(field) {
        var n = Number.parseFloat(field.text.replace(",", "."))
        if (!Number.isFinite(n) || n < 1.0) n = 1.0
        return n.toFixed(3)
    }

    function clampOm(field) {
        setOm(field, readOm(field))
    }

    // Light compensation gain: never let a blank/garbage entry through as 0
    // (would divide by zero at runtime); floor/ceiling match the firmware clamp.
    function readGain(field) {
        var n = Number.parseFloat(field.text.replace(",", "."))
        if (!Number.isFinite(n)) n = 1.0
        if (n < 0.3) n = 0.3
        if (n > 3.0) n = 3.0
        return n.toFixed(3)
    }

    function setGain(field, value) {
        var n = Number(value)
        if (!Number.isFinite(n)) n = 1.0
        if (n < 0.3) n = 0.3
        if (n > 3.0) n = 3.0
        field.text = n.toFixed(3)
    }

    function clampGain(field) {
        setGain(field, readGain(field))
    }

    function readOffsetV(field) {
        var n = Number.parseFloat(field.text.replace(",", "."))
        if (!Number.isFinite(n)) n = 0.0
        if (n < -1.5) n = -1.5
        if (n > 1.5) n = 1.5
        return n.toFixed(3)
    }

    function setOffsetV(field, value) {
        var n = Number(value)
        if (!Number.isFinite(n)) n = 0.0
        if (n < -1.5) n = -1.5
        if (n > 1.5) n = 1.5
        field.text = n.toFixed(3)
    }

    function clampOffsetV(field) {
        setOffsetV(field, readOffsetV(field))
    }

    // Calibration wizard state (light compensation sampling). One guided
    // button per channel walks through two held lever positions (released,
    // then full press). At each position the light is toggled off/on/off/on
    // and sampled each time, so the light-off and light-on readings are a
    // paired measurement from the identical lever position.
    property string calibRunning: "" // "" / "thr" / "brk" - which channel is active
    property string calibStage: "idle" // "idle" / "prep" / "settle" / "measure" / "release"
    property string calibPhaseLabel: "rel" // "rel" / "full" - lever position being sampled
    property string calibProgress: "" // "n/total" samples taken, shown while measuring
    readonly property real calibPrepDuration: 3.0 // must match scooter_support.lisp calib-prep-duration
    readonly property real calibReleaseDuration: 3.0 // must match calib-release-duration
    property real calibRemaining: 0
    // a failed run leaves its reason on the button it was started from, for a
    // few seconds - the status bar at the foot of the app is too easy to miss
    property string calibError: ""
    property string calibErrorText: ""
    Timer { id: calibErrorTimer; interval: 7000; onTriggered: root.calibError = "" }

    function calibFail(ch, txt) {
        root.calibRunning = ""
        root.calibStage = "idle"
        root.calibError = ch === "" ? "thr" : ch
        root.calibErrorText = txt
        calibErrorTimer.restart()
    }

    // Shown on the button itself while that channel is running, replacing
    // "Calibrate Throttle/Brake"; falls back to the button's normal label
    function calibButtonText(ch) {
        if (calibRunning === "" && calibError === ch)
            return calibErrorText
        if (calibRunning !== ch)
            return ch === "thr" ? "Calibrate Throttle" : "Calibrate Brake"
        var subject = ch === "thr" ? "throttle" : "brake"
        if (calibStage === "release") return "Release " + subject + ", ending."
        // the light toggles several times per position, each far too short for
        // a useful countdown - show sample progress across the run instead
        if (calibStage === "settle" || calibStage === "measure")
            return "Measuring... " + calibProgress
        // prep
        var base = (calibPhaseLabel === "full")
            ? "Press " + subject + " to maximum"
            : "Keep " + subject + " released"
        return base + " " + calibRemaining.toFixed(1) + "s"
    }

    function calibStartChannel(ch) {
        if (calibRunning !== "") return
        calibError = ""
        calibRunning = ch
        calibStage = "prep"
        calibPhaseLabel = "rel"
        calibRemaining = calibPrepDuration
        sendCode(ch === "thr" ? "(calib-start-thr)" : "(calib-start-brk)")
    }

    // Speed fields are stored/sent in km/h but shown in mph when imperial units
    // are on. Convert only at the UI boundary; km/h stays the internal unit.
    readonly property real mphFactor: 0.621371

    function readSpeed(field, decimals) {
        var n = Number.parseFloat(field.text.replace(",", "."))
        if (!Number.isFinite(n)) n = 0
        if (useMph.checked) n = n / mphFactor // mph -> km/h
        return n.toFixed(decimals)
    }

    function setSpeed(field, kmh, decimals) {
        var n = Number(kmh)
        if (!Number.isFinite(n)) return
        if (useMph.checked) n = n * mphFactor // km/h -> mph
        field.text = (Math.abs(n - Math.round(n)) < 0.05) ? Math.round(n).toString() : n.toFixed(decimals)
    }

    // Temperatures ride along with the same switch: the script keeps and stores
    // celsius, the fields and the tiles show fahrenheit when it is on.
    readonly property string degUnit: useMph.checked ? "°F" : "°C"

    function toShownTemp(c) { return useMph.checked ? (c * 9 / 5 + 32) : c }

    function readTemp(field, decimals) {
        var n = Number.parseFloat(field.text.replace(",", "."))
        if (!Number.isFinite(n)) n = 0
        if (useMph.checked) n = (n - 32) * 5 / 9 // F -> C
        return n.toFixed(decimals)
    }

    function setTemp(field, c, decimals) {
        var n = Number(c)
        if (!Number.isFinite(n)) return
        n = toShownTemp(n)
        field.text = (Math.abs(n - Math.round(n)) < 0.05) ? Math.round(n).toString() : n.toFixed(decimals)
    }

    // A warning threshold typed in fahrenheit still has to be compared against
    // the celsius the script reports, so the tiles read the field back down.
    function tempLimitC(field, fallback) {
        var n = Number.parseFloat(field.text.replace(",", "."))
        if (!Number.isFinite(n)) return fallback
        return useMph.checked ? (n - 32) * 5 / 9 : n
    }

    // Re-render all speed and temperature fields when the unit toggle flips
    function convertTempFields(toF) {
        var fs = [tempWarningMotor, tempWarningFet, bmsTempHi, bmsTempLo]
        for (var i = 0; i < fs.length; i++) {
            var n = Number.parseFloat(fs[i].text.replace(",", "."))
            if (!Number.isFinite(n)) continue
            var v = toF ? (n * 9 / 5 + 32) : ((n - 32) * 5 / 9)
            fs[i].text = (Math.abs(v - Math.round(v)) < 0.05) ? Math.round(v).toString() : v.toFixed(1)
        }
    }

    function convertSpeedFields(toMiles) {
        var factor = toMiles ? mphFactor : (1 / mphFactor)
        var fs = [ecoSpeed, driveSpeed, sportSpeed, secretEcoSpeed, secretDriveSpeed,
            secretSportSpeed, minSpeed, buttonSpeed, cruiseDeviation, cruiseMinSpeed,
            cruiseMaxSpeed, alarmSpeedThreshold]
        for (var i = 0; i < fs.length; i++) {
            var n = Number.parseFloat(fs[i].text.replace(",", "."))
            if (Number.isFinite(n)) {
                var v = n * factor
                fs[i].text = (Math.abs(v - Math.round(v)) < 0.05) ? Math.round(v).toString() : v.toFixed(1)
            }
        }
    }

    function saveAllSettings() {
        if (!settingsLoaded || saving)
            return
        saving = true
        saveTimeout.restart()
        // One call per group, values in the order setting-groups lists them.
        saveGroup("misc", [boolAtom(lightOnBoot), readSpeed(buttonSpeed, 1), boolAtom(useMph),
            boolAtom(bmsSoc), boolAtom(secretExitOnLock),
            readOffsetV(lightOffThr), readGain(lightGainThr),
            readOffsetV(lightOffBrk), readGain(lightGainBrk),
            (Number.parseInt(appPin.text) || 0), dashPowerOut.currentIndex,
            boolAtom(headOffLock)])

        saveGroup("general", [boolAtom(softwareAdc), boolAtom(softwareAdc2),
            boolAtom(showBatteryInIdle), boolAtom(showBatterySecret),
            readSpeed(minSpeed, 1), boolAtom(appEnable), idleDisplay.currentIndex])

        saveGroup("temps", [readTemp(tempWarningMotor, 1), readTemp(tempWarningFet, 1),
            readTemp(bmsTempHi, 1), readTemp(bmsTempLo, 1)])

        saveGroup("modes", [
            readSpeed(ecoSpeed, 1), readPct(ecoCurrent), readReal(ecoWatts, 0), readReal(ecoFw, 1),
            readSpeed(driveSpeed, 1), readPct(driveCurrent), readReal(driveWatts, 0), readReal(driveFw, 1),
            readSpeed(sportSpeed, 1), readPct(sportCurrent), readReal(sportWatts, 0), readReal(sportFw, 1),
            bootModeValue(), readOm(ecoOm), readOm(driveOm), readOm(sportOm)])

        saveGroup("secret", [boolAtom(secretEnabled),
            readSpeed(secretEcoSpeed, 1), readPct(secretEcoCurrent), readReal(secretEcoWatts, 0), readReal(secretEcoFw, 1),
            readSpeed(secretDriveSpeed, 1), readPct(secretDriveCurrent), readReal(secretDriveWatts, 0), readReal(secretDriveFw, 1),
            readSpeed(secretSportSpeed, 1), readPct(secretSportCurrent), readReal(secretSportWatts, 0), readReal(secretSportFw, 1),
            readOm(secretEcoOm), readOm(secretDriveOm), readOm(secretSportOm)])

        saveGroup("apply", [boolAtom(applySpeed), boolAtom(applyCurrent), boolAtom(applyWatts),
            boolAtom(applyFw), boolAtom(applyOm)])

        saveGroup("gesture", [
            secretPresses.currentIndex, comboFromBoxes(secretBrake, secretThrottle), boolAtom(secretRequiresLock),
            (lockPresses.currentIndex + 1), comboFromBoxes(lockBrake, lockThrottle),
            modePresses.currentIndex, comboFromBoxes(modeBrake, modeThrottle), boolAtom(modeLocked),
            lightPresses.currentIndex, comboFromBoxes(lightBrake, lightThrottle), boolAtom(lightLocked),
            secretOffPresses.currentIndex, comboFromBoxes(secretOffBrake, secretOffThrottle),
            boolAtom(secretOffRequiresLock)])

        saveGroup("rear", [boolAtom(rearLightEnable), boolAtom(autoTaillight),
            [1, 2, 0][brakeLightMode.currentIndex],
            ((tailBright.currentIndex + 1) / 10), boolAtom(tailOffLock)])

        saveGroup("cruise", [boolAtom(cruiseEnable), readReal(cruiseDelay, 1),
            readSpeed(cruiseDeviation, 1), readSpeed(cruiseMinSpeed, 1), readSpeed(cruiseMaxSpeed, 1)])

        saveGroup("alarm", [boolAtom(alarmTone), readSpeed(alarmSpeedThreshold, 1),
            readReal(alarmGyroThreshold, 1), readReal(alarmVoltage, 1)])

        queueCode("(finish-settings-save)")

        // Model change needs a lisp restart, ack-gated via "model-ok"
        if (modelBox.currentIndex !== loadedModel) {
            queueCode("(save-model " + modelBox.currentIndex + ")")
        }
    }

    function getSettings() {
        sendCode("(send-settings)")
    }

    // Picking a model is the moment a controller's settings are defined - it may
    // have run another package, or an older version of this one, and whatever
    // that left behind is still in the slots. The script sends the defaults for
    // every group, they land in the fields as an unsaved change, and the save
    // writes them over the top. Slave drives nothing, so it is left alone.
    function modelPicked(idx) {
        cfgDirty = true
        if (idx !== 2) sendCode("(send-defaults)")
    }

    property var cfgLines: ({})

    // The export is the very lines the script sends, so nothing can drift out of
    // step with the parser. The model is left out: it is per unit, and applying it
    // needs the restart that saving a model does.
    // misc first, exactly as send-settings orders it: it carries the mph switch, and
    // every speed after it is formatted for whichever unit it sets
    readonly property var cfgKeys: ["misc", "general", "temps", "modes", "secret",
        "apply", "gesture", "rear", "cruise", "alarm"]

    function cfgExport() {
        var out = ["vss-settings 1"]
        for (var i = 0; i < cfgKeys.length; i++) {
            var l = cfgLines[cfgKeys[i]]
            if (l !== undefined) out.push(l)
        }
        return out.join("\n")
    }

    // returns the number of groups applied, or -1 if this is not one of ours
    function cfgImport(txt) {
        var lines = txt.split("\n")
        var head = false
        var found = ({})
        for (var i = 0; i < lines.length; i++) {
            var l = lines[i].trim()
            if (l.length === 0) continue
            if (l.indexOf("vss-settings") === 0) { head = true; continue }
            var key = l.split(" ")[0]
            if (cfgKeys.indexOf(key) >= 0) found[key] = l
        }
        if (!head) return -1

        // Apply in cfgKeys order whatever order the file is in, and hold
        // settingsLoaded down: it is what gates useMph's field conversion, which
        // would otherwise convert values that arrived already converted.
        var wasLoaded = settingsLoaded
        settingsLoaded = false
        var n = 0
        // A backup from an older release is short a field or two per group.
        // Nothing downstream notices: setReal ignores a missing number, but
        // parseBoolToken reads undefined as false, so every toggle the old
        // build did not have would import as off. The line the script last sent
        // says how many fields a group takes now - anything else is refused.
        var skipped = 0
        for (var k = 0; k < cfgKeys.length; k++) {
            var line = found[cfgKeys[k]]
            if (line === undefined)
                continue
            var known = cfgLines[cfgKeys[k]]
            if (known !== undefined
                    && line.split(" ").length !== known.split(" ").length) {
                skipped += 1
                continue
            }
            applySettingsLine(line)
            n += 1
        }
        settingsLoaded = wasLoaded
        if (skipped > 0)
            VescIf.emitStatusMessage(
                "Skipped " + skipped + " group(s) from an older backup.", false)
        return n
    }

    function applySettingsLine(line) {
        var parts = line.split(" ")
        markSettingsSeen(parts[0])
        cfgLines[parts[0]] = line

        if (parts[0] === "model") {
            loadedModel = Number.parseInt(parts[1])
            modelBox.currentIndex = loadedModel
        } else if (parts[0] === "general") {
            softwareAdc.checked = parseBoolToken(parts[1])
            softwareAdc2.checked = parseBoolToken(parts[2])
            showBatteryInIdle.checked = parseBoolToken(parts[3])
            showBatterySecret.checked = parseBoolToken(parts[4])
            setSpeed(minSpeed, parts[5], 1)
            appEnable.checked = parseBoolToken(parts[6])
            idleDisplay.currentIndex = Number.parseInt(parts[7]) || 0
        } else if (parts[0] === "temps") {
            setTemp(tempWarningMotor, parts[1], 1)
            setTemp(tempWarningFet, parts[2], 1)
            setTemp(bmsTempHi, parts[3], 1)
            setTemp(bmsTempLo, parts[4], 1)
        } else if (parts[0] === "modes") {
            setSpeed(ecoSpeed, parts[1], 1)
            setPct(ecoCurrent, parts[2])
            setReal(ecoWatts, parts[3], 0)
            setReal(ecoFw, parts[4], 1)
            setSpeed(driveSpeed, parts[5], 1)
            setPct(driveCurrent, parts[6])
            setReal(driveWatts, parts[7], 0)
            setReal(driveFw, parts[8], 1)
            setSpeed(sportSpeed, parts[9], 1)
            setPct(sportCurrent, parts[10])
            setReal(sportWatts, parts[11], 0)
            setReal(sportFw, parts[12], 1)
            setBootMode(Number.parseInt(parts[13]) || 4)
            setOm(ecoOm, parts[14])
            setOm(driveOm, parts[15])
            setOm(sportOm, parts[16])
        } else if (parts[0] === "secret") {
            secretEnabled.checked = parseBoolToken(parts[1])
            setSpeed(secretEcoSpeed, parts[2], 1)
            setPct(secretEcoCurrent, parts[3])
            setReal(secretEcoWatts, parts[4], 0)
            setReal(secretEcoFw, parts[5], 1)
            setSpeed(secretDriveSpeed, parts[6], 1)
            setPct(secretDriveCurrent, parts[7])
            setReal(secretDriveWatts, parts[8], 0)
            setReal(secretDriveFw, parts[9], 1)
            setSpeed(secretSportSpeed, parts[10], 1)
            setPct(secretSportCurrent, parts[11])
            setReal(secretSportWatts, parts[12], 0)
            setReal(secretSportFw, parts[13], 1)
            setOm(secretEcoOm, parts[14])
            setOm(secretDriveOm, parts[15])
            setOm(secretSportOm, parts[16])
        } else if (parts[0] === "apply") {
            applySpeed.checked = parseBoolToken(parts[1])
            applyCurrent.checked = parseBoolToken(parts[2])
            applyWatts.checked = parseBoolToken(parts[3])
            applyFw.checked = parseBoolToken(parts[4])
            applyOm.checked = parseBoolToken(parts[5])
        } else if (parts[0] === "gesture") {
            pressesIndex(secretPresses, parts[1], 2)
            setBoxesFromCombo(Number.parseInt(parts[2]) || 0, secretBrake, secretThrottle)
            secretRequiresLock.checked = parseBoolToken(parts[3])
            var lp = Number.parseInt(parts[4])
            lockPresses.currentIndex = (Number.isNaN(lp) || lp < 1) ? 1 : lp - 1
            setBoxesFromCombo(Number.parseInt(parts[5]) || 0, lockBrake, lockThrottle)
            pressesIndex(modePresses, parts[6], 2)
            setBoxesFromCombo(Number.parseInt(parts[7]) || 0, modeBrake, modeThrottle)
            modeLocked.checked = parseBoolToken(parts[8])
            pressesIndex(lightPresses, parts[9], 1)
            setBoxesFromCombo(Number.parseInt(parts[10]) || 0, lightBrake, lightThrottle)
            lightLocked.checked = parseBoolToken(parts[11])
            pressesIndex(secretOffPresses, parts[12], 3)
            setBoxesFromCombo(Number.parseInt(parts[13]) || 0, secretOffBrake, secretOffThrottle)
            secretOffRequiresLock.checked = parseBoolToken(parts[14])
        } else if (parts[0] === "misc") {
            useMph.checked = parseBoolToken(parts[3]) // set unit before any speed field
            lightOnBoot.checked = parseBoolToken(parts[1])
            setSpeed(buttonSpeed, parts[2], 1)
            bmsSoc.checked = parseBoolToken(parts[4])
            secretExitOnLock.checked = parseBoolToken(parts[5])
            setOffsetV(lightOffThr, parts[6])
            setGain(lightGainThr, parts[7])
            setOffsetV(lightOffBrk, parts[8])
            setGain(lightGainBrk, parts[9])
            appPin.text = ("00000" + (Number.parseInt(parts[10]) || 0)).slice(-6)
            dashPowerOut.currentIndex = Number.parseInt(parts[11]) || 0
            headOffLock.checked = parseBoolToken(parts[12])
        } else if (parts[0] === "rear") {
            rearLightEnable.checked = parseBoolToken(parts[1])
            autoTaillight.checked = parseBoolToken(parts[2])
            var blm = Number.parseInt(parts[3])
            brakeLightMode.currentIndex = blm === 1 ? 0 : (blm === 2 ? 1 : 2)
            tailBright.currentIndex = Math.max(0, Math.min(9,
                Math.round((Number.parseFloat(parts[4]) || 0.4) * 10) - 1))
            tailOffLock.checked = parseBoolToken(parts[5])
        } else if (parts[0] === "cruise") {
            cruiseEnable.checked = parseBoolToken(parts[1])
            setReal(cruiseDelay, parts[2], 1)
            setSpeed(cruiseDeviation, parts[3], 1)
            setSpeed(cruiseMinSpeed, parts[4], 1)
            setSpeed(cruiseMaxSpeed, parts[5], 1)
        } else if (parts[0] === "alarm") {
            alarmTone.checked = parseBoolToken(parts[1])
            setSpeed(alarmSpeedThreshold, parts[2], 1)
            setReal(alarmGyroThreshold, parts[3], 1)
            setReal(alarmVoltage, parts[4], 1)
        }
    }

    Component.onCompleted: {
        initPrefs()
        // page 0 is the Control tab - its switches are written when they are
        // flipped, so they are not what Save is for. Settings loading must not
        // depend on this working, so it goes first and cannot take it down.
        try {
            for (var i = 1; i < swipeView.count; i++)
                watchEdits(swipeView.itemAt(i))
        } catch (e) {
            console.log("watchEdits: " + e)
        }
        getSettings()
    }

    Timer {
        id: restartTimer
        interval: 400
        onTriggered: {
            mCommands.lispSetRunning(true)
            reloadTimer.start()
        }
    }

    Timer {
        id: reloadTimer
        interval: 1500
        onTriggered: getSettings()
    }

    Timer {
        interval: 150
        repeat: true
        running: swipeView.currentIndex === 3 && (softwareAdc.checked || softwareAdc2.checked)
        onTriggered: mCommands.getDecodedAdc()
    }

    // Motor current and trip distance are the controller's own figures, so they
    // are read from it rather than carried through the script. Setup values are
    // combined across CAN, which is what setup-current-in gives the rest of the
    // state line, and tachometer_abs is metres with the wheel size applied.
    Timer {
        interval: 300
        repeat: true
        running: swipeView.currentIndex === 0
        onTriggered: mCommands.getValuesSetup()
    }

    // Client-side countdown for the light-calibration hold. Purely visual -
    // the actual result comes from calib-progress/calib-result messages, so a
    // slightly early/late display here has no functional effect.
    Timer {
        interval: 200
        repeat: true
        running: root.calibRunning !== ""
        onTriggered: {
            root.calibRemaining = Math.max(0, root.calibRemaining - 0.2)
        }
    }

    // Clears the "Saving..." state if the ack never comes back. Every setting
    // written yields to the rest of the system, so a full save is a few seconds.
    Timer {
        id: saveTimeout
        interval: 25000
        onTriggered: root.saving = false
    }

    // mc_fault_code in firmware order. A code past the end of the table is shown
    // as its number rather than guessed at, so a newer firmware still reads.
    readonly property var faultNames: [
        "None", "Over Voltage", "Under Voltage", "DRV", "ABS Over Current",
        "ESC Over Temperature", "Motor Over Temperature",
        "Gate Driver Over Voltage", "Gate Driver Under Voltage",
        "MCU Under Voltage", "Booting From Watchdog Reset", "Encoder SPI",
        "Encoder Sin/Cos Below Min Amplitude", "Encoder Sin/Cos Above Max Amplitude",
        "Flash Corruption", "High Offset Current Sensor 1",
        "High Offset Current Sensor 2", "High Offset Current Sensor 3",
        "Unbalanced Currents", "Brake", "Resolver LOT", "Resolver DOS",
        "Resolver LOS", "Flash Corruption App CFG", "Flash Corruption MC CFG",
        "Encoder No Magnet", "Encoder Magnet Too Strong", "Phase Filter",
        "Encoder Fault", "LV Output Fault"
    ]

    function faultName(code) {
        return (code >= 0 && code < faultNames.length) ? faultNames[code]
                                                       : ("Fault " + code)
    }

    Dialog {
        id: faultInfo
        background: Rectangle { radius: 16; color: root.cDialog }
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Math.min(parent.width - 40, 360)
        modal: true

        ColumnLayout {
            width: faultInfo.availableWidth
            spacing: 6

            Label {
                Layout.fillWidth: true
                Layout.bottomMargin: 4
                text: "Controller Fault"
                font.bold: true
                font.pointSize: root.titleSize * 1.1
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: faultText.implicitHeight + 28
                radius: 12
                color: root.cWarnBg
                Label {
                    id: faultText
                    anchors.fill: parent
                    anchors.margins: 14
                    wrapMode: Text.WordWrap
                    verticalAlignment: Text.AlignVCenter
                    text: root.faultName(root.stFault) + "  (" + root.stFault + ")"
                    font.bold: true
                    color: root.cWarnInk
                }
            }

            Label {
                Layout.fillWidth: true
                Layout.topMargin: 2
                wrapMode: Text.WordWrap
                text: "The controller's own fault code. VESC Tool's terminal has the "
                      + "full history with the values at the moment it tripped."
                font.pointSize: root.titleSize * 0.82
                color: root.cDim
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 6
                Layout.preferredHeight: 44
                radius: 12
                color: faultClose.pressed ? root.cCtlHi : root.cCtl
                Label {
                    anchors.centerIn: parent
                    text: "Close"
                    font.bold: true
                    color: root.cInk
                }
                MouseArea {
                    id: faultClose
                    anchors.fill: parent
                    onClicked: faultInfo.close()
                }
            }
        }
    }

    Dialog {
        id: statPick
        property int slot: 0
        function openAt(i) { slot = i; open() }
        background: Rectangle { radius: 16; color: root.cDialog }
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Math.min(parent.width - 40, 360)
        modal: true

        ColumnLayout {
            width: statPick.availableWidth
            spacing: 6

            Label {
                Layout.fillWidth: true
                Layout.bottomMargin: 4
                text: "Select content:"
                horizontalAlignment: Text.AlignHCenter
                font.bold: true
                font.pointSize: root.titleSize * 1.1
            }

            Repeater {
                model: root.statOptsShown
                Rectangle {
                    id: optRow
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: 12
                    property bool taken: root.statSel[statPick.slot] === modelData.key
                    color: taken ? root.cAccentBg2 : (optTouch.pressed ? root.cCtlHi : root.cCtl)
                    Label {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.name
                        font.bold: true
                        color: optRow.taken ? root.cAccent : root.cInk
                    }
                    MouseArea {
                        id: optTouch
                        anchors.fill: parent
                        onClicked: { root.setStat(statPick.slot, modelData.key); statPick.close() }
                    }
                }
            }
        }
    }

    Dialog {
        id: resetDialog
        background: Rectangle { radius: 16; color: root.cDialog }
        // centred from bindings that re-run when the size changes. anchors.centerIn
        // settles once, while the content is still resolving its width, and the
        // offset it lands on then sticks for every later open.
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Math.min(parent.width - 40, 360)
        modal: true
        // No title and no standardButtons: either one makes Material build a header
        // or footer with an opaque background of its own, drawn over the rounded
        // one - which is what banded the top and bottom. The title and the buttons
        // are part of the content instead, and match the rest of the UI.

        ColumnLayout {
            width: resetDialog.availableWidth
            spacing: 10

            Label {
                Layout.fillWidth: true
                text: "Reset all settings?"
                font.bold: true
                font.pointSize: root.titleSize * 1.1
            }

            Label {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                wrapMode: Text.WordWrap
                text: "This restores every setting to defaults, including the model, "
                      + "which goes back to Slave. The script restarts. This cannot be undone."
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 44
                    radius: 12
                    color: resetNo.pressed ? root.cCtlHi : root.cCtl
                    Label { anchors.centerIn: parent; text: "Cancel"; font.bold: true; color: root.cInk }
                    MouseArea { id: resetNo; anchors.fill: parent; onClicked: resetDialog.close() }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 44
                    radius: 12
                    color: resetYes.pressed ? "#d43a34" : "#c31f1f"
                    Label { anchors.centerIn: parent; text: "Reset"; font.bold: true; color: "#ffffff" }
                    MouseArea { id: resetYes; anchors.fill: parent; onClicked: {
                        resetDialog.close()
                        resetSettingsLoad()
                        sendCode("(restore-settings-ui)")
                    } }
                }
            }
        }
    }

    // Material's own item delegate draws a square highlight inside our rounded
    // popup. ListView.isCurrentItem is what the popup binds to highlightedIndex,
    // so one delegate serves every dropdown without knowing which one it is in.
    Component {
        id: comboItem
        ItemDelegate {
            id: comboCell
            width: ListView.view ? ListView.view.width : implicitWidth
            height: 34
            text: modelData
            font.weight: Font.Normal; font.pointSize: root.titleSize * 0.95
            highlighted: ListView.isCurrentItem
            background: Rectangle {
                radius: 10
                color: comboCell.highlighted ? root.cEdge : "transparent"
            }
        }
    }

    // VESC Tool's QML has no way to write a file on the phone or the desktop, so a
    // backup travels as text through the clipboard - paste it wherever you keep it.
    Dialog {
        id: exportDialog
        background: Rectangle { radius: 16; color: root.cDialog }
        // centred from bindings that re-run when the size changes. anchors.centerIn
        // settles once, while the content is still resolving its width, and the
        // offset it lands on then sticks for every later open.
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Math.min(parent.width - 40, 420)
        modal: true
        // No title and no standardButtons: either one makes Material build a header
        // or footer with an opaque background of its own, drawn over the rounded
        // one - which is what banded the top and bottom. The title and the buttons
        // are part of the content instead, and match the rest of the UI.

        ColumnLayout {
            width: exportDialog.availableWidth
            spacing: 8

            Label {
                Layout.fillWidth: true
                text: "Export settings"
                font.bold: true
                font.pointSize: root.titleSize * 1.1
            }

            Label {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                wrapMode: Text.WordWrap
                text: "This is everything saved on the ESC except the model. Copy it and "
                      + "keep it somewhere - a note, a file, a message to yourself."
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 150
                radius: 10
                color: root.cWell

                // TextArea.flickable is what makes a text box scroll: attached that
                // way the TextArea drives the Flickable's contentHeight and keeps the
                // caret in view. Anchored inside a fixed height parent it just grew
                // past it instead, with the caret walking off the bottom.
                Flickable {
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true
                    flickableDirection: Flickable.VerticalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    TextArea.flickable: TextArea {
                        id: exportText
                        readOnly: true
                        wrapMode: TextArea.Wrap
                        font.family: "monospace"
                        font.pointSize: root.titleSize * 0.72
                        padding: 0
                        background: Item {}
                    }
                    ScrollBar.vertical: ScrollBar { }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 8
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 44
                    radius: 12
                    color: closeTouch.pressed ? root.cCtlHi : root.cCtl
                    Label { anchors.centerIn: parent; text: "Close"; font.bold: true }
                    MouseArea { id: closeTouch; anchors.fill: parent; onClicked: exportDialog.close() }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 2
                    Layout.preferredHeight: 44
                    radius: 12
                    color: copyTouch.pressed ? "#1f9c2e" : "#1b8728"
                    Label { anchors.centerIn: parent; text: "Copy"; font.bold: true; color: "#ffffff" }
                    MouseArea {
                        id: copyTouch
                        anchors.fill: parent
                        onClicked: {
                            exportText.selectAll()
                            exportText.copy()
                            exportText.deselect()
                            VescIf.emitStatusMessage("Settings copied to clipboard.", true)
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: importDialog
        background: Rectangle { radius: 16; color: root.cDialog }
        // centred from bindings that re-run when the size changes. anchors.centerIn
        // settles once, while the content is still resolving its width, and the
        // offset it lands on then sticks for every later open.
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Math.min(parent.width - 40, 420)
        modal: true
        // No title and no standardButtons: either one makes Material build a header
        // or footer with an opaque background of its own, drawn over the rounded
        // one - which is what banded the top and bottom. The title and the buttons
        // are part of the content instead, and match the rest of the UI.

        ColumnLayout {
            width: importDialog.availableWidth
            spacing: 8

            Label {
                Layout.fillWidth: true
                text: "Import settings"
                font.bold: true
                font.pointSize: root.titleSize * 1.1
            }

            Label {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                wrapMode: Text.WordWrap
                text: "Paste a backup here. It only fills in the fields - press Save "
                      + "afterwards to write it to the ESC."
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 150
                radius: 10
                color: root.cWell

                // TextArea.flickable is what makes a text box scroll: attached that
                // way the TextArea drives the Flickable's contentHeight and keeps the
                // caret in view. Anchored inside a fixed height parent it just grew
                // past it instead, with the caret walking off the bottom.
                Flickable {
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true
                    flickableDirection: Flickable.VerticalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    TextArea.flickable: TextArea {
                        id: importText
                        wrapMode: TextArea.Wrap
                        font.family: "monospace"
                        font.pointSize: root.titleSize * 0.72
                        padding: 0
                        background: Item {}
                    }
                    ScrollBar.vertical: ScrollBar { }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 8
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 44
                    radius: 12
                    color: cancelTouch.pressed ? root.cCtlHi : root.cCtl
                    Label { anchors.centerIn: parent; text: "Cancel"; font.bold: true }
                    MouseArea { id: cancelTouch; anchors.fill: parent; onClicked: importDialog.close() }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 44
                    radius: 12
                    color: pasteTouch.pressed ? root.cCtlHi : root.cCtl
                    Label { anchors.centerIn: parent; text: "Paste"; font.bold: true }
                    MouseArea {
                        id: pasteTouch
                        anchors.fill: parent
                        onClicked: { importText.selectAll(); importText.paste() }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 44
                    radius: 12
                    color: applyTouch.pressed ? "#1f9c2e" : "#1b8728"
                    Label { anchors.centerIn: parent; text: "Apply"; font.bold: true; color: "#ffffff" }
                    MouseArea {
                        id: applyTouch
                        anchors.fill: parent
                        onClicked: {
                            var n = root.cfgImport(importText.text)
                            if (n < 0) {
                                VescIf.emitStatusMessage("That is not a settings backup.", false)
                            } else if (n === 0) {
                                VescIf.emitStatusMessage("Nothing in that backup could be read.", false)
                            } else {
                                importDialog.close()
                                VescIf.emitStatusMessage(n + " groups loaded - press Save to keep them.", true)
                            }
                        }
                    }
                }
            }
        }
    }

    // The script may still be booting (or writing first-install defaults)
    // when the UI opens - keep asking until it answers
    Timer {
        interval: 1200
        repeat: true
        running: !root.settingsLoaded
        onTriggered: getSettings()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 4

        // No chrome on the Control screen - its gear lives in the dial. This
        // header is the settings one: a way back, and a section picker.
        Item {
            visible: swipeView.currentIndex !== 0
            Layout.fillWidth: true
            Layout.preferredHeight: 42

            Rectangle {
                id: backBtn
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                height: 38
                radius: 12
                color: backTouch.pressed ? root.cCtlHi : root.cWell
                Behavior on color { ColorAnimation { duration: 140 } }

                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        var cx = width / 2
                        var cy = height / 2
                        var d = height * 0.20
                        ctx.strokeStyle = root.cInk
                        ctx.lineWidth = Math.max(2, height * 0.075)
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        ctx.beginPath()
                        ctx.moveTo(cx + d * 0.6, cy - d)
                        ctx.lineTo(cx - d * 0.6, cy)
                        ctx.lineTo(cx + d * 0.6, cy + d)
                        ctx.stroke()
                    }
                }
                MouseArea {
                    id: backTouch
                    anchors.fill: parent
                    onClicked: swipeView.currentIndex = 0
                }
            }

            Rectangle {
                id: secTrack
                anchors.left: backBtn.right
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 38
                radius: 12
                color: root.cWell

                Rectangle {
                    width: secTrack.width / 3
                    height: parent.height
                    radius: parent.radius
                    x: (swipeView.currentIndex - 1) * secTrack.width / 3
                    color: root.cEdge
                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }

                Row {
                    anchors.fill: parent
                    Repeater {
                        model: ["General", "Modes", "Setup"]
                        Item {
                            width: secTrack.width / 3
                            height: secTrack.height
                            Label {
                                anchors.centerIn: parent
                                text: modelData
                                font.bold: true
                                font.pointSize: root.titleSize * 0.95
                                color: swipeView.currentIndex === index + 1 ? root.cInk : root.cDim2
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: swipeView.currentIndex = index + 1
                            }
                        }
                    }
                }
            }
        }

        SwipeView {
            id: swipeView
            currentIndex: 0
            interactive: false
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Page {
                // Not enabled: !isSlave - the gear that reaches Setup is on this
                // page, and enabled is ANDed down the tree, so disabling the page
                // would leave a slaved unit with no way into its own settings.
                // The controls that command a scooter are gated one by one below.

                // Adaptive polling: keep at most one request in flight so it
                // paces to the BLE round-trip instead of piling up (which caused
                // periodic stalls). Re-sends after 700 ms if a reply is lost.
                Timer {
                    interval: 40
                    repeat: true
                    running: swipeView.currentIndex === 0 && !root.isSlave
                    onTriggered: {
                        var now = Date.now()
                        if (!root.statePending || (now - root.statePendingSince) > 700) {
                            root.statePending = true
                            root.statePendingSince = now
                            sendCode("(send-state)")
                        }
                    }
                }

                ScrollView {
                    id: ctlScroll
                    anchors.fill: parent
                    contentWidth: availableWidth
                    contentHeight: ctlCol.implicitHeight
                    clip: true
                    // Both explicit: a ColumnLayout sized off parent.width leaves
                    // ScrollView deriving contentHeight from an item whose own parent
                    // is height driven BY contentHeight, and it latches short. Overshoot
                    // hid that, because a drag always did something.
                    // nothing to scroll means nothing moves - the flickable a
                    // ScrollView makes still rubber bands a page that already fits
                    Component.onCompleted: contentItem.boundsBehavior = Flickable.StopAtBounds

                    // The dial, the battery bar and the figure cards follow the
                    // width and nothing else. Only the buttons, the mode picker and
                    // the gaps give way to a short window, and only down to 0.69 -
                    // hS is solved so the page fills the height exactly until it
                    // hits that floor, and scrolls from there.
                    readonly property real wS: Math.max(0.85, Math.min(1.25, availableWidth / 320))
                    // 96 is the height nothing scales: three 3px gaps between the three
                    // cards, 25 around the dial inside its own, the readings card's 2, and
                    // 20 of padding in it plus 40 in the buttons card, whose two rows each
                    // grew 10. 229 is what hS moves. 68 is the battery bar and the figure
                    // cards, which follow the width; 250 is everything hS does move.
                    readonly property real hS: Math.max(0.69, Math.min(1.0,
                        (height - availableWidth * 0.767 - 96 - 68 * wS) / 229))

                    ColumnLayout {
                        id: ctlCol
                        width: ctlScroll.availableWidth
                        spacing: 3

                        Rectangle {
                            visible: !root.stImgOk
                            Layout.fillWidth: true
                            Layout.topMargin: 10
                            Layout.preferredHeight: imgWarnText.implicitHeight + 20
                            radius: 12
                            color: root.cWarnBg
                            border.color: "#ff5252"
                            border.width: 1
                            Label {
                                id: imgWarnText
                                anchors.fill: parent
                                anchors.margins: 10
                                text: "Script too big to save - it will not start after a reboot."
                                color: root.cWarnInk
                                font.bold: true
                                wrapMode: Text.WordWrap
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        // Speed dial. Drawn rather than assembled from segments so
                        // it sweeps smoothly, and the value it paints is animated
                        // so it glides between samples that arrive three times a
                        // second. The 240 degree sweep leaves the lower right open
                        // for the power sub-dial.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: dial.height + 25
                            radius: 18
                            color: root.cDeep
                            border.width: root.darkUi ? 0 : 1
                            border.color: root.cEdge

                        Item {
                            id: dial
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.topMargin: 10
                            // only as tall as the arc reaches - it stops at bottom
                            // left, so the circle's bottom quarter is dead space
                            height: dcy + drad * 0.7071 + dlw / 2

                            readonly property real dcx: width / 2
                            readonly property real drad: width * 0.40
                            readonly property real dlw: Math.max(12, drad * 0.21)
                            readonly property real dcy: drad + dlw / 2
                            readonly property real srad: drad * 0.33
                            readonly property real slw: Math.max(6, srad * 0.20)
                            readonly property real ccd: dlw // as wide as the ring is thick
                            readonly property real pad: width * 0.02
                            // Both arcs stop at 135 and 330 degrees, so what the eye
                            // reads as their bottom and right is 0.7071 and 0.866 of the
                            // radius from centre, not the radius. Line the sub-dial up
                            // with those, or it sits short of both edges.
                            readonly property real subx: dcx + drad + dlw / 2 - srad * 0.866 - slw / 2
                            readonly property real suby: dcy + drad * 0.7071 + dlw / 2 - srad * 0.7071 - slw / 2

                            readonly property real shown: useMph.checked ? (root.stSpeed * 0.621371) : root.stSpeed
                            readonly property real shownMax: Math.max(1, useMph.checked ? (root.stMax * 0.621371) : root.stMax)

                            Canvas {
                                id: dialArc
                                anchors.fill: parent

                                property real sFrac: Math.max(0, Math.min(1, dial.shown / dial.shownMax))
                                property real wFrac: Math.max(0, Math.min(1, Math.abs(root.stWatts) / root.stWattMax))
                                property real sAnim: 0
                                property real wAnim: 0
                                Behavior on sAnim { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                Behavior on wAnim { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                onSFracChanged: sAnim = sFrac
                                onWFracChanged: wAnim = wFrac
                                onSAnimChanged: requestPaint()
                                onWAnimChanged: requestPaint()
                                Component.onCompleted: { sAnim = sFrac; wAnim = wFrac; requestPaint() }

                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.reset()
                                    ctx.lineCap = "round"

                                    var cx = dial.dcx, cy = dial.dcy, r = dial.drad
                                    var a0 = Math.PI * 0.75         // bottom left
                                    var a1 = Math.PI * (330 / 180)  // top right

                                    ctx.lineWidth = dial.dlw
                                    ctx.strokeStyle = root.cCtl
                                    ctx.beginPath()
                                    ctx.arc(cx, cy, r, a0, a1, false)
                                    ctx.stroke()

                                    if (sAnim > 0.004) {
                                        var g = ctx.createLinearGradient(cx - r, cy + r, cx + r, cy - r)
                                        g.addColorStop(0, "#f4ba2a")
                                        g.addColorStop(1, "#ec6e1c")
                                        ctx.strokeStyle = g
                                        ctx.beginPath()
                                        ctx.arc(cx, cy, r, a0, a0 + (a1 - a0) * sAnim, false)
                                        ctx.stroke()
                                    }

                                    var sr = dial.srad
                                    var b0 = a0
                                    var b1 = a1

                                    ctx.lineWidth = dial.slw
                                    ctx.strokeStyle = root.cCtl
                                    ctx.beginPath()
                                    ctx.arc(dial.subx, dial.suby, sr, b0, b1, false)
                                    ctx.stroke()

                                    if (wAnim > 0.004) {
                                        ctx.strokeStyle = root.stWatts < 0 ? "#5edf64" : "#70cef8"
                                        ctx.beginPath()
                                        ctx.arc(dial.subx, dial.suby, sr, b0, b0 + (b1 - b0) * wAnim, false)
                                        ctx.stroke()
                                    }
                                }
                            }

                            Label {
                                id: speedNum
                                anchors.horizontalCenter: parent.left
                                anchors.horizontalCenterOffset: dial.dcx
                                anchors.verticalCenter: parent.top
                                anchors.verticalCenterOffset: dial.dcy - dial.drad * 0.06
                                text: Math.round(dial.shown)
                                font.pixelSize: dial.drad * 0.50
                                font.bold: true
                            }
                            Label {
                                anchors.horizontalCenter: speedNum.horizontalCenter
                                anchors.top: speedNum.bottom
                                anchors.topMargin: -6
                                text: useMph.checked ? "mph" : "km/h"
                                font.pixelSize: dial.drad * 0.13
                                opacity: 0.55
                            }

                            Label {
                                id: wattNum
                                anchors.horizontalCenter: parent.left
                                anchors.horizontalCenterOffset: dial.subx
                                anchors.verticalCenter: parent.top
                                anchors.verticalCenterOffset: dial.suby
                                text: Math.round(root.stWatts)
                                font.pixelSize: dial.srad * 0.55
                                font.bold: true
                            }
                            Label {
                                anchors.horizontalCenter: wattNum.horizontalCenter
                                anchors.top: wattNum.bottom
                                anchors.topMargin: -4
                                text: "W"
                                font.pixelSize: dial.srad * 0.28
                                opacity: 0.5
                            }

                            // Power and cruise sit in the corners the arc leaves
                            // empty, level with the top of the dial
                            Rectangle {
                                id: powerBtn
                                enabled: !root.isSlave
                                opacity: root.isSlave ? 0.3 : 1.0
                                // whole pixels - a canvas on a fractional bound rounds its
                                // render target and the glyph drifts off the circle it sits in
                                x: Math.round(dial.width - width - dial.pad - 10)
                                y: Math.round(dial.dcy - dial.drad - dial.dlw / 2 + dial.pad)
                                width: Math.round(dial.width * 0.105)
                                height: width
                                radius: width / 2
                                color: powerTouch.pressed ? root.cEdge : root.cCtl
                                scale: powerTouch.pressed ? 0.94 : 1.0
                                Behavior on color { ColorAnimation { duration: 180 } }
                                Behavior on scale { NumberAnimation { duration: 90 } }

                                Canvas {
                                    // fills the badge and works from its own centre -
                                    // centerIn on a half-width canvas left the glyph off
                                    // by a rounded pixel, and the stem made it sit high,
                                    // so the ring drops by half of what the stem sticks out
                                    anchors.fill: parent
                                    // the badge is neutral now, so the mark carries the state
                                    property color ink: root.stOff ? root.cOff : root.cInk
                                    onInkChanged: requestPaint()
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.reset()
                                        var c = width / 2
                                        // 0.237 + half the stroke reaches 0.2875 either
                                        // side, the cog's own extent, so the two badges
                                        // carry a glyph of the same width
                                        var r = width * 0.237
                                        var cy = c + r * 0.11
                                        ctx.strokeStyle = ink
                                        ctx.lineWidth = Math.max(2, width * 0.100)
                                        ctx.lineCap = "round"
                                        ctx.beginPath()
                                        ctx.arc(c, cy, r, Math.PI * -0.28, Math.PI * 1.28, false)
                                        ctx.stroke()
                                        ctx.beginPath()
                                        ctx.moveTo(c, cy - r * 1.22)
                                        ctx.lineTo(c, cy - r * 0.10)
                                        ctx.stroke()
                                    }
                                }
                                MouseArea {
                                    id: powerTouch
                                    anchors.fill: parent
                                    anchors.margins: -12 // finger sized target under a small badge
                                    onClicked: ctrlCode("(ctrl-power " + (root.stOff ? "true" : "false") + ")")
                                }
                            }

                            Rectangle {
                                width: Math.round(dial.width * 0.105)
                                height: width
                                radius: width / 2
                                x: Math.round(dial.pad + 10)
                                y: Math.round(dial.dcy - dial.drad - dial.dlw / 2 + dial.pad)
                                color: gearTouch2.pressed ? root.cEdge : root.cCtl
                                Behavior on color { ColorAnimation { duration: 140 } }

                                Canvas {
                                    anchors.fill: parent
                                    property color hub: gearTouch2.pressed ? root.cEdge : root.cCtl
                                    onHubChanged: requestPaint()
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.reset()
                                        // seven teeth put no tooth due west, so the path
                                        // reaches 0.0042 further east than west - take that
                                        // back off so the drawn shape is what gets centred
                                        var c = width / 2 - width * 0.0042
                                        var cy = width / 2
                                        // A solid cog: seven trapezoid teeth walked as
                                        // alternating arcs at the tip and root radius, the
                                        // corners rounded by stroking the same path, then the
                                        // hub punched back out in the badge's own colour.
                                        // Its 0.288 extent is the power mark's, so the badge
                                        // shows the same ring of colour around both.
                                        var pitch = Math.PI * 2 / 7
                                        var half = pitch * 0.22
                                        ctx.beginPath()
                                        for (var i = 0; i < 7; i++) {
                                            var a = i * pitch
                                            ctx.arc(c, cy, width * 0.269, a - half, a + half, false)
                                            ctx.arc(c, cy, width * 0.170, a + half * 1.35,
                                                    a + pitch - half * 1.35, false)
                                        }
                                        ctx.closePath()
                                        ctx.fillStyle = root.cInk
                                        ctx.fill()
                                        ctx.lineJoin = "round"
                                        ctx.lineWidth = width * 0.037
                                        ctx.strokeStyle = root.cInk
                                        ctx.stroke()
                                        ctx.beginPath()
                                        ctx.arc(c, cy, width * 0.104, 0, Math.PI * 2)
                                        ctx.fillStyle = hub
                                        ctx.fill()
                                    }
                                }
                                MouseArea {
                                    id: gearTouch2
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    onClicked: swipeView.currentIndex = 1
                                }
                            }

                            // Consumption at the bottom centre, where the arc's opening
                            // leaves the space free, sat down on the level the ring's own
                            // ends reach. Figure in the speed's colour, unit in the same
                            // grey as km/h, so it reads as one more dial reading.
                            FontMetrics { id: whkmFm; font: whkmNum.font }

                            Row {
                                anchors.horizontalCenter: parent.left
                                anchors.horizontalCenterOffset: dial.dcx
                                anchors.bottom: parent.bottom
                                // a label's box carries the font's descent below the
                                // baseline, so bottom alignment alone would leave the
                                // digits floating - drop it by exactly that much and
                                // they sit on the level both rings end at
                                anchors.bottomMargin: -Math.round(whkmFm.height - whkmFm.ascent)
                                spacing: 3

                                Label {
                                    id: whkmNum
                                    text: fmtWhkm(useMph.checked ? (root.stWhkm / 0.621371) : root.stWhkm)
                                    font.bold: true
                                    font.pixelSize: dial.drad * 0.13
                                }
                                Label {
                                    anchors.baseline: whkmNum.baseline
                                    text: useMph.checked ? "Wh/mi" : "Wh/km"
                                    font.pixelSize: dial.drad * 0.10
                                    opacity: 0.55
                                }
                            }

                            // Warning lamps, centred above the speed: a fault from the
                            // controller, and wheel slip. Slip is the spread between the
                            // fastest and slowest wheel, so a single motor never shows it.
                            // Both are the size of the CC badge, and both are only there
                            // when they have something to say - the row recentres on
                            // whichever is left.
                            Row {
                                anchors.horizontalCenter: parent.left
                                anchors.horizontalCenterOffset: dial.dcx
                                anchors.verticalCenter: parent.top
                                anchors.verticalCenterOffset: dial.dcy - dial.drad * 0.56
                                spacing: Math.round(dial.ccd * 0.30)

                                // Filled like the CC badge, icon knocked out dark: a
                                // thin coloured glyph washes out in sun, and amber on
                                // the light theme's white was barely there at all. What
                                // carries outdoors is a solid disc of colour.
                                Rectangle {
                                    width: dial.ccd
                                    height: width
                                    radius: width / 2
                                    color: "#dc2e28"
                                    visible: root.stFault > 0
                                    Canvas {
                                        anchors.fill: parent
                                        // a canvas hidden before it ever drew comes back blank
                                        onVisibleChanged: if (visible) requestPaint()
                                        onPaint: root.paintIcon(getContext("2d"),
                                                                root.iconEngine, width,
                                                                0.64, 0, 0, root.palOnFill, 0.03)
                                    }
                                    // the badge is smaller than a fingertip, so the
                                    // tap that names the fault reaches past its edge
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -10
                                        onClicked: faultInfo.open()
                                    }
                                }

                                Rectangle {
                                    id: tcLamp
                                    width: dial.ccd
                                    height: width
                                    radius: width / 2
                                    readonly property bool slipping: root.stSlip > 0
                                    visible: slipping
                                    // The blink inverts instead of fading: filled disc
                                    // with the icon knocked out, then the icon alone in
                                    // the disc's own amber. Nothing ever goes
                                    // translucent, so neither half of the cycle washes
                                    // out against the light theme's white.
                                    property bool blinkOn: true
                                    color: blinkOn ? "#e49e26" : "transparent"
                                    onBlinkOnChanged: tcIcon.requestPaint()
                                    onSlippingChanged: if (slipping) blinkOn = true
                                    Timer {
                                        interval: 240
                                        repeat: true
                                        running: tcLamp.slipping
                                        onTriggered: tcLamp.blinkOn = !tcLamp.blinkOn
                                    }
                                    Canvas {
                                        id: tcIcon
                                        anchors.fill: parent
                                        onVisibleChanged: if (visible) requestPaint()
                                        onPaint: root.paintIcon(getContext("2d"),
                                                                root.iconSlip, width,
                                                                0.58, 0.015, 0.014,
                                                                tcLamp.blinkOn ? root.palOnFill
                                                                               : "#e49e26", 0.05)
                                    }
                                }
                            }

                            // cruise sits inside the ring, on the right, flush with
                            // the dial's own edge
                            Rectangle {
                                width: dial.ccd
                                height: width
                                radius: width / 2
                                x: dial.dcx + dial.drad + dial.dlw / 2 - width
                                y: dial.dcy - dial.drad * 0.05 - width / 2
                                color: root.stCruise ? "#17aabc" : root.cCtl
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Label {
                                    anchors.centerIn: parent
                                    text: "CC"
                                    font.bold: true
                                    font.pixelSize: dial.ccd * 0.42
                                    color: root.stCruise ? "#12262a" : root.cOff
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                            }
                        }
                        }

                        // Charge and the four readings are one card: they are one glance.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: Math.round(4 * ctlScroll.hS) + 2
                            Layout.preferredHeight: ctlReadCol.implicitHeight + 20
                            radius: 18
                            color: root.cDeep
                            border.width: root.darkUi ? 0 : 1
                            border.color: root.cEdge

                            ColumnLayout {
                                id: ctlReadCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 10
                                spacing: 0

                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.round(28 * ctlScroll.wS)

                                Rectangle {
                                    id: battTrack
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: Math.round(27 * ctlScroll.wS)
                                    radius: height / 2
                                    color: root.cCtl

                                    Rectangle {
                                        height: parent.height
                                        radius: parent.radius
                                        width: Math.max(height, battTrack.width * Math.max(0, Math.min(1, root.stBatt / 100)))
                                        // full green down to 60%, amber through the
                                        // thirties, red only when the pack is really low -
                                        // the same three colours the buttons are drawn from
                                        color: {
                                            var t = Math.max(0, Math.min(1, (root.stBatt - 8) / 52))
                                            return t < 0.5 ? root.mixColor(root.palRed, root.palAmber, t * 2)
                                                           : root.mixColor(root.palAmber, root.palGreen, (t - 0.5) * 2)
                                        }
                                        Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                                        Behavior on color { ColorAnimation { duration: 320 } }
                                    }

                                    Label {
                                        anchors.centerIn: parent
                                        text: Math.round(root.stBatt) + " %"
                                        font.bold: true
                                        font.pointSize: root.titleSize * 1.18
                                        color: root.battOnFill ? root.palOnFill : root.cInk
                                    }

                                    // Range keeps to whichever end of the bar is one
                                    // solid colour, so it never straddles the fill edge:
                                    // the filled left while there is charge to spare,
                                    // the empty right once the fill has retreated past
                                    // the middle. The percentage holds the centre.
                                    Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        // Positioned rather than re-anchored: binding an
                                        // anchor to undefined is how you break one, and
                                        // driving both ends that way leaves the label stuck
                                        // at whichever end it was on when the fill crossed.
                                        x: root.battOnFill ? 12 : (parent.width - width - 12)
                                        text: "~" + Math.round(useMph.checked ? (root.stRange * 0.621371)
                                                                              : root.stRange)
                                              + (useMph.checked ? " mi" : " km")
                                        font.bold: true
                                        font.pointSize: root.titleSize * 1.18
                                        color: root.battOnFill ? root.palOnFill : root.cInk
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: Math.round(12 * ctlScroll.hS)
                                spacing: 8

                                Repeater {
                                    model: root.statSel
                                    Rectangle {
                                        readonly property var tile: root.statTile(modelData)
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.preferredHeight: Math.round(34 * ctlScroll.wS)
                                        radius: 12
                                        color: root.cCtl

                                        clip: true

                                        // Two panes: the reading right-aligned against a
                                        // slightly offset unit pane. The warning tint is laid
                                        // over both, and the three labels over that, so the
                                        // pane never cuts the blink in half.
                                        Rectangle {
                                            id: chipUnit
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            width: root.chipUnitW
                                            radius: parent.radius
                                            color: root.cCtlHi
                                            // only the card's own right corners are round -
                                            // square off the edge that meets the reading
                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.top: parent.top
                                                anchors.bottom: parent.bottom
                                                width: parent.radius
                                                color: parent.color
                                            }
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: parent.radius
                                            color: root.cWarnTint
                                            // undefined is not assignable to bool,
                                            // and the property falls back to true
                                            visible: tile.warn === true
                                            SequentialAnimation on opacity {
                                                running: true
                                                loops: Animation.Infinite
                                                NumberAnimation { from: 0; to: 0.85; duration: 520; easing.type: Easing.InOutQuad }
                                                NumberAnimation { from: 0.85; to: 0; duration: 520; easing.type: Easing.InOutQuad }
                                            }
                                        }

                                        Label {
                                            anchors.right: chipUnit.left
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.verticalCenterOffset: root.inkNudge(1.0)
                                            text: tile.val
                                            font.bold: true
                                            font.pointSize: root.titleSize * 1.0
                                        }

                                        Label {
                                            anchors.centerIn: chipUnit
                                            anchors.verticalCenterOffset: root.inkNudge(0.96)
                                            visible: tile.icon === undefined
                                            text: tile.unit ? tile.unit : ""
                                            font.bold: true
                                            font.pointSize: root.titleSize * 0.96
                                            opacity: 0.6
                                        }

                                        Canvas {
                                            anchors.fill: chipUnit
                                            visible: tile.icon !== undefined
                                            opacity: 0.6
                                            // a canvas hidden before it ever drew comes back blank
                                            onVisibleChanged: if (visible) requestPaint()
                                            // the delegates outlive a value change now,
                                            // so nothing repaints them after layout - the
                                            // first paint can land before there is a size
                                            onWidthChanged: requestPaint()
                                            onHeightChanged: requestPaint()
                                            Component.onCompleted: requestPaint()
                                            onPaint: root.paintUnitIcon(getContext("2d"),
                                                                        tile.icon,
                                                                        width, height, root.cInk)
                                        }

                                        // Last child, so it is above the reading: a press on
                                        // the digits is a press on the tile, not a miss.
                                        MouseArea {
                                            id: chipTouch
                                            anchors.fill: parent
                                            property real pX: 0
                                            property real pY: 0
                                            // The scroll view steals the grab on the
                                            // smallest drift, which cancels a hold - so
                                            // hold the grab until the finger has actually
                                            // travelled, then hand it back so the page
                                            // still scrolls from here.
                                            onPressed: {
                                                pX = mouse.x; pY = mouse.y
                                                preventStealing = true
                                                chipHold.restart()
                                            }
                                            onPositionChanged: {
                                                if (Math.abs(mouse.x - pX) > 14
                                                        || Math.abs(mouse.y - pY) > 14) {
                                                    preventStealing = false
                                                    chipHold.stop()
                                                }
                                            }
                                            onReleased: { preventStealing = false; chipHold.stop() }
                                            onCanceled: { preventStealing = false; chipHold.stop() }
                                            Timer {
                                                id: chipHold
                                                interval: 500
                                                onTriggered: {
                                                    chipTouch.preventStealing = false
                                                    statPick.openAt(index)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            }
                        }

                        // The mode picker and the four controls share a card, as on every other screen.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: Math.round(7 * ctlScroll.hS)
                            Layout.preferredHeight: ctlBtnCol.implicitHeight + 20
                            radius: 18
                            color: root.cDeep
                            border.width: root.darkUi ? 0 : 1
                            border.color: root.cEdge

                            ColumnLayout {
                                id: ctlBtnCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 10
                                spacing: 0

                            // Segmented mode picker - the highlight slides to the
                            // active mode instead of three buttons lighting up
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.round(48 * ctlScroll.hS)

                                Rectangle {
                                    id: modeTrack
                                    anchors.fill: parent
                                    enabled: !root.isSlave
                                    opacity: root.isSlave ? 0.3 : 1.0
                                    radius: 14
                                    color: root.cCtl

                                    Rectangle {
                                        width: modeTrack.width / 3
                                        height: parent.height
                                        radius: parent.radius
                                        x: root.stMode === 2 ? 0 : (root.stMode === 1 ? modeTrack.width / 3 : modeTrack.width * 2 / 3)
                                        color: root.stMode === 2 ? "#25af32" : (root.stMode === 1 ? "#1e80d5" : "#dc2e28")
                                        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                        Behavior on color { ColorAnimation { duration: 220 } }
                                    }

                                    Row {
                                        anchors.fill: parent
                                        Repeater {
                                            model: [
                                                { t: "ECO", m: 2 },
                                                { t: "DRIVE", m: 1 },
                                                { t: "SPORT", m: 4 }
                                            ]
                                            Item {
                                                width: modeTrack.width / 3
                                                height: modeTrack.height
                                                Label {
                                                    anchors.centerIn: parent
                                                    anchors.verticalCenterOffset: root.inkNudge(0.92)
                                                    text: modelData.t
                                                    font.bold: true
                                                    font.pointSize: root.titleSize * 0.92
                                                    color: root.stMode === modelData.m ? "#ffffff" : root.cDim2
                                                    Behavior on color { ColorAnimation { duration: 220 } }
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: ctrlCode("(ctrl-mode " + modelData.m + ")")
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: Math.round(14 * ctlScroll.hS)
                                enabled: !root.isSlave
                                opacity: root.isSlave ? 0.3 : 1.0
                                columns: 2
                                rowSpacing: Math.round(16 * ctlScroll.hS)
                                columnSpacing: Math.round(14 * ctlScroll.hS)

                                Repeater {
                                    model: [
                                        { t: "LOCK", on: root.stLock, col: "#c31f1f", fg: "#ffffff",
                                          cmd: "(ctrl-lock " + (root.stLock ? "false" : "true") + ")", live: true },
                                        { t: "SECRET", on: root.stSecret, col: "#771ca2", fg: "#ffffff",
                                          cmd: "(ctrl-secret " + (root.stSecret ? "false" : "true") + ")",
                                          live: root.stSecretAllow },
                                        { t: "LIGHT", on: root.stLight, col: "#e49e26", fg: root.stLight ? "#1e1a10" : "#ffffff",
                                          cmd: "(ctrl-light " + (root.stLight ? "false" : "true") + ")", live: true },
                                        { t: "CRUISE", on: root.stCruiseEn, col: "#118579", fg: "#ffffff",
                                          cmd: "(ctrl-cruise " + (root.stCruiseEn ? "false" : "true") + ")", live: root.stCruiseAllow }
                                    ]
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.preferredHeight: Math.round(64 * ctlScroll.hS) + 10
                                        radius: 14
                                        // a switched off function reads as off, not as dimmed
                                        // colour - the state it was left in says nothing once
                                        // the function itself is gone
                                        readonly property bool lit: modelData.live && modelData.on
                                        color: lit ? modelData.col : root.cCtl
                                        opacity: modelData.live ? 1.0 : 0.35
                                        scale: cellTouch.pressed ? 0.975 : 1.0
                                        Behavior on color { ColorAnimation { duration: 180 } }
                                        Behavior on opacity { NumberAnimation { duration: 180 } }
                                        Behavior on scale { NumberAnimation { duration: 90 } }

                                        Label {
                                            anchors.centerIn: parent
                                            text: modelData.t
                                            font.bold: true
                                            font.pointSize: root.titleSize
                                            color: parent.lit ? modelData.fg : root.cInk
                                        }
                                        MouseArea {
                                            id: cellTouch
                                            anchors.fill: parent
                                            enabled: modelData.live
                                            onClicked: ctrlCode(modelData.cmd)
                                        }
                                    }
                                }
                            }
                            }
                        }
                    }
                }
            }

            Page {
                enabled: !isSlave

                ScrollView {
                    id: genScroll
                    anchors.fill: parent
                    contentWidth: availableWidth
                    contentHeight: genCol.implicitHeight
                    clip: true
                    // Both explicit: a ColumnLayout sized off parent.width leaves
                    // ScrollView deriving contentHeight from an item whose own parent
                    // is height driven BY contentHeight, and it latches short. Overshoot
                    // hid that, because a drag always did something.
                    // nothing to scroll means nothing moves - the flickable a
                    // ScrollView makes still rubber bands a page that already fits
                    Component.onCompleted: contentItem.boundsBehavior = Flickable.StopAtBounds

                    ColumnLayout {
                        id: genCol
                        width: genScroll.availableWidth
                        spacing: 4

                        Label { text: "General"; font.bold: true; font.pointSize: root.titleSize * 0.92; font.capitalization: Font.AllUppercase; font.letterSpacing: 1; opacity: 0.8; Layout.topMargin: 12; Layout.leftMargin: 4 }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: card1.implicitHeight + 28
                            radius: 14
                            color: root.cDeep
                            border.width: root.darkUi ? 0 : 1
                            border.color: root.cEdge
                            ColumnLayout {
                                id: card1
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 14
                                spacing: 12

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    Label { font.bold: true; text: "Startup Mode"; Layout.fillWidth: true }
                                    ComboBox {
                                        id: bootMode
                                        Layout.preferredWidth: 100
                                        model: ["Eco", "Drive", "Sport"]
                                        currentIndex: 1
                                        background: Rectangle { radius: 10; color: root.cCtl; implicitHeight: 34 }
                                        popup.background: Rectangle { radius: 12; color: root.cCard; border.width: 1; border.color: root.cEdge }
                                        popup.padding: 6
                                        popup.height: popup.contentItem.implicitHeight + 12
                                        topInset: 0
                                        bottomInset: 0
                                        topPadding: 0
                                        bottomPadding: 0
                                        implicitHeight: 34
                                        font.weight: Font.Normal; font.pointSize: root.titleSize * 0.95
                                        Component.onCompleted: { popup.contentItem.boundsBehavior = Flickable.StopAtBounds; popup.contentItem.interactive = false }
                                        delegate: comboItem
                                    }
                                }
                                Label { text: "The mode the scooter starts in when the VESC is turned on."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    enabled: secretEnabled.checked
                                    Label { font.bold: true; text: "Disable Secret when Locked"; Layout.fillWidth: true }
                                    CheckBox { id: secretExitOnLock; spacing: 4; padding: 7; indicator: Rectangle { implicitWidth: 40; implicitHeight: 22; x: parent.leftPadding; y: parent.height / 2 - height / 2; radius: 11; color: parent.checked ? root.cAccentBg : root.cTrack; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } Rectangle { y: 3; width: 16; height: 16; radius: 8; color: parent.parent.checked ? root.cAccent : root.cDim2; x: parent.parent.checked ? 21 : 3; Behavior on color { ColorAnimation { duration: 140 } } Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } } } }
                                }
                                Label { text: "Locking the scooter drops it back out of the secret modes."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    Label { font.bold: true; text: "Start Speed (" + (useMph.checked ? "mph" : "km/h") + ")"; Layout.fillWidth: true }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: minSpeed; horizontalAlignment: TextInput.AlignHCenter; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                }
                                Label { text: "Kick-off speed. Throttle will not work below this value."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    Label { font.bold: true; text: "Idle Display"; Layout.fillWidth: true }
                                    CheckBox { id: showBatteryInIdle; text: "Normal"; spacing: 4; topPadding: 0; bottomPadding: 0; leftPadding: 14; rightPadding: 14; indicator: Item { } background: Rectangle { radius: 9; implicitHeight: 36; color: parent.checked ? root.cAccentBg2 : root.cCard; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } } contentItem: Label { text: parent.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; font.weight: Font.DemiBold; font.pointSize: root.titleSize * 0.95; color: parent.checked ? root.cAccent : root.cDim } }
                                    CheckBox { id: showBatterySecret; text: "Secret"; spacing: 4
                                        enabled: secretEnabled.checked
                                        topPadding: 0; bottomPadding: 0; leftPadding: 14; rightPadding: 14; indicator: Item { } background: Rectangle { radius: 9; implicitHeight: 36; color: parent.checked ? root.cAccentBg2 : root.cCard; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } } contentItem: Label { text: parent.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; font.weight: Font.DemiBold; font.pointSize: root.titleSize * 0.95; color: parent.checked ? root.cAccent : root.cDim } }
                                }
                                Label { text: "Show a different value on the dash while standing still."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Label {
                                        text: "Idle Display Shows"
                                        font.bold: true
                                        Layout.fillWidth: true
                                        enabled: showBatteryInIdle.checked || showBatterySecret.checked
                                    }
                                    ComboBox {
                                        id: idleDisplay
                                        background: Rectangle { radius: 10; color: root.cCtl; implicitHeight: 34 }
                                        popup.background: Rectangle { radius: 12; color: root.cCard; border.width: 1; border.color: root.cEdge }
                                        popup.padding: 6
                                        popup.height: popup.contentItem.implicitHeight + 12
                                        topInset: 0
                                        bottomInset: 0
                                        topPadding: 0
                                        bottomPadding: 0
                                        implicitHeight: 34
                                        font.weight: Font.Normal; font.pointSize: root.titleSize * 0.95
                                        Component.onCompleted: { popup.contentItem.boundsBehavior = Flickable.StopAtBounds; popup.contentItem.interactive = false }
                                        delegate: comboItem
                                        Layout.preferredWidth: 130
                                        enabled: showBatteryInIdle.checked || showBatterySecret.checked
                                        model: ["Battery %", "Battery V", "VESC " + root.degUnit, "Motor " + root.degUnit]
                                    }
                                }
                                Label { text: "Select what to show while standing still."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    Label { font.bold: true; text: "Alarm"; Layout.fillWidth: true }
                                    CheckBox { id: alarmTone; spacing: 4; padding: 7; indicator: Rectangle { implicitWidth: 40; implicitHeight: 22; x: parent.leftPadding; y: parent.height / 2 - height / 2; radius: 11; color: parent.checked ? root.cAccentBg : root.cTrack; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } Rectangle { y: 3; width: 16; height: 16; radius: 8; color: parent.parent.checked ? root.cAccent : root.cDim2; x: parent.parent.checked ? 21 : 3; Behavior on color { ColorAnimation { duration: 140 } } Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } } } }
                                }
                                Label { text: "Enable the alarm when the scooter is locked."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6; Layout.bottomMargin: 6 }

                            }
                        }
                        Label { text: "Lights"; font.bold: true; font.pointSize: root.titleSize * 0.92; font.capitalization: Font.AllUppercase; font.letterSpacing: 1; opacity: 0.8; Layout.topMargin: 26; Layout.leftMargin: 4 }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: cardLights.implicitHeight + 28
                            radius: 14
                            color: root.cDeep
                            border.width: root.darkUi ? 0 : 1
                            border.color: root.cEdge
                            ColumnLayout {
                                id: cardLights
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 14
                                spacing: 12

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    Label { font.bold: true; text: "Auto Headlight"; Layout.fillWidth: true }
                                    CheckBox { id: lightOnBoot; spacing: 4; padding: 7; indicator: Rectangle { implicitWidth: 40; implicitHeight: 22; x: parent.leftPadding; y: parent.height / 2 - height / 2; radius: 11; color: parent.checked ? root.cAccentBg : root.cTrack; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } Rectangle { y: 3; width: 16; height: 16; radius: 8; color: parent.parent.checked ? root.cAccent : root.cDim2; x: parent.parent.checked ? 21 : 3; Behavior on color { ColorAnimation { duration: 140 } } Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } } } }
                                }
                                Label { text: "Headlight comes on by itself every time the scooter starts."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    Label { font.bold: true; text: "Headlight OFF when Locked"; Layout.fillWidth: true }
                                    CheckBox { id: headOffLock; spacing: 4; padding: 7; indicator: Rectangle { implicitWidth: 40; implicitHeight: 22; x: parent.leftPadding; y: parent.height / 2 - height / 2; radius: 11; color: parent.checked ? root.cAccentBg : root.cTrack; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } Rectangle { y: 3; width: 16; height: 16; radius: 8; color: parent.parent.checked ? root.cAccent : root.cDim2; x: parent.parent.checked ? 21 : 3; Behavior on color { ColorAnimation { duration: 140 } } Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } } } }
                                }
                                Label { text: "Headlight is turned OFF when locked, and restored when unlocked."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    Label { font.bold: true; text: "Always ON Tail Light"; Layout.fillWidth: true; enabled: rearLightEnable.checked }
                                    CheckBox { id: autoTaillight; spacing: 4; enabled: rearLightEnable.checked; padding: 7; indicator: Rectangle { implicitWidth: 40; implicitHeight: 22; x: parent.leftPadding; y: parent.height / 2 - height / 2; radius: 11; color: parent.checked ? root.cAccentBg : root.cTrack; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } Rectangle { y: 3; width: 16; height: 16; radius: 8; color: parent.parent.checked ? root.cAccent : root.cDim2; x: parent.parent.checked ? 21 : 3; Behavior on color { ColorAnimation { duration: 140 } } Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } } } }
                                }
                                Label { text: "Tail light stays lit the whole time the scooter is on, not only under braking."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    Label { font.bold: true; text: "Tail Light OFF when Locked"; Layout.fillWidth: true; enabled: rearLightEnable.checked }
                                    CheckBox { id: tailOffLock; spacing: 4; enabled: rearLightEnable.checked; padding: 7; indicator: Rectangle { implicitWidth: 40; implicitHeight: 22; x: parent.leftPadding; y: parent.height / 2 - height / 2; radius: 11; color: parent.checked ? root.cAccentBg : root.cTrack; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } Rectangle { y: 3; width: 16; height: 16; radius: 8; color: parent.parent.checked ? root.cAccent : root.cDim2; x: parent.parent.checked ? 21 : 3; Behavior on color { ColorAnimation { duration: 140 } } Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } } } }
                                }
                                Label { text: "Tail light is turned OFF when locked, and restored when unlocked."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    enabled: rearLightEnable.checked
                                    Label { font.bold: true; text: "Tail Light Brightness (1-10)"; Layout.fillWidth: true }
                                    ComboBox {
                                        id: tailBright
                                        Layout.preferredWidth: 100
                                        model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
                                        enabled: rearLightEnable.checked
                                        background: Rectangle { radius: 10; color: root.cCtl; implicitHeight: 34 }
                                        popup.background: Rectangle { radius: 12; color: root.cCard; border.width: 1; border.color: root.cEdge }
                                        popup.padding: 6
                                        popup.height: popup.contentItem.implicitHeight + 12
                                        topInset: 0
                                        bottomInset: 0
                                        topPadding: 0
                                        bottomPadding: 0
                                        implicitHeight: 34
                                        font.weight: Font.Normal; font.pointSize: root.titleSize * 0.95
                                        Component.onCompleted: { popup.contentItem.boundsBehavior = Flickable.StopAtBounds; popup.contentItem.interactive = false }
                                        delegate: comboItem
                                    }
                                }
                                Label { text: "Tail light brightness, in ten steps."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    Label { font.bold: true; text: "Brake Light"; Layout.fillWidth: true; enabled: rearLightEnable.checked }
                                    ComboBox {
                                        id: brakeLightMode
                                        Layout.preferredWidth: 100
                                        model: ["On", "Blink", "Off"]
                                        enabled: rearLightEnable.checked
                                        background: Rectangle { radius: 10; color: root.cCtl; implicitHeight: 34 }
                                        popup.background: Rectangle { radius: 12; color: root.cCard; border.width: 1; border.color: root.cEdge }
                                        popup.padding: 6
                                        popup.height: popup.contentItem.implicitHeight + 12
                                        topInset: 0
                                        bottomInset: 0
                                        topPadding: 0
                                        bottomPadding: 0
                                        implicitHeight: 34
                                        font.weight: Font.Normal; font.pointSize: root.titleSize * 0.95
                                        Component.onCompleted: { popup.contentItem.boundsBehavior = Flickable.StopAtBounds; popup.contentItem.interactive = false }
                                        delegate: comboItem
                                    }
                                }
                                Label { text: "Select the brake light effect when the brake is pressed."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6; Layout.bottomMargin: 6 }
                            }
                        }
                        Label { text: "Gestures"; font.bold: true; font.pointSize: root.titleSize * 0.92; font.capitalization: Font.AllUppercase; font.letterSpacing: 1; opacity: 0.8; Layout.topMargin: 26; Layout.leftMargin: 4 }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: card2.implicitHeight + 28
                            radius: 14
                            color: root.cDeep
                            border.width: root.darkUi ? 0 : 1
                            border.color: root.cEdge
                            ColumnLayout {
                                id: card2
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 14
                                spacing: 12

                                                                                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 8
                                    spacing: 4

                                    Label { text: "Lock"; font.bold: true; Layout.bottomMargin: 3 }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        CheckBox { id: lockBrake; text: "Brake"; checked: true; spacing: 4; topPadding: 0; bottomPadding: 0; leftPadding: 14; rightPadding: 14; indicator: Item { } background: Rectangle { radius: 9; implicitHeight: 36; color: parent.checked ? root.cAccentBg2 : root.cCard; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } } contentItem: Label { text: parent.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; font.weight: Font.DemiBold; font.pointSize: root.titleSize * 0.95; color: parent.checked ? root.cAccent : root.cDim } }
                                        CheckBox { id: lockThrottle; text: "Throttle"; spacing: 4; topPadding: 0; bottomPadding: 0; leftPadding: 14; rightPadding: 14; indicator: Item { } background: Rectangle { radius: 9; implicitHeight: 36; color: parent.checked ? root.cAccentBg2 : root.cCard; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } } contentItem: Label { text: parent.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; font.weight: Font.DemiBold; font.pointSize: root.titleSize * 0.95; color: parent.checked ? root.cAccent : root.cDim } }
                                        Item { Layout.fillWidth: true }
                                        ComboBox {
                                            id: lockPresses
                                            Layout.preferredWidth: 72
                                            model: ["1", "2", "3", "4", "5"]
                                            currentIndex: 1
                                            background: Rectangle { radius: 10; color: root.cCtl; implicitHeight: 34 }
                                            popup.background: Rectangle { radius: 12; color: root.cCard; border.width: 1; border.color: root.cEdge }
                                            popup.padding: 6
                                            popup.height: popup.contentItem.implicitHeight + 12
                                            topInset: 0
                                            bottomInset: 0
                                            topPadding: 0
                                            bottomPadding: 0
                                            implicitHeight: 34
                                            font.weight: Font.Normal; font.pointSize: root.titleSize * 0.95
                                            Component.onCompleted: { popup.contentItem.boundsBehavior = Flickable.StopAtBounds; popup.contentItem.interactive = false }
                                            delegate: comboItem
                                        }
                                    }
                                }

                                                                                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 8
                                    spacing: 4

                                    Label { text: "Modes"; font.bold: true; Layout.bottomMargin: 3 }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        CheckBox { id: modeBrake; text: "Brake"; spacing: 4; topPadding: 0; bottomPadding: 0; leftPadding: 14; rightPadding: 14; indicator: Item { } background: Rectangle { radius: 9; implicitHeight: 36; color: parent.checked ? root.cAccentBg2 : root.cCard; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } } contentItem: Label { text: parent.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; font.weight: Font.DemiBold; font.pointSize: root.titleSize * 0.95; color: parent.checked ? root.cAccent : root.cDim } }
                                        CheckBox { id: modeThrottle; text: "Throttle"; spacing: 4; topPadding: 0; bottomPadding: 0; leftPadding: 14; rightPadding: 14; indicator: Item { } background: Rectangle { radius: 9; implicitHeight: 36; color: parent.checked ? root.cAccentBg2 : root.cCard; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } } contentItem: Label { text: parent.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; font.weight: Font.DemiBold; font.pointSize: root.titleSize * 0.95; color: parent.checked ? root.cAccent : root.cDim } }
                                        CheckBox { id: modeLocked; text: "Locked"; spacing: 4; topPadding: 0; bottomPadding: 0; leftPadding: 14; rightPadding: 14; indicator: Item { } background: Rectangle { radius: 9; implicitHeight: 36; color: parent.checked ? root.cAccentBg2 : root.cCard; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } } contentItem: Label { text: parent.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; font.weight: Font.DemiBold; font.pointSize: root.titleSize * 0.95; color: parent.checked ? root.cAccent : root.cDim } }
                                        Item { Layout.fillWidth: true }
                                        ComboBox {
                                            id: modePresses
                                            Layout.preferredWidth: 72
                                            model: ["No", "1", "2", "3", "4", "5"]
                                            currentIndex: 2
                                            background: Rectangle { radius: 10; color: root.cCtl; implicitHeight: 34 }
                                            popup.background: Rectangle { radius: 12; color: root.cCard; border.width: 1; border.color: root.cEdge }
                                            popup.padding: 6
                                            popup.height: popup.contentItem.implicitHeight + 12
                                            topInset: 0
                                            bottomInset: 0
                                            topPadding: 0
                                            bottomPadding: 0
                                            implicitHeight: 34
                                            font.weight: Font.Normal; font.pointSize: root.titleSize * 0.95
                                            Component.onCompleted: { popup.contentItem.boundsBehavior = Flickable.StopAtBounds; popup.contentItem.interactive = false }
                                            delegate: comboItem
                                        }
                                    }
                                }

                                                                                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 8
                                    spacing: 4

                                    Label { text: "Headlight"; font.bold: true; Layout.bottomMargin: 3 }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        CheckBox { id: lightBrake; text: "Brake"; spacing: 4; topPadding: 0; bottomPadding: 0; leftPadding: 14; rightPadding: 14; indicator: Item { } background: Rectangle { radius: 9; implicitHeight: 36; color: parent.checked ? root.cAccentBg2 : root.cCard; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } } contentItem: Label { text: parent.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; font.weight: Font.DemiBold; font.pointSize: root.titleSize * 0.95; color: parent.checked ? root.cAccent : root.cDim } }
                                        CheckBox { id: lightThrottle; text: "Throttle"; spacing: 4; topPadding: 0; bottomPadding: 0; leftPadding: 14; rightPadding: 14; indicator: Item { } background: Rectangle { radius: 9; implicitHeight: 36; color: parent.checked ? root.cAccentBg2 : root.cCard; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } } contentItem: Label { text: parent.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; font.weight: Font.DemiBold; font.pointSize: root.titleSize * 0.95; color: parent.checked ? root.cAccent : root.cDim } }
                                        CheckBox { id: lightLocked; text: "Locked"; spacing: 4; topPadding: 0; bottomPadding: 0; leftPadding: 14; rightPadding: 14; indicator: Item { } background: Rectangle { radius: 9; implicitHeight: 36; color: parent.checked ? root.cAccentBg2 : root.cCard; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } } contentItem: Label { text: parent.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; font.weight: Font.DemiBold; font.pointSize: root.titleSize * 0.95; color: parent.checked ? root.cAccent : root.cDim } }
                                        Item { Layout.fillWidth: true }
                                        ComboBox {
                                            id: lightPresses
                                            Layout.preferredWidth: 72
                                            model: ["No", "1", "2", "3", "4", "5"]
                                            currentIndex: 1
                                            background: Rectangle { radius: 10; color: root.cCtl; implicitHeight: 34 }
                                            popup.background: Rectangle { radius: 12; color: root.cCard; border.width: 1; border.color: root.cEdge }
                                            popup.padding: 6
                                            popup.height: popup.contentItem.implicitHeight + 12
                                            topInset: 0
                                            bottomInset: 0
                                            topPadding: 0
                                            bottomPadding: 0
                                            implicitHeight: 34
                                            font.weight: Font.Normal; font.pointSize: root.titleSize * 0.95
                                            Component.onCompleted: { popup.contentItem.boundsBehavior = Flickable.StopAtBounds; popup.contentItem.interactive = false }
                                            delegate: comboItem
                                        }
                                    }
                                }

                                                                                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 8
                                    spacing: 4
                                    enabled: secretEnabled.checked

                                    Label { text: "Secret"; font.bold: true; Layout.bottomMargin: 3 }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        CheckBox { id: secretBrake; text: "Brake"; checked: true; spacing: 4; topPadding: 0; bottomPadding: 0; leftPadding: 14; rightPadding: 14; indicator: Item { } background: Rectangle { radius: 9; implicitHeight: 36; color: parent.checked ? root.cAccentBg2 : root.cCard; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } } contentItem: Label { text: parent.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; font.weight: Font.DemiBold; font.pointSize: root.titleSize * 0.95; color: parent.checked ? root.cAccent : root.cDim } }
                                        CheckBox { id: secretThrottle; text: "Throttle"; checked: true; spacing: 4; topPadding: 0; bottomPadding: 0; leftPadding: 14; rightPadding: 14; indicator: Item { } background: Rectangle { radius: 9; implicitHeight: 36; color: parent.checked ? root.cAccentBg2 : root.cCard; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } } contentItem: Label { text: parent.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; font.weight: Font.DemiBold; font.pointSize: root.titleSize * 0.95; color: parent.checked ? root.cAccent : root.cDim } }
                                        CheckBox { id: secretRequiresLock; text: "Locked"; spacing: 4; topPadding: 0; bottomPadding: 0; leftPadding: 14; rightPadding: 14; indicator: Item { } background: Rectangle { radius: 9; implicitHeight: 36; color: parent.checked ? root.cAccentBg2 : root.cCard; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } } contentItem: Label { text: parent.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; font.weight: Font.DemiBold; font.pointSize: root.titleSize * 0.95; color: parent.checked ? root.cAccent : root.cDim } }
                                        Item { Layout.fillWidth: true }
                                        ComboBox {
                                            id: secretPresses
                                            Layout.preferredWidth: 72
                                            model: ["No", "1", "2", "3", "4", "5"]
                                            currentIndex: 1
                                            background: Rectangle { radius: 10; color: root.cCtl; implicitHeight: 34 }
                                            popup.background: Rectangle { radius: 12; color: root.cCard; border.width: 1; border.color: root.cEdge }
                                            popup.padding: 6
                                            popup.height: popup.contentItem.implicitHeight + 12
                                            topInset: 0
                                            bottomInset: 0
                                            topPadding: 0
                                            bottomPadding: 0
                                            implicitHeight: 34
                                            font.weight: Font.Normal; font.pointSize: root.titleSize * 0.95
                                            Component.onCompleted: { popup.contentItem.boundsBehavior = Flickable.StopAtBounds; popup.contentItem.interactive = false }
                                            delegate: comboItem
                                        }
                                    }
                                }

                                                                                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 8
                                    spacing: 4
                                    enabled: secretEnabled.checked

                                    Label { text: "Secret OFF"; font.bold: true; Layout.bottomMargin: 3 }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        CheckBox { id: secretOffBrake; text: "Brake"; spacing: 4; topPadding: 0; bottomPadding: 0; leftPadding: 14; rightPadding: 14; indicator: Item { } background: Rectangle { radius: 9; implicitHeight: 36; color: parent.checked ? root.cAccentBg2 : root.cCard; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } } contentItem: Label { text: parent.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; font.weight: Font.DemiBold; font.pointSize: root.titleSize * 0.95; color: parent.checked ? root.cAccent : root.cDim } }
                                        CheckBox { id: secretOffThrottle; text: "Throttle"; spacing: 4; topPadding: 0; bottomPadding: 0; leftPadding: 14; rightPadding: 14; indicator: Item { } background: Rectangle { radius: 9; implicitHeight: 36; color: parent.checked ? root.cAccentBg2 : root.cCard; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } } contentItem: Label { text: parent.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; font.weight: Font.DemiBold; font.pointSize: root.titleSize * 0.95; color: parent.checked ? root.cAccent : root.cDim } }
                                        CheckBox { id: secretOffRequiresLock; text: "Locked"; spacing: 4; topPadding: 0; bottomPadding: 0; leftPadding: 14; rightPadding: 14; indicator: Item { } background: Rectangle { radius: 9; implicitHeight: 36; color: parent.checked ? root.cAccentBg2 : root.cCard; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } } contentItem: Label { text: parent.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; font.weight: Font.DemiBold; font.pointSize: root.titleSize * 0.95; color: parent.checked ? root.cAccent : root.cDim } }
                                        Item { Layout.fillWidth: true }
                                        ComboBox {
                                            id: secretOffPresses
                                            Layout.preferredWidth: 72
                                            model: ["No", "1", "2", "3", "4", "5"]
                                            currentIndex: 3
                                            background: Rectangle { radius: 10; color: root.cCtl; implicitHeight: 34 }
                                            popup.background: Rectangle { radius: 12; color: root.cCard; border.width: 1; border.color: root.cEdge }
                                            popup.padding: 6
                                            popup.height: popup.contentItem.implicitHeight + 12
                                            topInset: 0
                                            bottomInset: 0
                                            topPadding: 0
                                            bottomPadding: 0
                                            implicitHeight: 34
                                            font.weight: Font.Normal; font.pointSize: root.titleSize * 0.95
                                            Component.onCompleted: { popup.contentItem.boundsBehavior = Flickable.StopAtBounds; popup.contentItem.interactive = false }
                                            delegate: comboItem
                                        }
                                    }
                                }

                                Label { text: "Each gesture is a number of power button presses with the listed levers held down at the same time."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: 6; Layout.bottomMargin: 6 }
                            }
                        }
                    }
                }
            }

            Page {
                enabled: !isSlave

                ScrollView {
                    id: modScroll
                    anchors.fill: parent
                    contentWidth: availableWidth
                    contentHeight: modCol.implicitHeight
                    clip: true
                    // Both explicit: a ColumnLayout sized off parent.width leaves
                    // ScrollView deriving contentHeight from an item whose own parent
                    // is height driven BY contentHeight, and it latches short. Overshoot
                    // hid that, because a drag always did something.
                    // nothing to scroll means nothing moves - the flickable a
                    // ScrollView makes still rubber bands a page that already fits
                    Component.onCompleted: contentItem.boundsBehavior = Flickable.StopAtBounds

                    ColumnLayout {
                        id: modCol
                        width: modScroll.availableWidth
                        spacing: 4

                        Label { text: "Parameters"; font.bold: true; font.pointSize: root.titleSize * 0.92; font.capitalization: Font.AllUppercase; font.letterSpacing: 1; opacity: 0.8; Layout.topMargin: 12; Layout.leftMargin: 4 }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: cardApply.implicitHeight + 22
                            radius: 14
                            color: root.cDeep
                            border.width: root.darkUi ? 0 : 1
                            border.color: root.cEdge
                            ColumnLayout {
                                id: cardApply
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 14
                                anchors.topMargin: 8
                                spacing: 12

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    Label { font.bold: true; text: "Secret Modes"; Layout.fillWidth: true }
                                    CheckBox { id: secretEnabled; checked: true; spacing: 4; padding: 7; indicator: Rectangle { implicitWidth: 40; implicitHeight: 22; x: parent.leftPadding; y: parent.height / 2 - height / 2; radius: 11; color: parent.checked ? root.cAccentBg : root.cTrack; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } Rectangle { y: 3; width: 16; height: 16; radius: 8; color: parent.parent.checked ? root.cAccent : root.cDim2; x: parent.parent.checked ? 21 : 3; Behavior on color { ColorAnimation { duration: 140 } } Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } } } }
                                }

                                Label { text: "A second set of limits, reached with a button combination."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    Label { font.bold: true; text: "Maximum Speed"; Layout.fillWidth: true }
                                    CheckBox { id: applySpeed; checked: true; spacing: 4; padding: 7; indicator: Rectangle { implicitWidth: 40; implicitHeight: 22; x: parent.leftPadding; y: parent.height / 2 - height / 2; radius: 11; color: parent.checked ? root.cAccentBg : root.cTrack; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } Rectangle { y: 3; width: 16; height: 16; radius: 8; color: parent.parent.checked ? root.cAccent : root.cDim2; x: parent.parent.checked ? 21 : 3; Behavior on color { ColorAnimation { duration: 140 } } Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } } } }
                                }
                                Label { text: "Set the maximum speed for each mode."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }


                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    Label { font.bold: true; text: "Current Scaling"; Layout.fillWidth: true }
                                    CheckBox { id: applyCurrent; checked: true; spacing: 4; padding: 7; indicator: Rectangle { implicitWidth: 40; implicitHeight: 22; x: parent.leftPadding; y: parent.height / 2 - height / 2; radius: 11; color: parent.checked ? root.cAccentBg : root.cTrack; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } Rectangle { y: 3; width: 16; height: 16; radius: 8; color: parent.parent.checked ? root.cAccent : root.cDim2; x: parent.parent.checked ? 21 : 3; Behavior on color { ColorAnimation { duration: 140 } } Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } } } }
                                }
                                Label { text: "Scaling of the motor current configured in VESC."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }


                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    Label { font.bold: true; text: "Power"; Layout.fillWidth: true }
                                    CheckBox { id: applyWatts; checked: true; spacing: 4; padding: 7; indicator: Rectangle { implicitWidth: 40; implicitHeight: 22; x: parent.leftPadding; y: parent.height / 2 - height / 2; radius: 11; color: parent.checked ? root.cAccentBg : root.cTrack; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } Rectangle { y: 3; width: 16; height: 16; radius: 8; color: parent.parent.checked ? root.cAccent : root.cDim2; x: parent.parent.checked ? 21 : 3; Behavior on color { ColorAnimation { duration: 140 } } Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } } } }
                                }
                                Label { text: "Set maximum power in watts per mode."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }


                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    Label { font.bold: true; text: "Field Weakening"; Layout.fillWidth: true }
                                    CheckBox { id: applyFw; checked: true; spacing: 4; padding: 7; indicator: Rectangle { implicitWidth: 40; implicitHeight: 22; x: parent.leftPadding; y: parent.height / 2 - height / 2; radius: 11; color: parent.checked ? root.cAccentBg : root.cTrack; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } Rectangle { y: 3; width: 16; height: 16; radius: 8; color: parent.parent.checked ? root.cAccent : root.cDim2; x: parent.parent.checked ? 21 : 3; Behavior on color { ColorAnimation { duration: 140 } } Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } } } }
                                }
                                Label { text: "Maximum field weakening current. Raises top speed."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }


                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    Label { font.bold: true; text: "Overmodulation Factor"; Layout.fillWidth: true }
                                    CheckBox { id: applyOm; spacing: 4; padding: 7; indicator: Rectangle { implicitWidth: 40; implicitHeight: 22; x: parent.leftPadding; y: parent.height / 2 - height / 2; radius: 11; color: parent.checked ? root.cAccentBg : root.cTrack; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } Rectangle { y: 3; width: 16; height: 16; radius: 8; color: parent.parent.checked ? root.cAccent : root.cDim2; x: parent.parent.checked ? 21 : 3; Behavior on color { ColorAnimation { duration: 140 } } Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } } } }
                                }
                                Label { text: "Sets the FOC overmodulation factor. Raises top speed at the expense of voltage distortion."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }


                            }
                        }

                        Label { text: "Normal"; font.bold: true; font.pointSize: root.titleSize * 0.92; font.capitalization: Font.AllUppercase; font.letterSpacing: 1; opacity: 0.8; Layout.topMargin: 12; Layout.leftMargin: 4 }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: card3.implicitHeight + 28
                            radius: 14
                            color: root.cDeep
                            border.width: root.darkUi ? 0 : 1
                            border.color: root.cEdge
                            ColumnLayout {
                                id: card3
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 14
                                spacing: 12

                                RowLayout {
                                    Layout.fillWidth: true
                                    Item { Layout.preferredWidth: 106; Layout.rightMargin: 6 }
                                    Label { text: "Eco"; font.bold: true; Layout.fillWidth: true; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignHCenter }
                                    Label { text: "Drive"; font.bold: true; Layout.fillWidth: true; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignHCenter }
                                    Label { text: "Sport"; font.bold: true; Layout.fillWidth: true; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignHCenter }
                                }

                                RowLayout {
                                    visible: applySpeed.checked
                                    Layout.fillWidth: true
                                    Label { text: useMph.checked ? "Speed (mph)" : "Speed (km/h)"; font.bold: true; Layout.preferredWidth: 106; Layout.preferredHeight: 36; Layout.rightMargin: 6; verticalAlignment: Text.AlignVCenter }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: ecoSpeed; horizontalAlignment: TextInput.AlignHCenter; enabled: applySpeed.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: driveSpeed; horizontalAlignment: TextInput.AlignHCenter; enabled: applySpeed.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: sportSpeed; horizontalAlignment: TextInput.AlignHCenter; enabled: applySpeed.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                }

                                RowLayout {
                                    visible: applyCurrent.checked
                                    Layout.fillWidth: true
                                    Label { text: "Current (%)"; font.bold: true; Layout.preferredWidth: 106; Layout.preferredHeight: 36; Layout.rightMargin: 6; verticalAlignment: Text.AlignVCenter }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: ecoCurrent; horizontalAlignment: TextInput.AlignHCenter; enabled: applyCurrent.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; onEditingFinished: clampPct(ecoCurrent); topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: driveCurrent; horizontalAlignment: TextInput.AlignHCenter; enabled: applyCurrent.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; onEditingFinished: clampPct(driveCurrent); topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: sportCurrent; horizontalAlignment: TextInput.AlignHCenter; enabled: applyCurrent.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; onEditingFinished: clampPct(sportCurrent); topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                }

                                RowLayout {
                                    visible: applyWatts.checked
                                    Layout.fillWidth: true
                                    Label { text: "Power (W)"; font.bold: true; Layout.preferredWidth: 106; Layout.preferredHeight: 36; Layout.rightMargin: 6; verticalAlignment: Text.AlignVCenter }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: ecoWatts; horizontalAlignment: TextInput.AlignHCenter; enabled: applyWatts.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: driveWatts; horizontalAlignment: TextInput.AlignHCenter; enabled: applyWatts.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: sportWatts; horizontalAlignment: TextInput.AlignHCenter; enabled: applyWatts.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                }

                                RowLayout {
                                    visible: applyFw.checked
                                    Layout.fillWidth: true
                                    Label { text: "Field W. (A)"; font.bold: true; Layout.preferredWidth: 106; Layout.preferredHeight: 36; Layout.rightMargin: 6; verticalAlignment: Text.AlignVCenter }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: ecoFw; horizontalAlignment: TextInput.AlignHCenter; enabled: applyFw.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: driveFw; horizontalAlignment: TextInput.AlignHCenter; enabled: applyFw.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: sportFw; horizontalAlignment: TextInput.AlignHCenter; enabled: applyFw.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                }

                                RowLayout {
                                    visible: applyOm.checked
                                    Layout.fillWidth: true
                                    Label { text: "Overmod."; font.bold: true; Layout.preferredWidth: 106; Layout.preferredHeight: 36; Layout.rightMargin: 6; verticalAlignment: Text.AlignVCenter }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: ecoOm; horizontalAlignment: TextInput.AlignHCenter; enabled: applyOm.checked; text: "1.000"; onEditingFinished: clampOm(ecoOm); Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: driveOm; horizontalAlignment: TextInput.AlignHCenter; enabled: applyOm.checked; text: "1.000"; onEditingFinished: clampOm(driveOm); Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: sportOm; horizontalAlignment: TextInput.AlignHCenter; enabled: applyOm.checked; text: "1.000"; onEditingFinished: clampOm(sportOm); Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                }

                            }
                        }
                        Label { visible: secretEnabled.checked; text: "Secret"; font.bold: true; font.pointSize: root.titleSize * 0.92; font.capitalization: Font.AllUppercase; font.letterSpacing: 1; opacity: 0.8; Layout.topMargin: 26; Layout.leftMargin: 4 }
                        Rectangle {
                            visible: secretEnabled.checked
                            Layout.fillWidth: true
                            Layout.preferredHeight: card4.implicitHeight + 22
                            radius: 14
                            color: root.cDeep
                            border.width: root.darkUi ? 0 : 1
                            border.color: root.cEdge
                            ColumnLayout {
                                id: card4
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 14
                                anchors.topMargin: 8
                                spacing: 12

                                RowLayout {
                                    Layout.fillWidth: true
                                    Item { Layout.preferredWidth: 106; Layout.rightMargin: 6 }
                                    Label { text: "Eco"; font.bold: true; Layout.fillWidth: true; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignHCenter }
                                    Label { text: "Drive"; font.bold: true; Layout.fillWidth: true; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignHCenter }
                                    Label { text: "Sport"; font.bold: true; Layout.fillWidth: true; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignHCenter }
                                }

                                RowLayout {
                                    visible: applySpeed.checked
                                    Layout.fillWidth: true
                                    Label { text: useMph.checked ? "Speed (mph)" : "Speed (km/h)"; font.bold: true; Layout.preferredWidth: 106; Layout.preferredHeight: 36; Layout.rightMargin: 6; verticalAlignment: Text.AlignVCenter }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: secretEcoSpeed; horizontalAlignment: TextInput.AlignHCenter; enabled: applySpeed.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: secretDriveSpeed; horizontalAlignment: TextInput.AlignHCenter; enabled: applySpeed.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: secretSportSpeed; horizontalAlignment: TextInput.AlignHCenter; enabled: applySpeed.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                }

                                RowLayout {
                                    visible: applyCurrent.checked
                                    Layout.fillWidth: true
                                    Label { text: "Current (%)"; font.bold: true; Layout.preferredWidth: 106; Layout.preferredHeight: 36; Layout.rightMargin: 6; verticalAlignment: Text.AlignVCenter }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: secretEcoCurrent; horizontalAlignment: TextInput.AlignHCenter; enabled: applyCurrent.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; onEditingFinished: clampPct(secretEcoCurrent); topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: secretDriveCurrent; horizontalAlignment: TextInput.AlignHCenter; enabled: applyCurrent.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; onEditingFinished: clampPct(secretDriveCurrent); topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: secretSportCurrent; horizontalAlignment: TextInput.AlignHCenter; enabled: applyCurrent.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; onEditingFinished: clampPct(secretSportCurrent); topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                }

                                RowLayout {
                                    visible: applyWatts.checked
                                    Layout.fillWidth: true
                                    Label { text: "Power (W)"; font.bold: true; Layout.preferredWidth: 106; Layout.preferredHeight: 36; Layout.rightMargin: 6; verticalAlignment: Text.AlignVCenter }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: secretEcoWatts; horizontalAlignment: TextInput.AlignHCenter; enabled: applyWatts.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: secretDriveWatts; horizontalAlignment: TextInput.AlignHCenter; enabled: applyWatts.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: secretSportWatts; horizontalAlignment: TextInput.AlignHCenter; enabled: applyWatts.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                }

                                RowLayout {
                                    visible: applyFw.checked
                                    Layout.fillWidth: true
                                    Label { text: "Field W. (A)"; font.bold: true; Layout.preferredWidth: 106; Layout.preferredHeight: 36; Layout.rightMargin: 6; verticalAlignment: Text.AlignVCenter }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: secretEcoFw; horizontalAlignment: TextInput.AlignHCenter; enabled: applyFw.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: secretDriveFw; horizontalAlignment: TextInput.AlignHCenter; enabled: applyFw.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: secretSportFw; horizontalAlignment: TextInput.AlignHCenter; enabled: applyFw.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                }

                                RowLayout {
                                    visible: applyOm.checked
                                    Layout.fillWidth: true
                                    Label { text: "Overmod."; font.bold: true; Layout.preferredWidth: 106; Layout.preferredHeight: 36; Layout.rightMargin: 6; verticalAlignment: Text.AlignVCenter }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: secretEcoOm; horizontalAlignment: TextInput.AlignHCenter; enabled: applyOm.checked; text: "1.000"; onEditingFinished: clampOm(secretEcoOm); Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: secretDriveOm; horizontalAlignment: TextInput.AlignHCenter; enabled: applyOm.checked; text: "1.000"; onEditingFinished: clampOm(secretDriveOm); Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    TextField { font.pointSize: root.titleSize * 0.95; id: secretSportOm; horizontalAlignment: TextInput.AlignHCenter; enabled: applyOm.checked; text: "1.000"; onEditingFinished: clampOm(secretSportOm); Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            Layout.preferredHeight: modeNotes.implicitHeight + 28
                            radius: 14
                            color: root.cDeep
                            border.width: root.darkUi ? 0 : 1
                            border.color: root.cEdge
                            ColumnLayout {
                                id: modeNotes
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 14
                                spacing: 8

                                Label { text: "Every value here is applied to each controller separately. Two controllers on the CAN bus draw twice the watts and twice the current. Speed is not doubled - each one holds the same limit."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.bottomMargin: 6 }
                                Label { text: "Each switch under Parameters covers Normal and Secret together. Anything switched off is hidden here and left exactly as VESC has it."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                        }

                    }
                }
            }

            Page {
                ScrollView {
                    id: setScroll
                    anchors.fill: parent
                    contentWidth: availableWidth
                    contentHeight: setCol.implicitHeight
                    clip: true
                    // Both explicit: a ColumnLayout sized off parent.width leaves
                    // ScrollView deriving contentHeight from an item whose own parent
                    // is height driven BY contentHeight, and it latches short. Overshoot
                    // hid that, because a drag always did something.
                    // nothing to scroll means nothing moves - the flickable a
                    // ScrollView makes still rubber bands a page that already fits
                    Component.onCompleted: contentItem.boundsBehavior = Flickable.StopAtBounds

                    ColumnLayout {
                        id: setCol
                        width: setScroll.availableWidth
                        spacing: 4

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            Layout.preferredHeight: card0.implicitHeight + 28
                            radius: 14
                            color: root.cDeep
                            border.width: root.darkUi ? 0 : 1
                            border.color: root.cEdge
                                ColumnLayout {
                                    id: card0
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 14
                                    spacing: 12

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label { text: "Model"; font.bold: true; Layout.fillWidth: true }
                                        ComboBox {
                                            id: modelBox
                                            background: Rectangle { radius: 10; color: root.cCtl; implicitHeight: 34 }
                                            popup.background: Rectangle { radius: 12; color: root.cCard; border.width: 1; border.color: root.cEdge }
                                            popup.padding: 6
                                            popup.height: popup.contentItem.implicitHeight + 12
                                            topInset: 0
                                            bottomInset: 0
                                            topPadding: 0
                                            bottomPadding: 0
                                            implicitHeight: 34
                                            font.weight: Font.Normal; font.pointSize: root.titleSize * 0.95
                                            Component.onCompleted: { popup.contentItem.boundsBehavior = Flickable.StopAtBounds; popup.contentItem.interactive = false }
                                            delegate: comboItem
                                            Layout.preferredWidth: 170
                                            model: ["G30", "M365/1S/PRO2", "Slave", "G2 (untested)"]
                                            currentIndex: 2
                                            onActivated: root.modelPicked(index)
                                        }
                                    }
                                    Label { text: "Select your dashboard/scooter model."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6; Layout.bottomMargin: 6 }
                                }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            enabled: !isSlave

                            Label { text: "Throttle & Brake"; font.bold: true; font.pointSize: root.titleSize * 0.92; font.capitalization: Font.AllUppercase; font.letterSpacing: 1; opacity: 0.8; Layout.topMargin: 12; Layout.leftMargin: 4 }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: card5.implicitHeight + 28
                                radius: 14
                                color: root.cDeep
                                border.width: root.darkUi ? 0 : 1
                                border.color: root.cEdge
                                ColumnLayout {
                                    id: card5
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 14
                                    spacing: 12

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        Label { text: "Software ADC"; font.bold: true; Layout.fillWidth: true }
                                        CheckBox { id: softwareAdc; text: "Throttle"; spacing: 4; topPadding: 0; bottomPadding: 0; leftPadding: 14; rightPadding: 14; indicator: Item { } background: Rectangle { radius: 9; implicitHeight: 36; color: parent.checked ? root.cAccentBg2 : root.cCard; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } } contentItem: Label { text: parent.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; font.weight: Font.DemiBold; font.pointSize: root.titleSize * 0.95; color: parent.checked ? root.cAccent : root.cDim } }
                                        CheckBox { id: softwareAdc2; text: "Brake"; spacing: 4; topPadding: 0; bottomPadding: 0; leftPadding: 14; rightPadding: 14; indicator: Item { } background: Rectangle { radius: 9; implicitHeight: 36; color: parent.checked ? root.cAccentBg2 : root.cCard; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } } contentItem: Label { text: parent.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; font.weight: Font.DemiBold; font.pointSize: root.titleSize * 0.95; color: parent.checked ? root.cAccent : root.cDim } }
                                    }
                                    Label { text: "Throttle and brake come from the dashboard over UART. Turn this off when they are wired straight to the VESC's ADC pins."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        visible: softwareAdc.checked || softwareAdc2.checked

                                        Rectangle { Layout.fillWidth: true; Layout.topMargin: 14; height: 1; color: root.cDialog }

                                        Label { text: "Light Compensation"; font.bold: true; Layout.topMargin: 8 }
                                        Label { text: "The dash lifts the lever voltages when the headlight is on. These cancel that out so the throttle feels the same either way."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: 2 }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            visible: softwareAdc.checked

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 40
                                                Label { font.bold: true; text: "Throttle ADC1 (V)"; Layout.fillWidth: true }
                                                Label { text: root.adcV1.toFixed(4) + "V"; Layout.preferredWidth: 100; horizontalAlignment: Text.AlignHCenter; font.bold: true; color: root.cAccent }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 40
                                                Label { font.bold: true; text: "Throttle Offset (V)"; Layout.fillWidth: true }
                                                TextField { font.pointSize: root.titleSize * 0.95; id: lightOffThr; horizontalAlignment: TextInput.AlignHCenter; text: "0.000"; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; onEditingFinished: clampOffsetV(lightOffThr); topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 40
                                                Label { font.bold: true; text: "Throttle Gain (k)"; Layout.fillWidth: true }
                                                TextField { font.pointSize: root.titleSize * 0.95; id: lightGainThr; horizontalAlignment: TextInput.AlignHCenter; text: "1.000"; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; onEditingFinished: clampGain(lightGainThr); topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                            }

                                            Button {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 56
                                                Layout.topMargin: 4
                                                // stays enabled while THIS channel runs (so its own color
                                                // shows, not the greyed-out disabled palette) - only the
                                                // other channel's button locks out; re-tapping is a no-op
                                                enabled: root.calibRunning === "" || root.calibRunning === "thr"
                                                text: root.calibButtonText("thr")
                                                font.bold: true
                                                Material.foreground: root.calibRunning === "thr" ? "#d0faff" : root.cInk
                                                background: Rectangle {
                                                    radius: 14
                                                    color: root.calibRunning === "thr" ? "#118579" : root.cCtl
                                                }
                                                onClicked: root.calibStartChannel("thr")
                                            }

                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            visible: softwareAdc2.checked

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 40
                                                Label { font.bold: true; text: "Brake ADC2 (V)"; Layout.fillWidth: true }
                                                Label { text: root.adcV2.toFixed(4) + "V"; Layout.preferredWidth: 100; horizontalAlignment: Text.AlignHCenter; font.bold: true; color: root.cAccent }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 40
                                                Label { font.bold: true; text: "Brake Offset (V)"; Layout.fillWidth: true }
                                                TextField { font.pointSize: root.titleSize * 0.95; id: lightOffBrk; horizontalAlignment: TextInput.AlignHCenter; text: "0.000"; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; onEditingFinished: clampOffsetV(lightOffBrk); topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 40
                                                Label { font.bold: true; text: "Brake Gain (k)"; Layout.fillWidth: true }
                                                TextField { font.pointSize: root.titleSize * 0.95; id: lightGainBrk; horizontalAlignment: TextInput.AlignHCenter; text: "1.000"; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; onEditingFinished: clampGain(lightGainBrk); topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                            }

                                            Button {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 56
                                                Layout.topMargin: 4
                                                enabled: root.calibRunning === "" || root.calibRunning === "brk"
                                                text: root.calibButtonText("brk")
                                                font.bold: true
                                                Material.foreground: root.calibRunning === "brk" ? "#d0faff" : root.cInk
                                                background: Rectangle {
                                                    radius: 14
                                                    color: root.calibRunning === "brk" ? "#118579" : root.cCtl
                                                }
                                                onClicked: root.calibStartChannel("brk")
                                            }

                                        }
                                    }

                                }
                            }
                            Label { text: "Gestures"; font.bold: true; font.pointSize: root.titleSize * 0.92; font.capitalization: Font.AllUppercase; font.letterSpacing: 1; opacity: 0.8; Layout.topMargin: 26; Layout.leftMargin: 4 }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: card6.implicitHeight + 28
                                radius: 14
                                color: root.cDeep
                                border.width: root.darkUi ? 0 : 1
                                border.color: root.cEdge
                                ColumnLayout {
                                    id: card6
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 14
                                    spacing: 12

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        Label { font.bold: true; text: "Disable Gestures above (" + (useMph.checked ? "mph" : "km/h") + ")"; Layout.fillWidth: true }
                                        TextField { font.pointSize: root.titleSize * 0.95; id: buttonSpeed; horizontalAlignment: TextInput.AlignHCenter; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    }
                                    Label { text: "Button gestures are disabled above this speed."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6; Layout.bottomMargin: 6 }

                                }
                            }
                            Label { text: "Temperature"; font.bold: true; font.pointSize: root.titleSize * 0.92; font.capitalization: Font.AllUppercase; font.letterSpacing: 1; opacity: 0.8; Layout.topMargin: 26; Layout.leftMargin: 4 }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: card7.implicitHeight + 28
                                radius: 14
                                color: root.cDeep
                                border.width: root.darkUi ? 0 : 1
                                border.color: root.cEdge
                                ColumnLayout {
                                    id: card7
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 14
                                    spacing: 12

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        Label { font.bold: true; text: "Motor Temp Warning (" + root.degUnit + ")"; Layout.fillWidth: true }
                                        TextField { font.pointSize: root.titleSize * 0.95; id: tempWarningMotor; horizontalAlignment: TextInput.AlignHCenter; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        Label { font.bold: true; text: "VESC (MOSFET) Temp Warning (" + root.degUnit + ")"; Layout.fillWidth: true }
                                        TextField { font.pointSize: root.titleSize * 0.95; id: tempWarningFet; horizontalAlignment: TextInput.AlignHCenter; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    }

                                    // the pack temperature comes off the BMS, so these
                                    // do nothing until Use VESC BMS for Dash is on
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        Label { font.bold: true; text: "Battery Hot Warning (" + root.degUnit + ")"; Layout.fillWidth: true; enabled: bmsSoc.checked }
                                        TextField { font.pointSize: root.titleSize * 0.95; id: bmsTempHi; enabled: bmsSoc.checked; horizontalAlignment: TextInput.AlignHCenter; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        Label { font.bold: true; text: "Battery Cold Warning (" + root.degUnit + ")"; Layout.fillWidth: true; enabled: bmsSoc.checked }
                                        TextField { font.pointSize: root.titleSize * 0.95; id: bmsTempLo; enabled: bmsSoc.checked; horizontalAlignment: TextInput.AlignHCenter; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    }
                                    Label { text: "Show a warning on the dash when a temperature goes outside these limits."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6; Layout.bottomMargin: 6 }

                                }
                            }
                            Label { text: "Miscellaneous"; font.bold: true; font.pointSize: root.titleSize * 0.92; font.capitalization: Font.AllUppercase; font.letterSpacing: 1; opacity: 0.8; Layout.topMargin: 26; Layout.leftMargin: 4 }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: card8.implicitHeight + 28
                                radius: 14
                                color: root.cDeep
                                border.width: root.darkUi ? 0 : 1
                                border.color: root.cEdge
                                ColumnLayout {
                                    id: card8
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 14
                                    spacing: 12

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        Label { font.bold: true; text: "Use Imperial Units"; Layout.fillWidth: true }
                                        CheckBox {
                                            id: useMph
                                            spacing: 4
                                            // convert already-shown speed fields on user toggle only
                                            onCheckedChanged: if (root.settingsLoaded) { root.convertSpeedFields(checked); root.convertTempFields(checked) }
                                            padding: 7; indicator: Rectangle { implicitWidth: 40; implicitHeight: 22; x: parent.leftPadding; y: parent.height / 2 - height / 2; radius: 11; color: parent.checked ? root.cAccentBg : root.cTrack; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } Rectangle { y: 3; width: 16; height: 16; radius: 8; color: parent.parent.checked ? root.cAccent : root.cDim2; x: parent.parent.checked ? 21 : 3; Behavior on color { ColorAnimation { duration: 140 } } Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } } }
                                        }
                                    }
                                    Label { text: "Change values to imperial units everywhere."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        Label { font.bold: true; text: "Use VESC BMS"; Layout.fillWidth: true }
                                        CheckBox { id: bmsSoc; spacing: 4; padding: 7; indicator: Rectangle { implicitWidth: 40; implicitHeight: 22; x: parent.leftPadding; y: parent.height / 2 - height / 2; radius: 11; color: parent.checked ? root.cAccentBg : root.cTrack; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } Rectangle { y: 3; width: 16; height: 16; radius: 8; color: parent.parent.checked ? root.cAccent : root.cDim2; x: parent.parent.checked ? 21 : 3; Behavior on color { ColorAnimation { duration: 140 } } Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } } } }
                                    }
                                    Label { text: "Battery info is read from the VESC BMS."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        Label {
                                            Layout.fillWidth: true
                                            font.bold: true
                                            wrapMode: Text.WordWrap
                                            text: (root.isSlave ? "App Support"
                                                   : (modelBox.currentIndex === 1 ? "Xiaomi" : "Segway")
                                                     + " App Support (exp.)")
                                        }
                                        CheckBox { id: appEnable; spacing: 4; padding: 7; indicator: Rectangle { implicitWidth: 40; implicitHeight: 22; x: parent.leftPadding; y: parent.height / 2 - height / 2; radius: 11; color: parent.checked ? root.cAccentBg : root.cTrack; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } Rectangle { y: 3; width: 16; height: 16; radius: 8; color: parent.parent.checked ? root.cAccent : root.cDim2; x: parent.parent.checked ? 21 : 3; Behavior on color { ColorAnimation { duration: 140 } } Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } } } }
                                    }
                                    Label { text: "Enable the original Segway/Xiaomi and third-party apps to connect over the dashboard's BLE."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        Label { font.bold: true; text: "App pairing PIN"; Layout.fillWidth: true }
                                        TextField {
                                            id: appPin
                                            horizontalAlignment: TextInput.AlignHCenter
                                            enabled: appEnable.checked
                                            Layout.preferredWidth: 100
                                            maximumLength: 6
                                            inputMethodHints: Qt.ImhDigitsOnly
                                            topPadding: 0
                                            bottomPadding: 0
                                            leftPadding: 8
                                            rightPadding: 8
                                            verticalAlignment: TextInput.AlignVCenter
                                            validator: RegularExpressionValidator { regularExpression: /[0-9]{0,6}/ }
                                            background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard }
                                        }
                                    }
                                    Label { text: "The six digits the phone app asks for when it connects."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        Label { font.bold: true; text: "Tail Light Output (Servo/PPM)"; Layout.fillWidth: true }
                                        CheckBox { id: rearLightEnable; spacing: 4; padding: 7; indicator: Rectangle { implicitWidth: 40; implicitHeight: 22; x: parent.leftPadding; y: parent.height / 2 - height / 2; radius: 11; color: parent.checked ? root.cAccentBg : root.cTrack; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } Rectangle { y: 3; width: 16; height: 16; radius: 8; color: parent.parent.checked ? root.cAccent : root.cDim2; x: parent.parent.checked ? 21 : 3; Behavior on color { ColorAnimation { duration: 140 } } Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } } } }
                                    }
                                    Label { text: "Control rear light using MOSFET. Check README for more info."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        Label { font.bold: true; text: "Dashboard Power Pin (exp.)"; Layout.fillWidth: true }
                                        ComboBox {
                                            id: dashPowerOut
                                            Layout.preferredWidth: 100
                                            model: ["Off", "ADC1", "ADC2"]
                                            background: Rectangle { radius: 10; color: root.cCtl; implicitHeight: 34 }
                                            popup.background: Rectangle { radius: 12; color: root.cCard; border.width: 1; border.color: root.cEdge }
                                            popup.padding: 6
                                            popup.height: popup.contentItem.implicitHeight + 12
                                            topInset: 0
                                            bottomInset: 0
                                            topPadding: 0
                                            bottomPadding: 0
                                            implicitHeight: 34
                                            font.weight: Font.Normal; font.pointSize: root.titleSize * 0.95
                                            Component.onCompleted: { popup.contentItem.boundsBehavior = Flickable.StopAtBounds; popup.contentItem.interactive = false }
                                            delegate: comboItem
                                        }
                                    }
                                    Label { text: "Turn off the dash/stepdown using an ADC pin. Check README for more info."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                    Label {
                                        visible: dashPowerOut.currentIndex === 1 && !softwareAdc.checked
                                        text: "WARNING! You have no throttle!"
                                        color: "#ff5252"
                                        font.bold: true
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }

                                    Label {
                                        visible: dashPowerOut.currentIndex === 2 && !softwareAdc2.checked
                                        text: "WARNING! Cruise control cannot be stopped when braking!"
                                        color: "#ff5252"
                                        font.bold: true
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }

                                }
                            }
                            Label { text: "Cruise control (exp.)"; font.bold: true; font.pointSize: root.titleSize * 0.92; font.capitalization: Font.AllUppercase; font.letterSpacing: 1; opacity: 0.8; Layout.topMargin: 26; Layout.leftMargin: 4 }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: card9.implicitHeight + 28
                                radius: 14
                                color: root.cDeep
                                border.width: root.darkUi ? 0 : 1
                                border.color: root.cEdge
                                ColumnLayout {
                                    id: card9
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 14
                                    spacing: 12

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        Label { font.bold: true; text: "Cruise Control"; Layout.fillWidth: true }
                                        CheckBox { id: cruiseEnable; spacing: 4; padding: 7; indicator: Rectangle { implicitWidth: 40; implicitHeight: 22; x: parent.leftPadding; y: parent.height / 2 - height / 2; radius: 11; color: parent.checked ? root.cAccentBg : root.cTrack; opacity: parent.enabled ? 1 : 0.45; Behavior on color { ColorAnimation { duration: 140 } } Rectangle { y: 3; width: 16; height: 16; radius: 8; color: parent.parent.checked ? root.cAccent : root.cDim2; x: parent.parent.checked ? 21 : 3; Behavior on color { ColorAnimation { duration: 140 } } Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } } } }
                                    }
                                    Label { text: "Enables the use of Cruise Control. Can be quickly toggled on the dash."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        enabled: cruiseEnable.checked
                                        Label { font.bold: true; text: "Activation Delay (s)"; Layout.fillWidth: true }
                                        TextField { font.pointSize: root.titleSize * 0.95; id: cruiseDelay; horizontalAlignment: TextInput.AlignHCenter; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    }
                                    Label { text: "How long a steady speed must be held before cruise control takes over."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        enabled: cruiseEnable.checked
                                        Label { font.bold: true; text: "Speed Deviation (" + (useMph.checked ? "mph" : "km/h") + ")"; Layout.fillWidth: true }
                                        TextField { font.pointSize: root.titleSize * 0.95; id: cruiseDeviation; horizontalAlignment: TextInput.AlignHCenter; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    }
                                    Label { text: "The largest speed change still counted as steady."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        enabled: cruiseEnable.checked
                                        Label { font.bold: true; text: "Min. Activation Speed (" + (useMph.checked ? "mph" : "km/h") + ")"; Layout.fillWidth: true }
                                        TextField { font.pointSize: root.titleSize * 0.95; id: cruiseMinSpeed; horizontalAlignment: TextInput.AlignHCenter; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    }
                                    Label { text: "Lowest speed at which cruise control can trigger."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        enabled: cruiseEnable.checked
                                        Label { font.bold: true; text: "Max. Activation Speed (" + (useMph.checked ? "mph" : "km/h") + ")"; Layout.fillWidth: true }
                                        TextField { font.pointSize: root.titleSize * 0.95; id: cruiseMaxSpeed; horizontalAlignment: TextInput.AlignHCenter; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    }
                                    Label { text: "Highest speed at which cruise control can trigger."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6; Layout.bottomMargin: 6 }

                                }
                            }
                            Label { text: "Alarm"; font.bold: true; font.pointSize: root.titleSize * 0.92; font.capitalization: Font.AllUppercase; font.letterSpacing: 1; opacity: 0.8; Layout.topMargin: 26; Layout.leftMargin: 4 }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: card10.implicitHeight + 28
                                radius: 14
                                color: root.cDeep
                                border.width: root.darkUi ? 0 : 1
                                border.color: root.cEdge
                                ColumnLayout {
                                    id: card10
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 14
                                    spacing: 12

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        Label { font.bold: true; text: "Speed Trigger (" + (useMph.checked ? "mph" : "km/h") + ")"; Layout.fillWidth: true }
                                        TextField { font.pointSize: root.titleSize * 0.95; id: alarmSpeedThreshold; horizontalAlignment: TextInput.AlignHCenter; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    }
                                    Label { text: "Speed above which the alarm is triggered."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        Label { font.bold: true; text: "Gyro Trigger (deg/s)"; Layout.fillWidth: true }
                                        TextField { font.pointSize: root.titleSize * 0.95; id: alarmGyroThreshold; horizontalAlignment: TextInput.AlignHCenter; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    }
                                    Label { text: "Degrees above which the alarm is triggered."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6 }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        Label { font.bold: true; text: "Volume (V)"; Layout.fillWidth: true }
                                        TextField { font.pointSize: root.titleSize * 0.95; id: alarmVoltage; horizontalAlignment: TextInput.AlignHCenter; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; topPadding: 0; bottomPadding: 0; leftPadding: 6; rightPadding: 6; verticalAlignment: TextInput.AlignVCenter; background: Rectangle { radius: 10; implicitHeight: 34; color: parent.enabled ? root.cCtl : root.cCard } }
                                    }
                                    Label { text: "Alarm loudness. Higher is louder."; opacity: 0.6; font.pointSize: root.titleSize * 0.85; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: -6; Layout.bottomMargin: 6 }
                                }
                            }

                            Label { text: "Backup"; font.bold: true; font.pointSize: root.titleSize * 0.92; font.capitalization: Font.AllUppercase; font.letterSpacing: 1; opacity: 0.8; Layout.topMargin: 26; Layout.leftMargin: 4 }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: card11.implicitHeight + 28
                                radius: 14
                                color: root.cDeep
                                border.width: root.darkUi ? 0 : 1
                                border.color: root.cEdge
                                ColumnLayout {
                                    id: card11
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 14
                                    spacing: 12

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Repeater {
                                            model: [{ t: "Export", exp: true }, { t: "Import", exp: false }]
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 1
                                                Layout.preferredHeight: 44
                                                radius: 12
                                                color: cfgTouch.pressed ? root.cCtlHi : root.cCtl
                                                opacity: root.settingsLoaded ? 1.0 : 0.4
                                                Label {
                                                    anchors.centerIn: parent
                                                    text: modelData.t
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    id: cfgTouch
                                                    anchors.fill: parent
                                                    enabled: root.settingsLoaded
                                                    onClicked: {
                                                        if (modelData.exp) {
                                                            exportText.text = root.cfgExport()
                                                            exportDialog.open()
                                                        } else {
                                                            importText.text = ""
                                                            importDialog.open()
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 2
            spacing: 8
            visible: swipeView.currentIndex !== 0

            Repeater {
                model: [
                    { t: "Reset", act: 0, on: !root.saving, accent: false },
                    { t: root.settingsLoaded ? "Load" : "Loading...", act: 1, on: true, accent: false },
                    { t: root.saving ? "Saving..." : "Save",
                      act: 2, on: !root.saving, accent: true }
                ]
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 46
                    radius: 14
                    // green only while something on screen has not reached the
                    // controller - otherwise Save sits dark like Reset and Load
                    color: modelData.accent && root.cfgDirty && !root.saving ? "#1b8728" : root.cWell
                    opacity: modelData.on ? 1.0 : 0.4
                    scale: actTouch.pressed && modelData.on ? 0.975 : 1.0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 90 } }

                    Label {
                        id: actLabel
                        anchors.centerIn: parent
                        text: modelData.t
                        font.bold: true
                        color: modelData.accent && root.cfgDirty && !root.saving ? "#ffffff" : root.cInk
                    }
                    MouseArea {
                        id: actTouch
                        anchors.fill: parent
                        enabled: modelData.on
                        onClicked: {
                            if (modelData.act === 0) resetDialog.open()
                            else if (modelData.act === 1) { resetSettingsLoad(); getSettings() }
                            else saveAllSettings()
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: mCommands

        function onValuesSetupReceived(values, mask) {
            root.stMotAmps = values.current_motor
            root.stTrip = values.tachometer_abs / 1000
        }

        function onDecodedAdcReceived(value, voltage, value2, voltage2) {
            root.adcV1 = voltage
            root.adcV2 = voltage2
        }

        function onCustomAppDataReceived(data) {
            var message = data.toString().trim()

            if (message.startsWith("state ")) {
                root.statePending = false
                applyStateLine(message)
                return
            }

            if (message === "ack") {
                root.stepDone()
                return
            }

            if (message.startsWith("calib-stage ")) {
                // ["calib-stage", "prep"/"settle"/"measure", phaseLabel] mid-run,
                // the sampling stages also carry [n, total]; or
                // ["calib-stage", "release"/"idle", channel] for the tail end
                var sp = message.split(" ")
                var stage = sp[1]
                if (stage === "prep" || stage === "settle" || stage === "measure") {
                    root.calibStage = stage
                    root.calibPhaseLabel = sp[2]
                    if (stage === "prep") root.calibRemaining = root.calibPrepDuration
                    else root.calibProgress = sp[3] + "/" + sp[4]
                } else if (stage === "release") {
                    root.calibStage = "release"
                    root.calibRemaining = root.calibReleaseDuration
                } else if (stage === "idle") {
                    // release grace period elapsed - real control has resumed
                    root.calibRunning = ""
                    root.calibStage = "idle"
                }
                return
            }
            if (message.startsWith("calib-progress ")) {
                return // covered by the live step instruction; nothing to do
            }
            if (message.startsWith("calib-result ")) {
                // channel stays "running" through the release grace period -
                // cleared later by the "calib-stage idle" message above
                // ["calib-result", "thr"/"brk", offset, gain, offRel, offFull, onRel, onFull]
                var rp = message.split(" ")
                if (rp[1] === "thr") {
                    setOffsetV(lightOffThr, rp[2])
                    setGain(lightGainThr, rp[3])
                } else {
                    setOffsetV(lightOffBrk, rp[2])
                    setGain(lightGainBrk, rp[3])
                }
                root.cfgDirty = true
                return
            }
            if (message === "calib-refused") {
                calibFail(root.calibRunning, "Needs power on and standstill")
                return
            }
            if (message === "calib-aborted") {
                calibFail(root.calibRunning, "Cancelled - nothing changed")
                return
            }
            if (message.startsWith("calib-error ")) {
                // the script only gets here when released and full-press read
                // nearly the same - the lever never moved, or not far enough
                calibFail(message.split(" ")[1] === "brk" ? "brk" : "thr",
                          "Failed - lever not held fully pressed")
                return
            }

            if (message.startsWith("model ")
                    || message.startsWith("general ")
                    || message.startsWith("temps ")
                    || message.startsWith("modes ")
                    || message.startsWith("secret ")
                    || message.startsWith("apply ")
                    || message.startsWith("gesture ")
                    || message.startsWith("misc ")
                    || message.startsWith("rear ")
                    || message.startsWith("cruise ")
                    || message.startsWith("alarm ")) {
                applySettingsLine(message)
            } else if (message === "model-ok") {
                root.stepDone()
                loadedModel = modelBox.currentIndex
                resetSettingsLoad()
                VescIf.emitStatusMessage("Model saved, restarting...", true)
                mCommands.lispSetRunning(false)
                restartTimer.start()
            } else if (message === "reset-ok") {
                root.stepDone()
                // reset takes the model back to Slave, which only applies on a restart
                modelBox.currentIndex = 2
                loadedModel = 2
                root.saving = false
                saveTimeout.stop()
                resetSettingsLoad()
                VescIf.emitStatusMessage("Settings reset, restarting...", true)
                mCommands.lispSetRunning(false)
                restartTimer.start()
            } else if (message === "ok") {
                root.stepDone()
                root.saving = false
                root.cfgDirty = false
                saveTimeout.stop()
                VescIf.emitStatusMessage("Scooter settings saved.", true)
            }
        }
    }
}
