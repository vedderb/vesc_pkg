@const-start

; Minimum input voltage, stop logging when voltage drops lower
(def vin-min 18)

; Local data to log
;
; Format
; (optKey optName optUnit optPrecision optIsRel optIsTime value-function)
;
; All entries except value-function are optional and
; default values will be used if they are left out.
(def loglist-local '(
        ("Last Update s"                 (get-var (secs-since can-last-activity-time)))
        ("Input Voltage" "V"             (get-var vin))
        ("Current" "A"                  (get-var tot-current))
        ("Current In" "A"               (get-var bat-current))
        ("Duty"                         (get-var duty-cycle-now))
        ("Temp Fet" "degC" 1            (get-var fet-temp-filtered))
        ("Temp Motor" "degC" 1          (get-var motor-temp-filtered))
        ("kmh_vesc" "km/h" "Speed VESC" (get-var speed))
        ("roll"                         (get-var roll-angle))
        ("pitch"                        (get-var pitch-angle))
        ("fault"                        (get-var fault-code))
        ("ADC1" "V"                     (get-var footpad-adc1-t))
        ("ADC2" "V"                     (get-var footpad-adc2-t))
))

(defun loglist-parse (id lst res-fun)
    (looprange row 0 (length lst)
        (let (
                (field (ix lst row))
                (get-field
                    (fn (type default)
                        (let ((f (first field)))
                            (if (eq (type-of f) type)
                                (progn
                                    (setvar 'field (rest field))
                                    f
                                )
                                default
                ))))
                (key       (get-field type-array (str-from-n row "Field %d")))
                (unit      (get-field type-array ""))
                (name      (get-field type-array key))
                (precision (get-field type-i 2))
                (is-rel    (get-field type-symbol false))
                (is-time   (get-field type-symbol false))
            )
            (res-fun
                id ; CAN id
                row ; Field
                key ; Key
                name ; Name
                unit ; Unit
                precision ; Precision
                is-rel ; Is relative
                is-time ; Is timestamp
            )
)))
;Print all parsed fields of loglist lst
(defun print-loglist (lst) (loglist-parse 0 lst
        (fn (-2 row key name unit precision is-rel is-time)
            (print (list key name unit precision is-rel is-time (ix (ix lst row) -1)))
)))

(defun log-thd (rate lst) {
    (loopwhile log-running {
            ; Trapped: one bad field expression used to kill the writer
            ; thread silently, leaving log-running true and the UI claiming
            ; the log was still recording.
            (var r (trap (log-send-f32 -2 0
                (map
                    (fn (x) (eval (ix x -1)))
                    lst
                )
            )))
            (if (eq (ix r 0) 'exit-error) {
                (dbg-err (str-merge "sdlog write " (to-str (ix r 1))))
                (def log-running false)
            })
            (sleep (/ 1.0 rate))
            ;(print-loglist loglist)
    })
})

(defun start-log (append-gnss rate)
    (progn
        (stop-log)
        (def loglist loglist-local)
        (if (eq loglist nil)
            (progn
                (send-msg "Nothing to log. Make sure that everything on the CAN-bus has status messages enabled.")
            )

            (progn
                (loglist-parse -2 loglist-local 'log-config-field)

                (if (= (second (f-fatinfo)) 0) (dbg-warn "sdlog no SD card"))

                (log-start
                    -2 ; CAN id
                    (length loglist) ; Field num
                    rate ; Rate Hz
                    true ; Append time
                    (= append-gnss 1) ; Append gnss
                )

                (def log-running true)
                (def log-thd-id (spawn log-thd rate loglist))
                (dbg DBG-SDLOG (str-merge "sdlog start " (str-from-n (length loglist) "%d")
                    " fields " (str-from-n rate "%.1f") "Hz"))
                (send-msg "Log Started")
        ))
))

(defun stop-log ()
    (progn
        (log-stop -2)
        (if log-running
            (progn
                (def log-running false)
                (wait log-thd-id)
                (send-msg "Log stopped")
                (if (= (second (f-fatinfo)) 0) {
                    (send-msg "SD Card Error")
                })
        ))
))
; Voltage monitor thread that stops logging if the voltage drops too low
(defun logger-monitor () {
    (loopwhile t {
        (var low-vin (and (< vin vin-min) (!= vin -1)))
        (var no-card (and log-running (= (second (f-fatinfo)) 0)))
        (if (or low-vin no-card) {
            (if log-running
                (dbg-warn (if low-vin
                    (str-merge "sdlog stop, vin " (str-from-n (to-float vin) "%.1f"))
                    "sdlog stop, no SD card")))
            (stop-log)
            (sleep 1)
        })
        (sleep 0.01)
    })
})

(defun log-loop () {
    (sleep 10)
    (spawn 40 logger-monitor)
    (if (get-config 'log-enabled)
        (start-log
            (get-config 'log-append-gnss)
            (get-config 'log-rate)
    ))
})
@const-end