(def rx-cnt-can 0)

@const-start

(defun esc-request (code) {
    (var success true)
    (looprange i 0 (length config-can-id-esc) {
        (var ret (rcode-run (ix config-can-id-esc i) 0.2 code))
        (match ret
            (timeout {
                (print (str-merge "esc-request: timeout with esc id " (to-str (ix config-can-id-esc i))))
                (setq success false)
            })
            (eerror {
                (print (str-merge "esc-request: eerror with esc id " (to-str (ix config-can-id-esc i))))
                (setq success false)
            })
            (_ t)
        )
    })

    success
})

(defun proc-data (src des data rssi) {
    ; Ignore broadcast, only handle data sent directly to us
    (if (not-eq des broadcast-addr) {
        (def peer-addr src)
        ;(esp-now-add-peer src)
        ;(eval (read data))
    } {
        ; Broadcast data
        ;(var br-data (unflatten data))
    })

    (free data)
})


(defun proc-sid (id data) {
    (cond
        ((= id 20) {
            (def stats-battery-soc (/ (bufget-i16 data 0) 1000.0))
            (def stats-duty (/ (bufget-i16 data 2) 1000.0))
            (def stats-kmh (/ (bufget-i16 data 4) 10.0))
            (def stats-kw (* (/ (bufget-i16 data 6) 100.0) (length config-can-id-esc)))

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
            (def stats-wh (* (/ (bufget-u16 data 0) 10.0) (length config-can-id-esc)))
            (def stats-wh-chg (* (/ (bufget-u16 data 2) 10.0) (length config-can-id-esc)))
            (def stats-km (/ (bufget-u16 data 4) 10.0))
            (def stats-fault-code (bufget-u16 data 6))
            (setq rx-cnt-can (+ rx-cnt-can 1))
        })
        ((= id 23) {
            (def stats-amps-avg (* (bufget-u16 data 0) (length config-can-id-esc)))
            (def stats-amps-max (* (bufget-u16 data 2) (length config-can-id-esc)))
            (def stats-amps-now (* (bufget-i16 data 4) (length config-can-id-esc)))
            (def stats-battery-ah (bufget-u16 data 6))
            (setq rx-cnt-can (+ rx-cnt-can 1))
        })
        ((= id 24) {
            (def stats-vin (/ (bufget-u16 data 0) 10.0))
            (def stats-odom (/ (bufget-u32 data 2) 10.0))
            (def cruise-control-speed (/ (bufget-u16 data 6) 10.0))
            (setq rx-cnt-can (+ rx-cnt-can 1))
        })
        ((= id 30) {
            (var indicate-l (eq (bufget-u8 data 0) 1))
            (var indicate-r (eq (bufget-u8 data 1) 1))
            (def indicate-ms (bufget-u16 data 2))
            (def highbeam-on (eq (bufget-u8 data 4) 1))
            (def cruise-control-active (eq (bufget-u8 data 5) 1))

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
            (def kickstand-down (eq (bufget-u8 data 0) 0)) ; NOTE: Inverted
            (def drive-mode (match (bufget-u8 data 1)
                (0 'neutral)
                (1 'drive)
                (2 'reverse)
                (_ {
                    (print "Error: Invalid drive mode")
                    'neutral
                })
            ))
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
            (def battery-b-soc (/ (bufget-i16 data 2) 1000.0))
            (def battery-a-charging (eq (bufget-u8 data 4) 1))
            (def battery-b-charging (eq (bufget-u8 data 5) 1))
            (def battery-b-connected (eq (bufget-u8 data 6) 1))

            (setq rx-cnt-can (+ rx-cnt-can 1))
        })
    )

    (free data)
})


(defun event-handler ()
    (loopwhile t
        (recv
            ;;((event-esp-now-rx (? src) (? des) (? data) (? rssi)) (proc-data src des data rssi))
            ((event-can-sid . ((? id) . (? data))) (proc-sid id data))
            (_ nil)
)))


(event-register-handler (spawn event-handler))
;;(event-enable 'event-esp-now-rx)
(event-enable 'event-can-sid)
