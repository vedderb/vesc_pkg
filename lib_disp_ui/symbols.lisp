@const-start

; Power Symbol
(defun sym-pwr (img col cx cy rad fill) {
        (setq fill (m-trunc fill 0.0 1.0))
        (var attr (list 'thickness (* rad 0.2)))
        (var attr2 (list 'thickness (* rad 0.1)))
        (img-arc img cx (+ cy (* rad 0.2)) (* rad 0.8) (+ -50 (* fill 260)) -130 col attr '(rounded))
        (img-line img cx cy cx (- cy (* 0.5 rad)) col attr2 '(rounded))
})

@const-end
