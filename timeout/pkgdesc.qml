import QtQuick 2.15

Item {
    property string pkgName: "Remote Timeout"
    property string pkgDescriptionMd: "README.md"
    property string pkgLisp: "timeout.lisp"
    property string pkgQml: ""
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "timeout.vescpkg"

    // This function should return true when this package is compatible
    // with the connected vesc-based device
    function isCompatible (fwRxParams) {
        var hwName = fwRxParams.hw.toLowerCase();
        var fwName = fwRxParams.fwName.toLowerCase();
        var hwType = fwRxParams.hwTypeStr().toLowerCase();

        // The classic VESC BMS does not support packages at all
        if (hwType == "vesc bms") {
            return false
        }

        // Works on vesc-based ESCs only
        if (hwType != "vesc") {
            return false
        }

        return true
    }
}


