import QtQuick 2.15

Item {
    property string pkgName: "UCLights"
    property string pkgDescriptionMd: "README.md"
    property string pkgLisp: "UCLights.lisp"
    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "UCLights.vescpkg"

    // Return true only when this package is compatible
    // with the connected device running VESC(R) software.
    function isCompatible(fwRxParams) {
        var hwType = fwRxParams.hwTypeStr().toLowerCase()

        if (hwType != "custom module") {
            return false
        }

        return true
    }
}
