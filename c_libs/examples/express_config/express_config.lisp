; Custom config example for the VESC Express.
;
; Loading the native lib registers the custom config with the firmware, which
; makes an "Express Config Example" page appear in VESC Tool under the custom
; configuration of this device. The same values are readable and writable from
; here through the ext-cfg-* extensions the lib adds.

(import "express_config_esp32c3.bin" 'lib-esp32c3)
(import "express_config_esp32c6.bin" 'lib-esp32c6)
(import "express_config_esp32s3.bin" 'lib-esp32s3)
(import "express_config_esp32p4.bin" 'lib-esp32p4)

; Native libs only run on the chip they were built for, so pick the binary
; matching this hardware. Requires firmware with support for
; (sysinfo 'hw-target).
(def target (sysinfo 'hw-target))

(def lib (cond
    ((= (str-cmp target "esp32c3") 0) lib-esp32c3)
    ((= (str-cmp target "esp32c6") 0) lib-esp32c6)
    ((= (str-cmp target "esp32s3") 0) lib-esp32s3)
    ((= (str-cmp target "esp32p4") 0) lib-esp32p4)
    (t nil)
))

; Parameter names use the XML names, and the lib treats '-' and '_' as equal,
; so the usual dashed lisp symbols work.
(defun get-config (name)
    (ext-cfg-get (sym2str name))
)

(defun set-config (name value)
    (ext-cfg-set (sym2str name) value)
)

(defun print-config () {
    (print (str-merge "bool          " (str-from-n (get-config 'demo-bool))))
    (print (str-merge "enum          " (str-from-n (get-config 'demo-enum))))
    (print (str-merge "bitfield      " (str-from-n (get-config 'demo-bitfield))))
    (print (str-merge "uint8         " (str-from-n (get-config 'demo-uint8))))
    (print (str-merge "int8          " (str-from-n (get-config 'demo-int8))))
    (print (str-merge "uint16        " (str-from-n (get-config 'demo-uint16))))
    (print (str-merge "int16         " (str-from-n (get-config 'demo-int16))))
    (print (str-merge "uint32        " (str-from-n (get-config 'demo-uint32))))
    (print (str-merge "int32         " (str-from-n (get-config 'demo-int32))))
    (print (str-merge "float16       " (str-from-n (get-config 'demo-float16))))
    (print (str-merge "float32       " (str-from-n (get-config 'demo-float32))))
    (print (str-merge "float32-auto  " (str-from-n (get-config 'demo-float32-auto))))
    (print (str-merge "percent       " (str-from-n (get-config 'demo-percent))))
    (print (str-merge "string        " (get-config 'demo-string)))
})

; A bitfield is a plain integer here - test and set bits yourself.
(defun bit-set? (name n)
    (!= 0 (bitwise-and (get-config name) (shl 1 n)))
)

; Called whenever the config changed, either because VESC Tool wrote it or
; because this script did. A real package would (re)start its loops here.
(defun apply-config () {
    (print "Config applied:")
    (print-config)
})

(if (eq lib nil)
    (print (str-merge "No config example lib for target " target))
{
    (print (str-merge "Loading config example lib for " target))
    (print (load-native-lib lib))

    (apply-config)

    ; Writing from lisp: ext-cfg-set only touches RAM, ext-cfg-store persists.
    ; (set-config 'demo-float32 0.75)
    ; (set-config 'demo-string "world")
    ; (ext-cfg-store)

    ; ext-cfg-restore resets every parameter to the XML defaults and persists.
    ; (ext-cfg-restore)

    ; Poll for writes coming from VESC Tool so settings take effect without a
    ; reboot. ext-cfg-changed returns t once per write, then nil.
    (loopwhile t {
        (if (ext-cfg-changed) (apply-config))
        (sleep 0.5)
    })
})
