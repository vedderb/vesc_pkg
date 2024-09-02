@const-start

(defun view-init-settings () {
    (def view-settings-index nil)
    (def view-settings-index-next 0)
    (def view-settings-index-editing nil)
    (def view-settings-index-value 0)

    (def buf-bike (img-buffer 'indexed16 161 97))
    (def buf-settings-opt0 (img-buffer 'indexed4 290 25))
    (def buf-settings-opt1 (img-buffer 'indexed4 290 25))
    (def buf-settings-opt2 (img-buffer 'indexed4 290 25))
    (def buf-settings-opt3 (img-buffer 'indexed4 290 25))
    (def buf-settings-submenu (img-buffer 'indexed4 130 25))
    (txt-block-l buf-settings-submenu (list 0 1 2 3) 0 0 font24 (to-str "Save"))

    ; Get latest settings from ESC
    (def esc-opt-wheel-diameter (esc-request '(conf-get 'si-wheel-diameter)))
    (if esc-opt-wheel-diameter (setq esc-opt-wheel-diameter (* esc-opt-wheel-diameter 1000)))
    (def esc-opt-batt-cells (esc-request '(conf-get 'si-battery-cells)))
    (def esc-opt-batt-amps-max (esc-request '(conf-get 'l-current-max)))

    (defun on-btn-0-pressed () {
        (if view-settings-index-editing {
            (setq view-settings-index-editing nil)
            (view-settings-redraw)
        } (def state-view-next (previous-view)) )
    })
    (defun on-btn-1-pressed () {
        (if view-settings-index-editing {
            ; Decrease value
            (setq view-settings-index-value (- view-settings-index-value 1))
            (view-settings-redraw)
        } {
            ; Move menu down (increase value)
            (if (< view-settings-index 4)
                (setq view-settings-index-next (+ view-settings-index 1))
            )
        })
    })
    (defun on-btn-2-pressed () {
        (if view-settings-index-editing {
            ; Increase value
            (setq view-settings-index-value (+ view-settings-index-value 1))
            (view-settings-redraw)
        } {
            ; Move menu up (decrease value)
            (if (> view-settings-index 0)
                (setq view-settings-index-next (- view-settings-index 1))
            )
        })
    })
    (defun on-btn-3-pressed () {
        ; Accept current value or send to ESC depending on view-settings-index
        (match view-settings-index
            (0 {
                (if (eq view-settings-index-editing 0)
                    {
                        (var wheel-meters (/ view-settings-index-value 1000.0))
                        (esc-request `(conf-set 'si-wheel-diameter ,wheel-meters)) ; Save value to ESC
                        (setq esc-opt-wheel-diameter view-settings-index-value) ; Save value locally
                        (setq view-settings-index-editing nil) ; Clear editing value
                        (view-settings-redraw)
                    }
                    {
                        (setq view-settings-index-editing 0) ; Editing row
                        (view-settings-redraw)
                        (setq view-settings-index-value esc-opt-wheel-diameter) ; Set editing value
                    }
                )
            })
            (1 (if (eq view-settings-index-editing 1)
                {
                    (esc-request `(conf-set 'l-current-max ,view-settings-index-value)) ; Save value to ESC
                    (setq esc-opt-batt-amps-max view-settings-index-value) ; Save value locally
                    (setq view-settings-index-editing nil) ; Clear editing value
                    (view-settings-redraw)
                }
                {
                    (setq view-settings-index-editing 1) ; Editing row
                    (view-settings-redraw)
                    (setq view-settings-index-value esc-opt-batt-amps-max) ; Set editing value
                }
            ))
            (2 (if (eq view-settings-index-editing 2)
                {
                    (esc-request `(conf-set 'si-battery-cells ,view-settings-index-value)) ; Save value to ESC
                    (setq esc-opt-batt-cells view-settings-index-value) ; Save value locally
                    (setq view-settings-index-editing nil) ; Clear editing value
                    (view-settings-redraw)
                }
                {
                    (setq view-settings-index-editing 2) ; Editing row
                    (view-settings-redraw)
                    (setq view-settings-index-value esc-opt-batt-cells) ; Set editing value
                }
            ))
            (3 (if (eq view-settings-index-editing 3)
                {
                    (setq view-settings-index-editing nil) ; Clear editing value
                    (view-settings-redraw)
                }
                {
                    (setq view-settings-index-editing 3) ; Editing row
                    (view-settings-redraw)
                }
            ))
            (4 {
                ; Save settings on ESC
                (print (esc-request '(conf-store)))
                ; Return to initial view
                (def state-view-next 'view-main)
            })
        )
    })

    ; Render menu
    (view-draw-menu 'arrow-left 'arrow-down 'arrow-up "ENTER")
    (view-render-menu)
})

(defun view-settings-redraw () {
    (setq view-settings-index nil)
})

(defun view-draw-settings () {
    (if (not-eq view-settings-index view-settings-index-next) {
        (match view-settings-index
            (0 (img-clear buf-settings-opt0))
            (1 (img-clear buf-settings-opt1))
            (2 (img-clear buf-settings-opt2))
            (3 (img-clear buf-settings-opt3))
        )
        (match view-settings-index-next
            (0 (img-clear buf-settings-opt0))
            (1 (img-clear buf-settings-opt1))
            (2 (img-clear buf-settings-opt2))
            (3 (img-clear buf-settings-opt3))
        )

        ; Show latest values received from ESC
        (txt-block-l buf-settings-opt0 (list 0 1 2 3) 0 0 font24
            (str-from-n (if (eq 0 view-settings-index-editing) view-settings-index-value (to-float esc-opt-wheel-diameter)) "Wheel: %0.0fmm")
        )
        (txt-block-l buf-settings-opt1 (list 0 1 2 3) 0 0 font24
            (str-from-n (if (eq 1 view-settings-index-editing) view-settings-index-value (to-float esc-opt-batt-amps-max)) "Batt : %0.0fA"))
        (txt-block-l buf-settings-opt2 (list 0 1 2 3) 0 0 font24
            (str-from-n (if (eq 2 view-settings-index-editing) view-settings-index-value (to-i esc-opt-batt-cells)) "Batt : %dS"))
        (txt-block-l buf-settings-opt3 (list 0 1 2 3) 0 0 font24
            (to-str "Motor: Stock"))

        ; Update Bike Overlay
        (img-blit buf-bike (img-buffer-from-bin icon-bike) 0 0 -1)
        (var color-ix 6)
        (match view-settings-index-next
            (0 (img-circle buf-bike 134 69 25 color-ix '(thickness 3)))
            (1 (img-rectangle buf-bike 69 23 12 28 color-ix '(filled) '(rounded 4)))
            (2 (img-rectangle buf-bike 69 23 12 28 color-ix '(filled) '(rounded 4)))
            (3 (img-circle buf-bike 82 62 9 color-ix '(thickness 3)))
        )
    })
})

(defun menu-option-color (index highlight-index selected-index) {
    (var colors-menu '( 0x000000 0x4f514f 0x929491 0xfbfcfc))
    (var colors-menu-highlight '( 0x000000 0x113f60 0x1e659a 0x1d9aed))
    (var colors-menu-selected '( 0x000000 0x006107 0x039e06 0x0df412))

    (cond
        ((eq index selected-index) colors-menu-selected)
        ((eq index highlight-index) colors-menu-highlight)
        (_ colors-menu)
    )
})

(defun view-render-settings () {
    (if (not-eq view-settings-index view-settings-index-next) {
        (var next view-settings-index-next)

        (disp-render buf-settings-opt0 5 5 (menu-option-color 0 next view-settings-index-editing))
        (disp-render buf-settings-opt1 5 30 (menu-option-color 1 next view-settings-index-editing))
        (disp-render buf-settings-opt2 5 55 (menu-option-color 2 next view-settings-index-editing))
        (disp-render buf-settings-opt3 5 80 (menu-option-color 3 next view-settings-index-editing))
        (disp-render buf-settings-submenu 15 150 (menu-option-color 4 next view-settings-index-editing))

        (disp-render buf-bike 134 116
            '(  0x000000 0x080905 0x0f0f0c 0x1a1817 0x23201f 0x2b2726
                0x1d9aed
            ))

        (setq view-settings-index view-settings-index-next)
    })
})

(defun view-cleanup-settings () {
    (def buf-bike nil)
    (def buf-settings-opt0 nil)
    (def buf-settings-opt1 nil)
    (def buf-settings-opt2 nil)
    (def buf-settings-opt3 nil)
    (def buf-settings-submenu nil)
})
