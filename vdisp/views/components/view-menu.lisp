(defun view-init-menu () {
    (def buf-menu (img-buffer 'indexed4 320 25))
})

(defun view-draw-menu (button-0 button-1 button-2 button-3) {
    (img-clear buf-menu) ; TODO: Determine if re-draw is necessary
    (var btn-y 6)
    (var arrow-color 3)
    (var arrow-w 18)
    (var arrow-h 14)
    (var btn-1-center 115)
    (var btn-2-center 200)
    (var width 320)
    (var height 25)
    (img-line buf-menu 0 0 width 0 arrow-color '(thickness 2))

    (if (eq button-0 'arrow-left)
        (draw-arrow-left buf-menu 10 btn-y arrow-w arrow-h arrow-color)
        (if button-0 (txt-block-l buf-menu (list 0 1 2 3) 0 btn-y font15 (to-str button-0)))
    )

    (match button-1
        (arrow-up (draw-arrow-up buf-menu (- btn-1-center 10) btn-y arrow-h 14 arrow-color))
        (arrow-down (draw-arrow-down buf-menu (- btn-1-center 10) btn-y arrow-h 14 arrow-color))
        (_ (if button-1 (txt-block-c buf-menu (list 0 1 2 3) btn-1-center btn-y font15 (to-str button-1))))
    )

    (match button-2
        (arrow-up (draw-arrow-up buf-menu (- btn-2-center 5) btn-y arrow-h 14 arrow-color))
        (arrow-down (draw-arrow-down buf-menu (- btn-2-center 5) btn-y arrow-h 14 arrow-color))
        (_ (if button-2 (txt-block-c buf-menu (list 0 1 2 3) btn-2-center btn-y font15 (to-str button-2))))
    )

    (if (eq button-3 'arrow-right)
        (draw-arrow-right buf-menu 310 btn-y arrow-w arrow-h arrow-color)
        (if button-3 (txt-block-r buf-menu (list 0 1 2 3) 320 btn-y font15 (to-str button-3)))
    )
})

(defun view-render-menu () {
    ;(var height 25)
    (disp-render buf-menu 0 (- 240 25) '(0x000000 0x000055 0x0000aa 0x0000ff)) ; alt menu bar color 0x898989
})

(defun view-cleanup-menu () {
    (def buf-menu nil)
})
