; VESCXPRESS2X3Bridge -- runs on VESC Express. See README.md.

; ---- Pins (WROOM-1 V2.1+) ----
; Pin 7 (multipin) drives underglow only -- horn isn't implemented.

(define pin-indicator-right 4)
(define pin-indicator-left 5)
(define pin-rear-light 6)      ; PWM (LEDC)
(define pin-multipin 7)        ; underglow output

(define pwm-freq 5000)
(define pwm-channel 0)
(define pwm-bits 8)

(gpio-configure pin-indicator-right 'pin-mode-out)
(gpio-configure pin-indicator-left 'pin-mode-out)
(gpio-configure pin-multipin 'pin-mode-out)
(pwm-start pwm-freq 0.0 pwm-channel pin-rear-light pwm-bits)

; Vehicle constants, learned live from the VESC's registration message.
(define vesc-can-id 0)
(define motor-poles 30)
(define wheel-diam-mm 254)
(define battery-pct 100)
(define voltage-v 0.0)
(define motor-temp-c 0.0)

(define slot-vesc-info 0)
(define slot-speed-relay 1)
(define slot-vesc-register 2)

(define relay-targets (list))

(defun list-contains (lst val)
    (if (eq lst nil)
        nil
        (if (= (car lst) val)
            t
            (list-contains (cdr lst) val))))

(defun add-relay-target (id)
    (if (not (list-contains relay-targets id))
        (setq relay-targets (cons id relay-targets))))

(defun relay-speed-to-targets (targets buf)
    (if (not-eq targets nil)
        (progn
            (canmsg-send (car targets) slot-speed-relay buf)
            (relay-speed-to-targets (cdr targets) buf))))

; Express-side settings, eeprom-backed, editable via main-settings.qml.

(define ee-addr-sentinel 0)
(define ee-addr-disable-prof-sw 1)
(define ee-addr-freeze-batt-below-11 2)
(define ee-addr-bms-mode 3)
(define ee-addr-bypass-speed-limit-warning 4)
(define ee-addr-underglow-on-park 5)
(define ee-addr-enable-charge-light 6)
; Bump whenever a field is added, so old boards re-seed new defaults.
(define ee-settings-sentinel 0x5E78)

; eeprom-read-i returns nil (not 0) on a never-written address, so this
; must use not-eq (generic), not != (numeric-only, type-errors on nil).
(defun init-settings ()
    (if (not-eq (eeprom-read-i ee-addr-sentinel) ee-settings-sentinel)
        (progn
            (eeprom-store-i ee-addr-disable-prof-sw 0)
            (eeprom-store-i ee-addr-freeze-batt-below-11 0)
            (eeprom-store-i ee-addr-bms-mode 0)
            (eeprom-store-i ee-addr-bypass-speed-limit-warning 0)
            (eeprom-store-i ee-addr-underglow-on-park 0)
            (eeprom-store-i ee-addr-enable-charge-light 1)
            (eeprom-store-i ee-addr-sentinel ee-settings-sentinel))))

(init-settings)

(define disable-prof-sw (eeprom-read-i ee-addr-disable-prof-sw))
(define freeze-batt-below-11 (eeprom-read-i ee-addr-freeze-batt-below-11))
(define bms-mode (eeprom-read-i ee-addr-bms-mode))
(define bypass-speed-limit-warning (eeprom-read-i ee-addr-bypass-speed-limit-warning))
(define underglow-on-park (eeprom-read-i ee-addr-underglow-on-park))
(define enable-charge-light (eeprom-read-i ee-addr-enable-charge-light))

(define parkmode 0)

(define last-100-msg-time (systime))
(define dashboard-boot-gap-ms 2000)

(defun handle-park-state (data)
    (let ((now (systime))
          (mode-byte (bufget-u8 data 2)))
        (progn
            (if (and (> (- now last-100-msg-time) dashboard-boot-gap-ms) (= disable-prof-sw 0))
                (relay-speed-to-targets relay-targets (speed-relay-buf last-drive-mode-byte)))
            (setq last-100-msg-time now)
            (setq parkmode (if (or (= mode-byte 0x04) (= mode-byte 0x06)) 0 1)))))

(defun dispatch-sid (id data)
    (cond
        ((= id 0x20C) (progn (handle-lights data) (handle-drive-mode data)))
        ((= id 0x100) (handle-park-state data))
        (t nil)))

(defun event-loop ()
    (loopwhile t
        (recv
            ((event-can-sid . ((? id) . (? data))) (dispatch-sid id data))
            ((event-data-rx . (? data)) (handle-qml-data data))
            (_ nil))))

; ---- Lights (0x20C) ----

(define indicator-off 0)
(define indicator-left 1)
(define indicator-right 2)
(define indicator-hazard 3)

(define rear-off 0x10)
(define rear-charge-breathing 0x12)
(define rear-on 0x14)
(define rear-brake 0x16)
(define rear-flashing-brake 0x18)

(define last-indicator-byte indicator-off)
(define last-rear-byte rear-off)

; Two independent blink rates off one tick -- brake flash (~100ms) is
; faster than turn-signal blink (~300ms).
(define rear-blink-state 0)
(define indicator-blink-state 0)
(define blink-tick-count 0)

(defun apply-rear-light (rear-byte)
    (cond
        ((= rear-byte rear-on) (pwm-set-duty 0.5 pwm-channel))
        ((= rear-byte rear-brake) (pwm-set-duty 1.0 pwm-channel))
        ((= rear-byte rear-flashing-brake)
            (pwm-set-duty (if (= rear-blink-state 1) 1.0 0.0) pwm-channel))
        ((= rear-byte rear-charge-breathing)
            (pwm-set-duty (if (= enable-charge-light 1) 0.5 0.0) pwm-channel))
        (t (pwm-set-duty 0.0 pwm-channel))))

(defun apply-indicators (indicator-byte)
    (let ((left-active (or (= indicator-byte indicator-left) (= indicator-byte indicator-hazard)))
          (right-active (or (= indicator-byte indicator-right) (= indicator-byte indicator-hazard))))
        (progn
            (gpio-write pin-indicator-left (if (and left-active (= indicator-blink-state 1)) 1 0))
            (gpio-write pin-indicator-right (if (and right-active (= indicator-blink-state 1)) 1 0)))))

(defun apply-underglow ()
    (gpio-write pin-multipin (if (and (= underglow-on-park 1) (= parkmode 1) (= last-rear-byte rear-on)) 1 0)))

(defun handle-lights (data)
    (progn
        (setq last-indicator-byte (bufget-u8 data 0))
        (setq last-rear-byte (bufget-u8 data 1))
        (apply-indicators last-indicator-byte)
        (apply-rear-light last-rear-byte)))

(defun blink-timer ()
    (loopwhile t
        (progn
            (setq blink-tick-count (mod (+ blink-tick-count 1) 3))
            (setq rear-blink-state (- 1 rear-blink-state))
            (if (= blink-tick-count 0)
                (setq indicator-blink-state (- 1 indicator-blink-state)))
            (apply-indicators last-indicator-byte)
            (apply-rear-light last-rear-byte)
            (apply-underglow)
            (sleep 0.1))))

; ---- Profile-switch speed relay ----

(define last-drive-mode-byte 0)

(defun speed-relay-buf (drive-mode-byte)
    (let ((speed-x10 (to-i (* (/ drive-mode-byte 2.0) 10.0))))
        (let ((buf (bufcreate 2)))
            (progn
                (bufset-u8 buf 0 (bitwise-and speed-x10 255))
                (bufset-u8 buf 1 (bitwise-and (shr speed-x10 8) 255))
                buf))))

(defun handle-drive-mode (data)
    (let ((drive-mode-byte (bufget-u8 data 2)))
        (if (and (!= drive-mode-byte last-drive-mode-byte) (= disable-prof-sw 0))
            (progn
                (setq last-drive-mode-byte drive-mode-byte)
                (relay-speed-to-targets relay-targets (speed-relay-buf drive-mode-byte))))))

(defun send-current-speed-to (target-id)
    (if (= disable-prof-sw 0)
        (canmsg-send target-id slot-speed-relay (speed-relay-buf last-drive-mode-byte))))

; ---- Controller (MCU) status frame emulation ----
; Byte templates copied verbatim from the reference firmware; only
; specific bytes patched live.

(defun erpm-to-kmh (erpm)
    (let ((erpm-abs (if (< erpm 0.0) (- 0.0 erpm) erpm)))
        (let ((mech-rpm (/ erpm-abs (/ motor-poles 2.0)))
              (wheel-circum-m (* 3.14159 (/ (to-float wheel-diam-mm) 1000.0))))
            (* (/ mech-rpm 60.0) wheel-circum-m 3.6))))

(defun handle-vesc-info (data)
    (progn
        (setq vesc-can-id (bufget-u8 data 0))
        (setq motor-poles (bufget-u8 data 1))
        (setq wheel-diam-mm (bitwise-or (bufget-u8 data 2) (shl (bufget-u8 data 3) 8)))
        (setq battery-pct (bufget-u8 data 4))
        (if (>= (buflen data) 8)
            (progn
                (setq voltage-v (/ (bitwise-or (bufget-u8 data 5) (shl (bufget-u8 data 6) 8)) 10.0))
                (setq motor-temp-c (bufget-u8 data 7))))
        (add-relay-target vesc-can-id)
        (send-current-speed-to vesc-can-id)))

(defun handle-vesc-register (data)
    (let ((id (bufget-u8 data 0)))
        (progn
            (add-relay-target id)
            (send-current-speed-to id))))

(defun vesc-info-listener ()
    (loopwhile t
        (let ((data (canmsg-recv slot-vesc-info -1.0)))
            (if (not-eq data 'timeout) (handle-vesc-info data)))))

(defun vesc-register-listener ()
    (loopwhile t
        (let ((data (canmsg-recv slot-vesc-register -1.0)))
            (if (not-eq data 'timeout) (handle-vesc-register data)))))

(define buf-211 (bufcreate 8))
(bufset-u8 buf-211 0 0xE4) (bufset-u8 buf-211 1 0xE8) (bufset-u8 buf-211 2 0x2E)

(define buf-212 (bufcreate 8))
(bufset-u8 buf-212 0 0x48) (bufset-u8 buf-212 1 0x01) (bufset-u8 buf-212 7 0x59)

(define buf-341 (bufcreate 8))
(bufset-u8 buf-341 4 0x02)

(define buf-342 (bufcreate 8))
(define buf-343 (bufcreate 8))
(define buf-344 (bufcreate 8))

(define buf-401 (bufcreate 8))
(bufset-u8 buf-401 4 0x02)

(define buf-310 (bufcreate 8))
(bufset-u8 buf-310 0 0xF1) (bufset-u8 buf-310 1 0x0E) (bufset-u8 buf-310 2 0x08) (bufset-u8 buf-310 3 0x07)
(bufset-u8 buf-310 4 0x02) (bufset-u8 buf-310 5 0x01) (bufset-u8 buf-310 6 0x01) (bufset-u8 buf-310 7 0xC8)

(define buf-311 (bufcreate 8))
(bufset-u8 buf-311 0 0x39) (bufset-u8 buf-311 1 0x1E) (bufset-u8 buf-311 2 0x07) (bufset-u8 buf-311 3 0x3F)
(bufset-u8 buf-311 4 0x90) (bufset-u8 buf-311 5 0x01)

(define buf-420 (bufcreate 8))

(define buf-421 (bufcreate 8))
(bufset-u8 buf-421 0 0x39) (bufset-u8 buf-421 1 0x39) (bufset-u8 buf-421 2 0x39) (bufset-u8 buf-421 3 0x39)
(bufset-u8 buf-421 4 0xFB) (bufset-u8 buf-421 5 0x04) (bufset-u8 buf-421 6 0x64) (bufset-u8 buf-421 7 0x02)

(define buf-422 (bufcreate 8))
(bufset-u8 buf-422 2 0x20) (bufset-u8 buf-422 4 0x15) (bufset-u8 buf-422 6 0x02)

(define buf-423 (bufcreate 8))
(bufset-u8 buf-423 0 0x84) (bufset-u8 buf-423 1 0x03) (bufset-u8 buf-423 2 0x64)
(bufset-u8 buf-423 4 0x40) (bufset-u8 buf-423 5 0x01) (bufset-u8 buf-423 6 0x01)

(define buf-424 (bufcreate 8))   ; all-zero "BMS timer", unpatched in the reference too

(define buf-425 (bufcreate 8))
(bufset-u8 buf-425 0 0x01) (bufset-u8 buf-425 1 0x10) (bufset-u8 buf-425 2 0x48) (bufset-u8 buf-425 3 0x35)
(bufset-u8 buf-425 4 0x35) (bufset-u8 buf-425 5 0x35) (bufset-u8 buf-425 6 0x01) (bufset-u8 buf-425 7 0xFF)

(define buf-500 (bufcreate 8))
(bufset-u8 buf-500 0 0x47) (bufset-u8 buf-500 1 0x47) (bufset-u8 buf-500 2 0x48) (bufset-u8 buf-500 3 0xFF)
(bufset-u8 buf-500 4 0x47) (bufset-u8 buf-500 5 0x47) (bufset-u8 buf-500 6 0x47) (bufset-u8 buf-500 7 0xFF)

(define buf-501 (bufcreate 8))
(bufset-u8 buf-501 0 0xB4) (bufset-u8 buf-501 1 0xC1) (bufset-u8 buf-501 2 0x83) (bufset-u8 buf-501 3 0x58)
(bufset-u8 buf-501 4 0x31) (bufset-u8 buf-501 5 0xE5) (bufset-u8 buf-501 6 0xB2) (bufset-u8 buf-501 7 0x6B)

(define buf-502 (bufcreate 8))
(bufset-u8 buf-502 0 0x12) (bufset-u8 buf-502 1 0xBC) (bufset-u8 buf-502 2 0x86)
(bufset-u8 buf-502 3 0x0E) (bufset-u8 buf-502 4 0x1B) (bufset-u8 buf-502 5 0x36)

(define batt-freeze-threshold-pct 11)

(defun reported-battery-pct ()
    (if (and (= freeze-batt-below-11 1) (< battery-pct batt-freeze-threshold-pct))
        batt-freeze-threshold-pct
        battery-pct))

; (buffer id interval-ms is-bms) -- is-bms gates the whole BMS group
; together on bms-mode, see send-mcu-frame-if-due.
(define mcu-frames (list
    (list buf-310 0x310 200 1)
    (list buf-311 0x311 200 1)
    (list buf-420 0x420 500 1)
    (list buf-421 0x421 500 1)
    (list buf-422 0x422 500 1)
    (list buf-423 0x423 500 1)
    (list buf-424 0x424 1000 1)
    (list buf-425 0x425 500 1)
    (list buf-500 0x500 2000 1)
    (list buf-501 0x501 2000 1)
    (list buf-502 0x502 2000 1)
    (list buf-211 0x211 100 0)
    (list buf-212 0x212 100 0)
    (list buf-341 0x341 200 0)
    (list buf-342 0x342 200 0)
    (list buf-343 0x343 100 0)
    (list buf-344 0x344 200 0)
    (list buf-401 0x401 500 0)))

(define mcu-last-sent (list 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0))
(define mcu-frame-count 18)

; Polarity is intentionally inverted from the reference firmware, and the
; flash phase is deliberately stateless (recomputed every call, not
; tracked) -- an earlier stateful version got stuck flashing permanently
; on real hardware. Don't "fix" either.
(define speed-warn-trigger-ms 1000)
(define speed-warn-flash-ms 100)
(define speed-warn-period-ms (+ speed-warn-trigger-ms speed-warn-flash-ms))

(defun profile-limit-01kmh ()
    (* last-drive-mode-byte 5))   ; byte/2 km/h, in the same x10 units as real-speed-01kmh

(defun display-speed-01kmh (real-speed-01kmh)
    (if (or (= bypass-speed-limit-warning 0) (<= real-speed-01kmh (profile-limit-01kmh)))
        real-speed-01kmh
        (if (>= (mod (systime) speed-warn-period-ms) speed-warn-trigger-ms)
            10
            real-speed-01kmh)))

(defun patch-telemetry ()
    (let ((speed-kmh (erpm-to-kmh (canget-rpm vesc-can-id))))
        (let ((speed-01kmh (* (to-i (+ speed-kmh 0.5)) 10))
              (temp-byte (to-i (+ motor-temp-c 20.0))))
            (let ((display-01kmh (display-speed-01kmh speed-01kmh)))
                (progn
                    (bufset-u8 buf-211 6 (bitwise-and display-01kmh 255))
                    (bufset-u8 buf-211 7 (bitwise-and (shr display-01kmh 8) 255))
                    (bufset-u8 buf-212 4 (bitwise-and speed-01kmh 255))
                    (bufset-u8 buf-212 5 (bitwise-and (shr speed-01kmh 8) 255))
                    (bufset-u8 buf-212 7 (bitwise-and temp-byte 255)))))))

(defun patch-battery ()
    (let ((voltage-001v (to-i (* voltage-v 100.0)))
          (current-001a (to-i (* (canget-current vesc-can-id) 100.0)))
          (soc-01pct (to-i (* (reported-battery-pct) 10.0))))
        (progn
            (bufset-u8 buf-420 0 (bitwise-and voltage-001v 255))
            (bufset-u8 buf-420 1 (bitwise-and (shr voltage-001v 8) 255))
            (bufset-u8 buf-420 2 (bitwise-and current-001a 255))
            (bufset-u8 buf-420 3 (bitwise-and (shr current-001a 8) 255))
            (bufset-u8 buf-420 4 (bitwise-and soc-01pct 255))
            (bufset-u8 buf-420 5 (bitwise-and (shr soc-01pct 8) 255)))))

(defun send-mcu-frame-if-due (idx now)
    (let ((entry (ix mcu-frames idx))
          (last (ix mcu-last-sent idx)))
        (let ((buf (ix entry 0))
              (id (ix entry 1))
              (interval (ix entry 2))
              (is-bms (ix entry 3)))
            (if (and (>= (- now last) interval) (or (= is-bms 0) (= bms-mode 0)))
                (progn
                    (can-send-sid id buf)
                    (setix mcu-last-sent idx now))))))

(define qml-telemetry-interval 300)
(define qml-telemetry-last-sent 0)

(defun send-telemetry ()
    (let ((speed-kmh (erpm-to-kmh (canget-rpm vesc-can-id)))
          (current (canget-current vesc-can-id)))
        (let ((speed-x10 (to-i (* speed-kmh 10.0)))
              (voltage-x10 (to-i (* voltage-v 10.0)))
              (current-x10 (to-i (* current 10.0)))
              (buf (bufcreate 11)))
            (progn
                (bufset-u8 buf 0 0x03)
                (bufset-u8 buf 1 (bitwise-and speed-x10 255))
                (bufset-u8 buf 2 (bitwise-and (shr speed-x10 8) 255))
                (bufset-u8 buf 3 (bitwise-and (to-i motor-temp-c) 255))
                (bufset-u8 buf 4 (bitwise-and voltage-x10 255))
                (bufset-u8 buf 5 (bitwise-and (shr voltage-x10 8) 255))
                (bufset-u8 buf 6 (bitwise-and current-x10 255))
                (bufset-u8 buf 7 (bitwise-and (shr current-x10 8) 255))
                (bufset-u8 buf 8 last-indicator-byte)
                (bufset-u8 buf 9 last-rear-byte)
                (bufset-u8 buf 10 last-drive-mode-byte)
                (send-data buf)))))

(defun mcu-scheduler ()
    (loopwhile t
        (progn
            (patch-telemetry)
            (patch-battery)
            (var now (systime))
            (var i 0)
            (loopwhile (< i mcu-frame-count)
                (progn
                    (send-mcu-frame-if-due i now)
                    (setq i (+ i 1))))
            (if (>= (- now qml-telemetry-last-sent) qml-telemetry-interval)
                (progn
                    (send-telemetry)
                    (setq qml-telemetry-last-sent now)))
            (sleep 0.02))))

; QML settings channel -- send-data/event-data-rx here, sendCustomAppData/
; customAppDataReceived on the QML side.

(defun send-settings-reply ()
    (let ((buf (bufcreate 7)))
        (progn
            (bufset-u8 buf 0 0x01)
            (bufset-u8 buf 1 disable-prof-sw)
            (bufset-u8 buf 2 freeze-batt-below-11)
            (bufset-u8 buf 3 bms-mode)
            (bufset-u8 buf 4 bypass-speed-limit-warning)
            (bufset-u8 buf 5 underglow-on-park)
            (bufset-u8 buf 6 enable-charge-light)
            (send-data buf))))

(defun apply-settings-from-qml (data)
    (progn
        (setq disable-prof-sw (bufget-u8 data 1))
        (setq freeze-batt-below-11 (bufget-u8 data 2))
        (setq bms-mode (bufget-u8 data 3))
        (if (>= (buflen data) 5)
            (setq bypass-speed-limit-warning (bufget-u8 data 4)))
        (if (>= (buflen data) 7)
            (progn
                (setq underglow-on-park (bufget-u8 data 5))
                (setq enable-charge-light (bufget-u8 data 6))))
        (eeprom-store-i ee-addr-disable-prof-sw disable-prof-sw)
        (eeprom-store-i ee-addr-freeze-batt-below-11 freeze-batt-below-11)
        (eeprom-store-i ee-addr-bms-mode bms-mode)
        (eeprom-store-i ee-addr-bypass-speed-limit-warning bypass-speed-limit-warning)
        (eeprom-store-i ee-addr-underglow-on-park underglow-on-park)
        (eeprom-store-i ee-addr-enable-charge-light enable-charge-light)
        (send-settings-reply)))

(defun handle-qml-data (data)
    (let ((cmd (bufget-u8 data 0)))
        (cond
            ((= cmd 0x01) (send-settings-reply))
            ((= cmd 0x02) (apply-settings-from-qml data))
            (t nil))))

(event-register-handler (spawn event-loop))
(event-enable 'event-can-sid)
(event-enable 'event-data-rx)

(spawn blink-timer)
(spawn mcu-scheduler)
(spawn vesc-info-listener)
(spawn vesc-register-listener)
