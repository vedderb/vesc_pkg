; VESC-side companion -- SLAVE variant. Runs on additional motor(s) in a
; multi-motor setup; the master (code_stm.lisp) owns throttle input and
; dashboard decoding. Propulsion/braking/cruise reach this VESC on their
; own via VESC's built-in Multi ESC over CAN (enable it on the MASTER in
; VESC Tool: App Settings -> General -> Multi ESC over CAN) -- nothing
; here duplicates that. This script only keeps l-max-erpm in sync with
; the dashboard's active speed-limit profile, which Multi ESC over CAN
; doesn't cover since it's a config value, not a CAN command.
; See README_stm_slave.md.

; Change this if VESC Express's controller-id isn't the default (2).
(define express-can-id 2)
(define slot-speed-relay 1)
(define slot-vesc-register 2)

(define register-interval 1.0)   ; s, re-sent so a rebooted Express re-adds us
(define last-speed-x10 -1)

; speed-x10 (km/h * 10) -> target ERPM. Same formula as the master's
; apply-speed-limit, using this VESC's own motor configuration.
(defun apply-speed-limit (speed-x10)
    (if (!= speed-x10 last-speed-x10)
        (progn
            (setq last-speed-x10 speed-x10)
            (let ((speed-kmh (to-float (to-i (+ (/ speed-x10 10.0) 0.5))))
                  (poles (conf-get 'si-motor-poles))
                  (wheel-diam-m (conf-get 'si-wheel-diameter)))
                (let ((wheel-circum-m (* 3.14159 wheel-diam-m)))
                    (let ((wheel-rpm (/ (* speed-kmh 1000.0) (* wheel-circum-m 60.0))))
                        (conf-set 'l-max-erpm (* wheel-rpm (/ poles 2.0)))))))))

(defun speed-relay-listener ()
    (loopwhile t
        (let ((data (canmsg-recv slot-speed-relay -1.0)))
            (if (not-eq data 'timeout)
                (apply-speed-limit (bitwise-or (bufget-u8 data 0) (shl (bufget-u8 data 1) 8)))))))

; 1-byte payload (own CAN id) -- Express doesn't track a slave's motor
; config or battery, it just adds the id to its speed-relay target list.
(defun register-with-express ()
    (let ((own-can-id (to-i (conf-get 'controller-id)))
          (buf (bufcreate 1)))
        (progn
            (bufset-u8 buf 0 own-can-id)
            (canmsg-send express-can-id slot-vesc-register buf))))

(spawn speed-relay-listener)
(spawn (fn () (loopwhile t (progn (register-with-express) (sleep register-interval)))))
