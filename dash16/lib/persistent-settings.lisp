; Runtime copies of the persistent settings, and state the views read.
; Declared before @const-start because they are mutated at runtime.
(def settings-units-metric config-metric-speeds)
(def settings-temps-metric config-metric-temps)

; Number of drive modes the buttons cycle through. view_static labels 0-4 as
; R/N/1/2/3 and falls back to N, so five is the ceiling.
(def drive-mode-num 5)

; 0 follow the traffic, 1 assume dash_esc, 2 assume a stock controller.
(def settings-esc-mode 0)

; 0 discovers the lowest recently seen CAN id.
(def settings-esc-id 0)

; Action ids for short and long press, indexed by button. dash16 has two.
(def btn-actions-short (list 3 4))
(def btn-actions-long (list 1 6))

; Sources for the four readings on the live page. Index into slot-catalog.
; Changing the catalog order breaks saved settings.
(def settings-slots (list 2 6 7 15))

; Icons drawn. 0 signals 1 beam 2 kickstand 3 temp 4 fault 5 cruise.
(def settings-icon-mask 0x3F)

; Backlight as a pwm duty. The floor is not 0, which is an unreadable screen.
(def settings-bl-bright bl-lvl-bright)

; Colour the battery bar by charge rather than the accent.
(def settings-batt-ramp false)

; Lever calibration. The dash lever is read here and sent on as ADC2, so a
; wrong range silently becomes wrong brake current at the controller.
(def settings-lever-min 0.45)
(def settings-lever-max 2.10)

; Which pages the page button cycles through.
(def settings-page-mask 0x7)

@const-start

; Persistent settings
; Format: (label . (offset type))
(def eeprom-addrs '(
    (ver-code  . (0 i))
    (pf1-speed . (1 f))
    (pf1-brake . (2 f))
    (pf1-accel . (3 f))
    (pf2-speed . (4 f))
    (pf2-brake . (5 f))
    (pf2-accel . (6 f))
    (pf3-speed . (7 f))
    (pf3-brake . (8 f))
    (pf3-accel . (9 f))
    (pf-active . (10 i))

    (units-metric . (11 i))
    (temps-metric . (12 i))
    (drive-modes . (13 i))
    (esc-mode . (14 i))
    (esc-id . (15 i))

    (btn0-short . (16 i))
    (btn1-short . (17 i))
    (btn0-long . (18 i))
    (btn1-long . (19 i))

    (slot-0 . (20 i))
    (slot-1 . (21 i))
    (slot-2 . (22 i))
    (slot-3 . (23 i))

    (icon-mask . (24 i))
    (page-mask . (25 i))
    (bl-bright . (26 f))
    (batt-ramp . (27 i))
    (lever-min . (28 f))
    (lever-max . (29 f))
))

(defun print-settings ()
    (loopforeach it eeprom-addrs
        (print (list (first it) (read-setting (first it))))
))

