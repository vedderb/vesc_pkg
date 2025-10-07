
; ID 20
(def stats-battery-soc 0)
(def stats-duty 0)
(def stats-kmh 0)
(def stats-kw 0)
; ID 21
(def stats-temp-battery 0)
(def stats-temp-esc 0)
(def stats-temp-motor 0)
(def stats-angle-pitch 0)
; ID22
(def stats-wh 0)
(def stats-wh-chg 0)
(def stats-km 0)
(def stats-fault-code 0)
; ID23
(def stats-amps-avg 0)
(def stats-amps-max 0)
(def stats-amps-now 0)
(def stats-battery-ah 0)
; ID24
(def stats-vin 0)
(def stats-odom 0.0)

; Computed Statistics (resettable)
(def stats-reset-now nil)
(def stats-kmh-max 0)
(def stats-kw-max 0)
(def stats-temp-battery-max 0)
(def stats-temp-esc-max 0)
(def stats-temp-motor-max 0)
(def stats-amps-now-max 0)
(def stats-amps-now-min 0)
(def stats-fault-codes-observed (list))

; Computed Statistics (non-resettable)
(def stats-active-timer 0)
(def stats-active-timestamp nil)

@const-start

(defun stats-reset-max () {
    (def stats-reset-now true)
})

(defunret list-find (haystack needle) {
    (var i 0)
    (loopwhile (< i (length haystack)) {
        (if (eq needle (ix haystack i)) (return i))
        (setq i (+ i 1))
    })
    (return nil)
})

(defun stats-thread () {
    (loopwhile t {
        (sleep 0.05)
        (if stats-reset-now {
            (def stats-kmh-max 0)
            (def stats-kw-max 0)
            (def stats-temp-battery-max 0)
            (def stats-temp-esc-max 0)
            (def stats-temp-motor-max 0)
            (def stats-amps-now-max 0)
            (def stats-amps-now-min 0)
            (def stats-reset-now nil)
        })
    
        ; Max Speed
        (if (> stats-kmh stats-kmh-max) (def stats-kmh-max stats-kmh))
    
        ; Max KW
        (if (> stats-kw stats-kw-max) (def stats-kw-max stats-kw))

        ; Max Temps
        (if (> stats-temp-battery stats-temp-battery-max) (setq stats-temp-battery-max stats-temp-battery))
        (if (> stats-temp-esc stats-temp-esc-max) (setq stats-temp-esc-max stats-temp-esc))
        (if (> stats-temp-motor stats-temp-motor-max) (def stats-temp-motor-max stats-temp-motor))

        ; Max Amps Observed
        (if (< stats-amps-now-max stats-amps-now) (def stats-amps-now-max stats-amps-now))

        ; Min Amps Observed (Max Regen Amps)
        (if (> stats-amps-now-min stats-amps-now) (def stats-amps-now-min stats-amps-now))

        ; Fault Codes
        (if (> stats-fault-code 0) {
            ; Check if fault-code is already in list
            (if (not (list-find stats-fault-codes-observed stats-fault-code)) {
                (setq stats-fault-codes-observed (append stats-fault-codes-observed (list stats-fault-code)))
            })
        })

        ; Usage Timer - Start
        (if (and (> stats-kmh 0.0) (not stats-active-timestamp)) (def stats-active-timestamp (systime)))

        ; Usage Timer - End
        (if (and (= stats-kmh 0.0) (not-eq stats-active-timestamp nil)) {
            (var millis-active (- (systime) stats-active-timestamp))
            (setq stats-active-timer (+ stats-active-timer millis-active))
            (def stats-active-timestamp nil)
        })
    })
})

(if config-error-recovery
    (spawn (fn () (loopwhile t {
        (print "Starting stats-thread")
        (spawn-trap stats-thread)
        (recv   ((exit-error (? tid) (? e))
                    (print (str-merge "stats-thread error: " (to-str e)))
                )
                ((exit-ok (? tid) (? v)) 'ok))
        (sleep 1.0)
    })))
    (spawn stats-thread)
)
