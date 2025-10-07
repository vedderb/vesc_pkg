@const-start

(defun m-trunc (v min max)
    (cond
        ((< v min) min)
        ((> v max) max)
        (t v)
))

; Button
(defun btn-simple (img col-bg col-txt ofs-x ofs-y w h font txt) {
        (img-rectangle img ofs-x ofs-y w h col-bg '(rounded 10) '(filled))
        (txt-block-c img col-txt (+ ofs-x (* w 0.5 )) (+ ofs-y (* h 0.5 )) font txt)
})

; Button with bar
(defun btn-bar (img col-bg col-txt val ofs-x ofs-y w h font txt) {
        (setq val (m-trunc val 0.0 1.0))
        (var w1 (m-trunc (* w (- 1.0 val)) 20 100))
        (img-rectangle img ofs-x ofs-y w1 h col-bg '(rounded 10) '(filled))
        (txt-block-c img col-txt (+ ofs-x (* w 0.5 )) (+ ofs-y (* h 0.5 )) font txt)
})

@const-end
