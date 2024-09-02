@const-start

(defun view-init-speed-large  () {
    (def buf-units (img-buffer 'indexed4 50 25))
    (def buf-top-speed (img-buffer 'indexed4 50 25))
    (def buf-arcs (img-buffer 'indexed4 320 58))
    (def buf-speed-large (img-buffer 'indexed4 240 128))

    (view-init-menu)
    (defun on-btn-0-pressed () (def state-view-next (previous-view)))
    (defun on-btn-1-pressed () {
        (stats-reset-max)
    })
    (defun on-btn-2-pressed () {
        (setting-units-cycle)
        (def view-previous-stats (list 'stats-kmh 'stats-kmh-max))
    })
    (defun on-btn-3-pressed () (def state-view-next (next-view)))

    (def view-changed nil)
    (def view-previous-stats (list 'stats-kmh 'stats-kmh-max))

    (view-draw-menu 'arrow-left "RESET" "UNITS" 'arrow-right)
    (view-render-menu)
})

(defun view-draw-speed-large () {
    (if (or
        (not-eq stats-kmh (first view-previous-stats))
        (not-eq stats-kmh-max (second view-previous-stats)))
    {
        (def view-changed true)
        (def view-previous-stats (list stats-kmh stats-kmh-max))

        (var value-speed-pct (if (> stats-kmh-max 0) (/ stats-kmh stats-kmh-max) 0))
        (if (> value-speed-pct 1.0) (setq value-speed-pct 1.0))

        (img-clear buf-units)
        (draw-units buf-units 0 0 (list 0 1 2 3) font15)

        (draw-double-arcs buf-arcs value-speed-pct)

        (img-clear buf-speed-large)
        (var speed-now (match (car settings-units-speeds)
            (kmh stats-kmh)
            (mph (* stats-kmh km-to-mi))
            (_ (print "Unexpected settings-units-speeds value"))
        ))
        (txt-block-c buf-speed-large (list 0 1 2 3) 120 0 font128 (str-from-n speed-now "%0.0f"))

        (img-clear buf-top-speed)
        (var speed-max-now (match (car settings-units-speeds)
            (kmh stats-kmh-max)
            (mph (* stats-kmh-max km-to-mi))
            (_ (print "Unexpected settings-units-speeds value"))
        ))
        (draw-top-speed buf-top-speed 50 0 (list 0 1 2 3) speed-max-now font18)
    })
})

(defun view-render-speed-large () {
    (if view-changed {
        (def view-changed false)
        (var colors-smalltext-aa '(0x000000 0x4f514f 0x929491 0xf4f7f9))

        (disp-render buf-units 0 5 colors-smalltext-aa)
        (disp-render buf-top-speed (- 320 50) 3 colors-smalltext-aa)
        (disp-render buf-arcs 0 20 '(0x000000 0x1e9af3 0x65d7f5 0x444444))
        (disp-render buf-speed-large 40 78 colors-text-aa)
    })
    
})

(defun view-cleanup-speed-large () {
    (def buf-units nil)
    (def buf-top-speed nil)
    (def buf-arcs nil)
    (def buf-speed-large nil)
})

(defun draw-double-arcs (img arc-value) {
    (if (> arc-value 1.0) {
        (print (str-from-n arc-value "draw-double-arcs:arc-value > 1 : %0.1f"))
        (setq arc-value 1.0)
    })
    (if (< arc-value 0.0) {
        (print (str-from-n arc-value "draw-double-arcs:arc-value < 0 : %0.1f"))
        (setq arc-value 0.0)
    })
    (var y 20)
    (var radius 375)
    (var top-center-angle 270)

    ; Upper Arc
    (var angle-limit 50)
    (var angle-start (- top-center-angle 30))
    (var angle-end (+ angle-start (* angle-limit arc-value)))
    (img-arc img 160 radius radius angle-start (+ angle-start angle-limit) 3 '(thickness 4)) ; BG
    (img-arc img 160 radius radius angle-start angle-end 2 '(thickness 4)) ; FG

    ; Lower Arc
    (img-arc img 160 (+ radius 8) radius angle-start (+ top-center-angle 30) 1 '(thickness 12))
})
