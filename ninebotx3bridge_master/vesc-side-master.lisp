; VESC-side companion -- MASTER variant. Runs on the VESC that owns
; throttle input, not VESC Express. See README.md for setup and
; multi-motor notes.

; Change this if VESC Express's controller-id isn't the default (2).
(define express-can-id 2)
(define slot-vesc-info 0)       ; this VESC -> Express, registration/telemetry
(define slot-speed-relay 1)     ; Express -> this VESC, profile-switch speed
(define slot-external-adc 3)    ; Express -> this VESC, throttle/brake source

; 0 = dashboard ADC (throttle/brake come from 0x100, this script drives the
; ADC app via app-adc-override). 1 = External ADC: the dashboard's throttle
; and brake are ignored entirely and the ADC app is handed back its own
; physical ADC1/ADC2 inputs. Pushed from the Express settings page; the
; default here matches the app-adc-detach at the bottom of this file.
(define external-adc 0)

(define can-timeout 500)   ; ms, assumes 1000Hz tick rate
(define last-msg-time (systime))
(define last-mode-byte 0)
(define cruise-active nil)
(define last-speed-x10 -1)

; Only meaningful while this script owns the ADC app -- in external-adc
; mode a zeroing override would fight the physical throttle.
(defun check-timeout ()
    (if (and (= external-adc 0) (> (- (systime) last-msg-time) can-timeout))
        (progn
            (app-adc-override 0 0.0)
            (app-adc-override 1 0.0))))

; Releases the overrides before re-attaching, so the ADC app doesn't inherit
; a stale forced value; detaches again when going back to dashboard control.
(defun apply-external-adc (val)
    (if (!= val external-adc)
        (progn
            (setq external-adc val)
            (if (= external-adc 1)
                (progn
                    (app-adc-override 0 0.0)
                    (app-adc-override 1 0.0)
                    (app-adc-override 3 0.0)
                    (setq cruise-active nil)
                    (app-adc-detach 3 0))
                (app-adc-detach 3 1)))))

(defun external-adc-listener ()
    (loopwhile t
        (let ((data (canmsg-recv slot-external-adc -1.0)))
            (if (not-eq data 'timeout)
                (apply-external-adc (bufget-u8 data 0))))))

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

; ---- Throttle/brake voltage emulation ----
;
; 0x100 bytes 0/1 are 0x00-0xC8 (0-200), confirmed from the protocol docs.
; app-adc-override takes volts (clamped 0-3.3 in app_adc.c), so the full
; lever travel is emulated as a clean 0-3.3V sweep and nothing is shaped
; here. Response is configured on the VESC side as it would be for a real
; throttle: voltage range, deadband and throttle curve in the ADC app.
(define dash-adc-full 200.0)
(define dash-adc-vmax 3.3)

(defun dash-to-voltage (raw)
    (let ((clamped (if (> raw dash-adc-full) dash-adc-full (to-float raw))))
        (* (/ clamped dash-adc-full) dash-adc-vmax)))

; In external-adc mode every override below is skipped, so the dashboard's
; throttle and brake bytes are ignored and the VESC's own ADC inputs drive
; the motor. last-msg-time is still stamped so the timeout logic stays sane
; across a switch back to dashboard control.
(defun handle-throttle (data)
    (progn
        (setq last-msg-time (systime))
        (if (= external-adc 1) nil
        (let ((gas-raw (bufget-u8 data 0))
              (brake-raw (bufget-u8 data 1))
              (mode-byte (bufget-u8 data 2)))
            (progn
                (if (and (= last-mode-byte 0x04) (= mode-byte 0x06))
                    (progn (setq cruise-active t) (app-adc-override 3 1.0)))
                (if (and (= last-mode-byte 0x06) (= mode-byte 0x04))
                    (progn (setq cruise-active nil) (app-adc-override 3 0.0)))
                (setq last-mode-byte mode-byte)
                (let ((gas-voltage (dash-to-voltage gas-raw))
                      (brake-voltage (dash-to-voltage brake-raw)))
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
                        (t   ; park / any other mode -- idle both
                            (progn
                                (app-adc-override 0 0.0)
                                (app-adc-override 1 0.0))))))))))

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
(spawn external-adc-listener)
