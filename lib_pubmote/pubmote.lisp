;@const-symbol-strings
@const-start

; Pubmote: ESP-NOW / BLE tilt-remote link for the VESC Express.
;
; The library is host-agnostic: everything package-specific (where the
; config lives, what telemetry to send, what to do with control input)
; is injected through setup-pubmote callbacks. The host owns the event
; loop and routes packets in:
;
;   (setup-pubmote vehicle-type on-control get-telemetry send-msg
;                  get-cfg set-cfg save-cfg on-pairing-state)
;   (spawn pubmote-loop)
;   ; from the host's event handler:
;   ;   event-esp-now-rx  -> (pubmote-rx src des data rssi)
;   ;   custom app data starting with PUBMOTE_MAGIC -> (pubmote-ble-rx data)
;
; get-cfg/set-cfg/save-cfg persist these keys, whatever the storage is:
;   'pubmote-enabled 'pubmote-loop-delay 'pubmote-secret-code
;   'pubmote-remote-mac-a 'pubmote-remote-mac-b
;
; Pairing is driven with (pair-pubmote code) - code >= 0 starts pairing
; with that secret, -1 accepts, -2 rejects/aborts. on-pairing-state gets
; called with the PAIR_STATE_* value on every change.

; Pairing states
(def PAIR_STATE_IDLE 0)
(def PAIR_STATE_INITIATED 1)
(def PAIR_STATE_BONDING 2)

; Vehicle types reported to the remote
(def VEHICLE_TYPE_UNSPECIFIED 0)
(def VEHICLE_TYPE_ONEWHEEL 1)
(def VEHICLE_TYPE_ESKATE 2)
(def VEHICLE_TYPE_SCOOTER 3)
(def VEHICLE_TYPE_EUC 4)

; Protocol commands
(def REM_VERSION 0)
(def REM_VERSION_REC 5)
(def REM_PAIR_INIT 10)
(def REM_PAIR_BOND 11)
(def REM_PAIR_COMPLETE 12)
(def REM_SET_CORE_DATA 100)
(def REM_SET_INPUT_STATE 150)
(def PUBMOTE_MAGIC 169)

; State
(def pubmote-loop-delay)  ; Loop rate in Hz, read from the config
(def pairing-state PAIR_STATE_IDLE)
(def pubmote-exit-flag nil)
(def pubmote-send-pair-complete-retries 0)
(def pubmote-pair-complete-status 0)
(def pubmote-last-pairing-broadcast 0)
(def pubmote-last-activity-time (systime))
(def wifi-enabled-on-boot nil)
(def pubmote-remote-mac '())
(def pubmote-ble-paired nil)
(def pubmote-pairing-timer 31)
(def pubmote-pairing-timer-timeout 60) ; How many seconds to wait before aborting pairing
(def uni-mac '(255 255 255 255 255 255)) ; Universal mac (all devices)
(def channel-locked 0)
(def channel-locked-timeout 10) ; How many seconds of no activity to wait before unlocking locked wifi channel
(def pubmote-version '(0 0 0))
(def pubmote-api-version 1)
(def pubmote-vehicle-type VEHICLE_TYPE_UNSPECIFIED)

; Host callbacks, injected by setup-pubmote
(def pubmote-on-control nil)
(def pubmote-get-telemetry nil)
(def pubmote-send-msg-cb nil)
(def pubmote-get-config nil)
(def pubmote-set-config nil)
(def pubmote-save-config nil)
(def pubmote-on-pairing-state nil)

(def last-log-time-telemetry-tx 0)
(def last-log-time-telemetry-rx 0)

(defun setup-pubmote (vehicle-type on-control get-telemetry send-msg-cb get-cfg-cb set-cfg-cb save-cfg-cb on-pairing-state) {
    (setq pubmote-vehicle-type vehicle-type)
    (setq pubmote-on-control on-control)
    (setq pubmote-get-telemetry get-telemetry)
    (setq pubmote-send-msg-cb send-msg-cb)
    (setq pubmote-get-config get-cfg-cb)
    (setq pubmote-set-config set-cfg-cb)
    (setq pubmote-save-config save-cfg-cb)
    (setq pubmote-on-pairing-state on-pairing-state)
})

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
    (setq channel-locked (wifi-get-chan))
    (wifi-disconnect)
    (wifi-auto-reconnect nil)
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
            (esp-now-send dest-mac send-buf)
        })
    })
    (free send-buf)
})

