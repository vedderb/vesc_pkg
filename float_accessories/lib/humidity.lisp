;@const-symbol-strings
@const-start

; Humidity / temperature sensor support. Detects a Si7021 (0x40) or AHT20
; (0x38) on the configured I2C pins at init, then polls the detected sensor
; once a second into the shared hum / hum-temp vars (settings-vars.lisp),
; which the status feed and BMS reporting read.

(def has-si7021 nil)
(def has-aht20 nil)

(defunret init-humidity () {
    (dbg DBG-HUM (str-merge "hum i2c sda " (str-from-n (get-config 'humidity-sda-pin) "%d")
        " slc " (str-from-n (get-config 'humidity-slc-pin) "%d")))
    (i2c-start 'rate-400k (get-config 'humidity-sda-pin) (get-config 'humidity-slc-pin))
    (setq has-si7021 (i2c-detect-addr 0x40))
    (setq has-aht20 (i2c-detect-addr 0x38))

    (if (or has-si7021 has-aht20) {
        (print "Sensors detected:")
        (if has-si7021 { (print "- Using Si7021 logic at 0x40") })
        (if has-aht20  { (print "- Using AHT20 logic at 0x38") })

        (if has-aht20 {
            (sleep 0.04)
            (i2c-tx-rx 0x38 '(0xBE 0x08 0x00))
        })
        (if has-si7021 {
            (i2c-tx-rx 0x40 '(2 0x10 0))
            (i2c-tx-rx 0x40 '(0))
        })
        (return true)
    })
    (send-msg "No humidity sensor detected.")
    (return false)
})

(defun humidity-loop () {
    (if (init-humidity) {
        (var rx-si7021 (bufcreate 4))
        (var rx-aht20 (bufcreate 6))
        (loopwhile t {
            (if humidity-exit-flag {
                (break)
            })

            (if has-si7021 {
                (i2c-tx-rx 0x40 '() rx-si7021)
                (i2c-tx-rx 0x40 (list 0x0F 0x01))
                (i2c-tx-rx 0x40 '(0))

                (setq hum (* (/ (bufget-u16 rx-si7021 2 'little-endian) 65536.0) 100.0))
                (setq hum-temp (- (* (/ (bufget-u16 rx-si7021 0 'little-endian) 65536.0) 165.0) 40.5))

                (if (dbg-tick DBG-HUM 'hum-read 10.0)
                    (dbg DBG-HUM (str-merge "hum " (str-from-n hum "%.1f")
                        " " (str-from-n hum-temp "%.2f"))))
            })

            (if has-aht20 {
                (i2c-tx-rx 0x38 '(0xAC 0x33 0x00))
                (sleep 0.075)
                (i2c-tx-rx 0x38 '() rx-aht20)

                (var hum-raw (+ (shl (bufget-u8 rx-aht20 1) 12)
                                (shl (bufget-u8 rx-aht20 2) 4)
                                (shr (bufget-u8 rx-aht20 3) 4)))
                (var temp-raw (+ (shl (bitwise-and (bufget-u8 rx-aht20 3) 0x0F) 16)
                                 (shl (bufget-u8 rx-aht20 4) 8)
                                 (bufget-u8 rx-aht20 5)))

                (setq hum (* (/ hum-raw 1048576.0) 100.0))
                (setq hum-temp (- (* (/ temp-raw 1048576.0) 200.0) 50.0))
                (if (dbg-tick DBG-HUM 'hum-read 10.0)
                    (dbg DBG-HUM (str-merge "hum " (str-from-n hum "%.1f")
                        " " (str-from-n hum-temp "%.2f"))))
            })
            (sleep 1)
        })
        (free rx-si7021)
        (free rx-aht20)
        (setq humidity-exit-flag nil)
    } {
        ; Park rather than return: spawn-with-restart would respawn this
        ; every second, repeating the "No humidity sensor detected." dialog
        ; at 1 Hz. Same pattern gnss-loop uses.
        (dbg-warn "hum no sensor - parked")
        (loopwhile (not humidity-exit-flag) (sleep 1))
        (setq humidity-exit-flag nil)
    })
})

@const-end
