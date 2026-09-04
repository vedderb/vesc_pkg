import QtQuick 2.15

Item {
    property string pkgName: "Legacy DC DPV"
    property string pkgDescriptionMd: "README.md"
    property string pkgLisp: "legacy_dc_dpv.lisp"
    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "legacy_dc_dpv.vescpkg"

    // This function should return true when this package is compatible
    // with the connected vesc-based device
    function isCompatible (fwRxParams) {
        var hwName = fwRxParams.hw;

        // vesc, vesc bms or custom module
        // Note that VBMS32 is a custom module
        var hwType = fwRxParams.hwTypeStr().toLowerCase();

        var major = fwRxParams.major;
        var minor = fwRxParams.minor;

        // Prevent installing on VBMS
        if (hwType != "vesc") {
            return false
        }

        if (hwName != "410" && hwName != "60" && hwName != "60_MK5") {
            return false
        }

        if (major != 7 || minor != 0) {
            return false
        }

        return true
    }
}
