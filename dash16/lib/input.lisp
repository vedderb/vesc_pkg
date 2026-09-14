(def btn-0-pressed nil)
(def btn-1-pressed nil)

(def btn '(0 0))

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

        (def on-btn-0-long-pressed nil)
        (def on-btn-1-long-pressed nil)

        (def on-btn-0-repeat-press nil)
        (def on-btn-1-repeat-press nil)
})

(defun input-thread () {
        (var input-debounce-count 1)
        (var btn-0 0)
        (var btn-1 0)
        (var btn-0-start (systime))
        (var btn-1-start (systime))
        (var btn-0-long-fired nil)
        (var btn-1-long-fired nil)

        (gpio-configure 8 'pin-mode-in-pu)
        (gpio-configure 10 'pin-mode-in-pu)

        (loopwhile t {
                (sleep 0.02) ; TODO: Rate limit

                (var new-btn-0 (= (gpio-read 8) 0))
                (var new-btn-1 (= (gpio-read 10) 0))

                ; buttons are pressed on release
                (if (and (>= btn-0 input-debounce-count) (not new-btn-0) (not btn-0-long-fired))
                    (maybe-call (on-btn-0-pressed))
                )
                (if (and (>= btn-1 input-debounce-count) (not new-btn-1) (not btn-1-long-fired))
                    (maybe-call (on-btn-1-pressed))
                )

                (setq btn-0 (if new-btn-0 (+ btn-0 1) 0))
                (setq btn-1 (if new-btn-1 (+ btn-1 1) 0))

                (setq btn-0-pressed (>= btn-0 input-debounce-count))
                (setq btn-1-pressed (>= btn-1 input-debounce-count))

                (if (= btn-0 1) (setq btn-0-start (systime)))
                (if (= btn-1 1) (setq btn-1-start (systime)))

                ; repeat presses fire until release
                (if (and (>= btn-0 input-debounce-count) (>= (secs-since btn-0-start) 0.25)) {
                        (maybe-call (on-btn-0-repeat-press))
                })
                (if (and (>= btn-1 input-debounce-count) (>= (secs-since btn-1-start) 0.25)) {
                        (maybe-call (on-btn-1-repeat-press))
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

                (if (= btn-0 0) (setq btn-0-long-fired false))
                (if (= btn-1 0) (setq btn-1-long-fired false))
        })
})
