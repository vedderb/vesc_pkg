; State
(def log-running false)
(def last-can-id -1)

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
        ("Input Voltage" "V"            (get-vin))
        ("Current" "A"                  (get-current))
        ("Current In" "A"               (get-current-in))
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
))

(defun merge-lists (list-with-lists) (foldl append () list-with-lists))

(def fw-num (+ (first (sysinfo 'fw-ver)) (* (second (sysinfo 'fw-ver)) 0.01)))
(if (>= fw-num 6.02)
    (def is-esc (eq (sysinfo 'hw-type) 'hw-esc))
    (def is-esc true)
)

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
                    (if (and is-esc log-local) loglist-local ())
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

(defun stop-log (id)
    (progn
        (log-stop id)
        (if log-running
            (progn
                (def log-running false)
                (wait log-thd-id)
                (send-data "Log stopped")
        ))
))

(defun save-config (id append-gnss log-local log-can log-bms rate at-boot)
    (progn
        (write-setting 'can-id id)
        (write-setting 'log-at-boot at-boot)
        (write-setting 'log-rate rate)
        (write-setting 'append-gnss append-gnss)
        (write-setting 'log-local log-local)
        (write-setting 'log-can log-can)
        (write-setting 'log-bms log-bms)
        (send-data "Settings Saved!")
))

(defun event-handler ()
    (loopwhile t
        (recv
            ((event-data-rx ? data) (eval (read data)))
            (event-shutdown (stop-log last-can-id))
            (_ nil) ; Ignore other events
)))

(event-register-handler (spawn event-handler))
(event-enable 'event-data-rx)
(if is-esc
    (event-enable 'event-shutdown)
)

(defun vin-hw ()
    (if is-esc
        (get-vin)
        (if (can-list-devs)
            (canget-vin (first (can-list-devs)))
            20.0
        )
))

; Voltage monitor thread that stops logging if the voltage drops too low
(spawn 50 (fn ()
        (loopwhile t
            (progn
                (if (< (vin-hw) vin-min)
                    (progn
                        (stop-log last-can-id)
                        (sleep 1)
                ))
                (sleep 0.01)
))))

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

(defun restore-settings ()
    (progn
        (write-setting 'can-id -1)
        (write-setting 'log-at-boot false)
        (write-setting 'log-rate 10)
        (write-setting 'append-gnss true)
        (write-setting 'log-local true)
        (write-setting 'log-can false)
        (write-setting 'log-bms false)
        (write-setting 'ver-code settings-version)
))

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

; Restore settings if version number does not match
; as that probably means something else is in eeprom
(if (not-eq (read-setting 'ver-code) settings-version) (restore-settings))

; Avoid delay in case this script is imported and executed.
(spawn (fn ()
        (progn
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
)))
