; Wheelie Assist  -  by 3ShulMotors
; --------------------------------------------------------------------------
; Self-balancing wheelie limiter / assist for the rear-wheel-up region.
;
; While the front wheel is up, the rider's throttle is faded out as pitch
; approaches a ceiling angle, and a gentle reverse (pull-down) current is
; applied past the ceiling so the bike settles toward a target wheelie
; angle instead of flipping. Below the start angle the rider has full throttle.
;
; Tunable live from VESC Tool (custom-app-data channel) AND from a 3ShulMotors
; smart display over CAN (see WHEELIE_CAN_PROTOCOL.md). Settings persist in
; lisp EEPROM.
;
; ARMING: the assist always boots DISARMED and is armed / disarmed only from
; the app (Toggle Arm) or the 3ShulMotors display (CAN ARM command). While
; disarmed the normal throttle app drives the motor.
;
; REQUIREMENTS: a board with an IMU (get-imu-rpy / get-imu-gyro) and an
; ADC throttle (get-adc-decoded 0). Reverse requires l_min_erpm < 0 in the
; motor config, otherwise the pull-down current cannot be produced.
;
; SAFETY: this commands motor current directly. Test on a stand first.
; --------------------------------------------------------------------------

(def whl-version "1.0.0")

; ---- EEPROM layout (lisp eeprom, separate from mcconf/appconf) ----
;   slot 0 magic (i)   slot 4 pull-max  (f)
;   slot 1 start (f)   slot 5 rate-lpf  (f)
;   slot 2 end   (f)   slot 6 (retired - leave unused)
;   slot 3 damp  (f)   slot 7 pitch-sign(f)
(def whl-magic 1464685313)   ; 0x57484C01 = "WHL" v1

; ---- Tunables (live, persisted) ----  map 1:1 to CAN registers 0..5
(def whl-start   25.0)   ; reg 0  throttle fade starts here (deg)
(def whl-end     45.0)   ; reg 1  balance ceiling / hard cap (deg)
(def whl-damp     0.01)  ; reg 2  pitch-rate damping
(def pull-max     0.6)   ; reg 3  max reverse (pull-down) current, 0..1
(def rate-lpf     0.20)  ; reg 4  gyro low-pass alpha, 0..1
(def pitch-sign   1.0)   ; reg 5  +1.0 / -1.0 depending on IMU mounting

; Internal constants (not CAN registers): throttle signal conditioning.
; Deadband zeroes ADC noise near rest (no current at standstill); the low-pass
; smooths the throttle so a noisy signal cannot make the duty fluctuate.
(def thr-db  0.05)   ; throttle deadband (fraction of full, 0..1)
(def thr-lpf 0.25)   ; throttle low-pass alpha (0..1; higher = snappier)

; ---- Runtime state ----
(def whl-armed 0)     ; boot disarmed; armed only via app / display
(def whl-ctrl  0)     ; 1 while the script is actively driving the motor
(def prate-f   0.0)
(def whl-pitch 0.0)   ; telemetry: filtered pitch (deg)
(def whl-out   0.0)   ; telemetry: last current-rel command
(def whl-rider 0.0)   ; telemetry: conditioned throttle 0..1

(defun clamp (x lo hi) (if (< x lo) lo (if (> x hi) hi x)))

; ==========================================================================
;  3ShulMotors Wheelie Assist CAN protocol v1  (standard 11-bit frames, DLC 8)
;  Command  (display -> ctrl): id = whl-sid-cmd + controller-can-id
;  Response (ctrl -> display): id = whl-sid-rsp + controller-can-id
;  Byte 0 of every frame is the marker 0x57 ('W').  See WHEELIE_CAN_PROTOCOL.md
; ==========================================================================
(def whl-mark    0x57)
(def whl-sid-cmd 0x500)
(def whl-sid-rsp 0x540)
(def whl-canid   (can-local-id))

; command ids (byte 1, display -> controller)
(def whl-cmd-read-all  0x01)
(def whl-cmd-read-reg  0x02)
(def whl-cmd-write-reg 0x03)
(def whl-cmd-save      0x04)
(def whl-cmd-arm       0x05)
(def whl-cmd-sub       0x06)
; response ids (byte 1, controller -> display)
(def whl-rsp-telem     0x81)
(def whl-rsp-config    0x82)
(def whl-rsp-ack       0x83)

; pre-allocated tx buffers (telemetry thread vs response thread - no sharing)
(def whl-can-tx-t (bufcreate 8))
(def whl-can-tx-r (bufcreate 8))

; CAN telemetry cadence: broadcast every N ticks of the 100 ms telem loop.
(def whl-can-telem-rate 1)   ; 1 = 10 Hz, 0 = off
(def whl-can-telem-cnt  0)

; all registers are floats
(defun whl-get-reg (reg)
    (cond
        ((= reg 0) whl-start)
        ((= reg 1) whl-end)
        ((= reg 2) whl-damp)
        ((= reg 3) pull-max)
        ((= reg 4) rate-lpf)
        ((= reg 5) pitch-sign)
        (t 0.0)))

