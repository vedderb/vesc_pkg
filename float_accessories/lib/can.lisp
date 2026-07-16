;@const-symbol-strings
@const-start
(def can-loop-delay)
(def fault-code 0)
(def pitch-angle 0)
(def roll-angle 0)
(def state 0)
(def sat-t 0)
(def switch-state 0)
(def handtest-mode nil)
(def rpm 0)
(def speed 0)
(def tot-current 0)
(def bat-current 0)
(def duty-cycle-now 0)
(def distance-abs -1)
(def fet-temp-filtered 0)
(def motor-temp-filtered 0)
(def odometer -1)
(def can-id -1)
(def bms-can-id -1)
(def bms-is-charging nil)
(def bms-charger-just-plugged nil)
(def bms-charger-plug-in-time 0)
(def vin -1)
(def last-running-state-time 0)
(def battery-percent-remaining 0.0)
(def footpad-adc1-t 0.0)
(def footpad-adc2-t 0.0)
(def series-cells -1)
(def refloat-humidity nil)
(def soc-type 0)
(def cell-type)
(def voltage-curve)
(def need-fetch-cells nil)
(def last-fetch-cells-time 0)

(def FLOAT_MAGIC 101)
(def FLOAT_ACCESSORIES_MAGIC 102)

(def float-cmds '(
    (COMMAND_GET_INFO . 0)
    (COMMAND_GET_ALLDATA . 10)
    (COMMAND_HUMIDITY . 51)
))

(def float-accessories-cmds '(
    (COMMAND_GET_INFO . 0)
    (COMMAND_RUN_LISP . 1)
    (COMMAND_BMS_STATUS . 2)
))

(def discover-can-id -1)

(defun running-state (){
    (let ret (and (>= state 1) (<= state 5)))
})

