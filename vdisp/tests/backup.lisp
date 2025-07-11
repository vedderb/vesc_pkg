; Test disp-text && font
(def img (img-buffer 'indexed2 200 200))
(txt-block-c img 1 100 100 font '("First Line" "Another Line"))
(disp-render img 10 10 '(0x00FF00 0xFF0000))
(sleep 0.1) (def img nil) (gc)

; Test img-line
(def img (img-buffer 'indexed2 100 100))
(img-line img 10 10 90 90 1)
(disp-render img 10 10 '(0x00FF00 0xFF0000))
(sleep 0.1) (setq img nil) (gc)

; Test button-simple
(def img (img-buffer 'indexed2 128 64))
(btn-simple img 0 1 5 5 128 64 font "butt-on") ;btn-simple (img col-bg col-txt ofs-x ofs-y w h font txt)
(disp-render img 10 10 '(0xff0000 0xffffff))
(sleep 0.1) (setq img nil) (gc)

; Test gauge-simple
(def img (img-buffer 'indexed4 220 220))
(gauge-simple img 0 1 2 104 104 104 90 font "gauge") ;gauge-simple (img col-bg col-bar col-txt cx cy rad val font txt)
(disp-render img 0 0 '(0x000000 0x00ff00 0xffffff))
(sleep 0.1) (setq img nil) (gc)

; Preview UI Loop
(defun preview-ui-loop () {
    (def preview-ui true)
    (loopwhile preview-ui {
        (disp-render-jpg preview-left 0 0)
        (sleep 5.5)
        (disp-render-jpg preview-right 0 0)
        (sleep 5.5)
    })
})

(defun draw-gauge-quadrant (img cx cy r color thickness quadrant value reversed with-arrow) {
    (def angle-start (match quadrant 
        (0 (if reversed 270 180))
        (1 (if reversed 360 270))
        (2 (if reversed 90 360))
        (3 (if reversed 180 90))
        (_ (if reversed 270 180))
    ))
    (def angle-end (if reversed (- angle-start (* 90 value)) (+ angle-start (* 90 value))))

    (if reversed {
        (var temp angle-end)
        (setq angle-end angle-start)
        (setq angle-start temp)
    })

    ; Arc
    (img-arc img cx cy r angle-start angle-end color '(thickness 17)) ;img-arc (img cx cy r ang-s ang-e color opt-attr1 ... opt-attrN)

    (if with-arrow {
        ; TODO: Draw Arrow at end Position, same color
        (def pos-inner (rot-point-origin radius 0 (if reversed angle-start angle-end)))
        (def pos-outer (rot-point-origin (+ radius 9) 0 (if reversed angle-start angle-end)))

        (img-line img (+ (ix pos-inner 0) radius) (+ (ix pos-inner 1) radius) ;img-line (img x1 y1 x2 y2 color opt-attr1 ... opt-attrN)
        (+ (ix pos-outer 0) radius) (+ (ix pos-outer 1) radius) color)

        ;(img-triangle img 30 60 160 120 10 220 1 '(filled)) ;img-triangle (img x1 y1 x2 y2 x3 y3 color opt-attr1 ... opt-attrN)
    })
})

(defun draw-test-gauges () {
    (disp-clear)
    ; Test designed gauge
    (def fake-value 0.6)
    (def radius 104)

    (def img (img-buffer 'indexed4 222 222))
    (draw-gauge-quadrant img radius radius radius 1 17 0 fake-value true true)
    (draw-gauge-quadrant img radius radius radius 2 17 1 fake-value nil true)
    (draw-gauge-quadrant img radius radius radius 3 17 2 fake-value true true)
    (draw-gauge-quadrant img radius radius radius 2 17 3 fake-value nil nil)
    (disp-render img 10 10 '(0x000000 0xff0000 0x00ff00 0x0000ff))
    (sleep 1) (setq img nil) (gc)
})

(draw-test-gauges)

;(sleep 3)
;(preview-ui-loop)
