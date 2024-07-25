@const-start

(defun view-init-statistics () {
    (var buf-size 104)
    (var spacing 8)
    (var x-offs 0)
    (var y-offs 0)

    ; Quarter guage buffer (re-used for each quadrant to save memory)
    (def buf-gauge (img-buffer 'indexed16 buf-size buf-size))
    (def buf-efficiency (img-buffer 'indexed4 92 55))
    (def buf-trip (img-buffer 'indexed4 92 55))
    (def buf-range (img-buffer 'indexed4 92 55))

    (defun on-btn-0-pressed () (def state-view-next (previous-view)))
    (defun on-btn-2-pressed () {
        (setting-units-cycle)
        (setix view-previous-stats 3 'stats-km) ; Re-draw units
    })
    (defun on-btn-3-pressed () (def state-view-next (next-view)))

    ; Render menu
    (view-draw-menu 'arrow-left nil "UNITS" 'arrow-right)
    (view-render-menu)

    ; Render gauge background
    (var img (img-buffer 'indexed2 (* buf-size 2) 2))
    (img-line img spacing 0 (- (* buf-size 2) spacing -1) 0 1 '(thickness 2))
    (disp-render img (+ x-offs 2) (+ y-offs buf-size 2) '(0x000000 0x1b1b1b))

    (var img (img-buffer 'indexed2 2 (* buf-size 2)))
    (img-line img 0 spacing 0 (- (* buf-size 2) spacing -1) 1 '(thickness 2))
    (disp-render img (+ x-offs buf-size 2) (+ y-offs 2) '(0x000000 0x1b1b1b))

    ; Watch for value changes
    (def view-previous-stats (list 'stats-amps-now 'stats-wh 'stats-wh-chg 'stats-km))
})

(defun view-draw-statistics () {
    ; Drawing 3 boxes on right
    (if (not-eq stats-km (ix view-previous-stats 3)) {
        (img-clear buf-efficiency)
        (img-clear buf-trip)
        (img-clear buf-range)

        ; Watt Hours / Distance
        (var whkm 0.0)
        (if (> stats-km 0.0) (setq whkm (/ (- stats-wh stats-wh-chg) stats-km)))
        (var whmi 0.0)
        (if (> stats-km 0.0) (setq whmi (/ (- stats-wh stats-wh-chg) (* stats-km km-to-mi))))

        ; Efficiency
        (match (car settings-units-speeds)
            (kmh {
                (txt-block-l buf-efficiency (list 0 1 2 3) 0 0 font18 (list (to-str "Wh/km") (if (> whkm 10.0)
                    (str-from-n (to-i whkm) "%d")
                    (str-from-n whkm "%0.2f")
                )))
            })
            (mph {
                (txt-block-l buf-efficiency (list 0 1 2 3) 0 0 font18 (list (to-str "Wh/mi") (if (> whmi 10.0)
                    (str-from-n (to-i whmi) "%d")
                    (str-from-n whmi "%0.2f")
                )))
            })
            (_ (print "Unexpected settings-units-speeds value"))
        )

        ; Trip Distance
        (match (car settings-units-speeds)
            (kmh {
                (txt-block-l buf-trip (list 0 1 2 3) 0 0 font18 (list (to-str "Trip") (str-from-n stats-km (if (> stats-km 99.9) "%0.0fkm" "%0.1fkm"))))
            })
            (mph {
                (var stat-mi (* stats-km km-to-mi))
                (txt-block-l buf-trip (list 0 1 2 3) 0 0 font18 (list (to-str "Trip") (str-from-n stat-mi (if (> stat-mi 99.9) "%0.0fmi" "%0.1fmi"))))
            })
            (_ (print "Unexpected settings-units-speeds value"))
        )

        ; Range Estimate
        (var ah-remaining (* stats-battery-ah stats-battery-soc))
        (var wh-remaining (* ah-remaining stats-vin))
        (var range-remaining 0.0)
        (match (car settings-units-speeds)
            (kmh {
                (if (> whkm 0) (setq range-remaining (/ wh-remaining whkm)))
                (txt-block-l buf-range (list 0 1 2 3) 0 0 font18 (list (to-str "Range") (if (> range-remaining 10.0)
                    (str-from-n (to-i range-remaining) "%dkm")
                    (str-from-n range-remaining "%0.1fkm")
                )))
            })
            (mph {
                (if (> whkm 0) (setq range-remaining (/ wh-remaining whmi)))
                (txt-block-l buf-range (list 0 1 2 3) 0 0 font18 (list (to-str "Range") (if (> range-remaining 10.0)
                    (str-from-n (to-i range-remaining) "%dmi")
                    (str-from-n range-remaining "%0.1fmi")
                )))
            })
            (_ (print "Unexpected settings-units-speeds value"))
        )
    })
})

(defun view-render-statistics () {
    (var buf-size 104)
    (var spacing 8)
    (var radius 94)
    (var padding 8)
    (var x-offs 0)
    (var y-offs 0)
    (var colors-text-aa (list 0x000000 0x4f514f 0x929491 0xfbfcfc))

    (if (not-eq stats-amps-now (first view-previous-stats)) {
        ; Max Amps Regen
        (img-clear buf-gauge)
        (draw-gauge-quadrant buf-gauge buf-size buf-size radius 1 2 17 0 (if (and (< stats-amps-now 0) (< stats-amps-now-min 0)) (/ (to-float (abs stats-amps-now)) (abs stats-amps-now-min)) 0) true (< stats-amps-now 1) nil 4)
        (txt-block-r buf-gauge (list 5 6 7 8) buf-size 64 font18 (list (if (< stats-amps-now 0) (str-from-n stats-amps-now "%dA") (to-str "0A")) (str-from-n stats-amps-now-min "%dA")))
        (disp-render buf-gauge x-offs y-offs (append '(0x000000 0x0000ff 0x1b1b1b 0xfbfcfc 0x4f4f4f) colors-text-aa))

        ; Max Amps
        (img-clear buf-gauge)
        (draw-gauge-quadrant buf-gauge 0 buf-size radius 1 2 17 1 (if (and (> stats-amps-now 0) (> stats-amps-now-max 0)) (/ (to-float stats-amps-now) stats-amps-now-max) 0.0) nil (> stats-amps-now -1) (if (> stats-amps-now-max 0) (/ (to-float stats-amps-avg) stats-amps-now-max) 0) 4)
        (txt-block-l buf-gauge (list 5 6 7 8) 0 64 font18 (list (if (> stats-amps-now 0) (str-from-n stats-amps-now "%dA") (to-str "0A")) (str-from-n stats-amps-now-max "%dA")))
        (disp-render buf-gauge (+ spacing padding (+ x-offs radius)) y-offs (append '(0x000000 0x00d8ff 0x1b1b1b 0xfbfcfc 0x4f4f4f) colors-text-aa))
    })
    (if (or 
            (not-eq stats-wh (second view-previous-stats))
            (not-eq stats-wh-chg (third view-previous-stats))
        ) {
        ; Watt Hours Consumed
        (img-clear buf-gauge)
        (draw-gauge-quadrant buf-gauge 0 0 radius 1 2 17 2 (if (> stats-wh 0) (/ stats-wh (+ stats-wh stats-wh-chg)) 0) true nil nil nil)
        (var wh-out-str (cond
            ((< stats-wh 10.0) (str-from-n stats-wh "%0.1fWh"))
            ((< stats-wh 1000.0) (str-from-n (to-i stats-wh) "%dWh"))
            (_ (str-from-n (/ stats-wh 1000) "%0.1fkWh"))
        ))
        (txt-block-l buf-gauge (list 4 5 6 7) 0 0 font18 (list wh-out-str (to-str "out")))
        (disp-render buf-gauge (+ spacing padding (+ x-offs radius)) (+ spacing padding (+ y-offs radius)) (append '(0x000000 0xfbd00a 0x1b1b1b 0xfbfcfc) colors-text-aa))

        ; Watt Hours Regenerated
        (img-clear buf-gauge)
        (draw-gauge-quadrant buf-gauge buf-size 0 radius 1 2 17 3 (if (> stats-wh-chg 0) (/ stats-wh-chg (+ stats-wh stats-wh-chg)) 0) nil nil nil nil)
        (var wh-in-str (cond
            ((< stats-wh-chg 10.0) (str-from-n stats-wh-chg "%0.1fWh"))
            ((< stats-wh-chg 1000.0) (str-from-n (to-i stats-wh-chg) "%dWh"))
            (_ (str-from-n (/ stats-wh-chg 1000)"%0.1fkWh"))
        ))
        (txt-block-r buf-gauge (list 4 5 6 7) buf-size 0 font18 (list wh-in-str (to-str "in")))
        (disp-render buf-gauge x-offs (+ spacing padding (+ y-offs radius)) (append '(0x000000 0x97bf0d 0x1b1b1b 0xfbfcfc) colors-text-aa))
    })


    (if (not-eq stats-km (ix view-previous-stats 3)) {
        (var colors-text-aa '(0x000000 0x4f514f 0x929491 0xfbfcfc))
        (disp-render buf-efficiency 215 12 colors-text-aa)

        (disp-render buf-trip 215 84 colors-text-aa)

        (disp-render buf-range 215 158 colors-text-aa)
    })
    
    (def view-previous-stats (list stats-amps-now stats-wh stats-wh-chg stats-km))
})

(defun view-cleanup-statistics () {
    (def buf-gauge nil)
    (def buf-efficiency nil)
    (def buf-trip nil)
    (def buf-range nil)
})
