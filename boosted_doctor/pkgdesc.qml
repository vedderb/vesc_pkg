import QtQuick 2.15

Item {
    property string pkgName: "Boosted Doctor"
    property string pkgDescriptionMd: "README.md"
    property string pkgLisp: "code.lbm"
    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "boosted_doctor.vescpkg"

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

        return true;
    }
}
