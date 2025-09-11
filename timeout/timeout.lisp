; Fixed configuration: dead simple safety
@const-start
(def remote_drop_s 1.00)   ; fixed timeout (s)
(def loop_dt_s     0.02)   ; loop cadence (s)
@const-end

(def mote-age 0.0)
(def state nil)
(def age-val 0.0)

(defun main () (loopwhile t {
  (def state (get-remote-state))  ; (js-y js-x bt-c bt-z is-rev update-age)

  (def age-val (ix state 5))
  (def mote-age (if age-val age-val 9999.0))

  ; if age > threshold ? zero current
  (if (> mote-age remote_drop_s)
      (set-current 0 0.05)
      0)

  (sleep loop_dt_s)
}))

(trap (image-save))
(main)

