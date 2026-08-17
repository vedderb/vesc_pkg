;@const-symbol-strings
@const-start
;Future interesting functions
;(conf-detect-foc canFwd maxLoss minCurrIn maxCurrIn openloopErpm slErpm)
;(conf-set) 'can-status-rate-hz 'foc-fw-duty-start 'foc-fw-current-max  'foc-offsets-cal-on-boot 'foc-sl-erpm-start 'foc-observer-gain 'foc-f-zv 'si-battery-ah 'si-battery-cells 'si-wheel-diameter  'si-gear-ratio  'si-motor-poles 'motor-type 'foc-sensor-mode 'l-current-min 'l-current-max 'l-abs-current-max 'l-min-vin 'l-max-vin 'l-battery-cut-start 'l-battery-cut-end 'l-temp-motor-start 'l-temp-motor-end 'l-temp-accel-dec
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

(defun event-handler ()
    (loopwhile t
        (recv
            ((event-data-rx . (? data)) (float-command-rx data))
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
  (return (list (to-byte (shr packed-value 24))
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

(defun get-voltage-curve (cell-type)
    (cond
        ((= cell-type 0) { ; Linear
            (list 4.20 4.05 3.90 3.75 3.60 3.45 3.30 3.15 3.00 2.85 2.70)
        })
        ((= cell-type 1) { ; P28A
            (list 4.14 4.09 3.98 3.88 3.77 3.69 3.63 3.55 3.45 3.24 2.90)
        })
        ((= cell-type 2) { ; P30B
            (list 4.14 4.09 3.98 3.88 3.77 3.69 3.63 3.55 3.45 3.24 2.90)
        })
        ((= cell-type 3) { ; P42A
            (list 4.14 4.05 3.91 3.83 3.74 3.65 3.57 3.48 3.38 3.00 2.80)
        })
        ((= cell-type 4) { ; P45B
            (list 4.14 4.08 4.00 3.91 3.82 3.73 3.64 3.56 3.45 3.23 2.90)
        })
        ((= cell-type 5) { ; P50B
            (list 4.15 4.047 3.96 3.88 3.79 3.70 3.595 3.466 3.29 3.03 2.85)
        })
        ((= cell-type 6) { ; DG40
            (list 4.15 4.02 3.91 3.83 3.75 3.61 3.49 3.35 3.17 2.81 2.70)
        })
        ((= cell-type 7) { ; 50S
            (list 4.15 4.04 3.90 3.82 3.74 3.64 3.52 3.38 3.16 3.00 2.90)
        })
        ((= cell-type 8) { ; VTC6
            (list 4.14 4.00 3.90 3.80 3.70 3.60 3.50 3.40 3.30 3.10 2.80)
        })
        (true { ; Fallback Linear
            (list 4.20 4.05 3.90 3.75 3.60 3.45 3.30 3.15 3.00 2.85 2.70)
        })
    )
)

(defun apply-battery-config (new-soc-type new-cell-type new-series-cells) {
    (setq soc-type 1)
    (setq cell-type (to-i new-cell-type))

    (var cfg-series-cells (to-i new-series-cells))
    (if (and (>= cfg-series-cells 1) (<= cfg-series-cells 64)) {
        (setq series-cells cfg-series-cells)
    } {
        (setq series-cells -1)
    })

    (setq voltage-curve (get-voltage-curve cell-type))
    (print (str-merge "Cell info: type=" (str-from-n cell-type) " soc-type=" (str-from-n soc-type) " series-cells=" (str-from-n series-cells)))
})

(defun estimate-soc (v voltage-curve) {
    (var n (length voltage-curve))
    (var socs (list 100 90 80 70 60 50 40 30 20 10 0))
    (cond
        ((>= v (ix voltage-curve 0)) 100.0)
        ((<= v (ix voltage-curve (- n 1))) 0.0)
        (true {
            (var result 0.0)
            (var found nil)
            (looprange i 1 n {
                (if (and (>= v (ix voltage-curve i)) (<= v (ix voltage-curve (- i 1)))) {
                    (var v1 (ix voltage-curve (- i 1)))
                    (var v2 (ix voltage-curve i))
                    (var s1 (ix socs (- i 1)))
                    (var s2 (ix socs i))
                    (setq result (+ s1 (* (/ (- v v1) (- v2 v1)) (- s2 s1))))
                    (setq found t)
                    (break)
                })
            })
            (if found result 0.0)
        })
     )
})

(defun get-var (i) i)

(defun get-version () {
    (list 3 2 0) ; Major, Minor, Patch
})

(defun is-606-or-newer () {
    (or (> (first (sysinfo 'fw-ver)) 6) (and (= (first (sysinfo 'fw-ver)) 6) (>= (second (sysinfo 'fw-ver)) 6)))
})

@const-end