(defun save-settings (  pf1-speed pf1-brake pf1-accel
                        pf2-speed pf2-brake pf2-accel
                        pf3-speed pf3-brake pf3-accel
                        pf-active
)
    (progn
        (write-setting 'pf1-speed pf1-speed)
        (write-setting 'pf1-brake pf1-brake)
        (write-setting 'pf1-accel pf1-accel)
        (write-setting 'pf2-speed pf2-speed)
        (write-setting 'pf2-brake pf2-brake)
        (write-setting 'pf2-accel pf2-accel)
        (write-setting 'pf3-speed pf3-speed)
        (write-setting 'pf3-brake pf3-brake)
        (write-setting 'pf3-accel pf3-accel)
        (write-setting 'pf-active pf-active)
        (print "Settings Saved!")
))

; Settings version
(def settings-version 44i32)

(defun read-setting (name)
    (let (
            (addr (first (assoc eeprom-addrs name)))
            (type (second (assoc eeprom-addrs name)))
        )
        (cond
            ((eq type 'i) (eeprom-read-i addr))
            ((eq type 'f) (eeprom-read-f addr))
            ((eq type 'b) (!= (eeprom-read-i addr) 0))
)))

(defun write-setting (name val)
    (let (
            (addr (first (assoc eeprom-addrs name)))
            (type (second (assoc eeprom-addrs name)))
        )
        (cond
            ((eq type 'i) (eeprom-store-i addr val))
            ((eq type 'f) (eeprom-store-f addr val))
            ((eq type 'b) (eeprom-store-i addr (if val 1 0)))
)))

(defun restore-settings ()
    (progn
        (write-setting 'pf1-speed 39.3)
        (write-setting 'pf1-brake 1.0)
        (write-setting 'pf1-accel 1.0)
        (write-setting 'pf2-speed 18.8)
        (write-setting 'pf2-brake 0.4)
        (write-setting 'pf2-accel 0.6)
        (write-setting 'pf3-speed 11.2)
        (write-setting 'pf3-brake 0.2)
        (write-setting 'pf3-accel 0.4)
        (write-setting 'pf-active 0)
        ; Defaults come from config.lisp so that it stays the single source of
        ; truth for a freshly installed package.
        (write-setting 'units-metric (if config-metric-speeds 1 0))
        (write-setting 'temps-metric (if config-metric-temps 1 0))
        (write-setting 'drive-modes 5)
        (write-setting 'esc-mode 0)
        (write-setting 'esc-id 0)

        ; Defaults reproduce the button behaviour the package shipped with.
        (write-setting 'btn0-short 3)
        (write-setting 'btn1-short 4)
        (write-setting 'btn0-long 1)
        (write-setting 'btn1-long 6)

        ; Conservative starting profiles. Reverse and the first mode are slow
        ; on purpose, since a wrong guess here moves the bike.

        (write-setting 'icon-mask 0x3F)
        (write-setting 'bl-bright bl-lvl-bright)
        (write-setting 'batt-ramp 0)
        (write-setting 'lever-min 0.45)
        (write-setting 'lever-max 2.10)
        (write-setting 'page-mask 0x7)

        (write-setting 'slot-0 2)
        (write-setting 'slot-1 6)
        (write-setting 'slot-2 7)
        (write-setting 'slot-3 15)

        (write-setting 'ver-code settings-version)
        (print "Settings Restored!")
))

; Restore settings if version number does not match
; as that probably means something else is in eeprom
(defun setting-clamp (v lo hi dflt)
    (if (eq v nil) dflt
        (if (not (= v v)) dflt
            (if (< v lo) dflt
                (if (> v hi) dflt v)))))

; A cell that was never written reads nil, and comparing that to a number
; throws, so test for it before the equality checks.
(defun setting-flag (name dflt)
    (let ((v (read-setting name)))
        (cond
            ((eq v nil) dflt)
            ((= v 1) true)
            ((= v 0) false)
            (t dflt)
)))

(defun settings-load () {
        (setq settings-units-metric (setting-flag 'units-metric config-metric-speeds))
        (setq settings-temps-metric (setting-flag 'temps-metric config-metric-temps))
        (setq drive-mode-num (setting-clamp (read-setting 'drive-modes) 1 5 5))
        (setq settings-esc-mode (setting-clamp (read-setting 'esc-mode) 0 2 0))
        (setq settings-esc-id (setting-clamp (read-setting 'esc-id) 0 253 0))
        (setq btn-actions-short (map (fn (n) (setting-clamp (read-setting n) 0 7 0))
                '(btn0-short btn1-short)))
        (setq btn-actions-long (map (fn (n) (setting-clamp (read-setting n) 0 7 0))
                '(btn0-long btn1-long)))
        (setq settings-icon-mask (setting-clamp (read-setting 'icon-mask) 0 0x3F 0x3F))
        (setq settings-bl-bright (setting-clamp (read-setting 'bl-bright) 0.1 1.0 bl-lvl-bright))
        (setq settings-batt-ramp (setting-flag 'batt-ramp false))
        (setq settings-lever-min (setting-clamp (read-setting 'lever-min) 0.0 1.5 0.45))
        (setq settings-lever-max (setting-clamp (read-setting 'lever-max) 1.0 3.3 2.10))
        ; A collapsed or inverted range would make the lever unusable
        (if (< settings-lever-max (+ settings-lever-min 0.5))
            (setq settings-lever-max (+ settings-lever-min 0.5)))
        (setq settings-page-mask (setting-clamp (read-setting 'page-mask) 1 0x7 0x7))

        ; Per slot defaults, so an eeprom cell that was never written falls
        ; back to the intended source rather than to slot 0.
        (setq settings-slots (map (fn (p) (setting-clamp (read-setting (first p)) 0 17 (second p)))
                '((slot-0 2) (slot-1 6) (slot-2 7) (slot-3 15))))
        (if (>= drive-mode drive-mode-num) (setq drive-mode 0))
})

; True when an icon should be drawn.
(defun icon-on (n)
    (!= 0 (bitwise-and settings-icon-mask (shl 1 n))))

; True when the whole top strip is switched off: signals, beam and fault.
; Cruise sits lower down, so it does not count. The logo and the gear
; selector move up into the empty strip when this is true.
(defun icons-top-hidden ()
    (= 0 (bitwise-and settings-icon-mask 0x13)))

(defun settings-apply-units () {
        (setq view-force-static true)
        (setq view-force-pages true)
        (if settings-units-metric
            (def settings-units-speeds '(kmh . "km/h"))
            (def settings-units-speeds '(mph . "MPH"))
        )
        (if settings-temps-metric
            (def settings-units-temps '(celsius . "C"))
            (def settings-units-temps '(fahrenheit . "F"))
        )
})

(defun bl-apply () (pwm-set-duty settings-bl-bright 0))

; Preview without storing, for the slider
(defun bl-preview (v) (pwm-set-duty (setting-clamp v 0.1 1.0 settings-bl-bright) 0))

(defun settings-set (name val) {
        (write-setting name val)
        (settings-load)
        (bl-apply)
        (settings-apply-pages)
        ; Anything on screen may now be wrong, so redraw the lot.
        (setq view-force-static true)
        (setq view-force-pages true)
        (settings-apply-units)
})

; One framed packet over event-data-rx, not seven console prints. The REPL
; drops anything sent within 0.5 s of the last command; this path does not.
(defun send-cfg ()
    (send-data (str-merge
            "cfg "
            (str-from-n (if settings-units-metric 1 0) "%d ")
            (str-from-n (if settings-temps-metric 1 0) "%d ")
            (str-from-n drive-mode-num "%d ")
            (str-from-n settings-esc-mode "%d ")
            (str-from-n settings-esc-id "%d ")
            (str-from-n (if standalone-active 1 0) "%d ")
            (str-from-n standalone-esc-id "%d ")
            (str-from-n (ix btn-actions-short 0) "%d ")
            (str-from-n (ix btn-actions-short 1) "%d ")
            (str-from-n (ix btn-actions-long 0) "%d ")
            (str-from-n (ix btn-actions-long 1) "%d ")
            (str-from-n (ix settings-slots 0) "%d ")
            (str-from-n (ix settings-slots 1) "%d ")
            (str-from-n (ix settings-slots 2) "%d ")
            (str-from-n (ix settings-slots 3) "%d ")
            (str-from-n settings-icon-mask "%d ")
            (str-from-n settings-page-mask "%d ")
            (str-from-n settings-bl-bright "%.2f ")
            (str-from-n (if settings-batt-ramp 1 0) "%d ")
            (str-from-n settings-lever-min "%.3f ")
            (str-from-n settings-lever-max "%.3f")
)))

; Polled by the settings page while the lever section is open
(defun send-lever ()
    (send-data (str-merge
            "lever "
            (str-from-n thr-volts "%.3f ")
            (str-from-n thr-pos "%.3f")
)))

(defun settings-reset () {
        (restore-settings)
        (settings-load)
        (bl-apply)
        (settings-apply-units)
        (settings-apply-pages)
        (setq view-force-static true)
        (setq view-force-pages true)
        (send-cfg)
})

(if (not-eq (read-setting 'ver-code) settings-version) (restore-settings))

(settings-load)
