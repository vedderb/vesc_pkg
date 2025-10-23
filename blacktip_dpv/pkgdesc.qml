import QtQuick 2.15

Item {
    property string pkgName: "BlacktipDPV"
    property string pkgDescriptionMd: "README.dist.md"
    property string pkgLisp: "blacktip_dpv.lisp"
    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: true
    property string pkgOutput: "blacktip_dpv.vescpkg"

    // This function should return true when this package is compatible
    // with the connected vesc-based device
    function isCompatible (fwRxParams) {
        var hwName = fwRxParams.hw.toLowerCase();
        var fwName = fwRxParams.fwName.toLowerCase();

        // vesc, vesc bms or custom module
        // Note that VBMS32 is a custom module
        var hwType = fwRxParams.hwTypeStr().toLowerCase();

        var major = fwRxParams.major;
        var minor = fwRxParams.minor;

        console.log("HW Name: " + hwName)
        console.log("FW Name: " + fwName)
        console.log("HW Type: " + hwType)
        console.log("Major: " + major)
        console.log("Minor: " + minor)

        // Prevent installing on VBMS
        if (hwType != "vesc") {
            return false
        }

        if (hwName != "410" && hwName != "60" && hwName != "60_mk5") {
            return false
        }

        if (major != 6 || minor != 6) {
            return false
        }

        return true
    }
}
