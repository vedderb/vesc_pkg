import QtQuick 2.15

Item {
    property string pkgName: "Scooter Dashboard Support"
    property string pkgDescriptionMd: "README.md"
    property string pkgLisp: "scooter_support.lisp"
    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "scooter_dashboard_support.vescpkg"
    property string icon: "icon.svg"
    property string iconLight: "icon_light.svg"

    function isCompatible (fwRxParams) {
        var hwType = fwRxParams.hwTypeStr().toLowerCase()
        return hwType === "vesc"
    }
}
