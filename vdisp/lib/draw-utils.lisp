(def dm-pool (dm-create 25600))

@const-start

(def pi 3.141592)

(defun ease-in-out-quint (x)
    (if (< x 0.5)
        (* 16 x x x x x)
        (- 1 (/ (pow (+ (* -2.0 x) 2.0) 5) 2.0))
    )
)

(defun ease-in-sine (x)
    (/ (- 1 (cos (* x pi))) 2)
)

(defun ease-out-sine (x)
    (sin (/ (* x pi) 2))
)

(defun ease-in-out-sine (x)
    (/ (- (cos (* x pi)) -1) 2)
)

; Rotates a point around the origin in the clockwise direction. (note that the
; coordinate system is upside down). The returned position is a list containing
; the x and y coordinates. Angle is in degrees.
(defun rot-point-origin (x y angle) {
    (var s (sin (deg2rad angle)))
    (var c (cos (deg2rad angle)))

    (list
        (- (* x c) (* y s))
        (+ (* x s) (* y c))
    )
})

; Right aligned text block
(defun txt-block-r (img col x y font txt) {
    (if (eq (type-of txt) type-array) (setq txt (list txt)))

    (var rows (length txt))
    (var font-w (bufget-u8 font 0))
    (var font-h (bufget-u8 font 1))

    (looprange i 0 rows {
            (var chars (str-len (ix txt i)))

            (if (eq (type-of col) type-list)
                (img-text img
                    (- x (* chars font-w))
                    (+ y (* i font-h))
                    col font (ix txt i)
                )
                (img-text img
                    (- x (* chars font-w))
                    (+ y (* i font-h))
                    col -1 font (ix txt i)
                )
            )
    })
})

; TODO: This overrides the original implementation
; TODO: This does not center the y to make it easier to align with txt-block-l and txt-block-r
; Centered text block
(defun txt-block-c (img col cx y font txt) {
    (if (eq (type-of txt) type-array) (setq txt (list txt)))

    (var rows (length txt))
    (var font-w (bufget-u8 font 0))
    (var font-h (bufget-u8 font 1))

    (looprange i 0 rows {
            (var chars (str-len (ix txt i)))

            (if (eq (type-of col) type-list)
                (img-text img
                    (- cx (* font-w chars 0.5))
                    (+ y (* i font-h))
                    col font (ix txt i)
                )

                (img-text img
                    (- cx (* font-w chars 0.5))
                    (+ y (* i font-h))
                    col -1 font (ix txt i)
                )
            )
    })
})

