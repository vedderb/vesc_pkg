(import "pkg@://vesc_packages/lib_code_server/code_server.vescpkg" 'code-server)
(read-eval-program code-server)

(start-code-server)

(def buf-canid20 (array-create 8)) ; SOC, Duty, Speed, Current In
(def buf-canid21 (array-create 8)) ; BMS Temp, Mosfet Temp, Motor Temp, Pitch angle
(def buf-canid22 (array-create 8)) ; Wh, Wh Regen, Distance, Fault
(def buf-canid23 (array-create 8)) ; Current Avg, Current Max, Current Now, Batt Ah
(def buf-canid24 (array-create 8)) ; Votage, Odometer, Cruise Control Set Speed

(def buf-canid30 (array-create 8)) ; Indicators, High Beam, Cruise Control Active

@const-start

(spawn (fn ()
        (loopwhile t
            (progn
                (select-motor 1)
                (bufset-i16 buf-canid20 0 (* (get-batt) 1000))
                (bufset-i16 buf-canid20 2 (* (abs (get-duty)) 1000))
                (bufset-i16 buf-canid20 4 (* (abs (get-speed)) 3.6 10))
                (bufset-i16 buf-canid20 6 (* (get-current-in) (get-vin) 2 0.1))

                (if (> (get-bms-val 'bms-temp-adc-num) 0)
                    (bufset-i16 buf-canid21 0 (* (get-bms-val 'bms-temps-adc 0) 10))
                    (bufset-i16 buf-canid21 0 0)
                )
                (bufset-i16 buf-canid21 2 (* (get-temp-fet) 10))
                (bufset-i16 buf-canid21 4 (* (get-temp-mot) 10))
                (bufset-i16 buf-canid21 6 (* (ix (get-imu-rpy) 1) 100))

                (bufset-u16 buf-canid22 0 (* (get-wh) 10.0))
                (bufset-u16 buf-canid22 2 (* (get-wh-chg) 10.0))
                (bufset-u16 buf-canid22 4 (* (/ (get-dist-abs) 1000) 10))
                (bufset-u16 buf-canid22 6 (get-fault))

                (bufset-u16 buf-canid23 0 (to-i (stats 'stat-current-avg)))
                (bufset-u16 buf-canid23 2 (to-i (stats 'stat-current-max)))
                (bufset-i16 buf-canid23 4 (to-i (get-current)))
                (bufset-u16 buf-canid23 6 (to-i (conf-get 'si-battery-ah)))

                (bufset-u16 buf-canid24 0 (* (get-vin) 10))
                (bufset-u32 buf-canid24 2 (* (/ (sysinfo 'odometer) 1000.0) 10))
                (bufset-u16 buf-canid24 6 (* (abs (get-speed-set)) 3.6 10))

                (can-send-sid 20 buf-canid20)
                (can-send-sid 21 buf-canid21)
                (can-send-sid 22 buf-canid22)
                (can-send-sid 23 buf-canid23)
                (can-send-sid 24 buf-canid24)
                (sleep 0.1) ; 10 Hz
))))

; Indicators example for use with homologation view
(spawn (fn () (loopwhile t
        (progn
                (bufset-u8 buf-canid30 0 1) ; L Indicator ON
                (bufset-u8 buf-canid30 1 1) ; R Indicator ON
                (bufset-u16 buf-canid30 2 650) ; Indicator ON milliseconds
                (can-send-sid 30 buf-canid30)
            (sleep 0.65)
                (bufset-u8 buf-canid30 0 0) ; L Indicator OFF
                (bufset-u8 buf-canid30 1 0) ; R Indicator OFF
                (bufset-u16 buf-canid30 2 650) ; Indicator ON milliseconds
                (can-send-sid 30 buf-canid30)
            (sleep 0.5)
    ))
))
