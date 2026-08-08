#!/usr/bin/env python3
# Generates the Float Accessories package config from the PARAMS table:
#   settings.xml          - VESC Tool ConfigParams description
#   ../fa_cfg/datatypes.h - the FaConfig struct (fields in XML order)
#   ../fa_cfg/conf_lookup.h - name -> field offset/type table for the
#                             LispBM config access extensions
#
# vesc_tool --xmlConfToCode settings.xml then generates confparser/confxml/
# conf_default from settings.xml (see fa_cfg/Makefile).

import os

# (name, longName, kind, default, extra, description)
# kind: "bool" | ("int", min, max, suffix) | ("float", min, max, step, suffix)
#     | ("enum", [names]) | ("string", buflen)
# String fields are stored as a fixed char[buflen] in FaConfig and edited as
# free text in VESC Tool's native config page.
B, I, F, E, S = "bool", "int", "float", "enum", "string"

LED_MODES = [
    "White/Red", "Battery", "Cyan/Magenta", "Blue/Green", "Yellow/Green",
    "Rainbow", "Strobe", "Rave", "Rave Directional", "Knight Rider",
    "Felony", "Trans Pride",
]
COLOR_ORDERS = ["GRB", "RGB", "GRBW", "RGBW"]
# One enum per strip doubles as the enable switch and the wire timing of
# the esp_led driver: 0 disables the strip, the other values select the
# timing. Universal covers all the listed families; a specific preset can
# help marginal strips or long data lines.
STRIP_TIMINGS = ["Disabled", "Universal", "WS2812B", "WS2815", "SK6812",
                 "SK6815"]
# The config stores the concrete highbeam hardware description; the named
# board presets (Avaspark, JetFleet, ...) exist only in the QML page and
# just fill these fields in.
HIGHBEAM_MODES = ["None", "PWM Pin", "Embedded LEDs"]

