import QtQuick 2.15

Item {
    property string pkgName: "VL Link Status"
    property string pkgDescriptionMd: "README.md"
    property string pkgLisp: "code.lbm"
    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "vl_link_status.vescpkg"

    // Returns true when this package is compatible with the connected device.
    function isCompatible (fwRxParams) {
        var hwName = fwRxParams.hw.toLowerCase();
        var hwType = fwRxParams.hwTypeStr().toLowerCase();

        // The classic VESC BMS cannot run packages at all
        if (hwType == "vesc bms") {
            return false
        }

        // The VL Link is an ESP32-C3 running VESC Express, so it enumerates
        // as a custom module rather than a motor controller.
        if (hwType != "custom module") {
            return false
        }

        // This package drives GPIO 6 / 7 / 8 and the SIM7070G UART, which
        // only exist on the VL Link. Do not let it install anywhere else.
        return hwName == "vl link"
    }
}
