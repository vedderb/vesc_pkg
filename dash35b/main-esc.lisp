(import "pkg@://vesc_packages/lib_code_server/code_server.vescpkg" 'code-server)
(read-eval-program code-server)

(def light-on 0)
(def drive-mode 1)

(def cruise-on 0)
(def cruise-ts 0)

(def battery-a-charging false)
(def battery-a-chg-time 0.0)
(def stats-battery-ah 0.0)

(def log-running false)
(def last-can-id -1)

@const-start

(defmacro run-m2 (code) `(atomic {
            (var res nil)
            (select-motor 2)
            (setq res ,code)
            (select-motor 1)
            res
}))

(defun has-dual-motors () {
        (atomic
            (var motor-before (get-selected-motor))
            (select-motor 2)
            (var res (= (get-selected-motor) 2))
            (select-motor motor-before)
            res
        )
})

(def dual-motors (has-dual-motors))

(defun proc-sid (id data) {
        (cond
            ((= id 35) {
                    (setq battery-a-charging (= (bufget-u8 data 2) 1))
                    (setq battery-a-chg-time (bufget-u16 data 3))
                    (setq stats-battery-ah (/ (bufget-u16 data 5) 10.0))
            })

            ((= id 201) {
                    (var drive-mode-new (bufget-u8 data 0))
                    (setq light-on (bufget-u8 data 1))

                    (if (!= drive-mode drive-mode-new) (setq cruise-on 0))

                    (setq drive-mode drive-mode-new)

                    (match drive-mode
                        (0 { ; Reverse
                                (conf-set 'l-current-max-scale 0.4)
                                (conf-set 'min-speed (/ -10.0 3.6))
                                (if dual-motors {
                                        (run-m2 (conf-set 'l-current-max-scale 0.8))
                                        (run-m2 (conf-set 'max-speed (/ 10.0 3.6)))
                                })
                        })
                        (1 { ; Neutral
                                (conf-set 'l-current-max-scale 0.8)
                                (if dual-motors {
                                        (run-m2 (conf-set 'l-current-max-scale 0.8))
                                })
                        })
                        (2 { ; 1
                                (conf-set 'l-current-max-scale 0.5)
                                (conf-set 'max-speed (/ 20.0 3.6))
                                (if dual-motors {
                                        (run-m2 (conf-set 'l-current-max-scale 0.5))
                                        (run-m2 (conf-set 'max-speed (/ 20.0 3.6)))
                                })
                        })
                        (3 { ; 2
                                (conf-set 'l-current-max-scale 0.6)
                                (conf-set 'max-speed (/ 25.0 3.6))
                                (if dual-motors {
                                        (run-m2 (conf-set 'l-current-max-scale 0.6))
                                        (run-m2 (conf-set 'max-speed (/ 25.0 3.6)))
                                })
                        })
                        (4 { ; 3
                                (conf-set 'l-current-max-scale 1.0)
                                (conf-set 'max-speed (/ 200.0 3.6))
                                (if dual-motors {
                                        (run-m2 (conf-set 'l-current-max-scale 1.0))
                                        (run-m2 (conf-set 'max-speed (/ 200.0 3.6)))
                                })
                        })
                    )

                    (if (= light-on 1)
                        {
                            (set-aux 1 1)
                            (set-aux 2 1)
                        }
                        {
                            (set-aux 1 0)
                            (set-aux 2 0)
                        }
                    )
            })

            ; Event
            ((= id 250) {
                    (cond
                        ((= (bufget-u8 data 0) 0) { ; Toggle cruise control
                                (setq cruise-on (if (= cruise-on 0) 1 0))
                                (if (= cruise-on 1) (setq cruise-ts (systime)))
                        })

                        ((= (bufget-u8 data 0) 1) { ; About to turn off
                                ; store-backup is very new, so fall back to conf-store
                                ; if it does not exist using trap
                                (match (trap (store-backup))
                                    ((exit-ok (? a)) t)
                                    (_ (conf-store))
                                )
                        })
                    )
            })
        )
})

(defun event-handler ()
    (loopwhile t
        (recv
            ((event-data-rx . (? data)) (trap (eval (read data))))
            (event-shutdown (stop-log last-can-id))
            ((event-can-sid . ((? id) . (? data))) (proc-sid id data))
            (_ nil)
)))

; Local data to log
;
; Format
; (optKey optName optUnit optPrecision optIsRel optIsTime value-function)
;
; All entries except value-function are optional and
; default values will be used if they are left out.
(def loglist-local '(
        ("Input Voltage" "V"            (get-vin))
        ("Current" "A"                  (get-current 1))
        ("Current In" "A"               (get-current-in 1))
        ("Duty"                         (get-duty))
        ("RPM"                          (get-rpm))
        ("Temp Fet" "degC" 1            (get-temp-fet))
        ("Temp Motor" "degC" 1          (get-temp-mot))
        ("Batt" "%"                     (* (get-batt) 100))
        ("kmh_vesc" "km/h" "Speed VESC" (* (get-speed) 3.6))
        ("roll"                         (ix (get-imu-rpy) 0))
        ("pitch"                        (ix (get-imu-rpy) 1))
        ("yaw"                          (ix (get-imu-rpy) 2))
        ("fault"                        (get-fault))
        ("trip_vesc" "m"                (get-dist))
        ("trip_vesc_abs" "m"            (get-dist-abs))
        ("cnt_ah" "Ah" "Amp Hours"      (get-ah))
        ("cnt_wh" "Wh" "Watt Hours"     (get-wh))
        ("cnt_ah_chg" "Ah" "Ah Chg"     (get-ah-chg))
        ("cnt_wh_chg" "Wh" "Wh Chg"     (get-wh-chg))
        ("ADC1" "V"                     (get-adc 0))
        ("ADC2" "V"                     (get-adc 1))
        ("iq" "A"                       (get-iq 1))
        ("id" "A"                       (get-id 1))
        ("vq" "V"                       (get-vq 1))
        ("vd" "V"                       (get-vd 1))
        ("Fault"                        (get-fault))
        ("Drive Mode"                   (+ drive-mode 0))
))

; CAN-data template. Same format as above, but all %d in strings will
; be replaced with can-id. Id in the last field will also be replaced
; with can id.
(def loglist-can-template '(
        ("V%d Current" "A"              (canget-current id))
        ("V%d Current In" "A"           (canget-current-in id))
        ("V%d Duty"                     (canget-duty id))
        ("V%d RPM"                      (canget-rpm id))
        ("V%d Temp Fet" "degC" 1        (canget-temp-fet id))
        ("V%d Temp Motor" "degC" 1      (canget-temp-motor id))
        ("V%d ADC1" "V"                 (canget-adc id 0))
        ("V%d ADC2" "V"                 (canget-adc id 1))
        ("V%d Input Voltage" "V"        (canget-vin id))
))

(defun merge-lists (list-with-lists) (foldl append () list-with-lists))

; Scan CAN-bus and make loglists for all devices
(defun canlist-create ()
    (merge-lists
        (map
            (fn (id) ; For every CAN ID
                (map
                    (fn (row) ; For every row in template
                        (map
                            (fn (e) ; For every element in that row
                                (cond
                                    ((eq (type-of e) type-array) (str-from-n id e))
                                    ((eq (type-of e) type-list) (map (fn (x) (if (eq x 'id) id x)) e))
                                    (true e)
                                )
                            )
                            row
                        )
                    )
                    loglist-can-template
                )
            )
            (can-list-devs)
        )
    )
)

(defun bmslist-create()
    (let (
            (res ())
            (add (fn (x) (setvar 'res (append res (list x)))))
        )
        (if (< (get-bms-val 'bms-msg-age) 2)
            (progn
                (add '("bms_v_tot" "V" "BMS Voltage" (get-bms-val 'bms-v-tot)))
                (looprange i 0 (get-bms-val 'bms-cell-num)
                    (add (list (str-from-n (+ i 1) "BMS_C%d") "V" 3 (list 'get-bms-val ''bms-v-cell i)))
                )
                (add '("bms_i_in_ic" "A" "BMS Current" (get-bms-val 'bms-i-in-ic)))
                (add '("bms_soc" "%" "BMS SOC" (* (get-bms-val 'bms-soc) 100.0)))
                (add '("bms_hum" "%" "BMS Hum" (get-bms-val 'bms-hum)))
                (add '("bms_temp_hum" "degC" "BMS Temp Hum" (get-bms-val 'bms-temp-hum)))
                (looprange i 0 (get-bms-val 'bms-temp-adc-num)
                    (add (list (str-from-n (+ i 1) "BMS_T%d") "degC" 3 (list 'get-bms-val ''bms-temps-adc i)))
                )
                res
            )
            res

)))

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

; Confiure all log fields based on loglist lst
(defun log-configure (id lst) (loglist-parse id lst 'log-config-field))

; Print all parsed fields of loglist lst
(defun print-loglist (lst) (loglist-parse 0 lst
        (fn (id row key name unit precision is-rel is-time)
            (print (list key name unit precision is-rel is-time (ix (ix lst row) -1)))
)))

(defun log-thd (id rate lst)
    (loopwhile log-running
        (progn
            (log-send-f32 id 0
                (map
                    (fn (x) (eval (ix x -1)))
                    lst
                )
            )
            (sleep (/ 1.0 rate))
)))

(defun start-log (id append-gnss log-local log-can log-bms rate)
    (progn
        (def last-can-id id)
        (stop-log id)

        (def loglist (merge-lists
                (list
                    (if log-local loglist-local ())
                    (if log-can (canlist-create) ())
                    (if log-bms (bmslist-create) ())
        )))

        (if (eq loglist nil)
            (send-msg "Nothing to log. Make sure that everything on the CAN-bus has status messages enabled.")

            (progn
                (log-configure id loglist)

                (log-start
                    id ; CAN id
                    (length loglist) ; Field num
                    rate ; Rate Hz
                    true ; Append time
                    append-gnss ; Append gnss
                )

                (def log-running true)
                (def log-thd-id (spawn log-thd id rate loglist))
                (send-data "Log Started")
        ))
))

(defun stop-log (id) {
        (log-stop id)
        (if log-running {
                (def log-running false)
                (wait log-thd-id)
                (send-data "Log stopped")
        })
})

(defun save-config (id append-gnss log-local log-can log-bms rate at-boot) {
        (write-setting 'can-id id)
        (write-setting 'log-at-boot at-boot)
        (write-setting 'log-rate rate)
        (write-setting 'append-gnss append-gnss)
        (write-setting 'log-local log-local)
        (write-setting 'log-can log-can)
        (write-setting 'log-bms log-bms)
        (send-data "Settings Saved!")
})

; Persistent settings
; Format: (label . (offset type))
(def eeprom-addrs '(
        (ver-code    . (0 i))
        (can-id      . (1 i))
        (log-at-boot . (2 b))
        (append-gnss . (3 b))
        (log-rate    . (4 f))
        (log-local   . (5 b))
        (log-can     . (6 b))
        (log-bms     . (7 b))
))

(defun print-settings ()
    (loopforeach it eeprom-addrs
        (print (list (first it) (read-setting (first it))))
))

; Settings version
(def settings-version 239i32)

(defun read-setting (name)
    (let (
            (addr (first (assoc eeprom-addrs name)))
            (type (second (assoc eeprom-addrs name)))
        )
        (cond
            ((eq type 'i) (eeprom-read-i addr))
            ((eq type 'f) (eeprom-read-f addr))
            ((eq type 'b) (!= (eeprom-read-i addr) 0))
)))

(defun write-setting (name val)
    (let (
            (addr (first (assoc eeprom-addrs name)))
            (type (second (assoc eeprom-addrs name)))
        )
        (cond
            ((eq type 'i) (eeprom-store-i addr val))
            ((eq type 'f) (eeprom-store-f addr val))
            ((eq type 'b) (eeprom-store-i addr (if val 1 0)))
)))

(defun restore-settings () {
        (write-setting 'can-id (if (eq (sysinfo 'hw-type) 'hw-express) -2 2))
        (write-setting 'log-at-boot false)
        (write-setting 'log-rate 10)
        (write-setting 'append-gnss false)
        (write-setting 'log-local true)
        (write-setting 'log-can true)
        (write-setting 'log-bms false)
        (write-setting 'ver-code settings-version)
})

(defun send-settings ()
    (send-data (str-merge
            "settings "
            (str-from-n (read-setting 'can-id) "%d ")
            (if (read-setting 'log-at-boot) "1 " "0 ")
            (str-from-n (read-setting 'log-rate) "%.2f ")
            (if (read-setting 'append-gnss) "1 " "0 ")
            (if (read-setting 'log-local) "1 " "0 ")
            (if (read-setting 'log-can) "1 " "0 ")
            (if (read-setting 'log-bms) "1 " "0 ")
)))

(defun send-msg (text)
    (send-data (str-merge "msg " text))
)

(defun main () {
        (set-print-prefix "ESC-")

        (if (has-dual-motors) {
                (setq loglist-local (append
                        loglist-local
                        '(
                            ("M2 Current" "A"                  (run-m2 (get-current)))
                            ("M2 Current In" "A"               (run-m2 (get-current-in)))
                            ("M2 Duty"                         (run-m2 (get-duty)))
                            ("M2 RPM"                          (run-m2 (get-rpm)))
                            ("M2 Temp Fet" "degC" 1            (run-m2 (get-temp-fet)))
                            ("M2 Temp Motor" "degC" 1          (run-m2 (get-temp-mot)))
                            ("M2 iq" "A"                       (run-m2 (get-iq)))
                            ("M2 id" "A"                       (run-m2 (get-id)))
                            ("M2 Fault"                        (run-m2 (get-fault)))
                        )
                ))
        })

        ; Restore settings if version number does not match
        ; as that probably means something else is in eeprom
        (if (not-eq (read-setting 'ver-code) settings-version) (restore-settings))

        (event-register-handler (spawn event-handler))
        (event-enable 'event-can-sid)
        (event-enable 'event-shutdown)
        (event-enable 'event-data-rx)

        (var buf-can (array-create 8))

        (loopwhile-thd ("Send CAN" 100) t {
                (bufclear buf-can)
                (bufset-i16 buf-can 0 (* (get-batt) 1000))
                (bufset-i16 buf-can 2 (* (abs (get-duty)) 1000))
                (bufset-i16 buf-can 4 (* (abs (get-speed)) 3.6 10))
                (if dual-motors
                    {
                        (bufset-i16 buf-can 6 (* (+ (get-current-in) (run-m2 (get-current-in))) (get-vin) 0.1))
                    }
                    {
                        (bufset-i16 buf-can 6 (* (get-current-in) (get-vin) 0.1))
                    }
                )
                (can-send-sid 20 buf-can)

                (bufclear buf-can)
                (if (> (get-bms-val 'bms-temp-adc-num) 2)
                    (bufset-i16 buf-can 0 (* (get-bms-val 'bms-temps-adc 2) 10))
                    (bufset-i16 buf-can 0 0)
                )
                (bufset-i16 buf-can 2 (* (get-temp-fet) 10))
                (bufset-i16 buf-can 4 (* (get-temp-mot) 10))
                (bufset-i16 buf-can 6 (* (ix (get-imu-rpy) 1) 100))
                (can-send-sid 21 buf-can)

                (bufclear buf-can)
                (if dual-motors
                    {
                        (bufset-u16 buf-can 0 (* (+ (get-wh) (run-m2 (get-wh))) 10.0))
                        (bufset-u16 buf-can 2 (* (+ (get-wh-chg) (run-m2 (get-wh-chg))) 10.0))
                    }
                    {
                        (bufset-u16 buf-can 0 (* (get-wh) 10.0))
                        (bufset-u16 buf-can 2 (* (get-wh-chg) 10.0))
                    }
                )
                (bufset-u16 buf-can 4 (* (/ (get-dist-abs) 1000.0) 10))
                (bufset-u16 buf-can 6 (get-fault))
                (can-send-sid 22 buf-can)

                (bufclear buf-can)
                (if dual-motors
                    {
                        (bufset-u16 buf-can 0 (to-i (+ (stats 'stat-current-avg) (run-m2 (stats 'stat-current-avg)))))
                        (bufset-u16 buf-can 2 (to-i (+ (stats 'stat-current-max) (run-m2 (stats 'stat-current-max)))))
                        (bufset-i16 buf-can 4 (to-i (+ (get-current) (run-m2 (get-current)))))
                    }
                    {
                        (bufset-u16 buf-can 0 (to-i (stats 'stat-current-avg)))
                        (bufset-u16 buf-can 2 (to-i (stats 'stat-current-max)))
                        (bufset-i16 buf-can 4 (to-i (get-current)))
                    }
                )
                (bufset-u16 buf-can 6 (to-i (conf-get 'si-battery-ah)))
                (can-send-sid 23 buf-can)

                (bufclear buf-can)
                (bufset-u16 buf-can 0 (* (get-vin) 10))
                (bufset-u32 buf-can 2 (* (/ (sysinfo 'odometer) 1000.0) 10))
                (bufset-u16 buf-can 6 (* (abs (get-speed-set)) 3.6 10)) ; Cruise control speed
                ; Reserved space
                (can-send-sid 24 buf-can)

                (bufclear buf-can)
                (bufset-u8 buf-can 0 cruise-on)
                (can-send-sid 202 buf-can)

                (if (and (> (secs-since cruise-ts) 1) (< (* (abs (get-speed-set)) 3.6) 5.0)) {
                        (setq cruise-on 0)
                })

                (sleep 0.1) ; 10 Hz
        })

        (start-code-server)

        ; Wait for things to start up
        (sleep 10)

        ; Start logging at boot if configured
        (if (read-setting 'log-at-boot)
            (start-log
                (read-setting 'can-id)
                (read-setting 'append-gnss)
                (read-setting 'log-local)
                (read-setting 'log-can)
                (read-setting 'log-bms)
                (read-setting 'log-rate)
        ))
})

@const-end

(image-save)
(main)
