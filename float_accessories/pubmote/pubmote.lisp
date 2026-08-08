;@const-symbol-strings
@const-start

; Pubmote: ESP-NOW / BLE tilt-remote link for the VESC Express.
;
; The library is host-agnostic: everything package-specific (where the
; config lives, what telemetry to send, what to do with control input)
; is injected through pubmote-setup callbacks. The host owns the event
; loop and routes packets in:
;
;   (pubmote-setup vehicle-type on-control get-telemetry send-msg
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


; Depends on pubmote-consts / -vars / -utils, loaded in that order.

(defun pubmote-setup (vehicle-type on-control get-telemetry send-msg-cb get-cfg-cb set-cfg-cb save-cfg-cb on-pairing-state) {
    (setq pubmote-vehicle-type vehicle-type)
    (setq pubmote-on-control on-control)
    (setq pubmote-get-telemetry get-telemetry)
    (setq pubmote-send-msg-cb send-msg-cb)
    (setq pubmote-get-config get-cfg-cb)
    (setq pubmote-set-config set-cfg-cb)
    (setq pubmote-save-config save-cfg-cb)
    (setq pubmote-on-pairing-state on-pairing-state)
})


(defun set-pairing-state (new-state) {
    ; Pairing is the single most support-heavy part of the remote, and the
    ; state transitions are otherwise invisible - always printed.
    (if (!= new-state pairing-state)
        (print (str-merge "Pubmote pair state " (str-from-n new-state "%d"))))
    (setq pairing-state new-state)
    (if (not-eq pubmote-on-pairing-state nil) {
        (pubmote-on-pairing-state new-state)
    })
})

; Connected / disconnected edge for the remote link.
(defun dbg-rem-transitions () {
    (var conn (pubmote-connected))
    (if (!= conn dbg-prev-rem-conn) {
        (setq dbg-prev-rem-conn conn)
        (dbg DBG-REM (if (= conn 1) "rem up" "rem down"))
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
        (pubmote-send-msg "Pubmote: pubmote-setup must be called first")
        (return nil)
    })
    (setq wifi-enabled-on-boot (> (conf-get 'wifi-mode) 0))
    (setq pubmote-remote-mac (append (pubmote-unpack-u32 (pubmote-get-cfg 'pubmote-remote-mac-a)) (take (pubmote-unpack-u32 (pubmote-get-cfg 'pubmote-remote-mac-b)) 2)))
    ; A remote paired over BLE is stored with the all-zeros placeholder MAC
    (setq pubmote-ble-paired (= (pubmote-get-cfg 'pubmote-remote-mac-a) 0))
    (if pubmote-ble-paired {
        (print "Pubmote BLE paired with remote")
    } {
        (print (str-merge "Pubmote ESP-NOW paired with " (to-str pubmote-remote-mac)))
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
                (print (str-merge "Pubmote paired " (to-str pubmote-remote-mac)))
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
            (dbg-warn "rem bad rate, using 20Hz")
            (setq pubmote-loop-delay 20)
        })
        (var next-run-time (secs-since 0))
        (var loop-start-time 0)
        (var loop-end-time 0)
        (var pubmote-loop-delay-sec (/ 1.0 pubmote-loop-delay))
        (var data (bufcreate 33))

        (loopwhile t {
                (if (pubmote-get-cfg 'pubmote-enabled) {
                (if (!= dbg-mask 0) (setq dbg-ticks-rem (+ dbg-ticks-rem 1)))
                ; Check last pubmote activity
                (should-unlock-channel pubmote-last-activity-time)
                (dbg-rem-transitions)

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
                    (dbg DBG-REM "rem pair complete tx")
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

                    (if (dbg-tick DBG-REM 'rem-tx 2.0) {
                        (setq last-log-time-telemetry-tx (systime))
                        (dbg DBG-REM (str-merge "rem tx, last rx "
                            (str-from-n (secs-since pubmote-last-activity-time) "%.2f")))
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
                (print (str-merge "Pubmote remote version " (to-str pubmote-version)))
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
            (if (dbg-tick DBG-REM 'rem-in 2.0) {
                (setq last-log-time-telemetry-rx (systime))
                (dbg DBG-REM "rem input rx")
            })
            (if (!= (buflen data) 17)
                (dbg DBG-REM (str-merge "rem bad input len " (str-from-n (buflen data) "%d"))))
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
            ; Gated: an unpaired remote nearby sends these at input rate and
            ; an ungated print floods the console.
            (if (and (not is-ble) (dbg-active DBG-REM))
                (dbg DBG-REM (str-merge "rem cmd ? " (to-str cmd))))
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
                        (print (str-merge "Pubmote bond req " (to-str src)))
                        (setq pubmote-remote-mac src)
                        (esp-now-add-peer pubmote-remote-mac)
                        (var tmpbuf (bufcreate 5))
                        (bufset-u8 tmpbuf 0 REM_PAIR_BOND)
                        (bufset-i32 tmpbuf 1 (pubmote-get-cfg 'pubmote-secret-code))

                        (pubmote-send-packet pubmote-remote-mac tmpbuf nil)
                        (free tmpbuf)
                        (esp-now-del-peer pubmote-remote-mac)

                        (set-pairing-state PAIR_STATE_BONDING)
                    })
                } {
                    ; Not our remote, or our remote with the wrong secret
                    ; code. Distinguishing those two is exactly what people
                    ; need when a remote "connects to the wrong board".
                    (if (dbg-tick DBG-REM 'rem-drop 2.0)
                        (dbg DBG-REM (str-merge "rem drop from " (to-str src)
                            (if (eq pubmote-remote-mac src) " bad code" " bad mac"))))
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
                    ; Respond while INITIATED, or while BONDING if the bond in
                    ; progress is already a BLE one (all-zeros MAC): the remote
                    ; may have missed our first response, and refusing to
                    ; repeat it deadlocks the handshake until the pairing
                    ; timeout. The BONDING guard prevents a BLE request from
                    ; clobbering an in-progress ESP-NOW bond's MAC.
                    (if (or (= pairing-state PAIR_STATE_INITIATED) (and (= pairing-state PAIR_STATE_BONDING) (not (is-valid-espnow-mac pubmote-remote-mac)))) {
                        (print "Pubmote bond req (BLE)")
                        (setq pubmote-remote-mac '(0 0 0 0 0 0)) ; Initialize with dummy all-zeros MAC for BLE
                        (var tmpbuf (bufcreate 5))
                        (bufset-u8 tmpbuf 0 REM_PAIR_BOND)
                        (bufset-i32 tmpbuf 1 (pubmote-get-cfg 'pubmote-secret-code))

                        (pubmote-send-packet '() tmpbuf t)
                        (free tmpbuf)

                        (set-pairing-state PAIR_STATE_BONDING)
                    } {
                        (dbg DBG-REM "rem bond req ignored, wrong state")
                    })
                })
                ; Throttled: a secret-code mismatch (remote paired to a
                ; different board) arrives at input rate, so this is gated
                ; and rate-limited rather than printed per packet.
                (if (and (!= cmd REM_PAIR_BOND) (dbg-tick DBG-REM 'rem-drop 2.0))
                    (dbg DBG-REM (str-merge "rem drop ble cmd " (to-str cmd))))
            })
            (free payload)
        })
    })
})

@const-end
