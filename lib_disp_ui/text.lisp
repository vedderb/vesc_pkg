@const-start

; Centered text block
(defun txt-block-c (img col cx cy font txt) {
        (if (eq (type-of txt) type-array) (setq txt (list txt)))

        (var rows (length txt))
        (var font-w (bufget-u8 font 0))
        (var font-h (bufget-u8 font 1))

        (looprange i 0 rows {
                (var chars (str-len (ix txt i)))
                (img-text img
                    (- cx (* font-w chars 0.5))
                    (+ (- cy (* font-h rows 0.5)) (* i font-h))
                    col -1 font (ix txt i)
                )
        })
})

; Left aligned text block
(defun txt-block-l (img col x y font txt) {
        (if (eq (type-of txt) type-array) (setq txt (list txt)))

        (var rows (length txt))
        (var font-w (bufget-u8 font 0))
        (var font-h (bufget-u8 font 1))

        (looprange i 0 rows {
                (var chars (str-len (ix txt i)))
                (img-text img
                    x
                    (+ y (* i font-h))
                    col -1 font (ix txt i)
                )
        })
})

@const-end
