@const-start

(defun colors-make-aa (color1 color2 num) {
        (var colors (range num))

        (looprange i 0 num {
                (setix colors i (color-mix color1 color2 (/ (to-float i) (- num 1))))
        })

        colors
})

(def colors-theme-2 (colors-make-aa 0x000000 0x00BFFF 2))
(def colors-speed (list 0 0x006D8C 0x00C8FF 0xffffff))
(def colors-charging (list 0 0x00C321 0x00C8FF 0xffffff))

(def colors-vesc (colors-make-aa 0x000000 0xF05A22 4))
(def colors-red-icon (colors-make-aa 0x000000 0xff0303 4))
(def colors-green-icon (colors-make-aa 0x000000 (color-make 0.0 0.9 0.0) 4))
(def colors-blue-icon (colors-make-aa 0x000000 0x1d00e8 4))
(def colors-dim-icon (colors-make-aa 0x000000 (color-make 0.2 0.2 0.2) 4))
(def colors-white-icon (colors-make-aa 0x000000 0xfbfcfc 4))
(def colors-purple-icon (colors-make-aa 0x000000 0x9f20f1 4))

(def colors-text-aa (colors-make-aa 0x000000 0xfbfcfc 4))
(def colors-white-aa (colors-make-aa 0x000000 0xffffff 4))

@const-end
