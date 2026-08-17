import QtQuick 2.15

Item {
    property string pkgName: "Wheelie Assist"
    property string pkgDescriptionMd: "README.md"
    property string pkgLisp: "wheelie_limiter.lisp"
    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "wheelie_limiter.vescpkg"

    // Return true when this package is compatible with the connected
    // VESC-based device. This package drives the motor and needs an IMU and
    // an ADC throttle, so it only makes sense on a motor controller. The
    // IMU/throttle cannot be detected reliably here, but requiring the "vesc"
    // hardware type keeps it off the VESC BMS and VESC Express (which reports
    // as a custom module) so it only runs on motor controllers.
    function isCompatible (fwRxParams) {
        var hwType = fwRxParams.hwTypeStr().toLowerCase();

        // Only run on motor controllers (excludes VESC BMS and VESC Express)
        if (hwType != "vesc") {
            return false;
        }

        return true;
    }
}
