import QtQuick 2.15

Item {
    property string pkgName: "VESC X3 Bridge STM Slave"
    property string pkgDescriptionMd: "README_stm_slave.md"
    property string pkgLisp: "code_stm_slave.lisp"
    property string pkgQml: ""
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "vesc_x3_bridge_stm_slave.vescpkg"

    // Same hardware requirement as the master variant -- any real VESC,
    // identified over CAN via conf-get 'controller-id, not a fixed hw
    // string.
    function isCompatible(fwRxParams) {
        var hwType = fwRxParams.hwTypeStr().toLowerCase();

        // Excludes VESC Express ("custom module") and VESC BMS boards
        // ("vesc bms") -- this script uses conf-get/conf-set on motor
        // config (si-motor-poles, si-wheel-diameter, l-max-erpm), all
        // real-motor-controller-only APIs that don't exist on those
        // hardware types.
        return hwType == "vesc";
    }
}
