
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

; Live page sources, (label unit). Stored by index, so only append.
(def slot-catalog '(
        ("Speed"      "")
        ("Battery"    "%")
        ("Motor Amps" "A")
        ("Batt Amps"  "A")
        ("Power"      "kW")
        ("Voltage"    "V")
        ("Motor Temp" "")
        ("ESC Temp"   "")
        ("Pack Temp"  "")
        ("Duty"       "%")
        ("Trip"       "")
        ("Odometer"   "")
        ("Energy"     "Wh")
        ("Regen"      "Wh")
        ("Amp Hours"  "Ah")
        ("Peak Amps"  "A")
        ("Top Speed"  "")
        ("Pitch"      "deg")
))

(defun slot-value (i)
    (cond
        ((= i 0) (u-speed stats-kmh))
        ((= i 1) (* 100.0 stats-battery-soc))
        ((= i 2) stats-amps-now)
        ((= i 3) (if (= stats-vin 0) 0.0 (/ (* stats-kw 1000.0) stats-vin)))
        ((= i 4) stats-kw)
        ((= i 5) stats-vin)
        ((= i 6) (u-temp stats-temp-motor))
        ((= i 7) (u-temp stats-temp-esc))
        ((= i 8) (u-temp stats-temp-battery))
        ((= i 9) (* stats-duty 100.0))
        ((= i 10) (u-dist stats-km))
        ((= i 11) (u-dist stats-odom))
        ((= i 12) stats-wh)
        ((= i 13) stats-wh-chg)
        ((= i 14) stats-battery-ah)
        ((= i 15) stats-amps-max)
        ((= i 16) (u-speed stats-kmh-max))
        (t stats-angle-pitch)
))

; Units that follow the unit setting rather than being fixed.
(defun slot-unit (i)
    (cond
        ((or (= i 0) (= i 16)) (u-speed-str))
        ((or (= i 6) (= i 7) (= i 8)) (u-temp-str))
        ((or (= i 10) (= i 11)) (u-dist-str))
        (t (ix (ix slot-catalog i) 1))
))

(defun slot-label (i) (ix (ix slot-catalog i) 0))

; One decimal for the small numbers, none for the ones that get large.
(defun slot-fmt (i)
    (if (or (= i 1) (= i 5) (= i 9) (= i 12) (= i 13) (= i 15)
            (= i 2) (= i 3) (= i 6) (= i 7) (= i 8))
        "%.0f" "%.1f"))
