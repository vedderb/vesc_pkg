; VESC X3 Bridge -- runs on VESC Express. See README_esp.md.

; ---- Pins (WROOM-1 V2.1+) ----
; Pin 7 (multipin) drives underglow only -- horn isn't implemented.

(define pin-indicator-right 4)
(define pin-indicator-left 5)
(define pin-rear-light 6)      ; PWM (LEDC)
(define pin-multipin 7)        ; underglow output
(define pin-pwr_on 10)

(define pwm-freq 5000)
(define pwm-channel 0)
(define pwm-bits 8)

(gpio-configure pin-indicator-right 'pin-mode-out)
(gpio-configure pin-indicator-left 'pin-mode-out)
(gpio-configure pin-multipin 'pin-mode-out)
(gpio-configure pin-pwr_on 'pin-mode-out)
(pwm-start pwm-freq 0.0 pwm-channel pin-rear-light pwm-bits)

(gpio-write pin-pwr_on 1)

; Vehicle constants, learned live from the VESC's registration message.
(define vesc-can-id 0)
(define motor-poles 30)
(define wheel-diam-mm 254)
(define battery-pct 100)
(define voltage-v 0.0)
(define motor-temp-c 0.0)

(define slot-vesc-info 0)
(define slot-speed-relay 1)
(define slot-vesc-register 2)
(define slot-external-adc 3)   ; Express -> VESC(s), throttle/brake source

(define relay-targets (list))

(defun list-contains (lst val)
    (if (eq lst nil)
        nil
        (if (= (car lst) val)
            t
            (list-contains (cdr lst) val))))

(defun add-relay-target (id)
    (if (not (list-contains relay-targets id))
        (setq relay-targets (cons id relay-targets))))

(defun relay-speed-to-targets (targets buf)
    (if (not-eq targets nil)
        (progn
            (canmsg-send (car targets) slot-speed-relay buf)
            (relay-speed-to-targets (cdr targets) buf))))

; ---- External ADC relay ----
; external-adc lives here (it's a settings-page toggle) but only the VESC
; can act on it, so it's pushed to every registered VESC: on change, and
; again whenever one registers, since a VESC that reboots comes back up
; with its own default and would otherwise never hear about the setting.

(defun external-adc-buf ()
    (let ((buf (bufcreate 1)))
        (progn
            (bufset-u8 buf 0 external-adc)
            buf)))

(defun send-external-adc-to (target-id)
    (canmsg-send target-id slot-external-adc (external-adc-buf)))

(defun relay-external-adc-to-targets (targets)
    (if (not-eq targets nil)
        (progn
            (send-external-adc-to (car targets))
            (relay-external-adc-to-targets (cdr targets)))))

; Express-side settings, eeprom-backed, editable via ui_esp.qml.

(define ee-addr-sentinel 0)   ; legacy, unused -- see note below, don't reuse
(define ee-addr-disable-prof-sw 1)
(define ee-addr-freeze-batt-below-11 2)
(define ee-addr-bms-mode 3)
(define ee-addr-bypass-speed-limit-warning 4)
(define ee-addr-underglow-on-park 5)
(define ee-addr-enable-charge-light 6)
(define ee-addr-external-adc 7)
(define ee-addr-use-other-profiles 8)   ; reserved, no longer persisted
(define ee-addr-profile-walk 9)
(define ee-addr-profile-eco 10)
(define ee-addr-profile-drive 11)
(define ee-addr-profile-sport 12)

; eeprom-read-i returns nil (not 0) on a never-written address, which is
; what makes per-field seeding possible: never written -> take the default,
; already written -> keep whatever the rider set. Must use eq (generic),
; not = (numeric-only, type-errors on nil).
;
; This replaces an all-or-nothing sentinel that had to be bumped whenever a
; field was added, and re-seeded *every* field when it was -- wiping the
; rider's saved settings just to introduce one new one. Adding a field now
; needs no version bump and disturbs nothing. Address 0 still holds a stale
; sentinel value on boards flashed with the old scheme, so it stays
; reserved rather than being recycled for a real setting.
(defun seed-setting (addr default)
    (if (eq (eeprom-read-i addr) nil)
        (eeprom-store-i addr default)))

(defun init-settings ()
    (progn
        (seed-setting ee-addr-disable-prof-sw 0)
        (seed-setting ee-addr-freeze-batt-below-11 0)
        (seed-setting ee-addr-bms-mode 0)
        (seed-setting ee-addr-bypass-speed-limit-warning 1)
        (seed-setting ee-addr-underglow-on-park 0)
        (seed-setting ee-addr-enable-charge-light 1)
        (seed-setting ee-addr-external-adc 0)
        (seed-setting ee-addr-profile-walk 5)
        (seed-setting ee-addr-profile-eco 15)
        (seed-setting ee-addr-profile-drive 20)
        (seed-setting ee-addr-profile-sport 25)))

(init-settings)

(define disable-prof-sw (eeprom-read-i ee-addr-disable-prof-sw))
(define freeze-batt-below-11 (eeprom-read-i ee-addr-freeze-batt-below-11))
(define bms-mode (eeprom-read-i ee-addr-bms-mode))
(define bypass-speed-limit-warning (eeprom-read-i ee-addr-bypass-speed-limit-warning))
(define underglow-on-park (eeprom-read-i ee-addr-underglow-on-park))
(define enable-charge-light (eeprom-read-i ee-addr-enable-charge-light))
(define external-adc (eeprom-read-i ee-addr-external-adc))
; Deliberately NOT eeprom-backed. This is a temporary override, not a saved
; setting: it starts off at boot so the dashboard's own profile speeds apply,
; and is cleared again whenever the dashboard is switched off (see
; handle-park-state). The four km/h values below *are* persisted -- only the
; switch is transient.
(define use-other-profiles 0)
(define profile-walk-kmh (eeprom-read-i ee-addr-profile-walk))
(define profile-eco-kmh (eeprom-read-i ee-addr-profile-eco))
(define profile-drive-kmh (eeprom-read-i ee-addr-profile-drive))
(define profile-sport-kmh (eeprom-read-i ee-addr-profile-sport))

; ---- Dashboard drive profile (0x203 byte 0) ----
; Separate from 0x20C's speed byte: 0x203 says *which* profile the dashboard
; is in, 0x20C says what speed it wants for it. With use-other-profiles on,
; the rider's own km/h for the active profile replaces the dashboard's value.
(define profile-walk 0x01)
(define profile-eco 0x02)
(define profile-sport 0x03)
(define profile-race 0x04)   ; GT3 only
(define profile-drive 0x05)
(define last-profile-mode 0)

(define parkmode 0)

(define last-100-msg-time (systime))
(define dashboard-boot-gap-ms 2000)

; 0x100 byte 2 is the dashboard's mode byte: 0x04 normal drive, 0x06 cruise,
; anything else parked.
(define dash-mode-drive 0x04)
(define dash-mode-cruise 0x06)

; The dashboard won't light its cruise indicator off its own request -- it
; waits for the controller to acknowledge on 0x212 byte 2, 0x05 while cruise
; is engaged and 0x00 otherwise. Left at 0x00 the icon never appears, even
; though the VESC really is holding speed.
(define mcu-cruise-ack 0x05)
(define mcu-cruise-idle 0x00)

; Raw 0x100 throttle/brake, 0x00-0xC8 as the dashboard sends them. Express
; doesn't drive the motor from these -- the master VESC does -- it reads them
; for the settings page and for the cancel gesture below.
(define last-throttle-raw 0)
(define last-brake-raw 0)

; Holding throttle and brake both past half travel for 2s cancels the
; temporary profile override, so it can be dropped from the bar without
; reaching for a phone. Half of the 0-200 range is 100.
(define profile-cancel-threshold 100)
(define profile-cancel-hold-ms 2000)
(define profile-cancel-since nil)   ; nil = not currently held

(defun check-profile-cancel (now)
    (if (and (> last-throttle-raw profile-cancel-threshold)
             (> last-brake-raw profile-cancel-threshold))
        (progn
            (if (eq profile-cancel-since nil)
                (setq profile-cancel-since now))
            (if (and (= use-other-profiles 1)
                     (>= (- now profile-cancel-since) profile-cancel-hold-ms))
                (progn
                    (setq use-other-profiles 0)
                    (relay-active-speed)
                    ; cleared so a continued hold can't re-fire every frame
                    (setq profile-cancel-since nil))))
        (setq profile-cancel-since nil)))

(defun handle-park-state (data)
    (let ((now (systime))
          (mode-byte (bufget-u8 data 2)))
        (progn
            ; A gap in the dashboard's ~20ms heartbeat means it was switched
            ; off (or Express just booted). Drop the temporary profile
            ; override so the dashboard's own speeds come back, then re-apply.
            (if (> (- now last-100-msg-time) dashboard-boot-gap-ms)
                (progn
                    (setq use-other-profiles 0)
                    (relay-active-speed)))
            (setq last-100-msg-time now)
            (setq last-throttle-raw (bufget-u8 data 0))
            (setq last-brake-raw (bufget-u8 data 1))
            (check-profile-cancel now)
            (bufset-u8 buf-212 2
                (if (= mode-byte dash-mode-cruise) mcu-cruise-ack mcu-cruise-idle))
            (setq parkmode (if (or (= mode-byte dash-mode-drive) (= mode-byte dash-mode-cruise)) 0 1)))))

(defun dispatch-sid (id data)
    (cond
        ((= id 0x20C) (progn (handle-lights data) (handle-drive-mode data)))
        ((= id 0x203) (handle-drive-profile data))
        ((= id 0x100) (handle-park-state data))
        (t nil)))

(defun event-loop ()
    (loopwhile t
        (recv
            ((event-can-sid . ((? id) . (? data))) (dispatch-sid id data))
            ((event-can-eid . ((? id) . (? data))) (dispatch-eid id data))
            ((event-data-rx . (? data)) (handle-qml-data data))
            (_ nil))))

; ---- Extended-ID (29-bit) J1939 traffic ----
;
; Addressing: this board answers as the BMS at source address 0x07, the app
; is 0x3E. Every ID we receive ends ...073E (SA=0x3E -> DA=0x07) and every
; ID we send ends ...3E07. Note the Ninebot-X3-Protocol repo's docs/j1939.md
; states the reverse (app 0x07, BMS 0x3E); its own xiaodash-handler map and
; the reference firmware's actual RX/TX split both contradict it, so the
; addresses used here follow the firmware, which is known to work.

; The i32 suffixes are load-bearing. A bare hex literal is TOKTYPEI, which
; LispBM encodes with lbm_enc_i -- a 28-bit fixnum. Every 29-bit CAN ID here
; would be silently truncated (0x18EC073E stores as -118749378), while the
; event delivers the ID as a real i32, so the comparisons never match and no
; extended frame is ever dispatched.
(define eid-tp-cm-rx 0x18EC073Ei32)   ; app -> us, TP.CM (RTS)
(define eid-tp-dt-rx 0x18EB073Ei32)   ; app -> us, TP.DT (data)
(define eid-tp-cm-tx 0x1CEC3E07i32)   ; us -> app, TP.CM (CTS / EOM ACK)
(define eid-param-rx 0x18EF073Ei32)   ; app -> us, parameter/selector request
(define eid-param-tx 0x18EF3E07i32)   ; us -> app, parameter response

(define tp-ctl-rts 0x10)
(define tp-ctl-cts 0x11)
(define tp-ctl-eom 0x13)
(define tp-ctl-abort 0xFF)

; ---- BMS timer (0x424) ----
;
; Not a seconds counter -- a packed bitfield: bits 0-5 seconds, 6-11 minutes,
; 12-16 hours, 17+ days. Ticked once a second and written little-endian into
; 0x424 bytes 0-3. The value the app sends during time sync is in this same
; packed form, not a Unix epoch, so it can be stored verbatim.
;
; Not persisted -- restarting the script resets it to zero and the app has to
; set the time again, same as the reference firmware.
;
; The to-u32 casts are load-bearing, for the same reason the CAN IDs need i32
; suffixes: shifting a plain fixnum left by 17 or 24 overflows LispBM's 28-bit
; integer and silently corrupts the day field. Any byte >= 8 shifted by 24
; already exceeds it.
(define bms-clock-base 0u32)     ; total seconds at the last set
(define bms-clock-base-ms 0)     ; systime when that was set

; Pack/unpack between the wire's bitfield and a plain seconds count. Working
; in total seconds removes the manual carry entirely -- one division chain
; instead of three conditional roll-overs.
(defun packed-to-total (p)
    (+ (bitwise-and p 0x3F)
       (+ (* (bitwise-and (shr p 6) 0x3F) 60)
          (+ (* (bitwise-and (shr p 12) 0x1F) 3600)
             (* (shr p 17) 86400)))))

(defun total-to-packed (tot)
    (let ((days (/ tot 86400))
          (rem (mod tot 86400)))
        (let ((hours (/ rem 3600))
              (mins (mod (/ rem 60) 60))
              (secs (mod rem 60)))
            (bitwise-or (to-u32 secs)
                (bitwise-or (shl (to-u32 mins) 6)
                    (bitwise-or (shl (to-u32 hours) 12) (shl (to-u32 days) 17)))))))

; The clock is now a pure function of systime rather than a counter that gets
; incremented. Nothing accumulates, so no amount of scheduling delay, missed
; wake-ups or interpreter starvation can shift it -- if the publisher is late
; the value is simply correct when it does run. Any remaining error is
; systime's own accuracy, not this script's.
(defun bms-clock-total ()
    (+ bms-clock-base (/ (- (systime) bms-clock-base-ms) 1000)))

(defun bms-clock-set-packed (p)
    (progn
        (setq bms-clock-base (to-u32 (packed-to-total p)))
        (setq bms-clock-base-ms (systime))))

(defun bms-timer-publish ()
    (let ((packed (total-to-packed (bms-clock-total))))
        (progn
            (bufset-u8 buf-424 0 (bitwise-and packed 255))
            (bufset-u8 buf-424 1 (bitwise-and (shr packed 8) 255))
            (bufset-u8 buf-424 2 (bitwise-and (shr packed 16) 255))
            (bufset-u8 buf-424 3 (bitwise-and (shr packed 24) 255)))))

(defun bms-timer-task ()
    (loopwhile t
        (progn
            (bms-timer-publish)
            (sleep 0.2))))

; ---- Time sync (J1939 transport protocol) ----
;
; The app pushes the clock as a 2-packet TP transfer: RTS -> we answer CTS ->
; two TP.DT frames (7 then 5 payload bytes) -> we answer EOM ACK. The clock
; itself is a little-endian u32 at offset 6 of the reassembled payload.

(define tp-buf (bufcreate 12))
(define tp-seq 0)                  ; 0 idle, 1 awaiting packet 1, 2 awaiting packet 2
(define tp-total-size 0)
(define tp-total-packets 0)
(define tp-time-offset 6)

(defun tp-store (data dst count)
    (progn
        (var i 0)
        (loopwhile (< i count)
            (progn
                (bufset-u8 tp-buf (+ dst i) (bufget-u8 data (+ i 1)))
                (setq i (+ i 1))))))

(defun tp-send-cts (data)
    (let ((cts (bufcreate 8)))
        (progn
            (bufset-u8 cts 0 tp-ctl-cts)
            (bufset-u8 cts 1 tp-total-packets)
            (bufset-u8 cts 2 0x01)          ; next expected sequence number
            (bufset-u8 cts 3 0xFF)
            (bufset-u8 cts 4 0xFF)
            (bufset-u8 cts 5 (bufget-u8 data 5))   ; echo the PGN back
            (bufset-u8 cts 6 (bufget-u8 data 6))
            (bufset-u8 cts 7 (bufget-u8 data 7))
            (can-send-eid eid-tp-cm-tx cts))))

(defun tp-send-eom ()
    (let ((eom (bufcreate 8)))
        (progn
            (bufset-u8 eom 0 tp-ctl-eom)
            (bufset-u8 eom 1 (bitwise-and tp-total-size 255))
            (bufset-u8 eom 2 (bitwise-and (shr tp-total-size 8) 255))
            (bufset-u8 eom 3 tp-total-packets)
            (bufset-u8 eom 4 0xFF)
            (bufset-u8 eom 5 0x00)
            (bufset-u8 eom 6 0xEF)
            (bufset-u8 eom 7 0x00)
            (can-send-eid eid-tp-cm-tx eom))))

(defun tp-apply-time ()
    (progn
        (if (= debug-eid 1)
            (print (list "tp payload"
                (bufget-u8 tp-buf 0) (bufget-u8 tp-buf 1) (bufget-u8 tp-buf 2)
                (bufget-u8 tp-buf 3) (bufget-u8 tp-buf 4) (bufget-u8 tp-buf 5)
                (bufget-u8 tp-buf 6) (bufget-u8 tp-buf 7) (bufget-u8 tp-buf 8)
                (bufget-u8 tp-buf 9) (bufget-u8 tp-buf 10) (bufget-u8 tp-buf 11))))
        (bms-clock-set-packed
            (bitwise-or (to-u32 (bufget-u8 tp-buf tp-time-offset))
                (bitwise-or (shl (to-u32 (bufget-u8 tp-buf (+ tp-time-offset 1))) 8)
                    (bitwise-or (shl (to-u32 (bufget-u8 tp-buf (+ tp-time-offset 2))) 16)
                                (shl (to-u32 (bufget-u8 tp-buf (+ tp-time-offset 3))) 24)))))
        (if (= debug-eid 1) (print (list "clock set to" bms-clock-base)))
        (bms-timer-publish)))

; Abort frames (control 0xFF) are ignored, matching the reference. The buflen
; guards are not optional: these read bytes 5-7, and bufget-u8 past the end of
; a short frame is a hard eval_error that would kill the shared event loop --
; taking lights and profile switching down with it.
(defun handle-tp-cm (data)
    (if (and (>= (buflen data) 8) (= (bufget-u8 data 0) tp-ctl-rts))
        (progn
            (setq tp-total-size
                (bitwise-or (bufget-u8 data 1) (shl (bufget-u8 data 2) 8)))
            (setq tp-total-packets (bufget-u8 data 3))
            (setq tp-seq 1)
            (tp-send-cts data))))

(defun handle-tp-dt (data)
    (if (>= (buflen data) 8)
        (let ((seq (bufget-u8 data 0)))
            (cond
                ((and (= tp-seq 1) (= seq 0x01))
                    (progn (tp-store data 0 7) (setq tp-seq 2)))
                ((and (= tp-seq 2) (= seq 0x02))
                    (progn
                        (tp-store data 7 5)
                        (setq tp-seq 0)
                        (tp-send-eom)
                        (tp-apply-time)))
                (t nil)))))

; ---- Parameter request (0x18EF073E) ----
;
; Request is 4 bytes: 01 01 SS 80, where SS selects what's being asked for.
; Only the two single-value reads the reference answers are implemented:
; 0x8C pack voltage, 0x8D pack current, both x100 of the real value (same
; scaling as 0x420). The Xiaodash app also polls SS = 0x00/0x40/0x80/0xC0/
; 0x82 for whole BMS telemetry pages, which are answered as 133-byte blocks
; over 19 TP.DT frames on 0x1CEB3E07 -- not implemented here, and not in the
; reference either. See the protocol repo's xiaodash-handler map.
(define param-voltage 0x8C)
(define param-current 0x8D)

(defun param-response-value (param)
    (if (= param param-voltage)
        (to-i (* voltage-v 100.0))
        (to-i (* (canget-current vesc-can-id) 100.0))))

(defun handle-param-req (data)
    (if (and (= bms-mode 0)
             (>= (buflen data) 4)
             (= (bufget-u8 data 0) 0x01)
             (= (bufget-u8 data 1) 0x01))
        (let ((param (bufget-u8 data 2)))
            (if (or (= param param-voltage) (= param param-current))
                (let ((value (param-response-value param))
                      (resp (bufcreate 5)))
                    (progn
                        (bufset-u8 resp 0 0x01)
                        (bufset-u8 resp 1 0x04)
                        (bufset-u8 resp 2 param)
                        (bufset-u8 resp 3 (bitwise-and value 255))
                        (bufset-u8 resp 4 (bitwise-and (shr value 8) 255))
                        (can-send-eid eid-param-tx resp)))))))

; Diagnostic. Off by default; enable live from the VESC Tool Lisp console
; with (setq debug-eid 1). Only J1939-range IDs are logged -- VESC's own
; status frames are extended too, but sit below 0x10000000, and printing
; those would bury everything at their broadcast rate.
(define debug-eid 0)
(define eid-j1939-floor 0x10000000i32)   ; i32 for the same reason as above

(defun log-eid (id data)
    (if (and (= debug-eid 1) (> id eid-j1939-floor) (>= (buflen data) 3))
        (print (list "eid" id "len" (buflen data) "b0" (bufget-u8 data 0)
                     "b1" (bufget-u8 data 1) "b2" (bufget-u8 data 2)))))

(defun dispatch-eid (id data)
    (progn
        (log-eid id data)
        (cond
            ((= id eid-tp-cm-rx) (handle-tp-cm data))
            ((= id eid-tp-dt-rx) (handle-tp-dt data))
            ((= id eid-param-rx) (handle-param-req data))
            (t nil))))

; ---- Lights (0x20C) ----

; The indicator byte is a bitfield, not an enum -- bit 0 left, bit 1 right.
; Test the bit, don't compare the whole byte: the dashboard also sets other
; bits in it (bit 7 = underglow/position light), so a whole-byte compare
; against a bare 1/2/3 misses every real value.
(define indicator-mask-left 0x01)
(define indicator-mask-right 0x02)

; Rear-light byte, grouped by state rather than by variant -- the G3, ZT3
; and GT3 dashboards send different values for the same physical state
; (G3 / ZT3 / GT3 in that order). Anything unrecognised means off, so a
; G3-only table leaves a ZT3's or GT3's rear light dark permanently.
(define rear-off 0x10)
(define rear-charge-breathing 0x12)
(define rear-xlight 0x64)                    ; ZT3 hands off to its own controller
(define rear-steady (list 0x14 0x44 0x54))
(define rear-brake (list 0x16 0x56))
(define rear-flashing (list 0x18 0x48 0x58))

(define last-indicator-byte 0)
(define last-rear-byte rear-off)

; Brake flash only. Turn-signal blinking is not done here -- the dashboard
; blinks the indicators itself by toggling the bits in 0x20C, so the pins
; follow the byte directly.
(define rear-blink-state 0)

(defun apply-rear-light (rear-byte)
    (cond
        ((list-contains rear-steady rear-byte) (pwm-set-duty 0.5 pwm-channel))
        ((list-contains rear-brake rear-byte) (pwm-set-duty 1.0 pwm-channel))
        ((list-contains rear-flashing rear-byte)
            (pwm-set-duty (if (= rear-blink-state 1) 1.0 0.0) pwm-channel))
        ((= rear-byte rear-charge-breathing)
            (pwm-set-duty (if (= enable-charge-light 1) 0.5 0.0) pwm-channel))
        ; ZT3 hands the rear light to its own XLight controller here --
        ; leave the duty untouched rather than forcing it off.
        ((= rear-byte rear-xlight) nil)
        (t (pwm-set-duty 0.0 pwm-channel))))

(defun apply-indicators (indicator-byte)
    (progn
        (gpio-write pin-indicator-left
            (if (!= 0 (bitwise-and indicator-byte indicator-mask-left)) 1 0))
        (gpio-write pin-indicator-right
            (if (!= 0 (bitwise-and indicator-byte indicator-mask-right)) 1 0))))

(defun apply-underglow ()
    (gpio-write pin-multipin
        (if (and (= underglow-on-park 1) (= parkmode 1) (list-contains rear-steady last-rear-byte)) 1 0)))

; The bytes keep being tracked while lights-manual is set, so the settings
; page still shows what the dashboard is asking for -- only the outputs are
; suppressed.
(defun handle-lights (data)
    (progn
        (setq last-indicator-byte (bufget-u8 data 0))
        (setq last-rear-byte (bufget-u8 data 1))
        (if (= lights-manual 0)
            (progn
                (apply-indicators last-indicator-byte)
                (apply-rear-light last-rear-byte)))))

; PWR_ON gates the 12V rail every light output draws from, so it is held high
; here on every pass rather than only once at load. Re-asserting an already
; high pin costs nothing, and it means nothing -- a glitch, a sleep/wake, an
; accidental reconfigure elsewhere -- can leave the rail down with no way back
; short of a reboot.
(defun assert-power-on ()
    (gpio-write pin-pwr_on 1))

; Bench switch. (setq lights-manual 1) from the Lisp console stands the light
; outputs down so gpio-write / pwm-set-duty typed at the console actually
; stick -- otherwise this loop overwrites them within 100ms and a manual test
; looks like it did nothing. PWR_ON keeps being asserted either way, since
; the rail has to stay up for any manual test to mean anything.
(define lights-manual 0)

(defun blink-timer ()
    (loopwhile t
        (progn
            (assert-power-on)
            (setq rear-blink-state (- 1 rear-blink-state))
            (if (= lights-manual 0)
                (progn
                    (apply-indicators last-indicator-byte)
                    (apply-rear-light last-rear-byte)
                    (apply-underglow)))
            (sleep 0.1))))

; ---- Profile-switch speed relay ----

(define last-drive-mode-byte 0)

(defun speed-buf-x10 (speed-x10)
    (let ((buf (bufcreate 2)))
        (progn
            (bufset-u8 buf 0 (bitwise-and speed-x10 255))
            (bufset-u8 buf 1 (bitwise-and (shr speed-x10 8) 255))
            buf)))

; The rider's km/h for whichever profile the dashboard is currently in.
; Unknown/unset profiles fall back to the dashboard's own value rather than
; to zero, so an unrecognised mode byte can't strand the vehicle at 0 km/h.
(defun profile-kmh-for (mode)
    (cond
        ((= mode profile-walk) profile-walk-kmh)
        ((= mode profile-eco) profile-eco-kmh)
        ((= mode profile-drive) profile-drive-kmh)
        ((or (= mode profile-sport) (= mode profile-race)) profile-sport-kmh)
        (t nil)))

; x10 units, matching the VESC side's expectation.
(defun active-speed-x10 ()
    (if (= use-other-profiles 1)
        (let ((kmh (profile-kmh-for last-profile-mode)))
            (if (eq kmh nil)
                (* last-drive-mode-byte 5)
                (* kmh 10)))
        (* last-drive-mode-byte 5)))   ; 0x20C byte/2 km/h, x10

(defun speed-relay-buf () (speed-buf-x10 (to-i (active-speed-x10))))

(defun relay-active-speed ()
    (if (= disable-prof-sw 0)
        (relay-speed-to-targets relay-targets (speed-relay-buf))))

(defun handle-drive-mode (data)
    (let ((drive-mode-byte (bufget-u8 data 2)))
        (if (!= drive-mode-byte last-drive-mode-byte)
            (progn
                (setq last-drive-mode-byte drive-mode-byte)
                (relay-active-speed)))))

(defun handle-drive-profile (data)
    (let ((mode (bufget-u8 data 0)))
        (if (!= mode last-profile-mode)
            (progn
                (setq last-profile-mode mode)
                (relay-active-speed)))))

(defun send-current-speed-to (target-id)
    (if (= disable-prof-sw 0)
        (canmsg-send target-id slot-speed-relay (speed-relay-buf))))

; ---- Controller (MCU) status frame emulation ----
; Byte templates copied verbatim from the reference firmware; only
; specific bytes patched live.

(defun erpm-to-kmh (erpm)
    (let ((erpm-abs (if (< erpm 0.0) (- 0.0 erpm) erpm)))
        (let ((mech-rpm (/ erpm-abs (/ motor-poles 2.0)))
              (wheel-circum-m (* 3.14159 (/ (to-float wheel-diam-mm) 1000.0))))
            (* (/ mech-rpm 60.0) wheel-circum-m 3.6))))

(defun handle-vesc-info (data)
    (progn
        (setq vesc-can-id (bufget-u8 data 0))
        (setq motor-poles (bufget-u8 data 1))
        (setq wheel-diam-mm (bitwise-or (bufget-u8 data 2) (shl (bufget-u8 data 3) 8)))
        (setq battery-pct (bufget-u8 data 4))
        (if (>= (buflen data) 8)
            (progn
                (setq voltage-v (/ (bitwise-or (bufget-u8 data 5) (shl (bufget-u8 data 6) 8)) 10.0))
                (setq motor-temp-c (bufget-u8 data 7))))
        (add-relay-target vesc-can-id)
        (send-current-speed-to vesc-can-id)
        (send-external-adc-to vesc-can-id)))

(defun handle-vesc-register (data)
    (let ((id (bufget-u8 data 0)))
        (progn
            (add-relay-target id)
            (send-current-speed-to id)
            (send-external-adc-to id))))

(defun vesc-info-listener ()
    (loopwhile t
        (let ((data (canmsg-recv slot-vesc-info -1.0)))
            (if (not-eq data 'timeout) (handle-vesc-info data)))))

(defun vesc-register-listener ()
    (loopwhile t
        (let ((data (canmsg-recv slot-vesc-register -1.0)))
            (if (not-eq data 'timeout) (handle-vesc-register data)))))

(define buf-211 (bufcreate 8))
(bufset-u8 buf-211 0 0xE4) (bufset-u8 buf-211 1 0xE8) (bufset-u8 buf-211 2 0x2E)

(define buf-212 (bufcreate 8))
(bufset-u8 buf-212 0 0x48) (bufset-u8 buf-212 1 0x01) (bufset-u8 buf-212 7 0x59)

(define buf-341 (bufcreate 8))
(bufset-u8 buf-341 4 0x02)

(define buf-342 (bufcreate 8))
(define buf-343 (bufcreate 8))
(define buf-344 (bufcreate 8))

(define buf-401 (bufcreate 8))
(bufset-u8 buf-401 4 0x02)

(define buf-310 (bufcreate 8))
(bufset-u8 buf-310 0 0xF1) (bufset-u8 buf-310 1 0x0E) (bufset-u8 buf-310 2 0x08) (bufset-u8 buf-310 3 0x07)
(bufset-u8 buf-310 4 0x02) (bufset-u8 buf-310 5 0x01) (bufset-u8 buf-310 6 0x01) (bufset-u8 buf-310 7 0xC8)

(define buf-311 (bufcreate 8))
(bufset-u8 buf-311 0 0x39) (bufset-u8 buf-311 1 0x1E) (bufset-u8 buf-311 2 0x07) (bufset-u8 buf-311 3 0x3F)
(bufset-u8 buf-311 4 0x90) (bufset-u8 buf-311 5 0x01)

(define buf-420 (bufcreate 8))

(define buf-421 (bufcreate 8))
(bufset-u8 buf-421 0 0x39) (bufset-u8 buf-421 1 0x39) (bufset-u8 buf-421 2 0x39) (bufset-u8 buf-421 3 0x39)
(bufset-u8 buf-421 4 0xFB) (bufset-u8 buf-421 5 0x04) (bufset-u8 buf-421 6 0x64) (bufset-u8 buf-421 7 0x02)

(define buf-422 (bufcreate 8))
(bufset-u8 buf-422 2 0x20) (bufset-u8 buf-422 4 0x15) (bufset-u8 buf-422 6 0x02)

(define buf-423 (bufcreate 8))
(bufset-u8 buf-423 0 0x84) (bufset-u8 buf-423 1 0x03) (bufset-u8 buf-423 2 0x64)
(bufset-u8 buf-423 4 0x40) (bufset-u8 buf-423 5 0x01) (bufset-u8 buf-423 6 0x01)

(define buf-424 (bufcreate 8))   ; all-zero "BMS timer", unpatched in the reference too

(define buf-425 (bufcreate 8))
(bufset-u8 buf-425 0 0x01) (bufset-u8 buf-425 1 0x10) (bufset-u8 buf-425 2 0x48) (bufset-u8 buf-425 3 0x35)
(bufset-u8 buf-425 4 0x35) (bufset-u8 buf-425 5 0x35) (bufset-u8 buf-425 6 0x01) (bufset-u8 buf-425 7 0xFF)

(define buf-500 (bufcreate 8))
(bufset-u8 buf-500 0 0x47) (bufset-u8 buf-500 1 0x47) (bufset-u8 buf-500 2 0x48) (bufset-u8 buf-500 3 0xFF)
(bufset-u8 buf-500 4 0x47) (bufset-u8 buf-500 5 0x47) (bufset-u8 buf-500 6 0x47) (bufset-u8 buf-500 7 0xFF)

(define buf-501 (bufcreate 8))
(bufset-u8 buf-501 0 0xB4) (bufset-u8 buf-501 1 0xC1) (bufset-u8 buf-501 2 0x83) (bufset-u8 buf-501 3 0x58)
(bufset-u8 buf-501 4 0x31) (bufset-u8 buf-501 5 0xE5) (bufset-u8 buf-501 6 0xB2) (bufset-u8 buf-501 7 0x6B)

(define buf-502 (bufcreate 8))
(bufset-u8 buf-502 0 0x12) (bufset-u8 buf-502 1 0xBC) (bufset-u8 buf-502 2 0x86)
(bufset-u8 buf-502 3 0x0E) (bufset-u8 buf-502 4 0x1B) (bufset-u8 buf-502 5 0x36)

(define batt-freeze-threshold-pct 11)

(defun reported-battery-pct ()
    (if (and (= freeze-batt-below-11 1) (< battery-pct batt-freeze-threshold-pct))
        batt-freeze-threshold-pct
        battery-pct))

; (buffer id interval-ms is-bms) -- is-bms gates the whole BMS group
; together on bms-mode, see send-mcu-frame-if-due.
(define mcu-frames (list
    (list buf-310 0x310 200 1)
    (list buf-311 0x311 200 1)
    (list buf-420 0x420 500 1)
    (list buf-421 0x421 500 1)
    (list buf-422 0x422 500 1)
    (list buf-423 0x423 500 1)
    (list buf-424 0x424 1000 1)
    (list buf-425 0x425 500 1)
    (list buf-500 0x500 2000 1)
    (list buf-501 0x501 2000 1)
    (list buf-502 0x502 2000 1)
    (list buf-211 0x211 100 0)
    (list buf-212 0x212 100 0)
    (list buf-341 0x341 200 0)
    (list buf-342 0x342 200 0)
    (list buf-343 0x343 100 0)
    (list buf-344 0x344 200 0)
    (list buf-401 0x401 500 0)))

(define mcu-last-sent (list 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0))
(define mcu-frame-count 18)

; Polarity is intentionally inverted from the reference firmware, and the
; flash phase is deliberately stateless (recomputed every call, not
; tracked) -- an earlier stateful version got stuck flashing permanently
; on real hardware. Don't "fix" either.
; Counted in transmitted 0x211 frames, not wall-clock. 0x211 only goes out
; every 100ms while patch-telemetry runs every 20ms, so a time-window test
; gets sampled at an unrelated phase and the fake frames mostly never reach
; the wire. Deciding once per actual send makes the 1 km/h frame land
; between the real ones deterministically.
; Slightly tighter than the reference firmware, which ticks its display task
; every 50ms and counts 20 real ticks (1000ms) then 2 override ticks (100ms)
; -- 10 real frames to 1 fake at 0x211's 100ms period. Tuning: lower
; real-frames to reset the dashboard's overspeed timer more often, raise
; fake-frames if it needs to *see* the low value for longer.
(define speed-warn-real-frames 8)    ; real 0x211 frames between fake bursts
(define speed-warn-fake-frames 1)    ; consecutive fake frames per burst
(define speed-warn-cycle-frames (+ speed-warn-real-frames speed-warn-fake-frames))
(define speed-warn-fake-01kmh 10)    ; 1.0 km/h
(define speed-warn-frame-count 0)

(define last-real-speed-01kmh 0)

; Deliberately the dashboard's own limit (0x20C byte/2 km/h), NOT the active
; one -- this must not follow use-other-profiles. The dashboard raises its
; native overspeed warning by comparing the speed *it* displays against the
; limit *it* thinks is set; it has no idea the limit was overridden. Tracking
; a custom higher limit here would stop faking exactly when the dashboard
; starts complaining. A custom lower limit is harmless either way, since the
; rider never reaches the dashboard's threshold.
(defun profile-limit-01kmh () (* last-drive-mode-byte 5))

; Resets the counter whenever the speed is legal again, so the burst phase
; always restarts from a known point and can't latch on.
(defun display-speed-01kmh (real-speed-01kmh)
    (if (or (= bypass-speed-limit-warning 0) (<= real-speed-01kmh (profile-limit-01kmh)))
        (progn
            (setq speed-warn-frame-count 0)
            real-speed-01kmh)
        (progn
            (setq speed-warn-frame-count (mod (+ speed-warn-frame-count 1) speed-warn-cycle-frames))
            (if (< speed-warn-frame-count speed-warn-fake-frames)
                speed-warn-fake-01kmh
                real-speed-01kmh))))

; Called once per transmitted 0x211, from send-mcu-frame-if-due -- 0x211's
; speed field is owned entirely by this path, patch-telemetry doesn't touch it.
; 0x212 carries a speed field too ("MCU Throttle/Brake, Boot State, Speed"
; in the reference's own scheduled-message table). Both frames must carry
; the same value: publishing the real speed here while faking only 0x211
; leaves the dashboard a truthful copy to raise its overspeed warning from,
; which is exactly what defeated the bypass. The reference sidesteps this by
; never writing 0x212 bytes 4-5 at all -- they stay 0 for its whole runtime.
(defun patch-display-speed ()
    (let ((display-01kmh (display-speed-01kmh last-real-speed-01kmh)))
        (progn
            (bufset-u8 buf-211 6 (bitwise-and display-01kmh 255))
            (bufset-u8 buf-211 7 (bitwise-and (shr display-01kmh 8) 255))
            (bufset-u8 buf-212 4 (bitwise-and display-01kmh 255))
            (bufset-u8 buf-212 5 (bitwise-and (shr display-01kmh 8) 255)))))

(defun patch-telemetry ()
    (let ((speed-kmh (erpm-to-kmh (canget-rpm vesc-can-id))))
        (let ((speed-01kmh (* (to-i (+ speed-kmh 0.5)) 10))
              (temp-byte (to-i (+ motor-temp-c 20.0))))
            (progn
                (setq last-real-speed-01kmh speed-01kmh)
                (bufset-u8 buf-212 7 (bitwise-and temp-byte 255))))))

(defun patch-battery ()
    (let ((voltage-001v (to-i (* voltage-v 100.0)))
          (current-001a (to-i (* (canget-current vesc-can-id) 100.0)))
          (soc-01pct (to-i (* (reported-battery-pct) 10.0))))
        (progn
            (bufset-u8 buf-420 0 (bitwise-and voltage-001v 255))
            (bufset-u8 buf-420 1 (bitwise-and (shr voltage-001v 8) 255))
            (bufset-u8 buf-420 2 (bitwise-and current-001a 255))
            (bufset-u8 buf-420 3 (bitwise-and (shr current-001a 8) 255))
            (bufset-u8 buf-420 4 (bitwise-and soc-01pct 255))
            (bufset-u8 buf-420 5 (bitwise-and (shr soc-01pct 8) 255)))))

(defun send-mcu-frame-if-due (idx now)
    (let ((entry (ix mcu-frames idx))
          (last (ix mcu-last-sent idx)))
        (let ((buf (ix entry 0))
              (id (ix entry 1))
              (interval (ix entry 2))
              (is-bms (ix entry 3)))
            (if (and (>= (- now last) interval) (or (= is-bms 0) (= bms-mode 0)))
                (progn
                    (if (= id 0x211) (patch-display-speed))
                    (can-send-sid id buf)
                    (setix mcu-last-sent idx now))))))

(define qml-telemetry-interval 300)
(define qml-telemetry-last-sent 0)

(defun send-telemetry ()
    (let ((speed-kmh (erpm-to-kmh (canget-rpm vesc-can-id)))
          (current (canget-current vesc-can-id)))
        (let ((speed-x10 (to-i (* speed-kmh 10.0)))
              (voltage-x10 (to-i (* voltage-v 10.0)))
              (current-x10 (to-i (* current 10.0)))
              (buf (bufcreate 18)))
            (progn
                (bufset-u8 buf 0 0x03)
                (bufset-u8 buf 1 (bitwise-and speed-x10 255))
                (bufset-u8 buf 2 (bitwise-and (shr speed-x10 8) 255))
                (bufset-u8 buf 3 (bitwise-and (to-i motor-temp-c) 255))
                (bufset-u8 buf 4 (bitwise-and voltage-x10 255))
                (bufset-u8 buf 5 (bitwise-and (shr voltage-x10 8) 255))
                (bufset-u8 buf 6 (bitwise-and current-x10 255))
                (bufset-u8 buf 7 (bitwise-and (shr current-x10 8) 255))
                (bufset-u8 buf 8 last-indicator-byte)
                (bufset-u8 buf 9 last-rear-byte)
                (bufset-u8 buf 10 (bitwise-and (to-i (/ (active-speed-x10) 10)) 255))
                (bufset-u8 buf 11 last-throttle-raw)
                (bufset-u8 buf 12 last-brake-raw)
                ; BMS clock, unpacked here rather than sent as the raw u32 --
                ; VESC Tool's variable transport is float32, which can't
                ; resolve a +1/s change at ~1.8e9. Small fields survive it.
                (bufset-u8 buf 13 (bitwise-and (/ (mod (bms-clock-total) 86400) 3600) 255))
                (bufset-u8 buf 14 (bitwise-and (mod (/ (bms-clock-total) 60) 60) 255))
                (bufset-u8 buf 15 (bitwise-and (mod (bms-clock-total) 60) 255))
                (bufset-u8 buf 16 last-profile-mode)
                (bufset-u8 buf 17 use-other-profiles)
                (send-data buf)))))

(defun mcu-scheduler ()
    (loopwhile t
        (progn
            (patch-telemetry)
            (patch-battery)
            (var now (systime))
            (var i 0)
            (loopwhile (< i mcu-frame-count)
                (progn
                    (send-mcu-frame-if-due i now)
                    (setq i (+ i 1))))
            (if (>= (- now qml-telemetry-last-sent) qml-telemetry-interval)
                (progn
                    (send-telemetry)
                    (setq qml-telemetry-last-sent now)))
            (sleep 0.02))))

; QML settings channel -- send-data/event-data-rx here, sendCustomAppData/
; customAppDataReceived on the QML side.

(defun send-settings-reply ()
    (let ((buf (bufcreate 13)))
        (progn
            (bufset-u8 buf 0 0x01)
            (bufset-u8 buf 1 disable-prof-sw)
            (bufset-u8 buf 2 freeze-batt-below-11)
            (bufset-u8 buf 3 bms-mode)
            (bufset-u8 buf 4 bypass-speed-limit-warning)
            (bufset-u8 buf 5 underglow-on-park)
            (bufset-u8 buf 6 enable-charge-light)
            (bufset-u8 buf 7 external-adc)
            (bufset-u8 buf 8 use-other-profiles)
            (bufset-u8 buf 9 profile-walk-kmh)
            (bufset-u8 buf 10 profile-eco-kmh)
            (bufset-u8 buf 11 profile-drive-kmh)
            (bufset-u8 buf 12 profile-sport-kmh)
            (send-data buf))))

(defun apply-settings-from-qml (data)
    (progn
        (setq disable-prof-sw (bufget-u8 data 1))
        (setq freeze-batt-below-11 (bufget-u8 data 2))
        (setq bms-mode (bufget-u8 data 3))
        (if (>= (buflen data) 5)
            (setq bypass-speed-limit-warning (bufget-u8 data 4)))
        (if (>= (buflen data) 7)
            (progn
                (setq underglow-on-park (bufget-u8 data 5))
                (setq enable-charge-light (bufget-u8 data 6))))
        (if (>= (buflen data) 8)
            (setq external-adc (bufget-u8 data 7)))
        (if (>= (buflen data) 13)
            (progn
                (setq use-other-profiles (bufget-u8 data 8))
                (setq profile-walk-kmh (bufget-u8 data 9))
                (setq profile-eco-kmh (bufget-u8 data 10))
                (setq profile-drive-kmh (bufget-u8 data 11))
                (setq profile-sport-kmh (bufget-u8 data 12))))
        (eeprom-store-i ee-addr-disable-prof-sw disable-prof-sw)
        (eeprom-store-i ee-addr-freeze-batt-below-11 freeze-batt-below-11)
        (eeprom-store-i ee-addr-bms-mode bms-mode)
        (eeprom-store-i ee-addr-bypass-speed-limit-warning bypass-speed-limit-warning)
        (eeprom-store-i ee-addr-underglow-on-park underglow-on-park)
        (eeprom-store-i ee-addr-enable-charge-light enable-charge-light)
        (eeprom-store-i ee-addr-external-adc external-adc)
        (eeprom-store-i ee-addr-profile-walk profile-walk-kmh)
        (eeprom-store-i ee-addr-profile-eco profile-eco-kmh)
        (eeprom-store-i ee-addr-profile-drive profile-drive-kmh)
        (eeprom-store-i ee-addr-profile-sport profile-sport-kmh)
        (relay-external-adc-to-targets relay-targets)
        ; Push the new limit immediately -- otherwise it wouldn't reach the
        ; VESC until the rider next changed profile on the dashboard.
        (relay-active-speed)
        (send-settings-reply)))

(defun handle-qml-data (data)
    (let ((cmd (bufget-u8 data 0)))
        (cond
            ((= cmd 0x01) (send-settings-reply))
            ((= cmd 0x02) (apply-settings-from-qml data))
            (t nil))))

(event-register-handler (spawn event-loop))
(event-enable 'event-can-sid)
(event-enable 'event-can-eid)
(event-enable 'event-data-rx)

(spawn blink-timer)
(spawn mcu-scheduler)
(spawn vesc-info-listener)
(spawn vesc-register-listener)
; Runs regardless of bms-mode -- 0x424 is in the BMS frame group, so it's
; already suppressed on the wire when a real BMS owns the bus.
(spawn bms-timer-task)
