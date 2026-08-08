;@const-symbol-strings
@const-start

; GNSS receiver support. Two module types:
;   0 u-blox: driven by the firmware ublox driver (ublox-init), which
;     configures the module and parses in the background.
;   1 NMEA:   any module streaming NMEA sentences on a UART - read
;     line-wise and fed to nmea-parse.
; Either way the fix lands in the firmware GNSS state, so the gnss-*
; extensions work, the SD log can append position (Log GNSS) and the
; firmware answers the CAN GNSS broadcast.

(defunret init-gnss () {
    (var rx (get-config 'gnss-rx-pin))
    (var tx (get-config 'gnss-tx-pin))

    (dbg DBG-GNSS (str-merge "gnss type " (str-from-n (get-config 'gnss-type) "%d")
        " uart " (str-from-n (get-config 'gnss-uart-num) "%d")
        " rx " (str-from-n rx "%d")
        " tx " (str-from-n tx "%d")
        " baud " (str-from-n (get-config 'gnss-baud) "%d")))

    (if (< rx 0) {
        ; Enabled but not wired up: skip init quietly (print, not send-msg)
        ; so it doesn't pop an alert dialog on every boot.
        (print "GNSS: RX pin not set, not starting")
        (return nil)
    })

    (if (= (get-config 'gnss-type) 0) {
        (if (< tx 0) {
            (print "GNSS: u-blox needs both RX and TX pins, not starting")
            (return nil)
        })
        (if (ublox-init (get-config 'gnss-rate-ms) (get-config 'gnss-uart-num) rx tx) {
            (print "GNSS: u-blox started")
            (return 'ublox)
        } {
            ; No alert dialog: the GNSS status row already shows "No
            ; Signal" and this fires on every boot with the module
            ; unpowered or disconnected.
            (print "GNSS: u-blox module not responding")
            (return nil)
        })
    } {
        (uart-start (get-config 'gnss-uart-num) rx tx (get-config 'gnss-baud))
        (print "GNSS: NMEA UART started")
        (return 'nmea)
    })
})

; Fix acquired / lost is the one GNSS event worth a line, plus a throttled
; position while a fix is held. Same fix definition the status feed uses.
(defun dbg-gnss-fix-transitions () {
    (var ll (gnss-lat-lon))
    (var age (gnss-age))
    (var fix (if (and (< age 5.0) (or (!= (ix ll 0) 0.0) (!= (ix ll 1) 0.0))) 1 0))
    (if (!= fix dbg-prev-gnss-fix) {
        (setq dbg-prev-gnss-fix fix)
        (print (if (= fix 1) "GNSS fix" "GNSS fix lost"))
    })
    (if (and (= fix 1) (dbg-tick DBG-GNSS 'gnss-pos 10.0))
        (dbg DBG-GNSS (str-merge "gnss " (str-from-n (ix ll 0) "%.6f")
            " " (str-from-n (ix ll 1) "%.6f")
            " hdop " (str-from-n (gnss-hdop) "%.1f")
            " age " (str-from-n age "%.1f"))))
})

(defun gnss-loop () {
    (var mode (init-gnss))
    (cond
        ((eq mode 'nmea) {
            ; Read one NMEA sentence per iteration (up to the newline). A
            ; sentence split by the read timeout just fails the checksum in
            ; nmea-parse and is skipped.
            (var buf (bufcreate 128))
            (var sentences 0)
            (var empty-reads 0)
            (loopwhile (not gnss-exit-flag) {
                (var n (uart-read buf 127 0 10 1.0))
                (if (> n 0) {
                    (setq sentences (+ sentences 1))
                    (setq empty-reads 0)
                    (bufset-u8 buf n 0)
                    ; Trapped: a truncated sentence used to take the whole
                    ; GNSS loop down through nmea-parse.
                    (var r (trap (nmea-parse buf)))
                    (if (eq (ix r 0) 'exit-error)
                        (if (dbg-tick DBG-GNSS 'gnss-err 5.0)
                            (dbg-warn (str-merge "gnss parse " (to-str (ix r 1))))))
                    (if (dbg-tick DBG-GNSS 'gnss-nmea 5.0)
                        (dbg DBG-GNSS (str-merge "gnss rx " (str-from-n sentences "%d"))))
                } {
                    (setq empty-reads (+ empty-reads 1))
                    ; 1 s read timeout, so 10 empty reads is ~10 s of silence
                    (if (= empty-reads 10)
                        (dbg-warn "gnss no UART data"))
                })
                (dbg-gnss-fix-transitions)
            })
            (free buf)
            (uart-stop)
        })
        ((eq mode 'ublox) {
            ; The firmware driver runs on its own thread - just park here
            ; so the loop can be stopped/restarted on config changes. The
            ; driver itself keeps running; a restart re-inits it with the
            ; new settings.
            (loopwhile (not gnss-exit-flag) {
                (dbg-gnss-fix-transitions)
                (sleep 1)
            })
        })
        (t {
            ; Not configured or init failed: park until stopped so
            ; spawn-with-restart doesn't respawn (and re-alert) in a tight
            ; loop. A restart is still needed to pick up a later config.
            (loopwhile (not gnss-exit-flag) (sleep 1))
        })
    )
    (setq gnss-exit-flag nil)
})

@const-end
