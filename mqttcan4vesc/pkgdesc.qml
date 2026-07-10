import QtQuick 2.15

Item {
    property string pkgName: "MQTTCAN4VESC"
    property string pkgDescriptionMd: "README.md"
    property string pkgLisp: "mqttcan4vesc.lisp"
    property string pkgQml: "ui.qml"
    property bool   pkgQmlIsFullscreen: false
    property string pkgOutput: "mqttcan4vesc.vescpkg"

    // This package runs on a VESC Express, not on the motor controller.
    // Stock boards report "VESC Express"; custom Express variants commonly
    // report "VESC Exp <name>", so accept both spellings.
    function isCompatible(fwRxParams) {
        var hw = fwRxParams.hw.toLowerCase()
        return hw.indexOf("express") >= 0 || hw.indexOf("exp ") >= 0
    }
}
