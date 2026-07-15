; VESC-side companion -- MASTER variant. Runs on the VESC that owns
; throttle input, not VESC Express. See README.md for setup and
; multi-motor notes.

; Change this if VESC Express's controller-id isn't the default (2).
(define express-can-id 2)
(define slot-vesc-info 0)       ; this VESC -> Express, registration/telemetry
(define slot-speed-relay 1)     ; Express -> this VESC, profile-switch speed

(define can-timeout 500)   ; ms, assumes 1000Hz tick rate
(define last-msg-time (systime))
(define last-mode-byte 0)
(define cruise-active nil)
(define last-speed-x10 -1)

(defun check-timeout ()
    (if (> (- (systime) last-msg-time) can-timeout)
        (progn
            (app-adc-override 0 0.0)
            (app-adc-override 1 0.0))))

; speed-x10 (km/h * 10) -> target ERPM.
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

(defun handle-throttle (data)
    (progn
        (setq last-msg-time (systime))
        (let ((gas-raw (bufget-u8 data 0))
              (brake-raw (bufget-u8 data 1))
              (mode-byte (bufget-u8 data 2)))
            (progn
                (if (and (= last-mode-byte 0x04) (= mode-byte 0x06))
                    (progn (setq cruise-active t) (app-adc-override 3 1.0)))
                (if (and (= last-mode-byte 0x06) (= mode-byte 0x04))
                    (progn (setq cruise-active nil) (app-adc-override 3 0.0)))
                (setq last-mode-byte mode-byte)
                (let ((gas-voltage (* (/ gas-raw 200.0) 3.3))
                      (brake-voltage (* (/ brake-raw 200.0) 3.3)))
                    (cond
                        ((= mode-byte 0x06)   ; cruise
                            (if (> brake-raw 0)
                                (progn
                                    (if cruise-active
                                        (progn (setq cruise-active nil) (app-adc-override 3 0.0)))
                                    (app-adc-override 0 0.0)
                                    (app-adc-override 1 brake-voltage))
                                (app-adc-override 1 0.0)))
                        ((= mode-byte 0x04)   ; normal drive
                            (if (> brake-raw 0)
                                (progn
                                    (app-adc-override 0 0.0)
                                    (app-adc-override 1 brake-voltage))
                                (progn
                                    (app-adc-override 0 gas-voltage)
                                    (app-adc-override 1 0.0))))
                        (t   ; park / any other mode -- zero both
                            (progn
                                (app-adc-override 0 0.0)
                                (app-adc-override 1 0.0)))))))))

(defun dispatch-sid (id data)
    (cond
        ((= id 0x100) (handle-throttle data))
        (t nil)))

(defun can-event-loop ()
    (loopwhile t
        (recv
            ((event-can-sid . ((? id) . (? data))) (dispatch-sid id data))
            (_ nil))))

(define vesc-info-interval 1.0)

(defun broadcast-vesc-info ()
    (let ((own-can-id (to-i (conf-get 'controller-id)))
          (poles (to-i (conf-get 'si-motor-poles)))
          (wheel-diam-mm (to-i (* (conf-get 'si-wheel-diameter) 1000.0)))
          (batt-pct (to-i (* (get-batt) 100.0)))
          (voltage-01v (to-i (* (get-vin) 10.0)))
          (motor-temp (to-i (get-temp-mot))))
        (let ((buf (bufcreate 8)))
            (progn
                (bufset-u8 buf 0 own-can-id)
                (bufset-u8 buf 1 poles)
                (bufset-u8 buf 2 (bitwise-and wheel-diam-mm 255))
                (bufset-u8 buf 3 (bitwise-and (shr wheel-diam-mm 8) 255))
                (bufset-u8 buf 4 batt-pct)
                (bufset-u8 buf 5 (bitwise-and voltage-01v 255))
                (bufset-u8 buf 6 (bitwise-and (shr voltage-01v 8) 255))
                (bufset-u8 buf 7 motor-temp)
                (canmsg-send express-can-id slot-vesc-info buf)))))

(defun speed-relay-listener ()
    (loopwhile t
        (let ((data (canmsg-recv slot-speed-relay -1.0)))
            (if (not-eq data 'timeout)
                (apply-speed-limit (bitwise-or (bufget-u8 data 0) (shl (bufget-u8 data 1) 8)))))))

(app-adc-detach 3 1)

(event-register-handler (spawn can-event-loop))
(event-enable 'event-can-sid)

(spawn (fn () (loopwhile t (progn (check-timeout) (sleep 0.1)))))
(spawn (fn () (loopwhile t (progn (broadcast-vesc-info) (sleep vesc-info-interval)))))
(spawn speed-relay-listener)
