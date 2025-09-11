import QtQuick 2.15

Item {
    property string pkgName: "BlacktipSmartCruise"
    property string pkgDescriptionMd: "README.md"
    property string pkgLisp: "blacktip_smart_cruise.lisp"
    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: true
    property string pkgOutput: "blacktip_smart_cruise.vescpkg"

    // This function should return true when this package is compatible
    // with the connected vesc-based device
    function isCompatible (fwRxParams) {
        var hwName = fwRxParams.hw.toLowerCase();
        var fwName = fwRxParams.fwName.toLowerCase();

        // vesc, vesc bms or custom module
        // Note that VBMS32 is a custom module
        var hwType = fwRxParams.hwTypeStr().toLowerCase();		

        console.log("HW Name: " + hwName)
        console.log("FW Name: " + fwName)
        console.log("HW Type: " + hwType)

        // Prevent installing on VBMS
        if (hwType != "vesc") {
            return false
        }
		
        return true
    }
}
