import QtQuick 2.15

Item {
    property string pkgName: "VL Bike 39P STM"
    property string pkgDescriptionMd: "README_stm.md"
    property string pkgLisp: "code_stm.lbm"
    property string pkgQml: "ui_stm.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "vl_bike_39p_stm.vescpkg"

    // This function should return true when this package is compatible
    // with the connected vesc-based device
    function isCompatible (fwRxParams) {
        var hwName = fwRxParams.hw.toLowerCase();
        var fwName = fwRxParams.fwName.toLowerCase();

        // vesc, vesc bms or custom module
        // Note that VBMS16 is a custom module
        var hwType = fwRxParams.hwTypeStr().toLowerCase();		

        //console.log("HW Name: " + hwName)
        //console.log("FW Name: " + fwName)
        //console.log("HW Type: " + hwType)

        if (hwType == "vesc") {
            return true
        } else {
            return false
        }
    }
}