(defun set-pairing-state (new-state) {
    (setq pairing-state new-state)
    (if (not-eq pubmote-on-pairing-state nil) {
        (pubmote-on-pairing-state new-state)
    })
})

; ---- Connection state ----------------------------------------------------

; 1 while packets from the paired remote arrived within the last second
(defun pubmote-connected () {
    (if (< (secs-since pubmote-last-activity-time) 1) 1 0)
})

; ---- Lifecycle -----------------------------------------------------------

(defunret init-pubmote () {
    ; Running without the host callbacks would read nil config values and
    ; blow up in the MAC unpacking - refuse instead.
    (if (eq pubmote-get-config nil) {
        (pubmote-send-msg "Pubmote: setup-pubmote must be called first")
        (return nil)
    })
    (setq wifi-enabled-on-boot (> (conf-get 'wifi-mode) 0))
    (setq pubmote-remote-mac (append (pubmote-unpack-u32 (pubmote-get-cfg 'pubmote-remote-mac-a)) (take (pubmote-unpack-u32 (pubmote-get-cfg 'pubmote-remote-mac-b)) 2)))
    ; A remote paired over BLE is stored with the all-zeros placeholder MAC
    (setq pubmote-ble-paired (= (pubmote-get-cfg 'pubmote-remote-mac-a) 0))
    (if pubmote-ble-paired {
        (print "Pubmote BLE paired with remote")
    } {
        (print "Pubmote ESP-NOW paired with remote:" pubmote-remote-mac)
    })

    ; Read as bytes, convert to i so we can compare lists
    (loopfor i 0 (< i (length pubmote-remote-mac)) (+ i 1) {
        (setix pubmote-remote-mac i (to-i (ix pubmote-remote-mac i)))
    })

    (if (not wifi-enabled-on-boot) {
        (pubmote-send-msg "WiFi disabled. Pubmote running in BLE-only mode.")
    } {
        (esp-now-start)
        ; Skip the peer registration for BLE-paired remotes (placeholder MAC)
        (if (is-valid-espnow-mac pubmote-remote-mac) {
            (esp-now-del-peer pubmote-remote-mac)
            (esp-now-add-peer pubmote-remote-mac)
        })
        (esp-now-del-peer uni-mac)
        (esp-now-add-peer uni-mac)
    })
    (return true)
})

(defunret pair-pubmote (pairing) {
    (cond
        ((>= pairing 0) {
            (pubmote-set-cfg 'pubmote-secret-code (to-i32 pairing))
            (setq pubmote-pairing-timer (systime))
            (set-pairing-state PAIR_STATE_INITIATED)
        })

        ; Pairing accepted
        ((= pairing -1) {
            (if (= (length pubmote-remote-mac) 6) {
                (pubmote-set-cfg 'pubmote-remote-mac-a (pubmote-pack-u32 (take pubmote-remote-mac 4)))
                (pubmote-set-cfg 'pubmote-remote-mac-b (pubmote-pack-u32 (append (drop pubmote-remote-mac 4) '(0 0))))
            })
            (pubmote-save-cfg)
            (init-pubmote)
            (setq pubmote-pair-complete-status 1)
            (setq pubmote-send-pair-complete-retries 3)
            (set-pairing-state PAIR_STATE_IDLE)
        })

        ; Pairing rejected
        ((= pairing -2) {
            (pubmote-set-cfg 'pubmote-remote-mac-a -1)
            (pubmote-save-cfg)

            (setq pubmote-pair-complete-status 0)
            (setq pubmote-send-pair-complete-retries 3)

            (set-pairing-state PAIR_STATE_IDLE)

            ; Unlock wifi channel hopping
            (should-unlock-channel pubmote-last-activity-time)
        })
    )

    (return true)
})

(defun pubmote-loop () {
    (if (init-pubmote) {
        (setq pubmote-loop-delay (pubmote-get-cfg 'pubmote-loop-delay))
        ; A zero/negative configured rate would divide-by-zero below and put
        ; the loop into a crash-restart cycle
        (if (< pubmote-loop-delay 1) {
            (setq pubmote-loop-delay 20)
        })
        (var next-run-time (secs-since 0))
        (var loop-start-time 0)
        (var loop-end-time 0)
        (var pubmote-loop-delay-sec (/ 1.0 pubmote-loop-delay))
        (var data (bufcreate 33))

        (loopwhile t {
                (if (pubmote-get-cfg 'pubmote-enabled) {
                ; Check last pubmote activity
                (should-unlock-channel pubmote-last-activity-time)

                (setq loop-start-time  (secs-since 0))

                ; Escape as needed
                (if pubmote-exit-flag {
                    (break)
                })

                ; Send pair complete packets asynchronously without blocking QML
                (if (> pubmote-send-pair-complete-retries 0) {
                    (var tmpbuf (bufcreate 2))
                    (bufset-u8 tmpbuf 0 REM_PAIR_COMPLETE)
                    (bufset-u8 tmpbuf 1 pubmote-pair-complete-status)
                    (print "Sending pairing complete message to:" pubmote-remote-mac)
                    (pubmote-send-packet pubmote-remote-mac tmpbuf nil)
                    (if (connected-ble) {
                        (pubmote-send-packet '() tmpbuf t)
                    })
                    (free tmpbuf)
                    (setq pubmote-send-pair-complete-retries (- pubmote-send-pair-complete-retries 1))

                    (if (= pubmote-send-pair-complete-retries 0) {
                        ; Only wipe the MAC if no new pairing handshake has
                        ; started in the meantime (the deferred wipe must not
                        ; clobber a fresh bond)
                        (if (and (= pubmote-pair-complete-status 0) (= pairing-state PAIR_STATE_IDLE)) {
                            (setq pubmote-remote-mac '())
                        })
                    })
                })

                ; Timeout pairing process after set time has passed
                (if (and (> (secs-since pubmote-pairing-timer) pubmote-pairing-timer-timeout) (>= pairing-state PAIR_STATE_INITIATED)) {
                    (pair-pubmote -2)
                })

                ; Pairing search
                (if (= pairing-state PAIR_STATE_INITIATED) {
                    ; Update last activity time for pairing duration
                    (setq pubmote-last-activity-time (systime))

                    (if (> (- (systime) pubmote-last-pairing-broadcast) 50) {
                        (setq pubmote-last-pairing-broadcast (systime))
                        (if (should-lock-channel) {
                            (lock-channel "Begin pairing")
                        })

                        (var pairing-data (bufcreate 8))

                        (bufset-u8 pairing-data 0 REM_PAIR_INIT)
                        (var local-mac (get-mac-addr))

                        (looprange i 0 6 {
                            (bufset-u8 pairing-data (+ i 1) (ix local-mac i))
                        })

                        ; Append our actual WiFi channel to prevent race condition with channel switching or channel bleed
                        ; send 0 there - BLE pairing ignores the byte
                        (bufset-u8 pairing-data 7 (if wifi-enabled-on-boot (wifi-get-chan) 0))

                        (pubmote-send-packet uni-mac pairing-data nil)
                        (if (connected-ble) {
                            (pubmote-send-packet '() pairing-data t)
                        })
                        (free pairing-data)
                    })
                })

                ; Bond in progress
                (if (= pairing-state PAIR_STATE_BONDING) {
                    ; Update last activity time for pairing duration
                    (setq pubmote-last-activity-time (systime))
                })

                ; Connected, send data
                (if (should-send-message) {
                    (bufset-u8 data 0 REM_SET_CORE_DATA)
                    (bufset-i32 data 1 (pubmote-get-cfg 'pubmote-secret-code))

                    (if (not-eq pubmote-get-telemetry nil) {
                        (serialize-telemetry data (pubmote-get-telemetry))
                    })

                    (if (> (- (systime) last-log-time-telemetry-tx) 2000) {
                        (setq last-log-time-telemetry-tx (systime))
                    })
                    ; Push telemetry on the transport the remote paired with.
                    ; Pushing over BLE (rather than only replying to input
                    ; packets) keeps the remote's connection state solid even
                    ; when a single packet is lost.
                    (if pubmote-ble-paired {
                        (if (connected-ble) {
                            (pubmote-send-packet '() data t)
                        })
                    } {
                        (pubmote-send-packet pubmote-remote-mac data nil)
                    })
                })

                (setq loop-end-time (secs-since 0))
                (var actual-loop-time (- loop-end-time loop-start-time))
                (var time-to-wait (- next-run-time (secs-since 0)))

                (if (> time-to-wait 0) {
                    (yield (* time-to-wait 1000000))
                }{
                    (setq next-run-time (secs-since 0))
                })

                (setq next-run-time (+ next-run-time pubmote-loop-delay-sec))
            })
        })

        (free data)
        (setq pubmote-exit-flag nil)
    })
})

; ---- Packet handling -----------------------------------------------------

(defun process-pubmote-packet (data is-ble) {
    (var cmd (bufget-u8 data 0))

    (cond
        ((= cmd REM_VERSION) {
            (if (= (buflen data) 8) {
                (reset-last-activity-time)
                (setq pubmote-version (list (bufget-u8 data 5) (bufget-u8 data 6) (bufget-u8 data 7)))
                (print (str-merge (if is-ble "Remote BLE version: " "Remote version: ") (to-str (ix pubmote-version 0)) "." (to-str (ix pubmote-version 1)) "." (to-str (ix pubmote-version 2))))
            })
        })

        ((= cmd REM_VERSION_REC) {
            (reset-last-activity-time)
            (var tmpbuf (bufcreate 8))
            (bufset-u8 tmpbuf 0 REM_VERSION_REC)
            (bufset-i32 tmpbuf 1 (pubmote-get-cfg 'pubmote-secret-code))
            (bufset-u16 tmpbuf 5 pubmote-api-version 'little-endian)
            (bufset-u8 tmpbuf 7 pubmote-vehicle-type)

            (pubmote-send-packet (if is-ble '() pubmote-remote-mac) tmpbuf is-ble)
            (free tmpbuf)
        })

        ((= cmd REM_SET_INPUT_STATE) {
            (if (> (- (systime) last-log-time-telemetry-rx) 2000) {
                (setq last-log-time-telemetry-rx (systime))
            })
            (if (= (buflen data) 17) {
                (reset-last-activity-time)

                (var jsy (bufget-f32 data 5 'little-endian))
                (var jsx (bufget-f32 data 9 'little-endian))
                (var bt-c (bufget-u8 data 13))
                (var bt-z (bufget-u8 data 14))
                (var is-rev (bufget-u8 data 15))

                (if (not-eq pubmote-on-control nil) {
                    (pubmote-on-control jsy jsx bt-c bt-z is-rev)
                })
            })
        })

        (t {
            (if (not is-ble) {
                (print (str-join (list "No command found: " (to-str cmd))))
            })
        })
    )
})

(defun pubmote-rx (src des data rssi) {
    (if (and (pubmote-get-cfg 'pubmote-enabled) wifi-enabled-on-boot) {
        ; Verify and strip PUBMOTE_MAGIC
        (if (and (> (buflen data) 1) (= (bufget-u8 data 0) PUBMOTE_MAGIC)) {
            (bufcpy data 0 data 1 (-(buflen data) 1))
            (buf-resize data -1)

            (var cmd (bufget-u8 data 0))
            (if (should-process-message src data) {
                ; Only lock the wifi channel for traffic from our paired
                ; remote (or during pairing below) - otherwise any device
                ; sending the magic byte could stall our wifi reconnection
                (if (should-lock-channel) {
                    ; Update last activity time in case it does not establish a connection
                    (setq pubmote-last-activity-time (systime))

                    (lock-channel "ESP-NOW packet received")
                })

                (process-pubmote-packet data nil)
            } {
                ; ESP-NOW specific pairing. Also re-respond while BONDING:
                ; the remote may have missed our first response (or retried
                ; pairing), and refusing to repeat it deadlocks the handshake
                ; until the pairing timeout expires.
                (if (= cmd REM_PAIR_BOND) {
                    (if (or (= pairing-state PAIR_STATE_INITIATED) (and (= pairing-state PAIR_STATE_BONDING) (eq pubmote-remote-mac src))) {
                        (setq pubmote-remote-mac src)
                        (esp-now-add-peer pubmote-remote-mac)
                        (var tmpbuf (bufcreate 5))
                        (bufset-u8 tmpbuf 0 REM_PAIR_BOND)
                        (bufset-i32 tmpbuf 1 (pubmote-get-cfg 'pubmote-secret-code))

                        (print "Responding with pairing code")
                        (pubmote-send-packet pubmote-remote-mac tmpbuf nil)
                        (free tmpbuf)
                        (esp-now-del-peer pubmote-remote-mac)

                        (set-pairing-state PAIR_STATE_BONDING)
                    })
                })
            })
        })
    })
})

(defun pubmote-ble-rx (data) {
    (if (pubmote-get-cfg 'pubmote-enabled) {
        ; Verify and strip PUBMOTE_MAGIC
        (if (and (> (buflen data) 1) (= (bufget-u8 data 0) PUBMOTE_MAGIC)) {
            (var payload-len (- (buflen data) 1))
            (var payload (bufcreate payload-len))
            (bufcpy payload 0 data 1 payload-len)

            (var cmd (bufget-u8 payload 0))
            ; BLE doesn't check src/mac, but we verify pairing-state and secret code
            (if (and (= pairing-state PAIR_STATE_IDLE) (>= payload-len 5) (= (bufget-i32 payload 1 'little-endian) (pubmote-get-cfg 'pubmote-secret-code))) {
                (process-pubmote-packet payload t)
            } {
                ; BLE pairing request
                (if (= cmd REM_PAIR_BOND) {
                    (print "pubmote-ble-rx: Received REM_PAIR_BOND")
                    ; Respond while INITIATED, or while BONDING if the bond in
                    ; progress is already a BLE one (all-zeros MAC): the remote
                    ; may have missed our first response, and refusing to
                    ; repeat it deadlocks the handshake until the pairing
                    ; timeout. The BONDING guard prevents a BLE request from
                    ; clobbering an in-progress ESP-NOW bond's MAC.
                    (if (or (= pairing-state PAIR_STATE_INITIATED) (and (= pairing-state PAIR_STATE_BONDING) (not (is-valid-espnow-mac pubmote-remote-mac)))) {
                        (setq pubmote-remote-mac '(0 0 0 0 0 0)) ; Initialize with dummy all-zeros MAC for BLE
                        (var tmpbuf (bufcreate 5))
                        (bufset-u8 tmpbuf 0 REM_PAIR_BOND)
                        (bufset-i32 tmpbuf 1 (pubmote-get-cfg 'pubmote-secret-code))

                        (print "pubmote-ble-rx: Responding with pairing code over BLE")
                        (pubmote-send-packet '() tmpbuf t)
                        (free tmpbuf)

                        (set-pairing-state PAIR_STATE_BONDING)
                    } {
                        (print "pubmote-ble-rx: Ignored REM_PAIR_BOND because pairing-state != PAIR_STATE_INITIATED")
                    })
                })
                ; No print for other unmatched packets: a secret-code mismatch
                ; (remote paired to a different board) arrives at input rate
                ; and would flood the console
            })
            (free payload)
        })
    })
})

@const-end
