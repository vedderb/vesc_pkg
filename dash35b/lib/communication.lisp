(def rx-cnt-can 0)
(def crusie-new-msg-rx false)

@const-start

(defun proc-sid (id data) {
        (cond
            ((= id 20) {
                    ; Using SOC from BMS when available
                    (if (and (not battery-a-connected) (not battery-b-connected))
                        (def stats-battery-soc (/ (bufget-i16 data 0) 1000.0))
                    )
                    (def stats-duty (/ (bufget-i16 data 2) 1000.0))

                    ; Override speed if configured to use GPS speed
                    (if config-gnss-use-speed
                        (def stats-kmh (gnss-speed))
                        (def stats-kmh (/ (bufget-i16 data 4) 10.0))
                    )

                    (def stats-kw (/ (bufget-i16 data 6) 100.0))

                    (def stats-updated true)
                    (setq rx-cnt-can (+ rx-cnt-can 1))
            })
            ((= id 21) {
                    (def stats-temp-battery (/ (bufget-i16 data 0) 10.0))
                    (def stats-temp-esc (/ (bufget-i16 data 2) 10.0))
                    (def stats-temp-motor (/ (bufget-i16 data 4) 10.0))
                    (def stats-angle-pitch (/ (bufget-i16 data 6) 100.0))
                    (setq rx-cnt-can (+ rx-cnt-can 1))
            })
            ((= id 22) {
                    (def stats-wh (/ (bufget-u16 data 0) 10.0))
                    (def stats-wh-chg (/ (bufget-u16 data 2) 10.0))
                    (def stats-km (/ (bufget-u16 data 4) 10.0))
                    (def stats-fault-code (bufget-u16 data 6))
                    (setq rx-cnt-can (+ rx-cnt-can 1))
            })
            ((= id 23) {
                    (def stats-amps-avg (bufget-u16 data 0))
                    (def stats-amps-max (bufget-u16 data 2))
                    (def stats-amps-now (bufget-i16 data 4))
                    ; Use Ah from BMS when available
                    (if (not battery-a-connected) {
                            (def stats-battery-ah (bufget-u16 data 6))
                    })
                    (setq rx-cnt-can (+ rx-cnt-can 1))
            })
            ((= id 24) {
                    (def stats-vin (/ (bufget-u16 data 0) 10.0))
                    (def stats-odom (/ (bufget-u32 data 2) 10.0))
                    (def cruise-control-speed (/ (bufget-u16 data 6) 10.0))
                    (setq rx-cnt-can (+ rx-cnt-can 1))
            })
            ((= id 30) {
                    (var indicate-l (= (bufget-u8 data 0) 1))
                    (var indicate-r (= (bufget-u8 data 1) 1))
                    (def indicate-ms (bufget-u16 data 2))
                    (def highbeam-on (= (bufget-u8 data 4) 1))

                    (if (not crusie-new-msg-rx)
                        (setq cruise-control-active (eq (bufget-u8 data 5) 1))
                    )

                    ; Track when indicators activate for animation
                    (if (or
                            (and indicate-l (not indicate-l-on))
                            (and indicate-r (not indicate-r-on))
                        )
                        (def indicator-timestamp (systime))
                    )

                    (def indicate-l-on indicate-l)
                    (def indicate-r-on indicate-r)

                    (setq rx-cnt-can (+ rx-cnt-can 1))
            })
            ((= id 31) {
                    (def kickstand-down (= (bufget-u8 data 0) 0)) ; NOTE: Inverted
                    ;(def drive-mode (match (bufget-u8 data 1)
                            ;(0 'neutral)
                            ;(1 'drive)
                            ;(2 'reverse)
                            ;(_ {
                                    ;(print "Error: Invalid drive mode")
                                    ;'neutral
                            ;})
                    ;))
                    (def performance-mode (match (bufget-u8 data 2)
                            (0 'eco)
                            (1 'normal)
                            (2 'sport)
                            (_ {
                                    (print "Error: Invalid performance mode")
                                    'eco
                            })
                    ))

                    (setq rx-cnt-can (+ rx-cnt-can 1))
            })
            ((= id 35) {
                    (def stats-battery-soc (/ (bufget-i16 data 0) 1000.0))
                    (def battery-a-charging (eq (bufget-u8 data 2) 1))
                    (def battery-a-chg-time (bufget-u16 data 3))
                    (def stats-battery-ah (/ (bufget-u16 data 5) 10.0))

                    (def battery-a-connected true) ; TODO: Allow for BMS A connected to timeout
                    (setq rx-cnt-can (+ rx-cnt-can 1))
            })
            ((= id 36) {
                    (def battery-b-soc (/ (bufget-i16 data 0) 1000.0))
                    (def battery-b-charging (eq (bufget-u8 data 2) 1))
                    (def battery-b-chg-time (bufget-u16 data 3))

                    (def battery-b-connected true) ; TODO: Allow for BMS B connected to timeout
                    (setq rx-cnt-can (+ rx-cnt-can 1))
            })

            ((= id 202) {
                    (setq cruise-control-active (= (bufget-u8 data 0) 1))
                    (setq crusie-new-msg-rx true)
            })

            ((= id 203) {
                    (setq temp-ambient (/ (bufget-i16 data 0) 10.0))
                    (setq temp-ambient-rx true)
            })

            ((= id 204) {
                    (setq date-time (map (fn (x) (bufget-u8 data x)) (range (buflen data))))
                    (setq date-time-rx true)
            })
        )

        (free data)
})

(defun event-handler ()
    (loopwhile t
        (recv
            ((event-can-sid . ((? id) . (? data))) (proc-sid id data))
            (_ nil)
)))

(defun comm-tx-thread () {
        (loopwhile t {
                (can-send-sid 201 (list drive-mode (if light-on 1 0) 0 0 0 0 0 0))
                (sleep 0.1)
        })
})

; Send event
; ID 0: Toggle cruise control
; ID 1: Save data, power might turn off
(defun comm-send-event (event-id) {
        (var buf (bufcreate 2))
        (bufset-u8 buf 0 event-id)
        (can-send-sid 250 buf)
})
