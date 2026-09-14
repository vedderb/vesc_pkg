; Running without dash_esc on the controller.
;
; dash_esc broadcasts everything the display needs on SIDs 20 to 24. With no
; package on the controller none of that arrives, but the standard VESC status
; frames still do, and canget-* reads them. A VESC BMS on the bus is read
; directly with get-bms-val, which never depended on dash_esc either.
;
; What cannot be recovered this way, because it is in no status frame:
; watt hours, amp hours, odometer, fault codes, IMU pitch, average and peak
; current, cruise state, indicators, high beam and kickstand.

; True while the display is sourcing its own telemetry.
(def standalone-active false)

; CAN id currently being read. Resolved from settings-esc-id, or discovered.
(def standalone-esc-id -1)

; systime of the last dash_esc frame, for the auto detection below.
(def dash-esc-last 0)

@const-start

(def dash-esc-timeout 3.0)

; Pick the controller to talk to. A configured id wins; zero means take the
; lowest id that has spoken recently, so a single-controller bike needs no
; setting at all.
(defunret standalone-pick-esc () {
        (if (> settings-esc-id 0) (return settings-esc-id))

        (var devs (can-list-devs))
        (if (eq devs nil) (return -1))

        (var best -1)
        (loopforeach d devs
            ; Status 1 always broadcasts, so it is the frame to age-check.
            (if (and (< (can-msg-age d 1) 2.0) (or (< best 0) (< d best)))
                (setq best d)
        ))
        best
})

; Decide whether dash_esc is present.
;
; Mode 0 follows the traffic, 1 forces dash_esc, 2 forces standalone. Auto
; only reports standalone once nothing has arrived for a while, so a brief
; gap on the bus does not flip the display back and forth.
(defun standalone-should-run ()
    (cond
        ((= settings-esc-mode 1) false)
        ((= settings-esc-mode 2) true)
        (t (> (secs-since dash-esc-last) dash-esc-timeout))
))

; Fill the same globals the dash_esc handler writes, so every view carries on
; reading exactly what it read before.
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

        ; canget-dist is distance since the controller booted, not an odometer.
        ; It is shown as the trip and the odometer is left alone rather than
        ; filled with a number that resets on every power cycle.
        (def stats-km (/ (canget-dist id) 1000.0))

        ; A VESC BMS reaches the display on its own, so state of charge and
        ; pack temperature survive without dash_esc when one is fitted.
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