(defun txt-block-v (img col tc x y w h font txt) {
    (var buf-temp (img-buffer dm-pool 'indexed4 h w)) ; Create rotated buffer for img-blit
    (img-clear buf-temp (first col))

    (txt-block-c buf-temp col (/ h 2) 0 font txt)

    (img-blit img buf-temp (+ w x) y tc '(rotate 0 0 -90))
})

(defun draw-battery-horizontal (img x y w h soc line-w color-bg color-fg) {
    (if (< soc 0.0) (setq soc 0.0))
    (if (> soc 1.0) (setq soc 1.0))

    (var nub-width (- w (* w 0.93)))
    (var nub-indent (/ h 6))
    ; Outline
    (img-rectangle img x y (- w line-w nub-width) (- h line-w) color-bg `(thickness ,line-w))
    ; Nub
    (img-rectangle img (+ x (- w line-w nub-width)) (+ y nub-indent) nub-width (- h (* nub-indent 2)) color-bg `(thickness ,line-w))

    ; Fill
    (var fill-w (* (- w nub-width (* line-w 2)) soc))
    (if (< fill-w 1) (setq fill-w 1))
    (img-rectangle
        img
        (+ x line-w)
        (+ y line-w)
        fill-w
        (- h (* line-w 2))
        color-fg '(filled))
})

(defun draw-battery-vertical (img w h soc line-w) {
    (if (< soc 0.0) (setq soc 0.0))
    (if (> soc 1.0) (setq soc 1.0))

    (var nub-bottom (- h (* h 0.93)))
    (var nub-indent (/ w 6))
    ; Outline
    (img-rectangle img 0 nub-bottom (- w line-w) (- h nub-bottom line-w) 1 `(thickness ,line-w))
    ; Nub
    (img-rectangle img nub-indent 0 (- w (* nub-indent 2)) nub-bottom 1 `(thickness ,line-w))

    ; Fill
    (var fill-h (* (- h nub-bottom (* line-w 2)) soc))
    (if (< fill-h 1) (setq fill-h 1))
    (img-rectangle
        img
        line-w
        (+ nub-bottom (- h fill-h nub-bottom line-w))
        (- w (* line-w 2)) 
        fill-h
        2 '(filled))
})

(defun draw-vertical-bar (img x y w h colors pct) {
    (var rounding (if (ix (rest-args) 0) (ix (rest-args) 0) 0))
    (var with-outline (ix (rest-args) 1))
    (var invert-direction (ix (rest-args) 2))
    (if (< pct 0.0) (setq pct 0.0))
    (if (> pct 1.0) (setq pct 1.0))

    ; Fill
    (def fill-h (floor (* (- h 2) pct)))
    (if (< fill-h 25) (setq fill-h 25))
    (img-rectangle img (+ x 1) (+ y (if invert-direction 0 (- h fill-h)) -1) (- w 2) fill-h (second colors) '(filled) `(rounded ,rounding))

    ; Outline
    (if with-outline (img-rectangle img x y w h (first colors) '(thickness 4) `(rounded ,rounding)))
})

(defun draw-units (img x y color font) {
    (txt-block-l img color x y font (to-str (cdr settings-units-speeds)))
})


(defun draw-top-speed (img x y color value font) {
    (txt-block-r img color x y font (str-from-n (to-i value) "%d"))
})

(defun draw-triangle-left (img x y w h color) {
    (var x1 x)
    (var y1 (+ y (/ h 2)))

    (var x2 (+ x w))
    (var x3 (+ x w))

    (var y2 y)
    (var y3 (+ y h))

    ;(img-triangle img x1 y1 x2 y2 x3 y3 color '(thickness 1)) ; TODO: Does not draw the shape I desire
    (img-line img x1 y1 x2 y2 1 '(thickness 1))
    (img-line img x2 y2 x3 y3 1 '(thickness 1))
    (img-line img x1 y1 x3 y3 1 '(thickness 1)) ; TODO: x1 y1 x3 y3 is not the same as x3 y3 x1 y1
})

(defun draw-arrow-up (img x y w h color) {
    (var x1 (+ x (/ w 2)))
    (var y1 y)

    (var x2 x)
    (var x3 (+ x w))

    (var y2 (+ y h))
    (var y3 (+ y h))

    (var x4 x1)
    (var y4 (+ y (* h 0.68)))

    (img-line img x1 y1 x2 y2 color '(thickness 1))

    (img-line img x2 y2 x4 y4 color '(thickness 1))
    (img-line img x3 y3 x4 y4 color '(thickness 1))

    (img-line img x1 y1 x3 y3 color '(thickness 1))
})

(defun draw-arrow-down (img x y w h color) {
    (var x1 (+ x (/ w 2)))
    (var y1 (+ y h))

    (var x2 x)
    (var x3 (+ x w))

    (var y2 y)
    (var y3 y)

    (var x4 x1)
    (var y4 (- (+ y h) (* h 0.68)))

    (img-line img x1 y1 x2 y2 color '(thickness 1))

    (img-line img x2 y2 x4 y4 color '(thickness 1))
    (img-line img x3 y3 x4 y4 color '(thickness 1))

    (img-line img x1 y1 x3 y3 color '(thickness 1))
})

(defun draw-arrow-left (img x y w h color) {
    (var x1 x)
    (var y1 (+ y (/ h 2)))

    (var x2 (+ x w))
    (var x3 (+ x w))

    (var y2 y)
    (var y3 (+ y h))

    (var x4 (+ x (* w 0.68)))
    (var y4 y1)

    (img-line img x1 y1 x2 y2 color '(thickness 1))

    (img-line img x2 y2 x4 y4 color '(thickness 1))
    (img-line img x3 y3 x4 y4 color '(thickness 1))
    
    (img-line img x1 y1 x3 y3 color '(thickness 1))
})

(defun draw-arrow-right (img x y w h color) {
    (var x1 x)
    (var y1 (+ y (/ h 2)))

    (var x2 (- x w))
    (var x3 (- x w))

    (var y2 y)
    (var y3 (+ y h))

    (var x4 (- x (* w 0.68)))
    (var y4 y1)

    (img-line img x1 y1 x2 y2 color '(thickness 1))

    (img-line img x2 y2 x4 y4 color '(thickness 1))
    (img-line img x3 y3 x4 y4 color '(thickness 1))
    
    (img-line img x1 y1 x3 y3 color '(thickness 1))
})

(defun draw-turn-animation (img left-right pct) {
    (var dots 9)
    (var dot-spacing 2)
    (var dot-w 5)
    (var dot-h 17)
    (var dots-illuminated (to-i (* dots pct)))
    (looprange i 0 dots {
        (img-rectangle img
            (* i (+ dot-w dot-spacing))
            0
            dot-w
            dot-h
            (if (eq left-right 'left)
                (if (< (- 7 i) dots-illuminated) 2 3) ; TODO: improve readability/logic
                (if (< (- i 1) dots-illuminated) 2 3) ; TODO: improve readability/logic
            )
            '(filled)
            '(rounded 2))
    })
})

; img = image buffer
; cx = X center position
; cy = Y center position
; radius = gauge radius
; color = index of color used for gauge
; color-bg = (optional) index of background color
; thickness = width of gauge arc
; quadrant = 0-3 index starting in upper left rotating clockwise
; value = 0-1.0 value for gauge
; reversed = true makes the arc run counter clockwise
; with-arrow = true draws an arrow at the current value
; value-peak = (optional) 0-1.0 value for peak
; color-peak = (optional) index of peak value color
(defun draw-gauge-quadrant (img cx cy radius color color-bg thickness quadrant value reversed with-arrow value-peak color-peak) {
    (def angle-start (match quadrant
        (0 (if reversed 270 180))
        (1 (if reversed 360 270))
        (2 (if reversed 90 360))
        (3 (if reversed 180 90))
        (_ (if reversed 270 180))
    ))

    ; Optionally draw background color for quadrant
    (if (eq (type-of color-bg) 'type-i) {
        ;(print (list (to-str quadrant) (to-str angle-start) (to-str (if reversed (- angle-start 90) (+ angle-start 90)))))
        (if reversed {
            (img-arc img cx cy radius (- angle-start 90) angle-start color-bg '(thickness 17))
        } {
            (img-arc img cx cy radius angle-start (+ angle-start 90) color-bg '(thickness 17))
        })
    })

    (def angle-end (if reversed (- angle-start (* 90 value)) (+ angle-start (* 90 value))))

    (if reversed {
        (var temp angle-end)
        (setq angle-end angle-start)
        (setq angle-start temp)
    })

    ; Optionally draw peak value
    (if (and (eq (type-of value-peak) 'type-float) (eq (type-of color-peak) 'type-i)) {
        (if reversed {
            (def angle-end-peak (- angle-end (* 90 value-peak)))
            ;(print (list "reversed" (to-i angle-end-peak) (to-i angle-end)))
            (img-arc img cx cy radius angle-end-peak angle-end color-peak '(thickness 17))
        } {
            (def angle-end-peak (+ angle-start (* 90 value-peak)))
            ;(print (list "fwd" (to-i angle-start) (to-i angle-end-peak)))
            (img-arc img cx cy radius angle-start angle-end-peak color-peak '(thickness 17))
        })

    })

    ; Arc
    (img-arc img cx cy radius angle-start angle-end color '(thickness 17))

    (if with-arrow {
        ; Draw Arrow at end Position, same color
        (def pos-inner (rot-point-origin radius 0 (if reversed angle-start angle-end)))
        (def pos-outer-l (rot-point-origin (+ radius 9) 0 (if reversed (- angle-start 2) (+ angle-end 2))))
        (def pos-outer-h (rot-point-origin (+ radius 9) 0 (if reversed (+ angle-start 2) (- angle-end 2))))
        (img-triangle img
            (+ (ix pos-inner 0) cx)
            (+ (ix pos-inner 1) cy)
            (+ (ix pos-outer-l 0) cx)
            (+ (ix pos-outer-l 1) cy)
            (+ (ix pos-outer-h 0) cx)
            (+ (ix pos-outer-h 1) cy)
            color '(filled))
    })
})

(defun create-quad-guage (img cx cy radius color color-bg) {
    (var gauge (draw-gauge-quadrant))
    (list
        (cons 'gauge buf)
        (cons 'x x)
        (cons 'y y)
        (cons 'w width)
        (cons 'h height)
        (cons 'changed false)
    )
})

; Returns a list of values of specified length, covering a specified range.
; The range is inclusive.
(defun evenly-place-points (from to len) {
    (var diff (- to from))
    (var delta (/ diff (- len 1)))

    (map (fn (n) (+ (* delta n) from)) (range len))
})

; Clamp value to range 0-1
(defun clamp01 (v)
    (cond
        ((< v 0.0) 0.0)
        ((> v 1.0) 1.0)
        (t v)
))

; Map and clamp the range min-max to 0-1
(defun map-range-01 (v min max)
    (clamp01 (/ (- (to-float v) min) (- max min)))
)

(defun max-in-list (lst) {
    (first (sort > lst))
})

(defun min-in-list (lst) {
    (first (sort < lst))
})

(defun draw-live-chart (img x y w h color thickness values) {
    (var x-pos (evenly-place-points x (+ x w) (length values)))
    (var i 0)
    (var x-pre 0)
    (var y-pre 0)
    (var val-min (min-in-list values))
    (var val-max (max-in-list values))
    (loopwhile (< i (length values)) {
        (var y-pct (if (not-eq val-min val-max)
            (map-range-01 (ix values i) val-min val-max)
            (if (= val-max 0.0) 0.0 1.0)
        ))
        (var y-pos (+ y (* (- 1.0 y-pct) (- h 5))))
        ; Special case for first item
        (if (not-eq i 0) {
            ; Draw a line from x-pre to (ix x-pos i) and y-pre to y-pos
            (img-line img x-pre y-pre (ix x-pos i) y-pos color `(thickness ,thickness))
        })
        ; Set previous values for next iteration
        (setq x-pre (ix x-pos i))
        (setq y-pre y-pos)
        ; Increment
        (setq i (+ i 1))
    })
    (list val-min val-max)
})

; Rotates a point around the origin in the clockwise direction. (note that the
; coordinate system is upside down). The returned position is a list containing
; the x and y coordinates. Angle is in degrees.
(defun rot-point-origin (x y angle) {
    (var s (sin (deg2rad angle)))
    (var c (cos (deg2rad angle)))

    (list
        (- (* x c) (* y s))
        (+ (* x s) (* y c))
    )
})
