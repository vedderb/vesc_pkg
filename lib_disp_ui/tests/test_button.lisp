(import "pkg::font_16_26@://vesc_packages/lib_files/files.vescpkg" 'font)
(import "../text.lisp" 'disp-text)
(import "../button.lisp" 'disp-button)

(read-eval-program disp-text)
(read-eval-program disp-button)

(hw-init)

(def img (img-buffer 'indexed4 200 200))

(btn-simple img 2 1 20 20 100 50 font "Test")
(btn-simple img 2 1 20 90 120 70 font '("Line 1" "Line 2"))

(disp-render img 0 0 '(0 0xFF0000 0x003400))
