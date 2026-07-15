import QtQuick 2.15

Item {
    property string pkgName: "VESCXPRESS2X3Bridge Express"
    property string pkgDescriptionMd: "README.md"
    property string pkgLisp: "main.lisp"
    property string pkgQml: "main-settings.qml"
    property bool pkgQmlIsFullscreen: false
    property string pkgOutput: "VESCXPRESS2X3Bridge.vescpkg"

    // Verified against vesc_express's own COMM_FW_VERSION handler
    // (main/commands.c in vedderb/vesc_express, release_7_00) rather than
    // guessed -- confirmed working against real hardware.
    function isCompatible(fwRxParams) {
        // Every vesc_express-based board (this one included) always sends
        // HW_TYPE_CUSTOM_MODULE in COMM_FW_VERSION, regardless of hwconf --
        // see commands.c: "send_buffer[ind++] = HW_TYPE_CUSTOM_MODULE".
        // This alone rules out real VESCs ("VESC") and VESC BMS boards
        // ("VESC BMS"), which report their own distinct hwType.
        var hwType = fwRxParams.hwTypeStr().toLowerCase();
        if (hwType != "custom module") {
            return false;
        }

        // fwRxParams.hw is the firmware's compile-time HW_NAME string,
        // copied verbatim in the same handler ("strcpy(send_buffer + ind,
        // HW_NAME)"). This board's hwconf builds with
        // -DHW_NAME="VESCXPRESS2X3Bridge", so this is a board-specific
        // match -- unlike the hwType check above, it also rules out every
        // *other* custom module (e.g. VBMS32), not just real VESCs/VESC BMS.
        var hwName = fwRxParams.hw.toLowerCase();
        return hwName == "vescxpress2x3bridge";
    }
}
