(import "tnt/tnt.bin" 'tntlib)

(load-native-lib tntlib)

; Switch Balance App to UART App
(if (= (conf-get 'app-to-use) 9) (conf-set 'app-to-use 3))

; Set firmware version:
(apply ext-set-fw-version (sysinfo 'fw-ver))

; Set to 1 to monitor some debug variables using the extension ext-euc-dbg
(define debug 1)

(if (= debug 1)
    (loopwhile t
        (progn
            (define setpoint (ext-tnt-dbg 2))
            (define tt-filtered-current (ext-tnt-dbg 3))
            (define integral (ext-tnt-dbg 14))
            (sleep 0.1)
)))
