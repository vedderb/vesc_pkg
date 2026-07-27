;@const-symbol-strings
@const-start

; Pubmote internal helpers.
; Depends on pubmote-consts.lisp and pubmote-vars.lisp.

; ---- Internal helpers ----------------------------------------------------

(defun pubmote-send-msg (text) {
    (if (not-eq pubmote-send-msg-cb nil) {
        (pubmote-send-msg-cb text)
    } {
        (print text)
    })
})

(defun pubmote-get-cfg (name) {
    (if (not-eq pubmote-get-config nil) {
        (pubmote-get-config name)
    })
})

(defun pubmote-set-cfg (name val) {
    (if (not-eq pubmote-set-config nil) {
        (pubmote-set-config name val)
    })
})

(defun pubmote-save-cfg () {
    (if (not-eq pubmote-save-config nil) {
        (pubmote-save-config)
    })
})

(defunret pubmote-pack-u32 (byte-list) {
  (return (to-u32 (+ (shl (to-u32 (ix byte-list 0)) 24)
                     (shl (to-u32 (ix byte-list 1)) 16)
                     (shl (to-u32 (ix byte-list 2)) 8)
                     (to-u32 (ix byte-list 3)))))
})
(defunret pubmote-unpack-u32 (packed-value) {
  (return (list (to-byte (bitwise-and (shr packed-value 24) 0xFF))
                (to-byte (shr (bitwise-and packed-value 0xFF0000) 16))
                (to-byte (shr (bitwise-and packed-value 0xFF00) 8))
                (to-byte (bitwise-and packed-value 0xFF))))
})

(defun serialize-telemetry (buf telemetry) {
    (bufset-u8 buf 5 (ix telemetry 0))       ; fault-code
    (bufset-i16 buf 6 (floor (* (ix telemetry 1) 10))) ; pitch-angle
    (bufset-i16 buf 8 (floor (* (ix telemetry 2) 10))) ; roll-angle
    (bufset-u8 buf 10 (ix telemetry 3))      ; state
    (bufset-u8 buf 11 (ix telemetry 4))      ; switch-state
    (bufset-i16 buf 12 (floor (* (ix telemetry 5) 10))) ; vin
    (bufset-i16 buf 14 (floor (ix telemetry 6)))     ; rpm
    (bufset-i16 buf 16 (floor (* (ix telemetry 7) 10))) ; speed
    (bufset-i16 buf 18 (floor (* (ix telemetry 8) 10))) ; tot-current
    (bufset-u8 buf 20 (floor (* (+ (abs (ix telemetry 9)) 0.5) 100))) ; duty-cycle-now
    (bufset-f32 buf 21 (ix telemetry 10) 'little-endian) ; distance-abs
    (bufset-u8 buf 25 (floor (* (ix telemetry 11) 2))) ; fet-temp-filtered
    (bufset-u8 buf 26 (floor (* (ix telemetry 12) 2))) ; motor-temp-filtered
    (bufset-u32 buf 27 (ix telemetry 13))    ; odometer
    (bufset-u8 buf 31 (floor (* (ix telemetry 14) 200))) ; battery-percent-remaining
})

(defun lock-channel (reason) {
    (print (str-merge "Channel switching disabled. Reason: " reason))
    (var ch (wifi-get-chan))
    (wifi-disconnect)
    (wifi-auto-reconnect nil)
    (wifi-set-chan ch)
    (setq channel-locked ch)
    (print (str-merge "Pinned to channel " (str-from-n ch)))
})

(defun unlock-channel (reason) {
    (print (str-merge "Channel switching enabled. Reason: " reason))
    (setq channel-locked 0)
    (wifi-auto-reconnect true)
    (wifi-connect (conf-get `wifi-sta-ssid) (conf-get `wifi-sta-key))
})

(defun is-station-mode () {
    (eq (conf-get 'wifi-mode) 1)
})

(defun is-wifi-connected () {
    (eq (wifi-status) 'connected)
})

(defun should-lock-channel () {
    ; Channel is not locked
    ; Station mode
    ; Wifi is not connected
    (and (eq channel-locked 0) (is-station-mode) (not (is-wifi-connected)))
})

(defun should-unlock-channel (last-activity-time) {
    ; Channel is locked
    ; Station mode
    ; Last activity time is not set or more than set time passed since last rx
    (if (and (> channel-locked 0) (is-station-mode) (> (secs-since last-activity-time) channel-locked-timeout)) {
        (unlock-channel (str-from-n pubmote-last-activity-time "Last activity time greater than set time"))
    })
})

(defun should-send-message () {
    (and
        (= pairing-state PAIR_STATE_IDLE)
        (!= (pubmote-get-cfg 'pubmote-remote-mac-a) -1)
        (< (secs-since pubmote-last-activity-time) 1.0)
    )
})

; Valid destination for esp-now-send: 6 bytes and not the BLE placeholder MAC
(defun is-valid-espnow-mac (mac) {
    (and (= (length mac) 6) (not-eq mac '(0 0 0 0 0 0)))
})

(defun should-process-message (src data) {
    ; Length check must come before bufget-i32: an out-of-range bufget raises
    ; an eval error which would kill the event handler thread
    (and (= pairing-state PAIR_STATE_IDLE) (>= (buflen data) 5) (eq pubmote-remote-mac src) (= (bufget-i32 data 1 'little-endian) (pubmote-get-cfg 'pubmote-secret-code)))
})

(defun reset-last-activity-time () {
    (setq pubmote-last-activity-time (systime))
})

(defun pubmote-send-packet (dest-mac packet-buf is-ble) {
    (var send-buf (bufcreate (+ (buflen packet-buf) 1)))
    (bufset-u8 send-buf 0 PUBMOTE_MAGIC)
    (bufcpy send-buf 1 packet-buf 0 (buflen packet-buf))

    (if is-ble {
        (send-data send-buf 8)
    } {
        ; Never attempt an ESP-NOW send to the BLE placeholder (all-zeros) MAC
        (if (and wifi-enabled-on-boot (is-valid-espnow-mac dest-mac)) {
            (mutex-lock pubmote-send-mutex)
            (trap (esp-now-send dest-mac send-buf))
            (mutex-unlock pubmote-send-mutex)
        })
    })
    (free send-buf)
})

@const-end
