import QtQuick 2.15

Item {
    property string pkgName: "VESCXPRESS2X3Bridge VESC"
    property string pkgDescriptionMd: "README.md"
    property string pkgLisp: "vesc-side-master.lisp"
    property string pkgQml: ""
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "VESCXPRESS2X3Bridge_Master.vescpkg"

    // Unlike the Express-side package, this has no board-specific hardware
    // to check for -- it runs on any real VESC motor controller (identifies
    // itself over CAN via conf-get 'controller-id, not a fixed hw string),
    // so the only requirement is "a real VESC", not "this exact PCB".
    function isCompatible(fwRxParams) {
        var hwType = fwRxParams.hwTypeStr().toLowerCase();

        // Excludes VESC Express ("custom module") and VESC BMS boards
        // ("vesc bms") -- this script uses app-adc-override and
        // conf-get/conf-set on motor config (si-motor-poles,
        // si-wheel-diameter, l-max-erpm), all real-motor-controller-only
        // APIs that don't exist on those hardware types.
        return hwType == "vesc";
    }
}