PARAMS = [
    # --- Features -------------------------------------------------------
    ("led_enabled", "LED Enabled", (B,), 0,
     "Enable the LED module (needs the ESPLED Strip native lib)."),
    ("bms_enabled", "BMS Enabled", (B,), 0,
     "Enable the stock OW BMS RS485 bridge."),
    ("pubmote_enabled", "Pubmote Enabled", (B,), 0,
     "Enable the Pubmote ESP-NOW remote."),
    ("log_enabled", "Logging Enabled", (B,), 0,
     "Enable telemetry logging."),
    ("humidity_enabled", "Humidity Sensor Enabled", (B,), 0,
     "Enable the Si7021/AHT20 humidity sensor loop."),
    ("gnss_enabled", "GNSS Enabled", (B,), 0,
     "Enable the GNSS receiver (u-blox or NMEA). Feeds the gnss-*"
     " extensions, the SD log position (Log GNSS) and the CAN GNSS"
     " broadcast."),
    ("can_id", "CAN ID", (I, -1, 253, ""), -1,
     "CAN ID of the VESC. -1 scans and picks the first one found."),
    ("can_loop_delay", "CAN Loop Rate", (I, 1, 100, " Hz"), 20,
     "Telemetry poll rate on the CAN bus."),
    ("led_on", "LEDs On", (B,), 1,
     "Master LED on/off. Also toggled from the QML page and mall grab."),
    ("led_highbeam_on", "Highbeam On", (B,), 1,
     "Highbeam on/off."),
    ("led_mode", "LED Mode", (E, LED_MODES), 0,
     "Front/rear LED pattern while riding."),
    ("led_mode_idle", "LED Mode Idle", (E, LED_MODES), 5,
     "Front/rear LED pattern when idle."),
    ("led_mode_startup", "LED Mode Startup", (E, LED_MODES), 9,
     "Front/rear LED pattern during startup."),
    ("led_mode_status", "Status Bar Style", (E, ["Classic", "Alternate"]), 0,
     "Style of the footpad indication on the status bar."),
    ("led_mode_button", "Button LED Mode", (E, ["Rainbow", "Battery"]), 0,
     "Pattern of the single button LED."),
    ("led_mode_footpad", "Footpad LED Mode", (E, ["Rainbow"]), 0,
     "Pattern of the footpad strip."),
    ("led_mall_grab_enabled", "Mall Grab", (B,), 1,
     "Show the status pattern when the board is held nose-up."),
    ("led_brake_light_enabled", "Brake Light", (B,), 1,
     "Strobe the rear strip red when braking."),
    ("led_brake_light_min_amps", "Brake Light Min Current", (F, -50.0, 0.0, 0.5, " A"), -4.0,
     "Motor current threshold below which the brake light triggers."),
    ("idle_timeout", "Idle Timeout", (I, 0, 3600, " s"), 1,
     "Seconds without activity before the idle pattern shows."),
    ("idle_timeout_shutoff", "Idle Shutoff", (I, 0, 36000, " s"), 600,
     "Seconds without activity before the LEDs turn off."),
    ("led_brightness", "Brightness", (F, 0.0, 1.0, 0.05, ""), 0.8,
     "LED brightness while riding."),
    ("led_brightness_highbeam", "Highbeam Brightness", (F, 0.0, 1.0, 0.05, ""), 0.8,
     "Brightness of the highbeam."),
    ("led_brightness_idle", "Idle Brightness", (F, 0.0, 1.0, 0.05, ""), 0.5,
     "LED brightness when idle."),
    ("led_brightness_status", "Status Brightness", (F, 0.0, 1.0, 0.05, ""), 0.2,
     "Brightness of the status bar."),
    ("led_max_brightness", "Max Brightness", (F, 0.0, 1.0, 0.05, ""), 0.8,
     "Upper limit applied to every LED brightness."),
    ("led_dim_on_highbeam_ratio", "Dim On Highbeam", (F, 0.0, 1.0, 0.05, ""), 0.2,
     "How much the rest of the strip dims while the highbeam is on."),
    ("led_startup_timeout", "Startup Pattern Time", (I, 0, 600, " s"), 20,
     "How long the startup pattern shows after boot."),
    ("led_loop_delay", "LED Loop Rate", (I, 1, 100, " Hz"), 20,
     "Update rate of the LED state logic."),
    ("led_update_not_running", "Freeze While Riding", (B,), 0,
     "Freeze front/rear animations while riding."),
    ("led_show_battery_charging", "Show Charging", (B,), 1,
     "Show the battery pattern while the charger is plugged in."),

    # --- LEDs: front strip ----------------------------------------------
    ("led_front_timing", "Front Strip", (E, STRIP_TIMINGS), 0,
     "Front strip: disabled, or the wire timing preset to drive it with."),
    ("led_front_pin", "Front Pin", (I, -1, 48, ""), 8,
     "GPIO of the front strip data line."),
    ("led_front_num", "Front LED Count", (I, 0, 512, ""), 11,
     "Number of LEDs on the front strip (highbeam LEDs not included)."),
    ("led_front_type", "Front Color Order", (E, COLOR_ORDERS), 2,
     "Color order / RGBW type of the front strip."),
    ("led_front_reversed", "Front Reversed", (B,), 1,
     "Reverse the pixel order of the front strip."),
    ("led_front_highbeam_mode", "Front Highbeam", (E, HIGHBEAM_MODES), 0,
     "Front highbeam hardware: a separate PWM-driven pin, or LEDs embedded"
     " in the strip itself."),
    ("led_front_highbeam_pin", "Front Highbeam Pin", (I, -1, 48, ""), -1,
     "PWM highbeam GPIO for the front (highbeam mode PWM Pin)."),
    ("led_front_highbeam_pos", "Front Highbeam Positions",
     (I, -2147483648, 2147483647, ""), -1,
     "Embedded highbeam LED positions within the strip, packed one per"
     " byte from the lowest, 255 = unused (e.g. positions 3,8,14,19 ="
     " 320014339)."),
    ("led_front_highbeam_min", "Front Highbeam Min Drive",
     (F, 0.0, 1.0, 0.05, ""), 0.0,
     "Embedded highbeam brightness is mapped onto the min-max drive range"
     " some light bars expect."),
    ("led_front_highbeam_max", "Front Highbeam Max Drive",
     (F, 0.0, 1.0, 0.05, ""), 1.0,
     "Embedded highbeam brightness is mapped onto the min-max drive range"
     " some light bars expect."),

    # --- LEDs: rear strip -----------------------------------------------
    ("led_rear_timing", "Rear Strip", (E, STRIP_TIMINGS), 0,
     "Rear strip: disabled, or the wire timing preset to drive it with."),
    ("led_rear_pin", "Rear Pin", (I, -1, 48, ""), 9,
     "GPIO of the rear strip data line."),
    ("led_rear_num", "Rear LED Count", (I, 0, 512, ""), 11,
     "Number of LEDs on the rear strip (highbeam LEDs not included)."),
    ("led_rear_type", "Rear Color Order", (E, COLOR_ORDERS), 2,
     "Color order / RGBW type of the rear strip."),
    ("led_rear_reversed", "Rear Reversed", (B,), 1,
     "Reverse the pixel order of the rear strip."),
    ("led_rear_highbeam_mode", "Rear Highbeam", (E, HIGHBEAM_MODES), 0,
     "Rear highbeam hardware: a separate PWM-driven pin, or LEDs embedded"
     " in the strip itself."),
    ("led_rear_highbeam_pin", "Rear Highbeam Pin", (I, -1, 48, ""), -1,
     "PWM highbeam GPIO for the rear (highbeam mode PWM Pin)."),
    ("led_rear_highbeam_pos", "Rear Highbeam Positions",
     (I, -2147483648, 2147483647, ""), -1,
     "Embedded highbeam LED positions within the strip, packed one per"
     " byte from the lowest, 255 = unused (e.g. positions 3,8,14,19 ="
     " 320014339)."),
    ("led_rear_highbeam_min", "Rear Highbeam Min Drive",
     (F, 0.0, 1.0, 0.05, ""), 0.0,
     "Embedded highbeam brightness is mapped onto the min-max drive range"
     " some light bars expect."),
    ("led_rear_highbeam_max", "Rear Highbeam Max Drive",
     (F, 0.0, 1.0, 0.05, ""), 1.0,
     "Embedded highbeam brightness is mapped onto the min-max drive range"
     " some light bars expect."),

    # --- LEDs: status bar -----------------------------------------------
    ("led_status_timing", "Status Strip", (E, STRIP_TIMINGS), 0,
     "Status bar: disabled, or the wire timing preset to drive it with."),
    ("led_status_pin", "Status Pin", (I, -1, 48, ""), 7,
     "GPIO of the status bar data line."),
    ("led_status_num", "Status LED Count", (I, 0, 512, ""), 10,
     "Number of LEDs on the status bar."),
    ("led_status_type", "Status Color Order", (E, COLOR_ORDERS), 0,
     "Color order / RGBW type of the status bar."),
    ("led_status_reversed", "Status Reversed", (B,), 1,
     "Reverse the pixel order of the status bar."),

    # --- LEDs: footpad --------------------------------------------------
    ("led_footpad_timing", "Footpad Strip", (E, STRIP_TIMINGS), 0,
     "Footpad strip: disabled, or the wire timing preset to drive it"
     " with."),
    ("led_footpad_pin", "Footpad Pin", (I, -1, 48, ""), -1,
     "GPIO of the footpad strip data line."),
    ("led_footpad_num", "Footpad LED Count", (I, 0, 512, ""), 0,
     "Number of LEDs on the footpad strip."),
    ("led_footpad_type", "Footpad Color Order", (E, COLOR_ORDERS), 0,
     "Color order / RGBW type of the footpad strip."),
    ("led_footpad_reversed", "Footpad Reversed", (B,), 0,
     "Reverse the pixel order of the footpad strip."),

    # --- LEDs: button ---------------------------------------------------
    ("led_button_timing", "Button LED", (E, STRIP_TIMINGS), 0,
     "Single button LED: disabled, or the wire timing preset to drive it"
     " with."),
    ("led_button_pin", "Button Pin", (I, -1, 48, ""), -1,
     "GPIO of the button LED data line."),

    # --- Pubmote ---------------------------------------------------------
    ("pubmote_loop_delay", "Pubmote Loop Rate", (I, 1, 100, " Hz"), 20,
     "Telemetry rate to the remote."),
    ("pubmote_remote_mac_a", "Remote MAC A", (I, -2147483648, 2147483647, ""), -1,
     "Paired remote MAC (upper bytes). Set by the pairing flow."),
    ("pubmote_remote_mac_b", "Remote MAC B", (I, -2147483648, 2147483647, ""), -1,
     "Paired remote MAC (lower bytes). Set by the pairing flow."),
    ("pubmote_secret_code", "Pairing Secret", (I, -2147483648, 2147483647, ""), -1,
     "Pairing secret. Set by the pairing flow."),

    # --- BMS --------------------------------------------------------------
    ("bms_type", "BMS Type", (I, 0, 10, ""), 0,
     "BMS variant."),
    ("bms_rs485_chip", "RS485 Chip", (I, 0, 3, ""), 1,
     "RS485 transceiver variant."),
    ("bms_rs485_di_pin", "RS485 DI Pin", (I, -1, 48, ""), 16,
     "GPIO wired to the transceiver DI."),
    ("bms_rs485_ro_pin", "RS485 RO Pin", (I, -1, 48, ""), 8,
     "GPIO wired to the transceiver RO."),
    ("bms_rs485_dere_pin", "RS485 DE/RE Pin", (I, -1, 48, ""), 17,
     "GPIO wired to the transceiver DE/RE."),
    ("bms_wakeup_pin", "BMS Wakeup Pin", (I, -1, 48, ""), -1,
     "GPIO that wakes the BMS, -1 if unused."),
    ("bms_override_soc", "Override SOC", (I, 0, 1, ""), 0,
     "Report the locally estimated SOC instead of the BMS one."),
    ("bms_charge_only", "Charge Only", (B,), 0,
     "Only talk to the BMS while charging."),
    ("bms_buff_size", "RS485 Buffer", (I, 32, 1024, " B"), 128,
     "RS485 receive buffer size."),
    ("bms_loop_delay", "BMS Loop Rate", (I, 1, 100, " Hz"), 8,
     "BMS poll rate."),
    ("soc_type", "SOC Estimator", (I, 0, 10, ""), 0,
     "State-of-charge estimation method."),
    ("cell_type", "Cell Type", (I, 0, 10, ""), 0,
     "Battery cell type for the voltage curve."),
    ("bms_key_a", "BMS Key A", (I, -2147483648, 2147483647, ""), -1,
     "Stored BMS pairing key. Set from the QML page."),
    ("bms_key_b", "BMS Key B", (I, -2147483648, 2147483647, ""), -1,
     "Stored BMS pairing key. Set from the QML page."),
    ("bms_key_c", "BMS Key C", (I, -2147483648, 2147483647, ""), -1,
     "Stored BMS pairing key. Set from the QML page."),
    ("bms_key_d", "BMS Key D", (I, -2147483648, 2147483647, ""), -1,
     "Stored BMS pairing key. Set from the QML page."),
    ("bms_counter_a", "BMS Counter A", (I, -2147483648, 2147483647, ""), -1,
     "Stored BMS counter. Set from the QML page."),
    ("bms_counter_b", "BMS Counter B", (I, -2147483648, 2147483647, ""), -1,
     "Stored BMS counter. Set from the QML page."),
    ("bms_counter_c", "BMS Counter C", (I, -2147483648, 2147483647, ""), -1,
     "Stored BMS counter. Set from the QML page."),
    ("bms_counter_d", "BMS Counter D", (I, -2147483648, 2147483647, ""), -1,
     "Stored BMS counter. Set from the QML page."),

    # --- Logging / humidity ----------------------------------------------
    ("log_rate", "Log Rate", (F, 0.1, 50.0, 0.1, " Hz"), 2.0,
     "Telemetry log sample rate."),
    ("log_append_gnss", "Log GNSS", (B,), 0,
     "Append GNSS position to log samples (needs GNSS enabled)."),
    ("humidity_sda_pin", "Humidity SDA Pin", (I, -1, 48, ""), -1,
     "I2C SDA GPIO of the humidity sensor."),
    ("humidity_slc_pin", "Humidity SCL Pin", (I, -1, 48, ""), -1,
     "I2C SCL GPIO of the humidity sensor."),

    # --- GNSS -------------------------------------------------------------
    ("gnss_type", "GNSS Type", (E, ["u-blox (UBX)", "NMEA (UART)"]), 0,
     "u-blox modules are driven by the firmware driver; any other NMEA"
     " module is read from a plain UART."),
    ("gnss_rx_pin", "GNSS RX Pin", (I, -1, 48, ""), -1,
     "GPIO wired to the module's TX output."),
    ("gnss_tx_pin", "GNSS TX Pin", (I, -1, 48, ""), -1,
     "GPIO wired to the module's RX input. Required for u-blox, optional"
     " for NMEA (read-only)."),
    ("gnss_uart_num", "GNSS UART", (I, 0, 2, ""), 1,
     "UART peripheral to use."),
    ("gnss_rate_ms", "GNSS Nav Rate", (I, 100, 5000, " ms"), 500,
     "Navigation update interval (u-blox type only)."),
    ("gnss_baud", "GNSS Baud Rate", (I, 4800, 921600, ""), 9600,
     "UART baud rate (NMEA type only - the u-blox driver manages its"
     " own)."),

    # --- Internal ----------------------------------------------------------
    ("accept_tos", "TOS Accepted", (B,), 0,
     "Set once the terms-of-service prompt was accepted."),
]

