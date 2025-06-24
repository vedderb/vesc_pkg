@const-start

(defun wait-for-esc () {
    (var spin-buf (img-buffer dm-pool 'indexed2 65 64))
    (var angle-previous 0.0)
    (var spin-time 6.0)
    (var start-time (systime))
    (loopwhile (< stats-vin 3.3) {
        ; Draw spinner
        (var scale (/ (secs-since start-time) spin-time))

        (var angle (+ angle-previous 3 (* 10 (ease-in-out-sine scale))))
        (if (> angle 360.0) (setq angle (- angle 360.0)))

        (img-clear spin-buf)
        (img-arc spin-buf 31 31 31 angle (+ angle 90) 1 '(thickness 8))
        (setq angle-previous angle)
        (disp-render spin-buf (- 160 32) (- 120 32) '(0x00 0x037bc9))

        (sleep 0.04)
    })
    (img-clear spin-buf)
    (disp-render spin-buf (- 160 32) (- 120 32) '(0x00 0x00))
    (sleep 1) ; TODO: My ESC still needed time before midi would play
})

(defun start-boot-animation () {
    (var logo icon-logo)
    (var logo-w (first (img-dims logo)))
    (var logo-h (second (img-dims logo)))

    ; Play startup tone when ESC is ready
    ;(wait-for-esc)
    ;(rcode-run-noret config-can-id-esc '(alert-startup))

    ; First stripe
    (disp-render logo (- 160 (/ logo-w 2)) (- 120 (/ logo-h 2))
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
    (disp-render logo (- 160 (/ logo-w 2)) (- 120 (/ logo-h 2))
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

        (var logo-color-a (color-mix 0x000000 0xd9dee1 pct))
        (var logo-color-b (color-mix 0x000000 0xc5c9cc pct))
        (var logo-color-c (color-mix 0x000000 0xa6aaab pct))
        (var logo-color-d (color-mix 0x000000 0x7e8283 pct))
        (var logo-color-e (color-mix 0x000000 0x575a59 pct))
        (var logo-color-f (color-mix 0x000000 0x272928 pct))

        (disp-render logo (- 160 (/ logo-w 2)) (- 120 (/ logo-h 2))
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
    (disp-render logo (- 160 (/ logo-w 2)) (- 120 (/ logo-h 2))
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
