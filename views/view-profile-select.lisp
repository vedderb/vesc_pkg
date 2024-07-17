@const-start

(defun apply-profile-params (profile-number) {
    (var apply-success true)
    (print (str-from-n profile-number "Applying profile %d"))
    (var val-speed (read-setting (str2sym (str-from-n profile-number "pf%d-speed"))))
    (var val-break (read-setting (str2sym (str-from-n profile-number "pf%d-break"))))
    (var val-accel (read-setting (str2sym (str-from-n profile-number "pf%d-accel"))))

    ; Send values to ESC
    (if (not (esc-request `(conf-set 'max-speed ,(/ val-speed ms-to-kph)))) (setq apply-success nil))
    (if (not (esc-request `(conf-set 'l-current-min-scale ,val-break))) (setq apply-success nil))
    (if (not (esc-request `(conf-set 'l-current-max-scale ,val-accel))) (setq apply-success nil))

    (var buf-result (img-buffer 'indexed4 100 25))
    (txt-block-l buf-result
        '(0 1 2 3)
        0
        0
        font15
        (if apply-success (to-str "Set") (to-str "Not Set"))
    )
    (disp-render buf-result 5 4 '(0x000000 0x1f211f 0x4f514f 0x929491))
})

(defun view-init-profile-select () {
    (def profile-active (read-setting 'pf-active))
    (apply-profile-params (+ profile-active 1))

    (def buf-profiles (img-buffer 'indexed4 240 180))
    (def buf-title (img-buffer 'indexed4 150 25))

    (def profile-previous nil) ; Track last selection

    (defun on-btn-0-pressed () {
        (def state-view-next (previous-view))
    })

    (defun on-btn-1-pressed () {
        (if (eq profile-active 0i32)
            (setq profile-active 2i32)
            (setq profile-active (- profile-active 1))
        )
        (write-setting 'pf-active profile-active)
        (apply-profile-params (+ profile-active 1))
    })

    (defun on-btn-2-pressed () {
        (if (eq profile-active 2i32)
            (setq profile-active 0i32)
            (setq profile-active (+ profile-active 1))
        )
        (write-setting 'pf-active profile-active)
        (apply-profile-params (+ profile-active 1))
    })

    (defun on-btn-3-pressed () {
        (def state-view-next 'view-profile-edit)
    })

    ; Render menu
    (view-draw-menu 'arrow-left 'arrow-down 'arrow-up "EDIT")
    (view-render-menu)
})

(defun view-draw-profile-select () {
    (if (not-eq profile-active profile-previous) {
        (img-clear buf-title)
        (txt-block-r buf-title (list 0 1 2 3) (first (img-dims buf-title)) 0 font18 (str-from-n (+ profile-active 1) "Profile %d"))

        (img-clear buf-profiles)

        ; Background
        (var box-size '(239 179))
        (img-rectangle buf-profiles
            0
            0
            (first box-size)
            (second box-size)
            3
            '(thickness 0)
            '(rounded 10)
        )

        (var speeds-configured (list (read-setting 'pf1-speed) (read-setting 'pf2-speed) (read-setting 'pf3-speed)))
        (var speeds-max (first (sort > speeds-configured)))
        (var speeds-active (match profile-active
            (0i32 (read-setting 'pf1-speed))
            (1i32 (read-setting 'pf2-speed))
            (_ (read-setting 'pf3-speed))
        ))
        (draw-vertical-bar buf-profiles 20 15 42 120 '(1 3) (map-range-01 speeds-active 0.0 speeds-max))

        (txt-block-l buf-profiles
            '(0 1 2 3)
            10
            150
            font15
            (to-str "Speed")
        )

        ; Draw speed in bar
        (txt-block-c buf-profiles
            '(3 2 1 0)
            41
            119
            font15
            (match (car settings-units-speeds)
                    (kmh (str-from-n speeds-active "%0.0f"))
                    (mph (str-from-n (* speeds-active km-to-mi) "%0.0f"))
                )
        )

        (draw-vertical-bar buf-profiles 98 15 42 120 '(1 3) (match profile-active
            (0i32 (read-setting 'pf1-break))
            (1i32 (read-setting 'pf2-break))
            (_ (read-setting 'pf3-break))
        ))

        (txt-block-c buf-profiles
            '(0 1 2 3)
            (/ (first (img-dims buf-profiles)) 2)
            150
            font15
            (to-str "Break")
        )

        (draw-vertical-bar buf-profiles 176 15 42 120 '(1 3) (match profile-active
            (0i32 (read-setting 'pf1-accel))
            (1i32 (read-setting 'pf2-accel))
            (_ (read-setting 'pf3-accel))
        ))

        (txt-block-r buf-profiles
            '(0 1 2 3)
            (- (first (img-dims buf-profiles)) 10)
            150
            font15
            (to-str "Accel")
        )
    })
})

(defun view-render-profile-select () {
    (if (not-eq profile-active profile-previous) {
        (disp-render buf-title (- 310 (first (img-dims buf-title))) 4 '(0x000000 0x4f514f 0x929491 0xfbfcfc))

        (disp-render buf-profiles (- 160 (/ (first (img-dims buf-profiles)) 2)) 30 '(0x000000 0x4f514f 0x929491 0xfbfcfc))

        (setq profile-previous profile-active)
    })
})

(defun view-cleanup-profile-select () {
    (def buf-title nil)
    (def buf-profiles nil)
})
