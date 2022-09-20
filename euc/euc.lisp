(import "c_lib/euc/euc.bin" 'euclib)

(load-native-lib euclib)

; Set to 1 to monitor some debug variables using the extension ext-euc-dbg
(define debug 0)

(if (= debug 1)
    (loopwhile t
        (progn
            (define setpoint (ext-euc-dbg 2))
            (define tt-filtered-current (ext-euc-dbg 3))
            (define integral (ext-euc-dbg 14))
            (sleep 0.1)
)))
