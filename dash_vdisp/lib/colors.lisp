; Rebuilt at runtime from the accent and text settings
(def color-bg 0x000000)
(def color-accent 0x00C8FF)
(def color-text 0xfbfcfc)

(def settings-slot-cols (list 0xfbfcfc 0xfbfcfc 0xfbfcfc 0xfbfcfc))

(def colors-theme-2 nil)
(def colors-speed nil)
(def colors-charging nil)
(def colors-vesc nil)
(def colors-red-icon nil)
(def colors-green-icon nil)
(def colors-blue-icon nil)
(def colors-hidden nil)
(def colors-dim-icon nil)
(def colors-white-icon nil)
(def colors-purple-icon nil)
(def colors-text-aa nil)
(def colors-slots nil)
(def colors-warn nil)
(def colors-crit nil)
(def colors-ok nil)
(def colors-ok-2 nil)
(def colors-warn-2 nil)
(def colors-crit-2 nil)
(def colors-text-sel-aa nil)
(def colors-white-aa nil)

@const-start

(defun colors-make-aa (color1 color2 num) {
        (var colors (range num))

        (looprange i 0 num {
                (setix colors i (color-mix color1 color2 (/ (to-float i) (- num 1))))
        })

        colors
})

(defun colors-shade (c f) (color-mix 0x000000 c f))

(defun colors-build () {
        (setq colors-theme-2 (colors-make-aa color-bg color-accent 2))
        (setq colors-speed
            (list color-bg (colors-shade color-accent 0.55) color-accent color-text))
        (setq colors-charging
            (list color-bg 0x00C321 color-accent color-text))

        (setq colors-vesc (colors-make-aa color-bg 0xF05A22 4))
        (setq colors-red-icon (colors-make-aa color-bg 0xff0303 4))
        (setq colors-green-icon (colors-make-aa color-bg (color-make 0.0 0.9 0.0) 4))
        (setq colors-blue-icon (colors-make-aa color-bg 0x1d00e8 4))

        ; Erases an icon's footprint. Skipping the draw would leave it on screen.
        (setq colors-hidden (colors-make-aa color-bg color-bg 4))

        (setq colors-dim-icon (colors-make-aa color-bg (color-mix color-bg color-text 0.25) 4))
        (setq colors-white-icon (colors-make-aa color-bg color-text 4))
        (setq colors-purple-icon (colors-make-aa color-bg 0x9f20f1 4))

        (setq colors-text-aa (colors-make-aa color-bg color-text 4))

        (setq colors-ok (colors-make-aa color-bg 0x00C321 4))
        (setq colors-warn (colors-make-aa color-bg 0xFFD400 4))
        (setq colors-crit (colors-make-aa color-bg 0xFF3030 4))

        ; Battery bar segments are indexed2
        (setq colors-ok-2 (colors-make-aa color-bg 0x00C321 2))
        (setq colors-warn-2 (colors-make-aa color-bg 0xFFD400 2))
        (setq colors-crit-2 (colors-make-aa color-bg 0xFF3030 2))
        (setq colors-slots (map (fn (c) (colors-make-aa color-bg c 4)) settings-slot-cols))
        (setq colors-text-sel-aa (colors-make-aa color-bg 0x00FF00 4))
        (setq colors-white-aa (colors-make-aa color-bg color-text 4))
})

(if (eq (car (trap (colors-build))) 'exit-error)
    (print "colors-build failed"))

@const-end
