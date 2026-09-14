import QtQuick 2.15

Item {
    property string pkgName: "ESP LED Strip"
    property string pkgDescriptionMd: "README.md"
    property string pkgLisp: "esp_led_strip.lisp"
    property string pkgQml: "ui.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "esp_led_strip.vescpkg"

    function isCompatible (fwRxParams) {
        var hwType = fwRxParams.hwTypeStr().toLowerCase();
        return hwType === "custom module";
    }
}
