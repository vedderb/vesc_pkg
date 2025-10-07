(import "pkg@://vesc_packages/lib_code_server/code_server.vescpkg" 'code-server)
(read-eval-program code-server)

(import "pkg::midi@://vesc_packages/lib_midi/midi.vescpkg" 'midi)
(import "lib/audible-alerts.lisp" 'audible-alerts)
(import "./assets/alerts/startup.mid" 'midi-startup)
(import "./assets/alerts/ascend.mid" 'midi-ascend)
(import "./assets/alerts/descend.mid" 'midi-descend)
(read-eval-program audible-alerts)

(start-code-server)

; NOTE: ADC App? Cruise control test?
;(app-adc-detach 2 1) ; Give LBM control over CC button
;(app-adc-override 3 1) ; Activate CC
;(app-adc-override 3 0) ; Deactivate CC

; ESC
    ; 20 SOC, Duty, Speed, Current In
    ; 21 BMS Temp, Mosfet Temp, Motor Temp, Pitch angle
    ; 22 Wh, Wh Regen, Distance, Fault
    ; 23 Current Avg, Current Max, Current Now, Batt Ah
    ; 24 VIN, Odometer, Cruise Control Set Speed
(def buf-canid20 (array-create 8))
(def buf-canid21 (array-create 8))
(def buf-canid22 (array-create 8))
(def buf-canid23 (array-create 8))
(def buf-canid24 (array-create 8))

; IO
    ; 30 Indicators, High Beam, Cruise Control Active
    ; 31 Kickstand, Drive Mode, Performance Mode
(def buf-canid30 (array-create 8))
(def buf-canid31 (array-create 8))

; BMS
    ; 35 Battery A/B SOC, Battery A/B Charge Status
(def buf-canid35 (array-create 8))

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
                (bufset-u16 buf-canid22 4 (* (/ (get-dist-abs) 1000.0) 10))
                (bufset-u16 buf-canid22 6 (get-fault))

                (bufset-u16 buf-canid23 0 (to-i (stats 'stat-current-avg)))
                (bufset-u16 buf-canid23 2 (to-i (stats 'stat-current-max)))
                (bufset-i16 buf-canid23 4 (to-i (get-current)))
                (bufset-u16 buf-canid23 6 (to-i (conf-get 'si-battery-ah)))

                (bufset-u16 buf-canid24 0 (* (get-vin) 10))
                (bufset-u32 buf-canid24 2 (* (/ (sysinfo 'odometer) 1000.0) 10))
                (bufset-u16 buf-canid24 6 (* (abs (get-speed-set)) 3.6 10))

                (sleep 0.1) ; 10 Hz
))))

; TODO: Fake indicator signals, highbeam indicator, cruise control state
(spawn (fn () {
    ; Sending initial signal that would not have measured the Indicator Duration
    (bufset-u8 buf-canid30 0 1) ; L Indicator ON
    (bufset-u8 buf-canid30 1 1) ; R Indicator ON
    (bufset-u16 buf-canid30 2 0) ; Indicator ON milliseconds
    (bufset-u8 buf-canid30 4 0) ; Highbeam OFF
    (bufset-u8 buf-canid30 5 0) ; Cruise Control OFF
    (bufset-u16 buf-canid30 6 0) ; Cruise Control Speed
    (sleep 0.65)

    (bufset-u8 buf-canid30 0 0) ; L Indicator OFF
    (bufset-u8 buf-canid30 1 0) ; R Indicator OFF
    (bufset-u16 buf-canid30 2 0) ; Indicator ON milliseconds
    (sleep 0.5)

    (var highbeam-active false)
    ; Sending indicator signals with measured Indicator Duration
    (loopwhile t
        (progn
            (if highbeam-active {
                (bufset-u8 buf-canid30 5 0) ; Cruise Control OFF
            } {
                (bufset-u8 buf-canid30 5 1) ; Cruise Control ON
            })

            (bufset-u8 buf-canid30 0 1) ; L Indicator ON
            (bufset-u8 buf-canid30 1 (if highbeam-active 1 0)) ; R Indicator ON
            (bufset-u16 buf-canid30 2 650) ; Indicator ON milliseconds
            (if highbeam-active
                (bufset-u8 buf-canid30 4 1)
                (bufset-u8 buf-canid30 4 0)
            )
            (sleep 0.65)

            (bufset-u8 buf-canid30 0 0) ; L Indicator OFF
            (bufset-u8 buf-canid30 1 (if highbeam-active 0 0)) ; R Indicator OFF
            (bufset-u16 buf-canid30 2 650) ; Indicator ON milliseconds
            (sleep 0.5)

            (setq highbeam-active (not highbeam-active))
    ))
}))

; TODO: Fake kickstand, drive mode, performance mode
(spawn (fn () (loopwhile t
    (progn
        ; Raise kickstand, put in neutral
        (bufset-u8 buf-canid31 0 1) ; Kickstand Up
        (bufset-u8 buf-canid31 1 0) ; 'neutral
        (bufset-u8 buf-canid31 2 0) ; Performance Mode ECO
        (sleep 3.0)

        ; Raise kickstand, Put in Drive
        (bufset-u8 buf-canid31 0 1) ; Kickstand Up
        (bufset-u8 buf-canid31 1 1) ; 'drive
        (bufset-u8 buf-canid31 2 1) ; Performance Mode Normal
        (sleep 2.0)

        (bufset-u8 buf-canid31 1 2) ; 'reverse
        (sleep 2.0)
        (bufset-u8 buf-canid31 1 1) ; 'drive
        (sleep 2.0)

        ; Lower kickstand, put in neutral
        (bufset-u8 buf-canid31 0 0) ; Kickstand Down
        (bufset-u8 buf-canid31 1 0) ; 'neutral
        (bufset-u8 buf-canid31 2 2) ; Performance Mode Sport
        (sleep 3.0)
))))

; Fake Battery A/B SOC and charge status
@const-end
(def fake-charge-state 0)
(def fake-charge-swap (systime))
(def fake-battery-b-connected true)
@const-start

(spawn (fn () (loopwhile t
    (progn
        (bufset-i16 buf-canid35 0 (* (get-batt) 1000)) ; Battery A SOC
        (bufset-i16 buf-canid35 2 (* (- 1.0 (get-batt)) 1000)) ; Battery B SOC
        (bufset-u8 buf-canid35 4 fake-charge-state) ; Battery A Charging
        (bufset-u8 buf-canid35 5 (if (eq fake-charge-state 1) 0 1)) ; Battery B Charging
        (bufset-u8 buf-canid35 6 (if fake-battery-b-connected 1 0))

        (if (> (secs-since fake-charge-swap) 2.0) {
            (setq fake-charge-state (if (eq fake-charge-state 1) 0 1))
            (def fake-charge-swap (systime))
        })
        (sleep 0.1)
))))


(spawn (fn () (loopwhile t
    (progn
        ; ESC
        (can-send-sid 20 buf-canid20)
        (can-send-sid 21 buf-canid21)
        (can-send-sid 22 buf-canid22)
        (can-send-sid 23 buf-canid23)
        (can-send-sid 24 buf-canid24)

        ; I/O Board
        (can-send-sid 30 buf-canid30)
        (can-send-sid 31 buf-canid31)

        ; BMS
        (can-send-sid 35 buf-canid35)

        (sleep 0.1) ; 10 Hz
))))
