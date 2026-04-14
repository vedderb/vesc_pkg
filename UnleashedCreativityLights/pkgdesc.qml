import QtQuick 2.15

Item {
    property string pkgName: "UCLights"
    property string pkgDescriptionMd: "README.md"
    property string pkgLisp: "UCLights.lisp"
    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "UCLights.vescpkg"

    // Return true only when this package is compatible
    // with the connected VESC-based device.
    function isCompatible(fwRxParams) {
        var hwName = fwRxParams.hw.toLowerCase()
        var hwType = fwRxParams.hwTypeStr().toLowerCase()

        if (hwType == "vesc bms") {
            return false
        }

        if (hwName != "vesc express t") {
            return false
        }

        if (fwRxParams.major < 6) {
            return false
        }

        if (fwRxParams.major == 6 && fwRxParams.minor <= 6) {
            return false
        }

        return true
    }
}