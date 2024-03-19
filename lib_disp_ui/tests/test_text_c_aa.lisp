(import "pkg::font_16_26@://vesc_packages/lib_files/files.vescpkg" 'font)
(import "pkg::font_16_26_aa@://vesc_packages/lib_files/files.vescpkg" 'font_aa)

(import "../text.lisp" 'disp-text)

(read-eval-program disp-text)

(hw-init)

(def img (img-buffer 'indexed4 200 200))
(txt-block-c img 3 100 50 font '("First Line" "Line 2"))
(txt-block-c img '(0 1 2 3) 100 100 font_aa '("First Line" "Line 2"))

(disp-render img 0 0 '(0 0x550000 0xAA0000 0xFF0000))
