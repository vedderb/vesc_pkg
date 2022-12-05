(import "float/float.bin" 'floatlib)

(load-native-lib floatlib)

; Set to 1 to monitor some debug variables using the extension ext-euc-dbg
(define debug 1)

(if (= debug 1)
    (loopwhile t
        (progn
            (define setpoint (ext-float-dbg 2))
            (define tt-filtered-current (ext-float-dbg 3))
            (define integral (ext-float-dbg 14))
            (sleep 0.1)
)))
