import QtQuick 2.15

Item {
    property string pkgName: "Wheel-E"
    property string pkgDescriptionMd: "package_README-gen.md"
    property string pkgLisp: "lisp/package.lisp"
    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "wheel-e.vescpkg"
    property string icon: "icon.svg"
    property string iconLight: "icon_light.svg"

    function isCompatible (fwRxParams) {
        if (fwRxParams.hwTypeStr().toLowerCase() != "vesc") {
            return false;
        }

        return true;
    }
}