(defun can-loop (){
    (setq can-loop-delay (get-config 'can-loop-delay))
    (var next-run-time (secs-since 0))
    (var loop-start-time 0)
    (var loop-end-time 0)
    (var can-loop-delay-sec (/ 1.0 can-loop-delay))
    (init-can)
    (loopwhile t {
        (setq loop-start-time  (secs-since 0))
        (float-cmd can-id (list (assoc float-cmds 'COMMAND_GET_ALLDATA) 3))
        (if (and refloat-humidity (get-config 'humidity-enabled)) (float-cmd can-id (list (assoc float-cmds 'COMMAND_HUMIDITY) (to-byte hum))))

        (if (or (>= bms-can-id 0) (< (secs-since bms-last-activity-time) 1)){
            (var prev-charging-state bms-is-charging)
            (setq bms-is-charging (and (> (get-bms-val 'bms-v-charge) 10.0) (> (abs(get-bms-val 'bms-i-in-ic)) 0.1)))

            (if (and bms-is-charging (not prev-charging-state)){
                    (setq bms-charger-just-plugged t)
                    (setq bms-charger-plug-in-time (secs-since 0))
            })
            ; Check if we're within 5 seconds of initial plug-in and charging started
            (if (not (and bms-charger-just-plugged (<= (- (secs-since 0) bms-charger-plug-in-time) 5))){
                ; Reset the flag if more than 5 seconds have passed
                (setq bms-charger-just-plugged nil)
            })
        })

        (setq loop-end-time (secs-since 0))
        (var actual-loop-time (- loop-end-time loop-start-time))

        (if need-fetch-cells {
            (setq need-fetch-cells nil)
            (setq last-fetch-cells-time (secs-since 0))
            (fetch-series-cells)
            (apply-battery-config (get-config 'soc-type) (get-config 'cell-type))
        })

        (var time-to-wait (- next-run-time (secs-since 0)))
        (if (> time-to-wait 0) {
            (yield (* time-to-wait 1000000))
        } {
            (setq next-run-time (secs-since 0))
        })
        (setq next-run-time (+ next-run-time can-loop-delay-sec))
    })
})

(defun fetch-series-cells () {
    (if (>= can-id 0) {
        (var cells 0)
        (if (> (get-bms-val 'bms-can-id) -1) (setq cells (get-bms-val 'bms-cell-num)))
        (if (= cells 0) {
            (print "No BMS info; querying ESC for series cells...")
            (var response)
            
            ; Spawn thread to receive CAN response
            (loopwhile-thd 35 (eq response nil) {
                (setq response (canmsg-recv 0 5)) ; Blocks until message or 'timeout
            })

            ; Send ESC query
            (can-cmd can-id (str-merge
                "(progn "
                "(var resp (array-create 4)) "
                "(bufset-i32 resp 0 (conf-get 'si-battery-cells)) "
                "(canmsg-send " (str-from-n (can-local-id)) " 0 resp) "
                "(free resp))"
            ))

            ; Busy wait until thread updates response
            (loopwhile (eq response nil) {
                (sleep 0.01) ; Light spin, prevent CPU hammering
            })

            ; Evaluate the response
            (if (not (eq response 'timeout)) {
                (setq series-cells (bufget-i32 response 0))
                (print (str-merge "Battery cells (from ESC): " (str-from-n series-cells)))
            } {
                (print "ESC query for series cells timed out")
            })
        } {
            (setq series-cells cells)
            (print (str-merge "Battery cells (from BMS): " (str-from-n series-cells)))
        })
    })
})

(defun get-voltage-curve (cell-type)
    (cond
        ((= cell-type 0) { ; Linear
            (list 4.20 4.05 3.90 3.75 3.60 3.45 3.30 3.15 3.00 2.85 2.7)
        })
        ((= cell-type 1) { ; P28A
            (list 4.14 4.09 3.98 3.88 3.77 3.69 3.63 3.55 3.45 3.24 2.9)
        })
        ((= cell-type 2) { ; P30B
           (list 4.14 4.09 3.98 3.88 3.77 3.69 3.63 3.55 3.45 3.24 2.9)
        })
        ((= cell-type 3) { ; P42A
            (list 4.14 4.05 3.91 3.83 3.74 3.65 3.57 3.48 3.38 3 2.8)
        })
        ((= cell-type 4) { ; P45B
            (list 4.14 4.08 4.00 3.91 3.82 3.73 3.64 3.56 3.45 3.23 2.9)
        })
        ((= cell-type 5) { ; P50B
            (list 4.15 4.047 3.96 3.88 3.79 3.70 3.595 3.466 3.29 3.03 2.85)
        })
        ((= cell-type 6) { ; DG40
            (list 4.15 4.02 3.91 3.83 3.75 3.61 3.49 3.35 3.17 2.81 2.7)
        })
        ((= cell-type 7) { ; 50S
            (list 4.15 4.04 3.90 3.82 3.74 3.64 3.52 3.38 3.16 3.0 2.9)
        })
        ((= cell-type 8) { ; VTC6
            (list 4.14 4.00 3.9 3.8 3.7 3.6 3.5 3.4 3.3 3.1 2.8)
        })
        (true { ; Any other value we return Linear
            (list 4.20 4.05 3.90 3.75 3.60 3.45 3.30 3.15 3.00 2.85 2.7)
        })
    )
)

(defunret init-can () {
    (var can-devices '())
    (var original-can-id (get-config 'can-id ))
    (set-config 'can-id -1)
    (var init-time (systime))
    (loopwhile (<= (secs-since init-time) 10) {
        (if (and (>= original-can-id 0) (<= (secs-since init-time) 5)){
            (setq can-devices (list original-can-id))
        }{
            ; `can-scan` is a native C function that halts LispBM for ~2.5 seconds.
            ; We reimplement it cooperatively using `can-ping` and yielding in between
            ; (supported on firmware 6.6 and newer).
            (setq can-devices '())
            (if (not (is-606-or-newer)) {
                (setq can-devices (can-scan))
                (loopforeach probe-id can-devices {
                    (print (str-merge "Found CAN device at ID: " (str-from-n probe-id)))
                })
            } {
                (looprange probe-id 0 254 {
                    (if (can-ping probe-id) {
                        (print (str-merge "Found CAN device at ID: " (str-from-n probe-id)))
                        (setq can-devices (append can-devices (list probe-id)))
                    })
                    (sleep 0.005) ; 5ms cooperative yield to let LEDs run without stutter
                })
            })
        })
        (loopforeach can-id can-devices {
            (setq discover-can-id can-id)
            (float-cmd can-id (list (assoc float-cmds 'COMMAND_GET_ALLDATA) 3))
            (yield 500000)
            (if (>= (get-config 'can-id ) 0) {
                (if (not-eq (get-config 'can-id ) original-can-id) {
                    (ext-facfg-store)
                })
                (fetch-series-cells)
                (float-cmd can-id (list (assoc float-cmds 'COMMAND_HUMIDITY)))
                (apply-battery-config (get-config 'soc-type) (get-config 'cell-type))
                (return 1)
            })
        })
    })
    (return 0)
})

(defun float-cmd (can-id cmd) {
    (send-data (append (list FLOAT_MAGIC) cmd) 2 can-id)
})

(defun float-accessories-command-rx (data) {
    (match (cossa float-accessories-cmds (bufget-u8 data 1))
        ;(COMMAND_GET_INFO {
        ;})
        (COMMAND_RUN_LISP {
            (var payload-len (- (buflen data) 2))
            (var payload (bufcreate payload-len))
            (bufcpy payload 0 data 2 payload-len)
            (eval (read payload))
            (free payload)
        })
        (COMMAND_BMS_STATUS {
            (var send-buffer (bufcreate 3))
            (bufset-u8 send-buffer 0 FLOAT_ACCESSORIES_MAGIC)
            (bufset-u8 send-buffer 1 (assoc 'COMMAND_BMS_STATUS float-accessories-cmds))
            (bufset-u8 send-buffer 2 bms-status)
            (send-data send-buffer 2 can-id)
            (free send-buffer)
        })
        (_ nil) ; Ignore other commands
    )
})

(defun float-pkg-telemetry-rx (data) {
    (var time-since-last-can (- (systime) can-last-activity-time))
    (setq can-last-activity-time (systime))
    (match (cossa float-cmds (bufget-u8 data 1))
        (COMMAND_GET_ALLDATA {
            (if (or (< can-id 0) (> time-since-last-can 5000000)) {
                (set-config 'can-id discover-can-id)
                (setq can-id discover-can-id)
                (setq bms-can-id (get-bms-val 'bms-can-id))
                ; Only re-fetch if cells aren't already known and we haven't tried recently
                (if (and (< series-cells 1) (> (secs-since last-fetch-cells-time) 10)) {
                    (setq need-fetch-cells t)
                })
            })
            (if  (> (buflen data) 3){
                (var mode (bufget-u8 data 2))

                (if (= mode 69) {
                    (setq fault-code (bufget-u8 data 3))
                }{
                    (setq fault-code 0)
                    (if (>= (buflen data) 32) {
                        (setq roll-angle (/ (to-float (bufget-i16 data 7)) 10))
                        (var state-byte (bufget-u8 data 9))
                        (setq state (bitwise-and state-byte 0x0F))
                        (setq sat-t (shr state-byte 4))
                        (var switch-state-byte (bufget-u8 data 10))
                        (setq switch-state (bitwise-and switch-state-byte 0x07))
                        ;(var beep-reason-t (shr switch-state-byte 4))
                        (setq handtest-mode (= (bitwise-and switch-state-byte 0x08) 0x08))
                        (setq footpad-adc1-t (/ (to-float (bufget-u8 data 11)) 50))
                        (setq footpad-adc2-t (/ (to-float (bufget-u8 data 12)) 50))
                        (if (= switch-state 2) {
                            (setq switch-state 3)
                        })
                        (if (= switch-state 1) {
                            (if (> footpad-adc2-t footpad-adc1-t) {
                                (setq switch-state 2)
                            })
                        })
                        (setq pitch-angle (/ (to-float (bufget-i16 data 19)) 10))
                        (setq vin (/ (to-float (bufget-i16 data 22)) 10))
                        (if (= soc-type 1) { ; Use voltage curve
                            (setq battery-percent-remaining (/ (estimate-soc (/ vin series-cells) voltage-curve) 100))
                        })
                        (setq rpm (/ (to-float  (bufget-i16 data 24)) 10))
                        (setq speed (/ (to-float (bufget-i16 data 26)) 10))
                        (setq tot-current (/ (to-float (bufget-i16 data 28)) 10))
                        (setq bat-current (/ (to-float (bufget-i16 data 30)) 10))
                        (setq duty-cycle-now (/ (to-float (- (bufget-u8 data 32) 128)) 100))
                        (if (>= mode 2) {
                            (setq distance-abs (bufget-f32 data 34))
                            (setq fet-temp-filtered (/ (bufget-u8 data 38) 2.0))
                            (setq motor-temp-filtered (/ (bufget-u8 data 39) 2.0))
                        })
                        (if (>= mode 3) {
                            (setq odometer (bufget-u32 data 41))
                            
                            (if (= soc-type 0) { ; Ignore if using custom curves
                                (setq battery-percent-remaining (/ (to-float (bufget-u8 data 53)) 200))
                            })
                        })
                    })
                })
            })
        })
        (COMMAND_HUMIDITY {
            (setq refloat-humidity t)
            ;(print "Refloat Humidity supported")
        })
        (_ nil)
    )
})
@const-end

