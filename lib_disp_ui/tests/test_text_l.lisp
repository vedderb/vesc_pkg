(import "pkg::font_16_26@://vesc_packages/lib_files/files.vescpkg" 'font)
(import "../text.lisp" 'disp-text)

(read-eval-program disp-text)

(hw-init)

(def img (img-buffer 'indexed2 200 200))
(txt-block-l img 1 20 20 font '("First Line" "Line 2"))

(disp-render img 0 0 '(0 0xFF0000))
