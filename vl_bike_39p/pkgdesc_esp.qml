import QtQuick 2.15

Item {
    property string pkgName: "VL Bike 39P ESP"
    property string pkgDescriptionMd: "README_esp.md"
    property string pkgLisp: "code_esp.lbm"
    property string pkgQml: "ui_esp.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "vl_bike_39p_esp.vescpkg"

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

        // The classic VESC BMS does not support packages at all
        if (hwType == "vesc bms") {
            return false
        }
        
        // The ESP32 is a custom module
        if (hwType != "custom module") {
            return false
        }

        var res = false
        if (hwName == "str365 io") {
            res = true
        }

        return res
    }
}
