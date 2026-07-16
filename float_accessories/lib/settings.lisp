;@const-symbol-strings
@const-start

; Configuration access. The config itself is a VESC custom config provided
; by the fa_cfg native lib (see conf/settings.xml). It is edited in VESC
; Tool's standard parameter UI and persisted by the firmware - the package
; no longer implements its own eeprom layout, magic numbers or CRCs.
;
; Parameter names: the lisp code uses its traditional dashed symbols
; (e.g. 'led-front-pin); the native lib treats '-' and '_' as equal.

(defun get-config (name)
    (ext-facfg-get (sym2str name))
)

(defun set-config (name value)
    (ext-facfg-set (sym2str name) value)
)

(defun save-config () {
    (ext-facfg-store)
    (send-status "Settings saved")
})

(defun restore-config () {
    (ext-facfg-restore)
    (send-status "Settings restored")
})

(defun print-config ()
    (print "Configuration is in VESC Tool: Float Accessories Cfg")
)

; Applies runtime feature changes after the config was edited (from VESC
; Tool or from lisp). Starts/stops the feature loops to match the config.
(defun apply-config () {
    (setq led-on (get-config 'led-on))
    (setq led-highbeam-on (get-config 'led-highbeam-on))
    (setq led-brightness (get-config 'led-brightness))
    (setq led-brightness-highbeam (get-config 'led-brightness-highbeam))
    (setq led-brightness-idle (get-config 'led-brightness-idle))
    (setq led-brightness-status (get-config 'led-brightness-status))

    (if (or (!= (to-i soc-type) (get-config 'soc-type)) (!= (to-i cell-type) (get-config 'cell-type))) {
        (apply-battery-config (get-config 'soc-type) (get-config 'cell-type))
    })

    ; LED loop: reinit in place when running, spawn/stop on enable change
    (if (and (>= led-context-id 0) (!= (get-config 'led-enabled) 1)) {
        (var start-time (systime))
        (setq led-exit-flag t)
        (loopwhile (and led-exit-flag (< (- (systime) start-time) 2000000))
            (yield 10000))
        (if led-exit-flag (send-msg "WARNING: LED loop did not exit in time."))
        (setq led-context-id -1)
    })
    (if (and (>= led-context-id 0) (= (get-config 'led-enabled) 1)) {
        (setq led-reinit-flag t)
    })
    (if (and (= led-context-id -1) (= (get-config 'led-enabled) 1)) {
        (setq led-context-id (spawn led-loop))
    })

    ; BMS loop: restart to pick up new pins/settings
    (if (>= bms-context-id 0) {
        (var start-time (systime))
        (setq bms-exit-flag t)
        (loopwhile (and bms-exit-flag (< (- (systime) start-time) 2000000))
            (yield 10000))
        (if bms-exit-flag (send-msg "WARNING: BMS loop did not exit in time."))
    })
    (setq bms-context-id (if (= (get-config 'bms-enabled) 1) (spawn bms-loop) -1))

    ; Humidity loop
    (if (and (>= humidity-context-id 0) (!= (get-config 'humidity-enabled) 1)) {
        (var start-time (systime))
        (setq humidity-exit-flag t)
        (loopwhile (and humidity-exit-flag (< (- (systime) start-time) 2000000))
            (yield 10000))
        (if humidity-exit-flag (send-msg "WARNING: Humidity loop did not exit in time."))
        (setq humidity-context-id -1)
    })
    (if (and (= humidity-context-id -1) (= (get-config 'humidity-enabled) 1)) {
        (setq humidity-context-id (spawn humidity-loop))
    })

    ; GNSS: restart to pick up new pins/type
    (if (>= gnss-context-id 0) {
        (var start-time (systime))
        (setq gnss-exit-flag t)
        (loopwhile (and gnss-exit-flag (< (- (systime) start-time) 2000000))
            (yield 10000))
        (if gnss-exit-flag (send-msg "WARNING: GNSS loop did not exit in time."))
        (setq gnss-context-id -1)
    })
    (if (= (get-config 'gnss-enabled) 1) {
        (setq gnss-context-id (spawn gnss-loop))
    })

    ; MQTT: restart to pick up new broker / topic / credentials
    (if (>= mqtt-context-id 0) {
        (var start-time (systime))
        (setq mqtt-exit-flag t)
        (loopwhile (and mqtt-exit-flag (< (- (systime) start-time) 3000000))
            (yield 10000))
        (if mqtt-exit-flag (send-msg "WARNING: MQTT loop did not exit in time."))
        (setq mqtt-context-id -1)
    })
    (if (= (get-config 'mqtt-enabled) 1) {
        (setq mqtt-context-id (spawn mqtt-loop))
    })

    ; Pubmote loop
    (if (and (>= pubmote-context-id 0) (!= (get-config 'pubmote-enabled) 1)) {
        (var start-time (systime))
        (setq pubmote-exit-flag t)
        (loopwhile (and pubmote-exit-flag (< (- (systime) start-time) 2000000))
            (yield 10000))
        (if pubmote-exit-flag (send-msg "WARNING: Pubmote loop did not exit in time."))
        (setq pubmote-context-id -1)
    })
    (if (and (= pubmote-context-id -1) (= (get-config 'pubmote-enabled) 1)) {
        (setq pubmote-context-id (spawn pubmote-loop))
    })

    ; Logging
    (if (= (get-config 'log-enabled) 1) {
        (if (= log-context-id -1) {
            (setq log-context-id (spawn log-loop))
        }{
            (start-log (get-config 'log-append-gnss) (get-config 'log-rate))
        })
    }{
        (stop-log)
    })
})

; Poll for config writes from VESC Tool and apply them.
(defun config-watch-loop ()
    (loopwhile t {
        (if (ext-facfg-changed) {
            (send-status "Settings updated")
            (apply-config)
        })
        ; Debounced persist of live control changes: recv-control marks
        ; control-store-pending (a systime) instead of storing per slider
        ; sample; write the config once it has settled for ~0.75 s.
        (if (and control-store-pending (> (secs-since control-store-pending) 0.75)) {
            (setq control-store-pending nil)
            (ext-facfg-store)
        })
        (sleep 0.5)
    })
)

; Wire order of the settings string for the QML page. This matches the
; original package's eeprom layout order (token index = position + 1), so
; the original UI keeps working unchanged. magic/crc and the removed
; legacy params are constant placeholder slots.
(def qml-config-params '(
    (magic i) (crc i) (can-id i) (accept-tos b) (led-enabled b) (bms-enabled b)
    (pubmote-enabled b) (led-on b) (led-highbeam-on b) (led-mode i)
    (led-mode-idle i) (led-mode-status i) (led-mode-startup i)
    (led-mode-button i) (led-mode-footpad i) (led-mall-grab-enabled b)
    (led-brake-light-enabled b) (led-brake-light-min-amps f) (idle-timeout i)
    (idle-timeout-shutoff i) (led-brightness f) (led-brightness-highbeam f)
    (led-brightness-idle f) (led-brightness-status f) (led-status-pin i)
    (led-status-num i) (led-status-type i) (led-status-reversed b)
    (led-front-pin i) (led-front-num i) (led-front-type i)
    (led-front-reversed b) (led-front-timing i) (led-rear-pin i)
    (led-rear-num i) (led-rear-type i) (led-rear-reversed b)
    (led-rear-timing i) (led-button-pin b) (led-button-timing i)
    (led-footpad-pin i) (led-footpad-num i) (led-footpad-type i)
    (led-footpad-reversed b) (led-footpad-timing i)
    (pubmote-remote-mac-a i) (pubmote-remote-mac-b i) (pubmote-secret-code i)
    (bms-rs485-di-pin i) (bms-rs485-ro-pin i) (bms-rs485-dere-pin i)
    (bms-wakeup-pin i) (bms-override-soc i) (bms-rs485-chip b)
    (bms-key-a i) (bms-key-b i) (bms-key-c i) (bms-key-d i)
    (bms-counter-a i) (bms-counter-b i) (bms-counter-c i) (bms-counter-d i)
    (led-loop-delay i) (bms-loop-delay i) (pubmote-loop-delay i)
    (can-loop-delay i) (led-startup-timeout i)
    (led-dim-on-highbeam-ratio f) (bms-type i) (led-status-timing i)
    (bms-charge-only b) (led-show-battery-charging b)
    (led-front-highbeam-pin i) (led-rear-highbeam-pin i) (bms-buff-size i)
    (led-max-brightness f) (soc-type i) (cell-type i)
    (led-update-not-running b) (log-enabled b) (log-rate f)
    (log-append-gnss b) (humidity-enabled b) (humidity-sda-pin i)
    (humidity-slc-pin i)
    (led-front-highbeam-mode i) (led-front-highbeam-pos i)
    (led-front-highbeam-min f) (led-front-highbeam-max f)
    (led-rear-highbeam-mode i) (led-rear-highbeam-pos i)
    (led-rear-highbeam-min f) (led-rear-highbeam-max f)
    (gnss-enabled b) (gnss-type i) (gnss-rx-pin i) (gnss-tx-pin i)
    (gnss-uart-num i) (gnss-rate-ms i) (gnss-baud i)
))

(defun send-config () {
    ; One join instead of a str-merge accumulator, which would copy a
    ; growing ~1.5 KB string once per parameter.
    (send-data (str-join (cons "settings" (map (fn (p) {
        (var name (first p))
        (var value (cond
            ((eq name 'magic) 445)
            ((eq name 'crc) 0)
            (t (get-config name))
        ))
        (if (eq (second p) 'f)
            (str-from-n (to-float value) "%.2f")
            (str-from-n (to-i value) "%d")
        )
    }) qml-config-params)) " "))
    (send-mqtt-cfg)
    (send-status "Settings loaded")
})

; MQTT config round-trip for the QML page. The numeric fields ride a normal
; space-split line; each string is sent on its own line so a value with
; spaces survives (the QML side takes everything after the tag as the value).
(defun send-mqtt-cfg () {
    (send-data (str-join (list "mqtt-cfg"
        (str-from-n (to-i (get-config 'mqtt-enabled)) "%d")
        (str-from-n (to-i (get-config 'mqtt-qos)) "%d")
        (str-from-n (to-i (get-config 'mqtt-keepalive)) "%d")
        (str-from-n (to-i (get-config 'mqtt-publish-rate)) "%d")) " "))
    (send-data (str-merge "mqtt-uri " (get-config 'mqtt-broker-uri)))
    (send-data (str-merge "mqtt-cid " (get-config 'mqtt-client-id)))
    (send-data (str-merge "mqtt-user " (get-config 'mqtt-user)))
    (send-data (str-merge "mqtt-pass " (get-config 'mqtt-password)))
    (send-data (str-merge "mqtt-prefix " (get-config 'mqtt-topic-prefix)))
})

; Saved from the QML MQTT page. Strings arrive as quoted lisp strings via the
; (eval (read ...)) command path, so spaces in them are safe here.
(defun recv-mqtt-cfg (in-enabled in-qos in-keepalive in-rate in-uri in-cid in-user in-pass in-prefix) {
    (set-config 'mqtt-enabled (to-i in-enabled))
    (set-config 'mqtt-qos (to-i in-qos))
    (set-config 'mqtt-keepalive (to-i in-keepalive))
    (set-config 'mqtt-publish-rate (to-i in-rate))
    (set-config 'mqtt-broker-uri in-uri)
    (set-config 'mqtt-client-id in-cid)
    (set-config 'mqtt-user in-user)
    (set-config 'mqtt-password in-pass)
    (set-config 'mqtt-topic-prefix in-prefix)
    (ext-facfg-store)
    (apply-config)
    (send-mqtt-cfg)
})

; Full settings write from the QML settings page. Same signature as the
; original package minus the removed legacy params (blend count, led
; fix).
(defun recv-config (in-led-enabled in-bms-enabled in-pubmote-enabled in-led-on in-led-highbeam-on in-led-mode in-led-mode-idle in-led-mode-status
    in-led-mode-startup in-led-mode-button in-led-mode-footpad in-led-mall-grab-enabled in-led-brake-light-enabled in-led-brake-light-min-amps
    in-idle-timeout in-idle-timeout-shutoff in-led-brightness in-led-brightness-highbeam in-led-brightness-idle in-led-brightness-status
    in-led-status-pin in-led-status-num in-led-status-type in-led-status-reversed in-led-front-pin in-led-front-num in-led-front-type
    in-led-front-reversed in-led-front-timing in-led-rear-pin in-led-rear-num in-led-rear-type in-led-rear-reversed in-led-rear-timing
    in-led-button-pin in-led-button-timing in-led-footpad-pin in-led-footpad-num in-led-footpad-type in-led-footpad-reversed
    in-led-footpad-timing in-bms-rs485-di-pin in-bms-rs485-ro-pin in-bms-rs485-dere-pin in-bms-wakeup-pin in-bms-override-soc in-bms-rs485-chip
    in-led-loop-delay in-bms-loop-delay in-pubmote-loop-delay in-can-loop-delay in-led-startup-timeout
    in-led-dim-on-highbeam-ratio in-bms-type in-led-status-timing in-bms-charge-only in-led-show-battery-charging
    in-led-front-highbeam-pin in-led-rear-highbeam-pin in-bms-buff-size in-led-max-brightness in-soc-type in-cell-type in-led-update-not-running
    in-log-enabled in-log-rate in-log-append-gnss in-humidity-enabled in-humidity-sda-pin in-humidity-slc-pin
    in-led-front-highbeam-mode in-led-front-highbeam-pos in-led-front-highbeam-min in-led-front-highbeam-max
    in-led-rear-highbeam-mode in-led-rear-highbeam-pos in-led-rear-highbeam-min in-led-rear-highbeam-max
    in-gnss-enabled in-gnss-type in-gnss-rx-pin in-gnss-tx-pin in-gnss-uart-num in-gnss-rate-ms in-gnss-baud
) {
    (set-config 'led-enabled (to-i in-led-enabled))
    (set-config 'bms-enabled (to-i in-bms-enabled))
    (set-config 'pubmote-enabled (to-i in-pubmote-enabled))

    (if (or (!= (to-i soc-type) (to-i in-soc-type)) (!= (to-i cell-type) (to-i in-cell-type))) {
        (apply-battery-config in-soc-type in-cell-type)
    })

    (set-config 'led-on (to-i in-led-on))
    (set-config 'led-highbeam-on (to-i in-led-highbeam-on))
    (set-config 'led-mode (to-i in-led-mode))
    (set-config 'led-mode-idle (to-i in-led-mode-idle))
    (set-config 'led-mode-status (to-i in-led-mode-status))
    (set-config 'led-mode-startup (to-i in-led-mode-startup))
    (set-config 'led-mode-button (to-i in-led-mode-button))
    (set-config 'led-mode-footpad (to-i in-led-mode-footpad))
    (set-config 'led-mall-grab-enabled (to-i in-led-mall-grab-enabled))
    (set-config 'led-brake-light-enabled (to-i in-led-brake-light-enabled))
    (set-config 'led-brake-light-min-amps (to-float in-led-brake-light-min-amps))
    (set-config 'idle-timeout (to-i in-idle-timeout))
    (set-config 'idle-timeout-shutoff (to-i in-idle-timeout-shutoff))
    (set-config 'led-brightness (to-float in-led-brightness))
    (set-config 'led-brightness-highbeam (to-float in-led-brightness-highbeam))
    (set-config 'led-brightness-idle (to-float in-led-brightness-idle))
    (set-config 'led-brightness-status (to-float in-led-brightness-status))

    (set-config 'led-status-pin (to-i in-led-status-pin))
    (set-config 'led-status-num (to-i in-led-status-num))
    (set-config 'led-status-type (to-i in-led-status-type))
    (set-config 'led-status-reversed (to-i in-led-status-reversed))
    (set-config 'led-status-timing (to-i in-led-status-timing))

    (set-config 'led-front-pin (to-i in-led-front-pin))
    (set-config 'led-front-num (to-i in-led-front-num))
    (set-config 'led-front-type (to-i in-led-front-type))
    (set-config 'led-front-reversed (to-i in-led-front-reversed))
    (set-config 'led-front-timing (to-i in-led-front-timing))
    (set-config 'led-front-highbeam-mode (to-i in-led-front-highbeam-mode))
    (set-config 'led-front-highbeam-pin (to-i in-led-front-highbeam-pin))
    (set-config 'led-front-highbeam-pos (to-i in-led-front-highbeam-pos))
    (set-config 'led-front-highbeam-min (to-float in-led-front-highbeam-min))
    (set-config 'led-front-highbeam-max (to-float in-led-front-highbeam-max))

    (set-config 'led-rear-pin (to-i in-led-rear-pin))
    (set-config 'led-rear-num (to-i in-led-rear-num))
    (set-config 'led-rear-type (to-i in-led-rear-type))
    (set-config 'led-rear-reversed (to-i in-led-rear-reversed))
    (set-config 'led-rear-timing (to-i in-led-rear-timing))
    (set-config 'led-rear-highbeam-mode (to-i in-led-rear-highbeam-mode))
    (set-config 'led-rear-highbeam-pin (to-i in-led-rear-highbeam-pin))
    (set-config 'led-rear-highbeam-pos (to-i in-led-rear-highbeam-pos))
    (set-config 'led-rear-highbeam-min (to-float in-led-rear-highbeam-min))
    (set-config 'led-rear-highbeam-max (to-float in-led-rear-highbeam-max))

    (set-config 'led-button-pin (to-i in-led-button-pin))
    (set-config 'led-button-timing (to-i in-led-button-timing))

    (set-config 'led-footpad-pin (to-i in-led-footpad-pin))
    (set-config 'led-footpad-num (to-i in-led-footpad-num))
    (set-config 'led-footpad-type (to-i in-led-footpad-type))
    (set-config 'led-footpad-reversed (to-i in-led-footpad-reversed))
    (set-config 'led-footpad-timing (to-i in-led-footpad-timing))

    (set-config 'bms-rs485-di-pin (to-i in-bms-rs485-di-pin))
    (set-config 'bms-rs485-ro-pin (to-i in-bms-rs485-ro-pin))
    (set-config 'bms-rs485-dere-pin (to-i in-bms-rs485-dere-pin))
    (set-config 'bms-wakeup-pin (to-i in-bms-wakeup-pin))
    (set-config 'bms-override-soc (to-i in-bms-override-soc))
    (set-config 'bms-rs485-chip (to-i in-bms-rs485-chip))

    (set-config 'led-loop-delay (to-i in-led-loop-delay))
    (set-config 'bms-loop-delay (to-i in-bms-loop-delay))
    (set-config 'pubmote-loop-delay (to-i in-pubmote-loop-delay))
    (set-config 'can-loop-delay (to-i in-can-loop-delay))
    (set-config 'led-startup-timeout (to-i in-led-startup-timeout))
    (set-config 'led-dim-on-highbeam-ratio (to-float in-led-dim-on-highbeam-ratio))

    (set-config 'bms-type (to-i in-bms-type))
    (set-config 'bms-charge-only (to-i in-bms-charge-only))
    (set-config 'led-show-battery-charging (to-i in-led-show-battery-charging))
    (set-config 'bms-buff-size (to-i in-bms-buff-size))
    (set-config 'led-max-brightness (to-float in-led-max-brightness))
    (set-config 'soc-type (to-i in-soc-type))
    (set-config 'cell-type (to-i in-cell-type))
    (set-config 'led-update-not-running (to-i in-led-update-not-running))

    (set-config 'log-enabled (to-i in-log-enabled))
    (set-config 'log-rate (to-float in-log-rate))
    (set-config 'log-append-gnss (to-i in-log-append-gnss))
    (set-config 'humidity-enabled (to-i in-humidity-enabled))
    (set-config 'humidity-sda-pin (to-i in-humidity-sda-pin))
    (set-config 'humidity-slc-pin (to-i in-humidity-slc-pin))

    (set-config 'gnss-enabled (to-i in-gnss-enabled))
    (set-config 'gnss-type (to-i in-gnss-type))
    (set-config 'gnss-rx-pin (to-i in-gnss-rx-pin))
    (set-config 'gnss-tx-pin (to-i in-gnss-tx-pin))
    (set-config 'gnss-uart-num (to-i in-gnss-uart-num))
    (set-config 'gnss-rate-ms (to-i in-gnss-rate-ms))
    (set-config 'gnss-baud (to-i in-gnss-baud))

    (ext-facfg-store)
    (apply-config)
    (send-config)
})

; Quick controls from the QML page (brightness / on-off), persisted.
(defun recv-control (in-led-on in-led-highbeam-on in-led-brightness in-led-brightness-highbeam in-led-brightness-idle in-led-brightness-status in-bms-charge-state) {
    (setq led-on (to-i in-led-on))
    (setq led-highbeam-on (to-i in-led-highbeam-on))
    (setq led-brightness (to-float in-led-brightness))
    (setq led-brightness-highbeam (to-float in-led-brightness-highbeam))
    (setq led-brightness-idle (to-float in-led-brightness-idle))
    (setq led-brightness-status (to-float in-led-brightness-status))

    (set-config 'led-on (to-i in-led-on))
    (set-config 'led-highbeam-on (to-i in-led-highbeam-on))
    (set-config 'led-brightness (to-float in-led-brightness))
    (set-config 'led-brightness-highbeam (to-float in-led-brightness-highbeam))
    (set-config 'led-brightness-idle (to-float in-led-brightness-idle))
    (set-config 'led-brightness-status (to-float in-led-brightness-status))
    ; Applied to RAM above; the LED loop picks it up on its next tick. Persist
    ; is deferred/debounced (config-watch-loop) so dragging a slider doesn't
    ; store the whole config to NVS on every sample - that was the lag.
    (setq control-store-pending (systime))

    (if (and (= (get-config 'bms-enabled) 1) (> bms-type 1) (!= bms-charge-state in-bms-charge-state) ) {
        (setq bms-charge-state (if (= bms-charge-state 1) 1 0))
        (setq bms-user-cmd 0x64)
    })
})

(defun bms-trigger-factory-init () {
    (if (and (= (get-config 'bms-enabled) 1) (> bms-type 1) (= bms-rs485-chip 1) ) {
        (setq bms-user-cmd 0x0e)
    })
})

(defun send-control () {
    (var config-string "control ")

    (setq config-string (
        str-merge
        config-string
        (str-from-n (to-i led-on) "%d ")
        (str-from-n (to-i led-highbeam-on) "%d ")
        (str-from-n led-brightness "%.2f ")
        (str-from-n led-brightness-highbeam "%.2f ")
        (str-from-n led-brightness-idle "%.2f ")
        (str-from-n led-brightness-status "%.2f ")
        (str-from-n (to-i bms-charge-state) "%d ")
    ))

    (send-data config-string)
})

(defun send-keys (key-list counter-list) {
    (print "Received key: ")
    (print key-list)
    (setq key-list (split-list key-list 4))
    (set-config 'bms-key-a (pack-bytes-to-uint32 (ix key-list 0)))
    (set-config 'bms-key-b (pack-bytes-to-uint32 (ix key-list 1)))
    (set-config 'bms-key-c (pack-bytes-to-uint32 (ix key-list 2)))
    (set-config 'bms-key-d (pack-bytes-to-uint32 (ix key-list 3)))
    (print "Received counter: ")
    (print counter-list)
    (setq counter-list (split-list counter-list 4))
    (set-config 'bms-counter-a (pack-bytes-to-uint32 (ix counter-list 0)))
    (set-config 'bms-counter-b (pack-bytes-to-uint32 (ix counter-list 1)))
    (set-config 'bms-counter-c (pack-bytes-to-uint32 (ix counter-list 2)))
    (set-config 'bms-counter-d (pack-bytes-to-uint32 (ix counter-list 3)))
    (save-config)
})

(defun accept-tos() {
    (set-config 'accept-tos 1)
    (ext-facfg-store)
})

(defun status () {
    ; Built as a list and joined once: accumulating with str-merge copies
    ; the growing string on every step, which at the QML poll rate was the
    ; main source of lbm memory churn between GC cycles.
    ;
    ; GNSS: fix flag, seconds since the last sentence, hdop, speed (m/s).
    ; The firmware stamps the age on every decoded sentence (fix or not),
    ; so a fix additionally needs a non-zero position.
    (var gnss-ll (gnss-lat-lon))
    (var gnss-age-s (gnss-age))
    (var gnss-fix (if (and (< gnss-age-s 5.0) (or (!= (ix gnss-ll 0) 0.0) (!= (ix gnss-ll 1) 0.0))) 1 0))
    (send-data (str-join (list
        "float-stats"
        (str-from-n (if (< (secs-since can-last-activity-time) 1) 1 0) "%d")
        (str-from-n (is-pubmote-connected) "%d")
        (str-from-n (if (< (secs-since bms-last-activity-time) 1) 1 0) "%d")
        (str-from-n bms-status "%d")
        (str-from-n bms-battery-type "%d")
        (str-from-n bms-battery-cycles "%d")
        (str-from-n (if (> (conf-get 'wifi-mode) 0) (wifi-get-chan) -1) "%d")
        (str-from-n hum "%.0f")
        (str-from-n hum-temp "%.2f")
        (str-from-n (get-bms-val 'bms-hum) "%.0f")
        (str-from-n (get-bms-val 'bms-temp-hum) "%.0f")
        (str-from-n (if log-running 1 0) "%d")
        (str-from-n gnss-fix "%d")
        (str-from-n (to-float (min gnss-age-s 9999.0)) "%.1f")
        (str-from-n (gnss-hdop) "%.1f")
        (str-from-n (gnss-speed) "%.2f")
    ) " "))

    (if (= (is-pubmote-connected) 1) {
        (send-data (str-merge "pubmote-info " (to-str (ix pubmote-version 0)) "." (to-str (ix pubmote-version 1)) "." (to-str (ix pubmote-version 2))))
    })
})

(defun input-state () {
    (send-data (str-join (list
        "input-state"
        (str-from-n (is-pubmote-connected) "%d")
        (str-from-n pubmote-last-jsy "%.3f")
        (str-from-n pubmote-last-jsx "%.3f")
        (str-from-n pubmote-last-bt-c "%d")
        (str-from-n pubmote-last-bt-z "%d")
        (str-from-n pubmote-last-is-rev "%d")
    ) " "))
})

@const-end