GROUPS = [
    ("General", [
        ("Features", ["led_enabled", "bms_enabled", "pubmote_enabled",
                     "log_enabled", "humidity_enabled", "gnss_enabled",
                     "::sep::CAN Bus", "can_id", "can_loop_delay"]),
        ("LEDs", ["led_on", "led_highbeam_on", "led_mode", "led_mode_idle",
                     "led_mode_startup", "led_mode_status", "led_mode_button",
                     "led_mode_footpad",
                     "::sep::Behavior", "led_mall_grab_enabled",
                     "led_brake_light_enabled", "led_brake_light_min_amps",
                     "idle_timeout", "idle_timeout_shutoff",
                     "::sep::Brightness", "led_brightness",
                     "led_brightness_highbeam", "led_brightness_idle",
                     "led_brightness_status", "led_max_brightness",
                     "led_dim_on_highbeam_ratio",
                     "::sep::Advanced", "led_startup_timeout",
                     "led_loop_delay", "led_update_not_running",
                     "led_show_battery_charging"]),
        ("Front", ["led_front_timing", "led_front_pin", "led_front_num",
                   "led_front_type", "led_front_reversed",
                   "::sep::Highbeam", "led_front_highbeam_mode", "led_front_highbeam_pin",
                   "led_front_highbeam_pos", "led_front_highbeam_min",
                   "led_front_highbeam_max"]),
        ("Rear", ["led_rear_timing", "led_rear_pin", "led_rear_num",
                  "led_rear_type", "led_rear_reversed",
                  "::sep::Highbeam", "led_rear_highbeam_mode", "led_rear_highbeam_pin",
                  "led_rear_highbeam_pos", "led_rear_highbeam_min",
                  "led_rear_highbeam_max"]),
        ("Status Bar", ["led_status_timing", "led_status_pin",
                        "led_status_num", "led_status_type",
                        "led_status_reversed"]),
        ("Footpad", ["led_footpad_timing", "led_footpad_pin",
                     "led_footpad_num", "led_footpad_type",
                     "led_footpad_reversed"]),
        ("Button", ["led_button_timing", "led_button_pin"]),
        ("Pubmote", ["pubmote_loop_delay",
                    "::sep::Paired Remote", "pubmote_remote_mac_a",
                    "pubmote_remote_mac_b", "pubmote_secret_code"]),
        ("BMS", ["bms_type", "bms_rs485_chip", "bms_rs485_di_pin",
                 "bms_rs485_ro_pin", "bms_rs485_dere_pin",
                 "bms_wakeup_pin", "bms_override_soc",
                 "bms_charge_only", "bms_buff_size", "bms_loop_delay",
                 "::sep::Battery", "soc_type", "cell_type",
                 "::sep::Pairing", "bms_key_a", "bms_key_b", "bms_key_c", "bms_key_d",
                 "bms_counter_a", "bms_counter_b", "bms_counter_c",
                 "bms_counter_d"]),
        ("Logging", ["log_rate", "log_append_gnss"]),
        ("Humidity", ["humidity_sda_pin", "humidity_slc_pin"]),
        ("GNSS", ["gnss_type", "gnss_rx_pin", "gnss_tx_pin",
                      "gnss_uart_num", "gnss_rate_ms", "gnss_baud"]),
    ]),
    ("Internal", [
        ("Meta", ["accept_tos"]),
    ]),
]


