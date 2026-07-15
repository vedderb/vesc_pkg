(import "express_extension_esp32c3.bin" 'lib-esp32c3)
(import "express_extension_esp32c6.bin" 'lib-esp32c6)
(import "express_extension_esp32s3.bin" 'lib-esp32s3)
(import "express_extension_esp32p4.bin" 'lib-esp32p4)

; Native libs only run on the chip they were built for, so pick the
; binary matching this hardware. Requires firmware with support for
; (sysinfo 'hw-target).
(def target (sysinfo 'hw-target))

(def lib (cond
    ((= (str-cmp target "esp32c3") 0) lib-esp32c3)
    ((= (str-cmp target "esp32c6") 0) lib-esp32c6)
    ((= (str-cmp target "esp32s3") 0) lib-esp32s3)
    ((= (str-cmp target "esp32p4") 0) lib-esp32p4)
    (t nil)
))

(if (eq lib nil)
    (print (str-merge "No native test lib for target " target))
{
    (print (str-merge "Loading native test lib for " target))
    (print (load-native-lib lib))
    (ext-test-hello)
    (print (str-merge "2.5 * 3.0 = " (str-from-n (ext-test-mul 2.5 3.0))))
    (sleep 1)
    (print (str-merge "Counter after 1s (expect ~10): " (str-from-n (ext-test-counter))))
})
