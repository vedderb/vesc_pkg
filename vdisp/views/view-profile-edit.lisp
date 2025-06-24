@const-start

; Level 0: Selecting which option to edit
(defun set-menu-select-option () {
    (defun on-btn-0-pressed () {
        (def state-view-next 'view-profile-select)
    })

    ; Select previous option (wrap to end)
    (defun on-btn-1-pressed () {
        (if (eq profile-edit-item 2)
            (setq profile-edit-item-next 0)
            (setq profile-edit-item-next (+ profile-edit-item 1))
        )
    })
    ; Select next option (wrap to start)
    (defun on-btn-2-pressed () {
        (if (eq profile-edit-item 0)
            (setq profile-edit-item-next 2)
            (setq profile-edit-item-next (- profile-edit-item 1))
        )
    })

    (defun on-btn-3-pressed () {
        (setq view-profile-mode 'edit-option)
        (set-menu-edit-option)

        (def profile-edit-value (match profile-edit-item
            (0 (read-setting (str2sym (str-from-n profile-active "pf%d-speed"))))
            (1 (read-setting (str2sym (str-from-n profile-active "pf%d-brake"))))
            (2 (read-setting (str2sym (str-from-n profile-active "pf%d-accel"))))
        ))
        (def profile-edit-value-previous nil)
    })

    ; Render menu
    (view-draw-menu "BACK" 'arrow-down 'arrow-up "EDIT")
    (view-render-menu)
})

; Level 1: Editing value for selected option
(defun set-menu-edit-option () {
    (defun on-btn-0-pressed () {
        ; Switch to option selection
        (setq view-profile-mode 'select-option)
        (set-menu-select-option)
        (def profile-edit-item nil) ; Remove highlight from selected option
    })

    ; Decrease value
    (defun on-btn-1-pressed () {
        (match profile-edit-item
            (0 (if (> profile-edit-value 0.1)
                (setq profile-edit-value (- profile-edit-value 0.1))))
            (_ (if (> profile-edit-value 0.01)
                (setq profile-edit-value (- profile-edit-value 0.01))))
        )
    })
    (defun on-btn-1-repeat-press () (on-btn-1-pressed))

    ; Increase value
    (defun on-btn-2-pressed () {
        (match profile-edit-item
            (0 (if (< profile-edit-value 402.3)
                (setq profile-edit-value (+ profile-edit-value 0.1))))
            (_ (if (<= profile-edit-value 0.99)
                (setq profile-edit-value (+ profile-edit-value 0.01))))
        )
    })
    (defun on-btn-2-repeat-press () (on-btn-2-pressed))

    (defun on-btn-3-pressed () {
        ; Save user changes
        (match profile-edit-item
            (0 (write-setting (str2sym (str-from-n profile-active "pf%d-speed")) profile-edit-value))
            (1 (write-setting (str2sym (str-from-n profile-active "pf%d-brake")) profile-edit-value))
            (2 (write-setting (str2sym (str-from-n profile-active "pf%d-accel")) profile-edit-value))
        )

        ; Switch to option selection
        (setq view-profile-mode 'select-option)
        (set-menu-select-option)
        (def profile-edit-item nil) ; Remove highlight from selected option
    })
    ; Render menu
    (view-draw-menu "BACK" 'arrow-down 'arrow-up "SAVE")
    (view-render-menu)
})

(defun view-init-profile-edit () {
    (def profile-active (+ (read-setting 'pf-active) 1))

    (def buf-profile-opt0 (img-buffer dm-pool 'indexed4 305 30))
    (def buf-profile-opt1 (img-buffer dm-pool 'indexed4 220 30))
    (def buf-profile-opt2 (img-buffer dm-pool 'indexed4 220 30))

    (var buf-title (img-buffer dm-pool 'indexed4 220 25))
    (txt-block-r buf-title (list 0 1 2 3) 220 0 font18
        (str-from-n profile-active "Edit Profile %d")
    )
    (disp-render buf-title (- 310 (first (img-dims buf-title))) 4 '(0x000000 0x4f514f 0x929491 0xfbfcfc))

    (def profile-edit-item nil)
    (def profile-edit-item-next 0)
    (def profile-edit-value nil)
    (def profile-edit-value-previous nil)

    (def view-profile-mode 'select-option) ; 'select-option or 'edit-option
    (set-menu-select-option)
})

(defun view-draw-profile-edit () {
    (match view-profile-mode
        (select-option {
            (if (not-eq profile-edit-item profile-edit-item-next) {
                ; Draw saved values
                (var max-speed-kph (read-setting (str2sym (str-from-n profile-active "pf%d-speed"))))
                (match (car settings-units-speeds)
                    (kmh (txt-block-l buf-profile-opt0 (list 0 1 2 3) 0 0 font24
                        (str-merge (str-from-n max-speed-kph "Speed %0.1f") "kph")
                    ))
                    (mph (txt-block-l buf-profile-opt0 (list 0 1 2 3) 0 0 font24
                        (str-merge (str-from-n (* max-speed-kph km-to-mi) "Speed %0.1f") "mph")
                    ))
                )

                (txt-block-l buf-profile-opt1 (list 0 1 2 3) 0 0 font24
                    (str-merge (str-from-n (to-i (* (read-setting (str2sym (str-from-n profile-active "pf%d-brake"))) 100)) "Brake %d") "%")
                )

                (txt-block-l buf-profile-opt2 (list 0 1 2 3) 0 0 font24
                    (str-merge (str-from-n (to-i (* (read-setting (str2sym (str-from-n profile-active "pf%d-accel"))) 100)) "Accel %d") "%")
                )
            })
        })
        (edit-option {
            (if (not-eq profile-edit-value profile-edit-value-previous) {
                (match profile-edit-item
                    (0 {
                        (img-clear buf-profile-opt0)
                        (match (car settings-units-speeds)
                            (kmh (txt-block-l buf-profile-opt0 (list 0 1 2 3) 0 0 font24
                                (str-merge (str-from-n profile-edit-value "Speed %0.1f") "kph")
                            ))
                            (mph (txt-block-l buf-profile-opt0 (list 0 1 2 3) 0 0 font24
                                (str-merge (str-from-n (* profile-edit-value km-to-mi) "Speed %0.1f") "mph")
                            ))
                        )
                    })
                    (1 {
                        (img-clear buf-profile-opt1)
                        (txt-block-l buf-profile-opt1 (list 0 1 2 3) 0 0 font24
                            (str-merge (str-from-n (to-i (* profile-edit-value 100)) "Brake %d") "%")
                        )
                    })
                    (2 {
                        (img-clear buf-profile-opt2)
                        (txt-block-l buf-profile-opt2 (list 0 1 2 3) 0 0 font24
                            (str-merge (str-from-n (to-i (* profile-edit-value 100)) "Accel %d") "%")
                        )
                    })
                )
            })
        })
    )
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

(defun view-render-profile-edit () {
    (match view-profile-mode
        (select-option {
            (if (not-eq profile-edit-item profile-edit-item-next) {
                ; Render
                (disp-render buf-profile-opt0 5 35  (menu-option-color 0 profile-edit-item-next -1))
                (disp-render buf-profile-opt1 5 95  (menu-option-color 1 profile-edit-item-next -1))
                (disp-render buf-profile-opt2 5 155 (menu-option-color 2 profile-edit-item-next -1))
                (setq profile-edit-item profile-edit-item-next)
            })
        })
        (edit-option {
            (if (not-eq profile-edit-value profile-edit-value-previous) {
                ; Render
                (disp-render buf-profile-opt0 5 35  (menu-option-color 0 -1 profile-edit-item))
                (disp-render buf-profile-opt1 5 95  (menu-option-color 1 -1 profile-edit-item))
                (disp-render buf-profile-opt2 5 155 (menu-option-color 2 -1 profile-edit-item))
                (setq profile-edit-value-previous profile-edit-value)
            })
        })
    )
})

(defun view-cleanup-profile-edit () {
    (def buf-profile-opt0 nil)
    (def buf-profile-opt1 nil)
    (def buf-profile-opt2 nil)
})
