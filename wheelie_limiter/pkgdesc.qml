import QtQuick 2.15

Item {
    property string pkgName: "Wheelie Assist"
    property string pkgDescriptionMd: "README.md"
    property string pkgLisp: "wheelie_limiter.lisp"
    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "wheelie_limiter.vescpkg"

    // Return true when this package is compatible with the connected
    // VESC-based device. Requires an IMU and an ADC throttle; those cannot
    // be detected reliably here, so we only exclude the classic VESC BMS
    // (which does not support packages).
    function isCompatible (fwRxParams) {
        var hwType = fwRxParams.hwTypeStr().toLowerCase();

        if (hwType == "vesc bms") {
            return false;
        }

        return true;
    }
}
