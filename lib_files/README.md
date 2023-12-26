# Files

This library contains various files that can be used in packages for convenience, such as fonts and images.

```clj
; Fonts
(import "pkg::font_16_26@://vesc_packages/lib_files/files.vescpkg" 'font_16_26)

; Images
(import "pkg::jpg_test_160_80@://vesc_packages/lib_files/files.vescpkg" 'jpg_test_160_80)
(import "pkg::jpg_test_320_240@://vesc_packages/lib_files/files.vescpkg" 'jpg_test_320_240)
(import "pkg::jpg_test_480_320@://vesc_packages/lib_files/files.vescpkg" 'jpg_test_480_320)

; Midi Files
(import "pkg::midi_axelf_base@://vesc_packages/lib_files/files.vescpkg" 'midi_axelf_base)
(import "pkg::midi_axelf_melody@://vesc_packages/lib_files/files.vescpkg" 'midi_axelf_melody)
```