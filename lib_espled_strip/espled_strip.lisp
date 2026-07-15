(import "espled_strip/espled_strip_esp32c3.bin" 'lib-esp32c3)
(import "espled_strip/espled_strip_esp32c6.bin" 'lib-esp32c6)
(import "espled_strip/espled_strip_esp32s3.bin" 'lib-esp32s3)
(import "espled_strip/espled_strip_esp32p4.bin" 'lib-esp32p4)

; Native libs only run on the chip they were built for. Requires firmware
; with support for (sysinfo 'hw-target).
(def target (sysinfo 'hw-target))

(def lib (cond
    ((= (str-cmp target "esp32c3") 0) lib-esp32c3)
    ((= (str-cmp target "esp32c6") 0) lib-esp32c6)
    ((= (str-cmp target "esp32s3") 0) lib-esp32s3)
    ((= (str-cmp target "esp32p4") 0) lib-esp32p4)
    (t nil)
))

(if (eq lib nil)
    (print (str-merge "fled: no native lib for target " target))
    (load-native-lib lib)
)

; Convenience used by the test UI: single strip on one pin as segment 0.
; timing: 0 generic, 1 WS2812B, 2 WS2815, 3 SK6812, 4 SK6815.
(defun espled-setup (pin len type timing) {
    (ext-espled-deinit)
    (ext-espled-seg-def 0 pin type len 0 timing)
    (ext-espled-init 1)
})

; The test UI sends lisp expressions as custom app data - evaluate them.
; Other UIs (e.g. a FloWLED page stored on the device) send binary
; commands on the same channel - ignore anything that is not a lisp
; expression instead of raising read errors.
(defun event-handler ()
    (loopwhile t
        (recv
            ((event-data-rx . (? data))
                (if (and (> (buflen data) 0) (= (bufget-u8 data 0) 40)) ; '('
                    (trap (eval (read data)))
            ))
            (_ nil)
)))

(event-register-handler (spawn event-handler))
(event-enable 'event-data-rx)