(defun whl-set-reg (reg val)
    (cond
        ((= reg 0) (setvar 'whl-start val))
        ((= reg 1) (setvar 'whl-end val))
        ((= reg 2) (setvar 'whl-damp val))
        ((= reg 3) (setvar 'pull-max val))
        ((= reg 4) (setvar 'rate-lpf val))
        ((= reg 5) (setvar 'pitch-sign val))
        (t nil)))

(defun whl-can-send-config (reg)
    (let ((tx whl-can-tx-r))
        (progn
            (bufset-u8  tx 0 whl-mark)
            (bufset-u8  tx 1 whl-rsp-config)
            (bufset-u8  tx 2 reg)
            (bufset-u8  tx 3 0)               ; type 0 = float (all registers)
            (bufset-f32 tx 4 (to-float (whl-get-reg reg)))
            (can-send-sid (+ whl-sid-rsp whl-canid) tx))))

(defun whl-can-send-all ()
    (progn
        (whl-can-send-config 0) (whl-can-send-config 1)
        (whl-can-send-config 2) (whl-can-send-config 3)
        (whl-can-send-config 4) (whl-can-send-config 5)))

(defun whl-can-ack (refcmd status)
    (let ((tx whl-can-tx-r))
        (progn
            (bufset-u8  tx 0 whl-mark)
            (bufset-u8  tx 1 whl-rsp-ack)
            (bufset-u8  tx 2 refcmd)
            (bufset-u8  tx 3 status)
            (bufset-i32 tx 4 0)
            (can-send-sid (+ whl-sid-rsp whl-canid) tx))))

(defun whl-can-write (data)
    (whl-set-reg (bufget-u8 data 2) (bufget-f32 data 4)))

(defun whl-can-arm (mode)
    (cond
        ((= mode 0) (setvar 'whl-armed 0))
        ((= mode 1) (setvar 'whl-armed 1))
        ((= mode 2) (setvar 'whl-armed (if (= whl-armed 1) 0 1)))
        (t nil)))

(defun whl-can-send-telem ()
    (let ((tx whl-can-tx-t))
        (progn
            (bufset-u8  tx 0 whl-mark)
            (bufset-u8  tx 1 whl-rsp-telem)
            (bufset-i16 tx 2 (to-i (* whl-pitch 10.0)))
            (bufset-i16 tx 4 (to-i (* prate-f 10.0)))
            (bufset-u8  tx 6 (bitwise-or (if (= whl-armed 1) 1 0)
                                         (if (= whl-ctrl 1) 4 0)))
            (bufset-i8  tx 7 (to-i (* whl-out 100.0)))
            (can-send-sid (+ whl-sid-rsp whl-canid) tx))))

(defun whl-can-handle (id data)
    (if (and (= id (+ whl-sid-cmd whl-canid))
             (>= (buflen data) 2)
             (= (bufget-u8 data 0) whl-mark))
        (let ((cmd (bufget-u8 data 1)))
            (cond
                ((= cmd whl-cmd-read-all) (whl-can-send-all))
                ((= cmd whl-cmd-read-reg)
                    (if (>= (buflen data) 3) (whl-can-send-config (bufget-u8 data 2))))
                ((= cmd whl-cmd-write-reg)
                    (if (>= (buflen data) 8)
                        (progn (whl-can-write data) (whl-can-send-config (bufget-u8 data 2)))))
                ((= cmd whl-cmd-save) (progn (whl-save) (whl-can-ack whl-cmd-save 1)))
                ((= cmd whl-cmd-arm)
                    (if (>= (buflen data) 3) (whl-can-arm (bufget-u8 data 2))))
                ((= cmd whl-cmd-sub)
                    (if (>= (buflen data) 3) (setvar 'whl-can-telem-rate (bufget-u8 data 2))))
                (t nil)))))

; ---- Persistence ----
(defun whl-save ()
    (progn
        (eeprom-store-f 1 whl-start)
        (eeprom-store-f 2 whl-end)
        (eeprom-store-f 3 whl-damp)
        (eeprom-store-f 4 pull-max)
        (eeprom-store-f 5 rate-lpf)
        (eeprom-store-f 7 pitch-sign)        ; slot 7 (slot 6 retired)
        (eeprom-store-i 0 whl-magic)))       ; magic written last = commit

(defun whl-load ()
    (progn
        (setvar 'whl-start   (eeprom-read-f 1))
        (setvar 'whl-end     (eeprom-read-f 2))
        (setvar 'whl-damp    (eeprom-read-f 3))
        (setvar 'pull-max    (eeprom-read-f 4))
        (setvar 'rate-lpf    (eeprom-read-f 5))
        (setvar 'pitch-sign  (eeprom-read-f 7))))

; First run writes defaults; later runs load the saved values.
; eeprom-read-i returns nil for a never-written slot - guard the (=) compare
; against nil so a fresh install does not abort startup with a type error.
(if (let ((m (eeprom-read-i 0))) (and m (= m whl-magic)))
    (whl-load)
    (whl-save))

; ---- VESC Tool comm (custom app data) ----
; QML -> device (binary):
;   [u8 1]                                            -> request config
;   [u8 2][f32 start][f32 end][f32 damp][f32 pullmax]
;         [f32 ratelpf][f32 psign]                    -> apply + save
;   [u8 3]                                            -> toggle armed
; device -> QML (string):
;   "conf start end damp pullmax ratelpf psign armed"
;   "rt pitch prate armed out rider"

(defun send-conf ()
    (send-data (str-merge "conf "
        (str-from-n whl-start  "%.2f ")
        (str-from-n whl-end    "%.2f ")
        (str-from-n whl-damp   "%.4f ")
        (str-from-n pull-max   "%.3f ")
        (str-from-n rate-lpf   "%.3f ")
        (str-from-n pitch-sign "%.1f ")
        (str-from-n whl-armed  "%d"))))

(defun apply-set (data)
    (progn
        (setvar 'whl-start   (bufget-f32 data 1))
        (setvar 'whl-end     (bufget-f32 data 5))
        (setvar 'whl-damp    (bufget-f32 data 9))
        (setvar 'pull-max    (bufget-f32 data 13))
        (setvar 'rate-lpf    (bufget-f32 data 17))
        (setvar 'pitch-sign  (bufget-f32 data 21))
        (whl-save)
        (send-conf)))

(defun handle-rx (data)
    (if (>= (buflen data) 1)
        (let ((cmd (bufget-u8 data 0)))
            (cond
                ((= cmd 1) (send-conf))
                ((and (= cmd 2) (>= (buflen data) 25)) (apply-set data))
                ((= cmd 3) (setvar 'whl-armed (if (= whl-armed 1) 0 1)))
                (t nil)))))

(defun event-loop ()
    (loopwhile t
        (recv
            ((event-data-rx . (? data)) (handle-rx data))
            ((event-can-sid . ((? id) . (? data))) (whl-can-handle id data))
            (_ nil))))

(defun telem-loop ()
    (loopwhile t
        (progn
            ; VESC Tool telemetry (USB/BLE custom app data)
            (send-data (str-merge "rt "
                (str-from-n whl-pitch "%.1f ")
                (str-from-n prate-f   "%.1f ")
                (str-from-n whl-armed "%d ")
                (str-from-n whl-out   "%.3f ")
                (str-from-n whl-rider "%.3f")))
            ; 3ShulMotors display telemetry (CAN), rate-limited
            (if (> whl-can-telem-rate 0)
                (progn
                    (setvar 'whl-can-telem-cnt (+ whl-can-telem-cnt 1))
                    (if (>= whl-can-telem-cnt whl-can-telem-rate)
                        (progn (setvar 'whl-can-telem-cnt 0) (whl-can-send-telem)))))
            (sleep 0.1))))

; ---- Control loop ----
; When armed, the script drives the motor at all angles: full throttle below
; the start angle (so you can pull the wheelie up), faded between start and the
; ceiling, reverse pull-down past the ceiling. When disarmed, output is handed
; back to the normal throttle app. The throttle is deadbanded + low-pass
; filtered so a noisy ADC signal cannot dither the duty at standstill.
(defun control-loop ()
    (loopwhile t
        (progn
            ; pitch / rate
            (var pitch (* pitch-sign (rad2deg (ix (get-imu-rpy) 1))))
            (setvar 'whl-pitch pitch)
            (setvar 'prate-f (+ (* prate-f (- 1.0 rate-lpf))
                                (* (* pitch-sign (ix (get-imu-gyro) 1)) rate-lpf)))

            ; throttle: clamp 0..1, deadband (rescaled), then low-pass filter
            (var raw (clamp (get-adc-decoded 0) 0.0 1.0))
            (var db (if (< raw thr-db) 0.0 (/ (- raw thr-db) (- 1.0 thr-db))))
            (setvar 'whl-rider (+ (* whl-rider (- 1.0 thr-lpf)) (* db thr-lpf)))

            (if (= whl-armed 1)
                (progn
                    (app-disable-output 100)
                    (setvar 'whl-ctrl 1)
                    (var ctrl (- (/ (- whl-end pitch) (- whl-end whl-start))
                                 (* whl-damp prate-f)))
                    (if (>= ctrl 0.0)
                        (progn
                            (setvar 'whl-out (clamp (* whl-rider ctrl) 0.0 whl-rider))
                            (set-current-rel whl-out))
                        (progn
                            (setvar 'whl-out (clamp ctrl (- pull-max) 0.0))
                            (set-current-rel whl-out))))
                (progn
                    (setvar 'whl-out 0.0)
                    (if (= whl-ctrl 1)
                        (progn (app-disable-output 0) (setvar 'whl-ctrl 0)))))

            (sleep 0.01))))

; ---- Boot ----
(setvar 'whl-armed 0)   ; always start disarmed

(event-register-handler (spawn event-loop))
(event-enable 'event-data-rx)
(event-enable 'event-can-sid)
(spawn telem-loop)
(spawn control-loop)

(print (str-merge "Wheelie Assist (3ShulMotors) v" whl-version " started"))
