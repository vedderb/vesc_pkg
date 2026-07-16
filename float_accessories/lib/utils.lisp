;@const-symbol-strings
@const-start
;Future interesting functions
;(conf-detect-foc canFwd maxLoss minCurrIn maxCurrIn openloopErpm slErpm)
;(conf-set) 'can-status-rate-hz 'foc-fw-duty-start 'foc-fw-current-max  'foc-offsets-cal-on-boot 'foc-sl-erpm-start 'foc-observer-gain 'foc-f-zv 'si-battery-ah 'si-battery-cells 'si-wheel-diameter  'si-gear-ratio  'si-motor-poles 'motor-type 'foc-sensor-mode 'l-current-min 'l-current-max 'l-abs-current-max 'l-min-vin 'l-max-vin 'l-battery-cut-start 'l-battery-cut-end 'l-temp-motor-start 'l-temp-motor-end 'l-temp-accel-dec 'bms-limit-mode 'bms-t-limit-start 'bms-t-limit-end 'bms-vmin-limit-start 'bms-vmin-limit-end 'bms-vmax-limit-start 'bms-vmax-limit-end
;(stats 'stat-speed-max) ; Maximum speed in m/s
;(stats-reset)

;(event-enable 'event-shutdown) ; -> event-shutdown
;(lbm-set-quota quota)
;(timeout-reset)
;GNSS stuff

;(reboot)

(defun max (a b)
    (if (> a b) a b)
)

(defun min (a b)
    (if (< a b) a b)
)

(defun print-hex (data)
    (print
        (map (fn (x) (bufget-u8 data x)) (range (buflen data)))
    )
)

; Dispatch handlers are wrapped in trap so a malformed packet can never kill
; the event thread - an unhandled eval error would otherwise cost a >=1s
; control/telemetry blackout while the restart monitor respawns it.
(defun dispatch-trapped (name res)
    (if (eq (ix res 0) 'exit-error)
        (print (str-merge name " error: " (to-str (ix res 1))))
    )
)

(defun event-handler ()
    (loopwhile t
        (recv
            ((event-esp-now-rx (? src) (? des) (? data) (? rssi))
                (dispatch-trapped "pubmote-rx" (trap (pubmote-rx src des data rssi))))
            ((event-data-rx . (? data))
                (dispatch-trapped "command-rx" (trap (command-rx data))))
            ((event-mqtt-connected)
                (dispatch-trapped "mqtt-connected" (trap (mqtt-on-connect))))
            ((event-mqtt-rx (? topic) (? data))
                (dispatch-trapped "mqtt-rx" (trap (mqtt-rx topic data))))
            (_ nil)
        )
    )
)

(defun send-msg (text)
    (send-data (str-merge "msg " text))
)

(defun send-status (text)
    (send-data (str-merge "status " text))
)

(defun mklist (len val)
    (map (fn (x) val) (range len))
)

(defun split-list (lst n)
    (if (eq lst nil)
        nil
        (cons (take lst n) (split-list (drop lst n) n))
    )
)

(defunret pack-bytes-to-uint32 (byte-list) {
  (return (to-u32 (+ (shl (to-u32 (ix byte-list 0)) 24)
                     (shl (to-u32 (ix byte-list 1)) 16)
                     (shl (to-u32 (ix byte-list 2)) 8)
                     (to-u32 (ix byte-list 3)))))
})
(defunret unpack-uint32-to-bytes (packed-value) {
  (return (list (to-byte (bitwise-and (shr packed-value 24) 0xFF))
                (to-byte (shr (bitwise-and packed-value 0xFF0000) 16))
                (to-byte (shr (bitwise-and packed-value 0xFF00) 8))
                (to-byte (bitwise-and packed-value 0xFF))))
})

(defun swap-rg (color-list) {
    (looprange led-index 0 (length color-list) {
        (var color (color-split (ix color-list led-index) 1))
        (var new-color (color-make (ix color 1) (ix color 0) (ix color 2) (ix color 3)))
        (setix color-list led-index new-color)
    })
})

(def has-si7021 nil)
(def has-aht20 nil)

(defunret init-humidity () {
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

                ;(print (str-merge "[Si7021] Humidity: " (str-from-n hum "%.2f%%")
                ;                   ", Temp: " (str-from-n (+ (* hum-temp 1.8) 32) "%.2fF")
                ;                   " / " (str-from-n hum-temp "%.2fC")))
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
                ;(print (str-merge "[AHT20] Humidity: " (str-from-n hum "%.2f%%")
                ;                   ", Temp: " (str-from-n (+ (* hum-temp 1.8) 32) "%.2fF")
                ;                   " / " (str-from-n hum-temp "%.2fC")))
            })
            (sleep 1)
        })
        (free rx-si7021)
        (free rx-aht20)
        (setq humidity-exit-flag nil)
    })
})

(defun apply-battery-config (new-soc-type new-cell-type) {
    (setq soc-type new-soc-type)
    (setq cell-type new-cell-type)
    ;(setq series-cells (get-config 'series-cells))
    (setq voltage-curve (get-voltage-curve cell-type))
    (print (str-merge "Cell info: type=" (str-from-n cell-type) " soc-type=" (str-from-n soc-type) " series-cells=" (str-from-n series-cells)))
})

(defun estimate-soc (v voltage-curve) {
    (var n (length voltage-curve))
    (var socs (list 100 90 80 70 60 50 40 30 20 10 0))
    (cond
        ((>= v (ix voltage-curve 0)) 100.0)
        ((<= v (ix voltage-curve (- n 1))) 0.0)
        (true
            (looprange i 1 (- n 1)
                (if (and (>= v (ix voltage-curve i)) (<= v (ix voltage-curve (- i 1))))
                    (break (let ((v1 (ix voltage-curve (- i 1)))
                    (v2 (ix voltage-curve i))
                    (s1 (ix socs (- i 1)))
                    (s2 (ix socs i)))
                    (+ s1 (* (/ (- v v1) (- v2 v1)) (- s2 s1)))))
                )
            )
         )
     )
})

(defun get-var (i) i)

(defun get-version () {
    (list 3 4 0) ; Major, Minor, Patch
})

(defun is-606-or-newer () {
    (or (> (first (sysinfo 'fw-ver)) 6) (and (= (first (sysinfo 'fw-ver)) 6) (>= (second (sysinfo 'fw-ver)) 6)))
})

(defun is-pubmote-connected ()
    (if (= (get-config 'pubmote-enabled) 1) (pubmote-connected) 0)
)

@const-end