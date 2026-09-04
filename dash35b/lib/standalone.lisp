; Without dash_esc. Status frames carry speed, duty, voltage, current and
; temps, but not Wh, Ah, odometer or faults.

(def standalone-active false)

(def standalone-esc-id -1)

(def dash-esc-last 0)

@const-start

(def dash-esc-timeout 3.0)

; 0 takes the lowest recently seen id
(defunret standalone-pick-esc () {
        (if (> settings-esc-id 0) (return settings-esc-id))

        (var devs (can-list-devs))
        (if (eq devs nil) (return -1))

        (var best -1)
        (loopforeach d devs
                (if (and (< (can-msg-age d 1) 2.0) (or (< best 0) (< d best)))
                (setq best d)
        ))
        best
})

; 0 auto, 1 force dash_esc, 2 force standalone
(defun standalone-should-run ()
    (cond
        ((= settings-esc-mode 1) false)
        ((= settings-esc-mode 2) true)
        (t (> (secs-since dash-esc-last) dash-esc-timeout))
))

(defun standalone-sample (id) {
        (var speed (canget-speed id))
        (if config-gnss-use-speed
            (def stats-kmh (gnss-speed))
            (def stats-kmh (* (abs speed) 3.6))
        )

        (def stats-duty (canget-duty id))
        (def stats-vin (canget-vin id))
        (def stats-temp-esc (canget-temp-fet id))
        (def stats-temp-motor (canget-temp-motor id))

        (var i-in (canget-current-in id))
        (def stats-amps-now i-in)
        (def stats-kw (/ (* i-in stats-vin) 1000.0))

        ; Since controller boot, not an odometer
        (def stats-km (/ (canget-dist id) 1000.0))

        (if (> (get-bms-val 'bms-cell-num) 0) {
                (def stats-battery-soc (get-bms-val 'bms-soc))
                (def stats-battery-ah (get-bms-val 'bms-ah-cnt))
                (if (> (get-bms-val 'bms-temp-adc-num) 2)
                    (def stats-temp-battery (get-bms-val 'bms-temps-adc 2))
                )
        })

        (def stats-updated true)
})

(defun standalone-thread ()
    (loopwhile t {
            (var want (standalone-should-run))

            (if (not-eq want standalone-active) {
                    (setq standalone-active want)
                    (setq view-force-static true)
                    (setq view-force-pages true)
                    (print (if want
                        "dash_esc not seen, reading CAN status frames directly"
                        "dash_esc present"
                    ))
            })

            (if standalone-active {
                    (setq standalone-esc-id (standalone-pick-esc))
                    (if (>= standalone-esc-id 0)
                        (standalone-sample standalone-esc-id)
                    )
            })

            (sleep 0.1)
}))
