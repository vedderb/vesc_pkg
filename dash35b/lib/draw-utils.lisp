@const-start

(defun ttf-txt-center (txt font imgbuf) {
        (var (w-txt h-txt) (ttf-text-dims font txt))
        (var (w-glyph h-glyph) (ttf-glyph-dims font "D"))
        (var (w-img h-img) (img-dims imgbuf))

        (var colors (if (ix (rest-args) 0) (ix (rest-args) 0) '(0 1 2 3)))
        (var py (if (ix (rest-args) 1) (ix (rest-args) 1) (+ h-glyph (/ (- h-img h-glyph) 2))))

        (ttf-text imgbuf
            (/ (- w-img w-txt) 2)
            py
            colors font txt
        )
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
