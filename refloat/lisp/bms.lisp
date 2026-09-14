(defun bms-loop () {
    (var v-cell-support (eq (first (trap (get-bms-val 'bms-v-cell-min))) 'exit-ok))
    (var err-print-time nil)
    (loopwhile t {
        (var res (trap {
            (if (and (>= (get-bms-val 'bms-can-id) 0) (ext-bms)) {
                (var msg-age (get-bms-val 'bms-msg-age))
                (var temp-max (get-bms-val 'bms-temp-cell-max))
                (var temp-min temp-max)
                (var temp-fet -281)
                (var v-min 0)
                (var v-max 0)

                (if v-cell-support {
                    (if (>= (get-bms-val 'bms-data-version) 1) {
                        (var num-temps (get-bms-val 'bms-temp-adc-num))
                        (if (> num-temps 1) (setq temp-min (get-bms-val 'bms-temps-adc 1)))
                        (if (> num-temps 3) (setq temp-fet (get-bms-val 'bms-temps-adc 3)))
                    })
                    (setq v-min (get-bms-val 'bms-v-cell-min))
                    (setq v-max (get-bms-val 'bms-v-cell-max))
                } {
                    (var num-cells (get-bms-val 'bms-cell-num))
                    (if (> num-cells 0) {
                        (setq v-min (get-bms-val 'bms-v-cell 0))
                        (setq v-max v-min)
                        (looprange i 1 num-cells {
                            (var cell-v (get-bms-val 'bms-v-cell i))
                            (if (< cell-v v-min) (setq v-min cell-v))
                            (if (> cell-v v-max) (setq v-max cell-v))
                        })
                    })
                })

                (ext-bms v-min v-max temp-min temp-max temp-fet msg-age)
            })
        }))

        (if (and (eq (first res) 'exit-error)
                 (or (not err-print-time) (>= (secs-since err-print-time) 5))) {
            (setq err-print-time (systime))
            (print (str-merge "[refloat] BMS loop error: " (to-str (second res))))
        })

        (sleep 0.2)
    })
})
