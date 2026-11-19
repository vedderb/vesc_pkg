import QtQuick 2.15

Item {
    property string pkgName: "slcan Adapter"
    property string pkgDescriptionMd: "README.md"
    property string pkgLisp: "slcan.lisp"
    property string pkgQml: ""
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "slcan_adapter.vescpkg"
    property string icon: "icon.svg"
    property string iconLight: "icon_light.svg"

    function isCompatible (fwRxParams) {
        return fwRxParams.hwTypeStr().toLowerCase() == "custom module"
    }
}
