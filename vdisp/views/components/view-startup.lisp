(defun start-boot-animation () {
    (var logo (img-buffer-from-bin icon-logo))

    ; First stripe
    (disp-render logo (- 160 (/ (first (img-dims logo)) 2)) (- 120 (/ (second (img-dims logo)) 2))
        '(  0x000000
            0x009edf
            0x007dc4
            0x005684
            0x012e47
            0x191c1c
        )
    )
    (sleep 0.5)

    ; Second stripe
    (disp-render logo (- 160 (/ (first (img-dims logo)) 2)) (- 120 (/ (second (img-dims logo)) 2))
        '(  0x000000
            0x009edf
            0x007dc4
            0x005684
            0x012e47
            0x191c1c

            0x007dc4
            0x005684
            0x012e47
            0x191c1c
        )
    )
    (sleep 0.5)

    ; VESC
    (var fade-time 2.0)
    (var start-time (systime))
    (loopwhile (< (secs-since start-time) fade-time) {
        (def pct (/ (secs-since start-time) fade-time))

        (var logo-color-a (lerp-color 0x000000 0xd9dee1 pct))
        (var logo-color-b (lerp-color 0x000000 0xc5c9cc pct))
        (var logo-color-c (lerp-color 0x000000 0xa6aaab pct))
        (var logo-color-d (lerp-color 0x000000 0x7e8283 pct))
        (var logo-color-e (lerp-color 0x000000 0x575a59 pct))
        (var logo-color-f (lerp-color 0x000000 0x272928 pct))

        (disp-render logo (- 160 (/ (first (img-dims logo)) 2)) (- 120 (/ (second (img-dims logo)) 2))
            `(  0x000000
                0x009edf
                0x007dc4
                0x005684
                0x012e47
                0x191c1c

                0x007dc4
                0x005684
                0x012e47
                0x191c1c

                ,logo-color-a
                ,logo-color-b
                ,logo-color-c
                ,logo-color-d
                ,logo-color-e
                ,logo-color-f
            )
        )
        (sleep 0.04)
    })
    (disp-render logo (- 160 (/ (first (img-dims logo)) 2)) (- 120 (/ (second (img-dims logo)) 2))
        '(  0x000000
            0x009edf
            0x007dc4
            0x005684
            0x012e47
            0x191c1c

            0x007dc4
            0x005684
            0x012e47
            0x191c1c

            0xd9dee1
            0xc5c9cc
            0xa6aaab
            0x7e8283
            0x575a59
            0x272928
        )
    )
    (setq logo nil)
    (sleep 1)
    (disp-clear)
})