def esc(s):
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace('"', "&quot;"))


def emit_xml(path):
    out = []
    a = out.append
    a('<?xml version="1.0" encoding="UTF-8"?>')
    a("<ConfigParams>")
    a("    <Params>")
    a("        <config_name>")
    a("            <longName>none</longName>")
    a("            <type>3</type>")
    a("            <transmittable>0</transmittable>")
    a("            <description>Float Accessories configuration</description>")
    a("            <cDefine></cDefine>")
    a("            <valString>FaConfig</valString>")
    a("            <maxLen>0</maxLen>")
    a("        </config_name>")
    a("        <hw_name>")
    a("            <longName>Float Accessories</longName>")
    a("            <type>0</type>")
    a("            <transmittable>0</transmittable>")
    a("            <description>Smart LED control, tilt remote and stock OW BMS bridge for the VESC Express.</description>")
    a("            <cDefine></cDefine>")
    a("        </hw_name>")

    for name, long_name, kind, default, desc in iter_params():
        a("        <%s>" % name)
        a("            <longName>%s</longName>" % esc(long_name))
        k = kind[0]
        if k == F:
            a("            <type>1</type>")
            a("            <transmittable>1</transmittable>")
            a("            <description>%s</description>" % esc(desc))
            a("            <cDefine>CFG_DFLT_%s</cDefine>" % name.upper())
            a("            <editorDecimalsDouble>2</editorDecimalsDouble>")
            a("            <editorScale>1</editorScale>")
            a("            <editAsPercentage>0</editAsPercentage>")
            a("            <maxDouble>%s</maxDouble>" % kind[2])
            a("            <minDouble>%s</minDouble>" % kind[1])
            a("            <showDisplay>0</showDisplay>")
            a("            <stepDouble>%s</stepDouble>" % kind[3])
            a("            <valDouble>%s</valDouble>" % default)
            a("            <vTxDoubleScale>1</vTxDoubleScale>")
            a("            <suffix>%s</suffix>" % esc(kind[4]))
            a("            <vTx>9</vTx>")  # double32_auto
        elif k == I:
            a("            <type>2</type>")
            a("            <transmittable>1</transmittable>")
            a("            <description>%s</description>" % esc(desc))
            a("            <cDefine>CFG_DFLT_%s</cDefine>" % name.upper())
            a("            <editorScale>1</editorScale>")
            a("            <editAsPercentage>0</editAsPercentage>")
            a("            <maxInt>%d</maxInt>" % kind[2])
            a("            <minInt>%d</minInt>" % kind[1])
            a("            <showDisplay>0</showDisplay>")
            a("            <stepInt>1</stepInt>")
            a("            <valInt>%d</valInt>" % default)
            a("            <suffix>%s</suffix>" % esc(kind[3]))
            a("            <vTx>6</vTx>")  # int32
        elif k == E:
            a("            <type>4</type>")
            a("            <transmittable>1</transmittable>")
            a("            <description>%s</description>" % esc(desc))
            a("            <cDefine>CFG_DFLT_%s</cDefine>" % name.upper())
            a("            <valInt>%d</valInt>" % default)
            for en in kind[1]:
                a("            <enumNames>%s</enumNames>" % esc(en))
        elif k == B:
            a("            <type>5</type>")
            a("            <transmittable>1</transmittable>")
            a("            <description>%s</description>" % esc(desc))
            a("            <cDefine>CFG_DFLT_%s</cDefine>" % name.upper())
            a("            <valInt>%d</valInt>" % default)
        elif k == S:
            # QString param. maxLen is the editable length; the FaConfig
            # buffer is one larger for the null terminator (see datatypes).
            a("            <type>3</type>")
            a("            <transmittable>1</transmittable>")
            a("            <description>%s</description>" % esc(desc))
            a("            <cDefine>CFG_DFLT_%s</cDefine>" % name.upper())
            a("            <valString>%s</valString>" % esc(default))
            a("            <maxLen>%d</maxLen>" % (kind[1] - 1))
        a("        </%s>" % name)

    a("    </Params>")
    a("    <SerOrder>")
    for name, _ln, _kind, _d, _desc in iter_params():
        a("        <ser>%s</ser>" % name)
    a("    </SerOrder>")
    a("    <Grouping>")
    for group, subgroups in GROUPS:
        a("        <group>")
        a("            <groupName>%s</groupName>" % esc(group))
        for sub, params in subgroups:
            a("            <subgroup>")
            a("                <subgroupName>%s</subgroupName>" % esc(sub))
            a("                <subgroupParams>")
            for p in params:
                a("                    <param>%s</param>" % p)
            a("                </subgroupParams>")
            a("            </subgroup>")
        a("        </group>")
    a("    </Grouping>")
    a("</ConfigParams>")
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")


