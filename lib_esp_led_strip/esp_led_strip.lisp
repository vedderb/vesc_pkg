(import "esp_led_strip/esp_led_strip_esp32c3.bin" 'lib-esp32c3)
(import "esp_led_strip/esp_led_strip_esp32c6.bin" 'lib-esp32c6)
(import "esp_led_strip/esp_led_strip_esp32s3.bin" 'lib-esp32s3)
(import "esp_led_strip/esp_led_strip_esp32p4.bin" 'lib-esp32p4)

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
    (print (str-merge "esp_led_strip: no native lib for target " target))
    (load-native-lib lib)
)

; The test UI sends lisp expressions as custom app data - evaluate them.
(defun event-handler ()
    (loopwhile t
        (recv
            ((event-data-rx . (? data))
                (if (and (> (buflen data) 0) (= (bufget-u8 data 0) 40))
                    {
                        ; trap keeps a bad command from killing the handler;
                        ; log the error and the offending command so failures
                        ; are visible in the VESC Tool lisp console.
                        (var res (trap (eval (read data))))
                        (if (eq (car res) 'exit-error)
                            (print (list "esp_led eval error" (ix res 1) data)))
                    }
            ))
            (_ nil)
)))

(event-register-handler (spawn event-handler))
(event-enable 'event-data-rx)
