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
        (dbg-err (str-merge name " " (to-str (ix res 1))))
    )
)

(defun event-handler ()
    (loopwhile t
        (recv
            ((event-esp-now-rx (? src) (? des) (? data) (? rssi)) {
                (if (!= dbg-mask 0) (setq dbg-ticks-evt (+ dbg-ticks-evt 1)))
                (if (dbg-tick DBG-REM 'rem-rx 2.0)
                    (dbg DBG-REM (str-merge "rem rx " (str-from-n (buflen data) "%d")
                        " rssi " (str-from-n rssi "%d"))))
                (dispatch-trapped "pubmote-rx" (trap (pubmote-rx src des data rssi)))
            })
            ((event-data-rx . (? data)) {
                (if (!= dbg-mask 0) (setq dbg-ticks-evt (+ dbg-ticks-evt 1)))
                (dispatch-trapped "command-rx" (trap (command-rx data)))
            })
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

(defun apply-battery-config (new-soc-type new-cell-type) {
    (setq soc-type new-soc-type)
    (setq cell-type new-cell-type)
    ;(setq series-cells (get-config 'series-cells))
    (setq voltage-curve (get-voltage-curve cell-type))
    (print (str-merge "Cell info: type=" (str-from-n cell-type) " soc-type=" (str-from-n soc-type) " series-cells=" (str-from-n series-cells)))
    ; A voltage-curve SoC with an unknown cell count silently reports
    ; nonsense (vin / -1), which shows up as a stuck battery gauge.
    (if (and (= (to-i soc-type) 1) (< series-cells 1))
        (dbg-warn "curve SoC but cell count unknown"))
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