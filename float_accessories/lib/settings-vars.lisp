;@const-symbol-strings

@const-start

; Configuration lives in the fa_cfg native lib as a VESC custom config
; ("Float Accessories Cfg" in VESC Tool), described by conf/settings.xml
; and persisted by the firmware. get-config/set-config in settings.lisp
; access it through the ext-facfg-* extensions.

; Runtime state (not persisted)
(def bms-context-id -1)
(def bms-exit-flag nil)
(def humidity-exit-flag nil)
(def bms-last-activity-time (systime))
(def pubmote-context-id -1)
(def led-context-id -1)
(def led-exit-flag nil)
(def led-reinit-flag nil)
(def led-last-activity-time (systime))
(def can-context-id -1)
(def can-last-activity-time (systime))
(def bms-charge-state 0) ;0 if 100, 1 if 90
(def log-context-id -1)

; LED control state mirrored from config for fast access in the LED loop
(def led-on)
(def led-highbeam-on)
(def led-brightness 0.0)
(def led-brightness-highbeam 0.0)
(def led-brightness-idle 0.0)
(def led-brightness-status 0.0)

(def bms-status -1)
(def bms-battery-type -1)
(def bms-battery-cycles -1)

(def humidity-context-id -1)

(def gnss-context-id -1)
(def gnss-exit-flag nil)

(def mqtt-context-id -1)
(def mqtt-exit-flag nil)

; State
(def log-running false)

(def hum 0)
(def hum-temp 0)

; Last input state received from the remote, for the QML input preview
(def pubmote-last-jsy 0.0)
(def pubmote-last-jsx 0.0)
(def pubmote-last-bt-c 0)
(def pubmote-last-bt-z 0)
(def pubmote-last-is-rev 0)

@const-end
