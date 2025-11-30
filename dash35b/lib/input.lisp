(def btn-0-pressed nil)
(def btn-1-pressed nil)
(def btn-2-pressed nil)
(def btn-3-pressed nil)

(def v0 0.0)
(def v1 0.0)
(def btn '(0 0 0 0))
(def usb 0)

(def ads-addr 0x48)
(def buf-ads-tx (bufcreate 3))
(def buf-ads-rx (bufcreate 2))

@const-start

; Evaluate expression if the function isn't nil.
; Ex: ```
; (defun fun-a (a) (print a))
; (def fun-b nil)
; (maybe-call (fun-a 5)) ; prints 5
; (maybe-call (fun-b 5)) ; does nothing
;```
(def maybe-call (macro (expr) {
            (var fun (first expr))
            `(if ,fun
                ,expr
            )
}))

(defun input-cleanup-on-pressed () {
        (def on-btn-0-pressed nil)
        (def on-btn-1-pressed nil)
        (def on-btn-2-pressed nil)
        (def on-btn-3-pressed nil)

        (def on-btn-0-long-pressed nil)
        (def on-btn-1-long-pressed nil)
        (def on-btn-2-long-pressed nil)
        (def on-btn-3-long-pressed nil)

        (def on-btn-0-repeat-press nil)
        (def on-btn-1-repeat-press nil)
        (def on-btn-2-repeat-press nil)
        (def on-btn-3-repeat-press nil)
})

(defun input-thread () {
        (var input-debounce-count 1)
        (var btn-0 0)
        (var btn-1 0)
        (var btn-2 0)
        (var btn-3 0)
        (var btn-0-start (systime))
        (var btn-1-start (systime))
        (var btn-2-start (systime))
        (var btn-3-start (systime))
        (var btn-0-long-fired nil)
        (var btn-1-long-fired nil)
        (var btn-2-long-fired nil)
        (var btn-3-long-fired nil)

        (loopwhile t {
                (sleep 0.02) ; TODO: Rate limit

                (bufset-u8 buf-ads-tx 0 1)

                (if (not (connected-usb)) {
                        (setq usb 0)
                        (btn-pull-en true)

                        (looprange i 0 2 {
                                (bufset-u16 buf-ads-tx 1 (+
                                        (bits-enc-int 0 12 (+ i 4) 3) ; Channel i
                                        (bits-enc-int 0 9 1 3) ; +- 4.096 V
                                        (bits-enc-int 0 5 5 3) ; 1600 SPS
                                        (bits-enc-int 0 0 3 2) ; Disable comparator
                                ))

                                (i2c-tx-rx ads-addr buf-ads-tx)
                                (sleep 0.005)
                                (i2c-tx-rx ads-addr '(0) buf-ads-rx)
                                (set (ix '(v0 v1 v2 v3) i) (* (/ (bufget-i16 buf-ads-rx 0) 32768.0) 4.096))
                                (sleep 0.005)
                        })

                        (btn-pull-en false)
                    }
                    {
                        (setq usb 1)
                })

                (var new-btn-0 (and (> v1 1.18) (< v1 1.3)))
                (var new-btn-1 (and (> v1 1.5) (< v1 1.8)))
                (var new-btn-2 (and (> v1 2.1) (< v1 2.4)))
                (var new-btn-3 (< v0 1.6))

                ; buttons are pressed on release
                (if (and (>= btn-0 input-debounce-count) (not new-btn-0) (not btn-0-long-fired))
                    (maybe-call (on-btn-0-pressed))
                )
                (if (and (>= btn-1 input-debounce-count) (not new-btn-1) (not btn-1-long-fired))
                    (maybe-call (on-btn-1-pressed))
                )
                (if (and (>= btn-2 input-debounce-count) (not new-btn-2) (not btn-2-long-fired))
                    (maybe-call (on-btn-2-pressed))
                )
                (if (and (>= btn-3 input-debounce-count) (not new-btn-3) (not btn-3-long-fired))
                    (maybe-call (on-btn-3-pressed))
                )

                (setq btn-0 (if new-btn-0 (+ btn-0 1) 0))
                (setq btn-1 (if new-btn-1 (+ btn-1 1) 0))
                (setq btn-2 (if new-btn-2 (+ btn-2 1) 0))
                (setq btn-3 (if new-btn-3 (+ btn-3 1) 0))

                (setq btn-0-pressed (>= btn-0 input-debounce-count))
                (setq btn-1-pressed (>= btn-1 input-debounce-count))
                (setq btn-2-pressed (>= btn-2 input-debounce-count))
                (setq btn-3-pressed (>= btn-3 input-debounce-count))

                (if (= btn-0 1) (setq btn-0-start (systime)))
                (if (= btn-1 1) (setq btn-1-start (systime)))
                (if (= btn-2 1) (setq btn-2-start (systime)))
                (if (= btn-3 1) (setq btn-3-start (systime)))

                ; repeat presses fire until release
                (if (and (>= btn-0 input-debounce-count) (>= (secs-since btn-0-start) 0.25)) {
                        (maybe-call (on-btn-0-repeat-press))
                })
                (if (and (>= btn-1 input-debounce-count) (>= (secs-since btn-1-start) 0.25)) {
                        (maybe-call (on-btn-1-repeat-press))
                })
                (if (and (>= btn-2 input-debounce-count) (>= (secs-since btn-2-start) 0.25)) {
                        (maybe-call (on-btn-2-repeat-press))
                })
                (if (and (>= btn-3 input-debounce-count) (>= (secs-since btn-3-start) 0.25)) {
                        (maybe-call (on-btn-3-repeat-press))
                })

                (var t-long-press 1.0)

                ; long presses fire as soon as possible and not on release
                (if (and (>= btn-0 input-debounce-count) (>= (secs-since btn-0-start) t-long-press) (not btn-0-long-fired)) {
                        (setq btn-0-long-fired true)
                        (maybe-call (on-btn-0-long-pressed))
                })
                (if (and (>= btn-1 input-debounce-count) (>= (secs-since btn-1-start) t-long-press) (not btn-1-long-fired)) {
                        (setq btn-1-long-fired true)
                        (maybe-call (on-btn-1-long-pressed))
                })
                (if (and (>= btn-2 input-debounce-count) (>= (secs-since btn-2-start) t-long-press) (not btn-2-long-fired)) {
                        (setq btn-2-long-fired true)
                        (maybe-call (on-btn-2-long-pressed))
                })
                (if (and (>= btn-3 input-debounce-count) (>= (secs-since btn-3-start) t-long-press) (not btn-3-long-fired)) {
                        (setq btn-3-long-fired true)
                        (maybe-call (on-btn-3-long-pressed))
                })

                (if (and (>= (secs-since btn-1-start) 6.13) btn-1-long-fired (eq state-view 'view-main)) (def state-view-next 'view-minigame))

                (if (= btn-0 0) (setq btn-0-long-fired false))
                (if (= btn-1 0) (setq btn-1-long-fired false))
                (if (= btn-2 0) (setq btn-2-long-fired false))
                (if (= btn-3 0) (setq btn-3-long-fired false))
        })
})
