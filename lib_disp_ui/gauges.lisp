@const-start

(defun m-trunc (v min max)
    (cond
        ((< v min) min)
        ((> v max) max)
        (t v)
))

; Round Gauge
(defun gauge-simple (img col-bg col-bar col-txt cx cy rad val font txt) {
        (setq val (m-trunc val 0.0 1.0))
        (var attr (list 'thickness (* rad 0.2)))
        (img-arc img cx cy rad 120 60 col-bg attr '(rounded))
        (img-arc img cx cy rad 120 (+ 120 (* val 300.0)) col-bar attr '(rounded))
        (txt-block-c img col-txt cx cy font txt)
})

@const-end