def iter_params():
    for name, long_name, kind, default, desc in PARAMS:
        yield name, long_name, kind, default, desc


def emit_datatypes(path):
    out = []
    a = out.append
    a("// Generated by conf/gen_conf.py - do not edit.")
    a("#ifndef DATATYPES_H_")
    a("#define DATATYPES_H_")
    a("")
    a("#include <stdbool.h>")
    a("#include <stdint.h>")
    a("")
    a("typedef struct {")
    for name, _ln, kind, _d, _desc in iter_params():
        k = kind[0]
        if k == S:
            a("    char %s[%d];" % (name, kind[1]))
            continue
        ctype = {F: "float", I: "int32_t", E: "uint8_t", B: "uint8_t"}[k]
        a("    %s %s;" % (ctype, name))
    a("} FaConfig;")
    a("")
    a("// DATATYPES_H_")
    a("#endif")
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")


def emit_lookup(path):
    # Value-only tables: on the RISC-V targets native libs execute in place
    # from flash without load-time relocation, so statically initialized
    # POINTERS hold meaningless link-time addresses. Names are stored as
    # fixed-size char arrays instead (their addresses are computed at
    # runtime, which is position-independent).
    name_len = max(len(p[0]) for p in PARAMS) + 1
    out = []
    a = out.append
    a("// Generated by conf/gen_conf.py - do not edit.")
    a("// Name -> FaConfig field lookup for the LispBM config extensions.")
    a("// Value-only tables - no statically initialized pointers, which do")
    a("// not survive execute-in-place loading on the RISC-V targets.")
    a("#ifndef CONF_LOOKUP_H_")
    a("#define CONF_LOOKUP_H_")
    a("")
    a("#include <stddef.h>")
    a('#include "datatypes.h"')
    a("")
    a("typedef enum { CFG_F32 = 0, CFG_I32, CFG_U8, CFG_STR } cfg_field_type;")
    a("")
    a("#define CFG_NAME_LEN %d" % name_len)
    a("#define CFG_FIELD_COUNT %d" % len(PARAMS))
    a("")
    a("static const char cfg_names[CFG_FIELD_COUNT][CFG_NAME_LEN] = {")
    for name, _ln, _kind, _d, _desc in iter_params():
        a('    "%s",' % name)
    a("};")
    a("")
    a("static const uint16_t cfg_offsets[CFG_FIELD_COUNT] = {")
    for name, _ln, _kind, _d, _desc in iter_params():
        a("    offsetof(FaConfig, %s)," % name)
    a("};")
    a("")
    a("static const uint8_t cfg_types[CFG_FIELD_COUNT] = {")
    for name, _ln, kind, _d, _desc in iter_params():
        k = kind[0]
        t = {F: "CFG_F32", I: "CFG_I32", E: "CFG_U8", B: "CFG_U8",
             S: "CFG_STR"}[k]
        a("    %s," % t)
    a("};")
    a("")
    a("// Buffer size (bytes) for CFG_STR fields, 0 otherwise. Used to bound")
    a("// the copy in the string set/get handlers.")
    a("static const uint16_t cfg_lengths[CFG_FIELD_COUNT] = {")
    for name, _ln, kind, _d, _desc in iter_params():
        a("    %d," % (kind[1] if kind[0] == S else 0))
    a("};")
    a("")
    a("// CONF_LOOKUP_H_")
    a("#endif")
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    emit_xml(os.path.join(here, "settings.xml"))
    emit_datatypes(os.path.join(here, "..", "fa_cfg", "datatypes.h"))
    emit_lookup(os.path.join(here, "..", "fa_cfg", "conf_lookup.h"))
    print("generated settings.xml, datatypes.h, conf_lookup.h (%d params)"
          % len(PARAMS))
