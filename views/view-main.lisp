@const-start

(defun view-init-main  () {
    (def buf-stripe-bg (img-buffer-from-bin icon-stripe))
    (def buf-stripe-fg (img-buffer 'indexed16 141 19))
    (def buf-stripe-top (img-buffer-from-bin icon-stripe-top))
    (def buf-arrow-l (img-buffer-from-bin icon-arrow-l))
    (def buf-arrow-r (img-buffer-from-bin icon-arrow-r))
    (img-blit buf-stripe-fg buf-stripe-top 0 0 -1)

    (def buf-motor-icon (img-buffer-from-bin icon-motor))
    (def buf-esc-icon (img-buffer-from-bin icon-esc))
    (def buf-battery-icon (img-buffer-from-bin icon-battery))
    (def buf-warning-icon (img-buffer-from-bin icon-warning))

    (def buf-motor-val (img-buffer 'indexed4 59 20))
    (def buf-esc-val (img-buffer 'indexed4 59 20))
    (def buf-battery-val (img-buffer 'indexed4 59 20))

    (def buf-incline (img-buffer 'indexed4 120 35))
    (def buf-battery (img-buffer 'indexed4 42 120))
    (def buf-battery-soc (img-buffer 'indexed4 50 20))
    
    (def buf-speed (img-buffer 'indexed4 179 90))
    (def buf-units (img-buffer 'indexed4 50 15))

    (view-init-menu)
    (defun on-btn-0-long-pressed () {
        (hw-sleep)
    })
    (defun on-btn-2-pressed () {
        (setting-units-cycle)
        (setix view-previous-stats 0 'stats-kmh) ; Re-draw units
        (setix view-previous-stats 2 'stats-temp-battery)
        (setix view-previous-stats 3 'stats-temp-esc)
        (setix view-previous-stats 4 'stats-temp-motor)
    })
    (defun on-btn-2-long-pressed () {
        (setting-units-cycle-temps)
        (setix view-previous-stats 2 'stats-temp-battery)
        (setix view-previous-stats 3 'stats-temp-esc)
        (setix view-previous-stats 4 'stats-temp-motor)
    })
    (defun on-btn-3-pressed () (def state-view-next (next-view)))

    (def view-previous-stats (list 'stats-kmh 'stats-battery-soc 'stats-temp-battery 'stats-temp-esc 'stats-temp-motor 'stats-angle-pitch))

    (view-draw-menu "PWR" nil "UNITS" 'arrow-right)
    (view-render-menu)
    (disp-render buf-stripe-bg 5 68
        '(
            0x000000
            0x1d9af7 ; top fg
            0x1574b6 ; 2
            0x0e5179 ; 3
            0x143e59 ; 4
            0x0e222f ; 5
            0x00c7ff ; bottom fg
            0x10b2e6 ; 7
            0x1295bf ; 8
            0x0984ac ; 9
            0x007095 ; a
            0x0e5179 ; b
            0x08475c ; c
            0x143e59 ; d
            0x0e222f ; e
        ))
    (def buf-stripe-bg nil)

    (disp-render buf-motor-icon 4 10 colors-text-aa)
    (disp-render buf-esc-icon 63 10 colors-text-aa)
    (disp-render buf-battery-icon 132 10 colors-text-aa)
})

(defun view-draw-main () {
    (if (not-eq stats-kmh (first view-previous-stats)) {
        ; Update Speed
        (img-clear buf-units)
        (draw-units buf-units 0 0 (list 0 1 2 3) font15)

        (img-clear buf-speed)
        (var speed-now (match (car settings-units-speeds)
            (kmh stats-kmh)
            (mph (* stats-kmh km-to-mi))
            (_ (print "Unexpected settings-units-speeds value"))
        ))
        (txt-block-c buf-speed (list 0 1 2 3) 87 0 font88 (str-from-n speed-now "%0.0f"))

        ; Update Speed Arrow
        (var arrow-x-max (- 141 24))
        (def arrow-x (if (> stats-kmh-max 0.0)
            (* arrow-x-max (/ stats-kmh stats-kmh-max))
            0
        ))
        (img-blit buf-stripe-fg buf-stripe-top 0 0 -1)
        (if (> arrow-x 0) {
            ; Fill area behind arrow
            (img-rectangle buf-stripe-fg 0 0 arrow-x 19 1 '(filled))
        })
        (img-blit buf-stripe-fg buf-arrow-l arrow-x 0 -1)
        (img-blit buf-stripe-fg buf-arrow-r (+ arrow-x 12) 0 -1)
    })
    (if (not-eq (to-i (* 100 stats-battery-soc)) (second view-previous-stats)) {
        ; Update Battery %
        (img-clear buf-battery)
        (var displayed-soc (* 100 stats-battery-soc))
        (if (< displayed-soc 0) (setq displayed-soc 0))
        (draw-battery-soc buf-battery 38 (second (img-dims buf-battery)) stats-battery-soc)

        (img-clear buf-battery-soc)
        (txt-block-c buf-battery-soc (list 0 1 2 3) (/ (first (img-dims buf-battery-soc)) 2) 0 font15 (str-merge (str-from-n displayed-soc "%0.0f") "%"))
    })

    (if (not-eq stats-temp-battery (ix view-previous-stats 2)) {
        (img-clear buf-battery-val)
        (match (car settings-units-temps)
            (celsius (txt-block-c buf-battery-val (list 0 1 2 3) (/ (first (img-dims buf-battery-val)) 2) 0 font18 (str-from-n (to-i stats-temp-battery) "%dC")))
            (fahrenheit {
                (var battery-temp-f (c-to-f stats-temp-battery))
                (txt-block-c buf-battery-val (list 0 1 2 3) (/ (first (img-dims buf-battery-val)) 2) 0 font18 (str-from-n (to-i battery-temp-f) "%dF"))
            })
        )
    })
    (if (not-eq stats-temp-esc (ix view-previous-stats 3)) {
        (img-clear buf-esc-val)
        (match (car settings-units-temps)
            (celsius (txt-block-c buf-esc-val (list 0 1 2 3) (/ (first (img-dims buf-esc-val)) 2) 0 font18 (str-from-n (to-i stats-temp-esc) "%dC")))
            (fahrenheit {
                (var esc-temp-f (c-to-f stats-temp-esc))
                (txt-block-c buf-esc-val (list 0 1 2 3) (/ (first (img-dims buf-esc-val)) 2) 0 font18 (str-from-n (to-i esc-temp-f) "%dF"))
            })
        )
    })
    (if (not-eq stats-temp-motor (ix view-previous-stats 4)) {
        (img-clear buf-motor-val)
        (match (car settings-units-temps)
            (celsius (txt-block-c buf-motor-val (list 0 1 2 3) (/ (first (img-dims buf-motor-val)) 2) 0 font18 (str-from-n (to-i stats-temp-motor) "%dC")))
            (fahrenheit {
                (var motor-temp-f (c-to-f stats-temp-motor))
                (txt-block-c buf-motor-val (list 0 1 2 3) (/ (first (img-dims buf-motor-val)) 2) 0 font18 (str-from-n (to-i motor-temp-f) "%dF"))
            })
        )
    })

    (if (not-eq stats-angle-pitch (ix view-previous-stats 5)) {
        (img-clear buf-incline)
        (var hill-grade (* (tan stats-angle-pitch) 100))
        (if (> hill-grade 500) (setq hill-grade 500))
        (if (< hill-grade -500) (setq hill-grade -500))

        (var font-w (bufget-u8 font18 1))
        (var buf-height (second (img-dims buf-incline)))
        (var angle-displayed (* stats-angle-pitch 57.2958))
        (if (> angle-displayed 45.0) (setq angle-displayed 45.0))
        (if (< angle-displayed -45.0) (setq angle-displayed -45.0))
        (var half-height (/ buf-height 2.0))

        (img-line buf-incline 0 ; x1
            (+ half-height (* half-height (/ angle-displayed 45.0 ))) ;y1
            (first (img-dims buf-incline)) ;x2 at right end
            (- half-height (* half-height (/ angle-displayed 45.0 ))) ;y2
            1
        )

        ; Draw text centered over line
        (var out-str (str-merge (str-from-n (to-i hill-grade) "%d") "%"))
        (var txt-w (+ (* (bufget-u8 font18 0) (str-len out-str)) 6))
        (var font-h (bufget-u8 font18 1))
        (var half-width (/ (first (img-dims buf-incline)) 2))
        (img-rectangle buf-incline (- half-width (/ txt-w 2)) (- half-height (/ font-h 2)) txt-w font-h 0 '(filled))
        (txt-block-c buf-incline (list 0 1 2 3) (/ (first (img-dims buf-incline)) 2) 13 font18 out-str)
    })
})

(defun view-render-main () {
    (if (not-eq stats-kmh (first view-previous-stats)) {
        (disp-render buf-speed 0 105 colors-text-aa)
        (disp-render buf-units 175 197 colors-text-aa)

        (disp-render buf-stripe-fg 5 68
            '(
                0x000000
                0x1d9af7 ; top fg
                0x1574b6 ; 2
                0x0e5179 ; 3
                0x143e59 ; 4
                0x0e222f ; 5
                0x00c7ff ; bottom fg
                0x10b2e6 ; 7
                0x1295bf ; 8
                0x0984ac ; 9
                0x007095 ; a
                0x0e5179 ; b
                0x08475c ; c
                0x143e59 ; d
                0x0e222f ; e
            ))
    })
    
    (if (not-eq (to-i (* 100 stats-battery-soc)) (second view-previous-stats)) {
        (var color 0x7f9a0d)
        (if (< stats-battery-soc 0.5)
            (setq color (color-mix 0xe72a62 0xffa500 (ease-in-out-quint (* stats-battery-soc 2))))
            (setq color (color-mix 0xffa500 0x7f9a0d (ease-in-out-quint (* (- stats-battery-soc 0.5) 2))))
        )
        (disp-render buf-battery 265 95 `(0x000000 0xfbfcfc ,color 0x0000ff))
        (disp-render buf-battery-soc 261 75 colors-text-aa)
    })

    (if (not-eq stats-temp-motor (ix view-previous-stats 4)) {
        (disp-render buf-motor-val 0 44 colors-text-aa)
    })
    (if (not-eq stats-temp-battery (ix view-previous-stats 2)) {
        (disp-render buf-battery-val 124 44 colors-text-aa)
    })
    (if (not-eq stats-temp-esc (ix view-previous-stats 3)) {
        (disp-render buf-esc-val 62 44 colors-text-aa)
    })

    (if (not-eq stats-angle-pitch (ix view-previous-stats 5)) {
        (disp-render buf-incline 188 4 colors-text-aa)
    })

    (def view-previous-stats (list stats-kmh (to-i (* 100 stats-battery-soc)) stats-temp-battery stats-temp-esc stats-temp-motor stats-angle-pitch))

    (if (> (length stats-fault-codes-observed) 0) {
        (disp-render buf-warning-icon 206 46 '(0x000000 0xff0000 0x929491 0xfbfcfc))
    })
})

(defun view-cleanup-main () {
    (def buf-stripe-bg nil)
    (def buf-stripe-fg nil)
    (def buf-stripe-top nil)
    (def buf-arrow-l nil)
    (def buf-arrow-r nil)
    (def buf-motor-icon nil)
    (def buf-esc-icon nil)
    (def buf-battery-icon nil)
    (def buf-warning-icon nil)
    (def buf-motor-val nil)
    (def buf-esc-val nil)
    (def buf-battery-val nil)
    (def buf-battery nil)
    (def buf-battery-val nil)
    (def buf-speed nil)
    (def buf-units nil)
})
