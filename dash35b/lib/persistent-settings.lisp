; Runtime copies for the views. Before @const-start because they are mutated.
(def settings-units-metric config-metric-speeds)
(def settings-temps-metric config-metric-temps)
(def settings-batt-hot config-battery-hot)
(def settings-esc-hot config-esc-hot)
(def settings-motor-hot config-motor-hot)
(def settings-bl-bright bl-lvl-bright)
(def settings-bl-dim bl-lvl-dim)

; Drive modes the buttons cycle through.
(def drive-mode-num 5)

; Rotating pages in the button-0 cycle. Settings page sits at page-num.
(def settings-page-mask 0xF)

(def settings-setting-mask 0xF)

; Short/long action id per button. See btn-do-action.
(def btn-actions-short (list 1 5 4 6))
(def btn-actions-long (list 3 8 0 7))

; 0 auto, 1 assume dash_esc, 2 assume stock.
(def settings-esc-mode 0)

(def settings-esc-id 0)

; Icons drawn. 0 signals 1 beam 2 kickstand 3 temp 4 fault 5 cruise.
(def settings-icon-mask 0x3F)

; Index into slot-catalog. Changing that order breaks saved settings.
(def settings-slots (list 2 6 7 15))

; Per slot: 0 a fixed colour, 1 a green to red ramp across the range below.
(def settings-slot-modes (list 0 0 0 0))

; Colour the battery bar by charge rather than the accent.
(def settings-batt-ramp false)

(def settings-splash true)
(def settings-slot-mins (list 0.0 0.0 0.0 0.0))
(def settings-slot-maxs (list 100.0 100.0 100.0 100.0))

; The worker repaints on this, so a redraw never blocks the data channel.
(def settings-redraw false)

; Built by settings-build.
(def setting-list-page1 nil)
(def setting-step-page1 nil)
(def setting-lim-page1 nil)
(def setting-label-page1 nil)
(def setting-fmt-page1 nil)

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

    (whl-active . (11 i))
    (whl-start . (12 f))
    (whl-end . (13 f))
    (whl-kd . (14 f))

    (units-metric . (15 i))
    (temps-metric . (16 i))
    (batt-hot . (17 f))
    (esc-hot . (18 f))
    (motor-hot . (19 f))
    (bl-bright . (20 i))
    (bl-dim . (21 i))

    (drive-modes . (22 i))
    (page-mask . (23 i))
    (setting-mask . (24 i))

    (btn0-short . (25 i))
    (btn1-short . (26 i))
    (btn2-short . (27 i))
    (btn3-short . (28 i))
    (btn0-long . (29 i))
    (btn1-long . (30 i))
    (btn2-long . (31 i))
    (btn3-long . (32 i))

    (esc-mode . (33 i))
    (esc-id . (34 i))

    (icon-mask . (52 i))

    (col-accent . (55 i))
    (col-text . (56 i))

    (slot-0 . (57 i))
    (slot-1 . (58 i))
    (slot-2 . (59 i))
    (slot-3 . (60 i))

    (slot-col-0 . (61 i))
    (slot-col-1 . (62 i))
    (slot-col-2 . (63 i))
    (slot-col-3 . (64 i))
    (slot-mode-0 . (65 i))
    (slot-mode-1 . (66 i))
    (slot-mode-2 . (67 i))
    (slot-mode-3 . (68 i))
    (slot-min-0 . (69 f))
    (slot-min-1 . (70 f))
    (slot-min-2 . (71 f))
    (slot-min-3 . (72 f))
    (slot-max-0 . (73 f))
    (slot-max-1 . (74 f))
    (slot-max-2 . (75 f))
    (slot-max-3 . (76 f))

    (batt-ramp . (77 i))
    (splash-en . (78 i))
))

(defun print-settings ()
    (loopforeach it eeprom-addrs
        (print (list (first it) (read-setting (first it))))
))

; Settings version
(def settings-version 54i32)

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

; (name label format step min max). Page fits six rows.
(def setting-catalog '(
        (whl-active   "Wheelie EN"  "%d"       1     0    1)
        (whl-start    "Angle Start" "%.1f deg" 0.5   0.0  55.0)
        (whl-end      "Angle End"   "%.1f deg" 0.5   0.0  55.0)
        (whl-kd       "Damping"     "%.3f"     0.001 0.0  0.2)
        (bl-bright    "BL Bright"   "%d"       1     1    7)
        (bl-dim       "BL Dim"      "%d"       1     1    7)
        (batt-hot     "Batt Warn"   "%.0f C"   1.0   0.0  200.0)
        (esc-hot      "ESC Warn"    "%.0f C"   1.0   0.0  200.0)
        (motor-hot    "Motor Warn"  "%.0f C"   1.0   0.0  200.0)
        (units-metric "Metric Spd"  "%d"       1     0    1)
        (temps-metric "Metric Tmp"  "%d"       1     0    1)
))

(def setting-catalog-max 6)

; An unwritten cell reads -1, which as a float is NaN, so test that first.
(defun setting-clamp (v lo hi dflt)
    (if (not (= v v)) dflt
        (if (< v lo) dflt
            (if (> v hi) dflt v))))

; A never written cell reads nil, and comparing that to a number throws.
(defun setting-flag (name dflt)
    (let ((v (read-setting name)))
        (cond
            ((eq v nil) dflt)
            ((= v 1) true)
            ((= v 0) false)
            (t dflt)
)))

; Backlight floor is 1: zero is a black screen that looks like a crash.
(defun settings-load () {
        (setq settings-units-metric (setting-flag 'units-metric config-metric-speeds))
        (setq settings-temps-metric (setting-flag 'temps-metric config-metric-temps))
        (setq settings-batt-hot (setting-clamp (read-setting 'batt-hot) 0.0 200.0 config-battery-hot))
        (setq settings-esc-hot (setting-clamp (read-setting 'esc-hot) 0.0 200.0 config-esc-hot))
        (setq settings-motor-hot (setting-clamp (read-setting 'motor-hot) 0.0 200.0 config-motor-hot))
        (setq settings-bl-bright (setting-clamp (read-setting 'bl-bright) 1 7 bl-lvl-bright))
        (setq settings-bl-dim (setting-clamp (read-setting 'bl-dim) 1 7 bl-lvl-dim))
        ; view_static labels only 0-4, dash_esc matches only 0-4.
        (setq drive-mode-num (setting-clamp (read-setting 'drive-modes) 1 5 5))
        (setq settings-page-mask (setting-clamp (read-setting 'page-mask) 1 0xF 0xF))
        (setq settings-setting-mask (setting-clamp (read-setting 'setting-mask) 0 0x7FF 0xF))

        (setq btn-actions-short (map (fn (n) (setting-clamp (read-setting n) 0 8 0))
                '(btn0-short btn1-short btn2-short btn3-short)))
        (setq btn-actions-long (map (fn (n) (setting-clamp (read-setting n) 0 8 0))
                '(btn0-long btn1-long btn2-long btn3-long)))

        (setq settings-esc-mode (setting-clamp (read-setting 'esc-mode) 0 2 0))
        (setq settings-esc-id (setting-clamp (read-setting 'esc-id) 0 253 0))
        (setq settings-icon-mask (setting-clamp (read-setting 'icon-mask) 0 0x3F 0x3F))
        (setq settings-batt-ramp (setting-flag 'batt-ramp false))
        (setq settings-splash (setting-flag 'splash-en true))
        (setq color-accent (setting-clamp (read-setting 'col-accent) 0 0xFFFFFF 0x00C8FF))
        (setq color-text (setting-clamp (read-setting 'col-text) 0 0xFFFFFF 0xfbfcfc))
        (setq settings-slots (map (fn (n) (setting-clamp (read-setting n) 0 17 0))
                '(slot-0 slot-1 slot-2 slot-3)))
        (setq settings-slot-cols (map (fn (n) (setting-clamp (read-setting n) 0 0xFFFFFF 0xfbfcfc))
                '(slot-col-0 slot-col-1 slot-col-2 slot-col-3)))
        (setq settings-slot-modes (map (fn (n) (setting-clamp (read-setting n) 0 1 0))
                '(slot-mode-0 slot-mode-1 slot-mode-2 slot-mode-3)))
        (setq settings-slot-mins (map (fn (n) (setting-clamp (read-setting n) -1000.0 10000.0 0.0))
                '(slot-min-0 slot-min-1 slot-min-2 slot-min-3)))
        (setq settings-slot-maxs (map (fn (n) (setting-clamp (read-setting n) -1000.0 10000.0 100.0))
                '(slot-max-0 slot-max-1 slot-max-2 slot-max-3)))

        (if (>= drive-mode drive-mode-num) (setq drive-mode 0))
})

; Rows from the mask, capped so none draw off the page.
(defun settings-build () {
        (var names nil)
        (var steps nil)
        (var lims nil)
        (var labels nil)
        (var fmts nil)
        (var shown 0)

        (looprange i 0 (length setting-catalog) {
                (var row (ix setting-catalog i))
                (if (and (!= 0 (bitwise-and settings-setting-mask (shl 1 i)))
                         (< shown setting-catalog-max)) {
                        (setq names (cons (ix row 0) names))
                        (setq labels (cons (ix row 1) labels))
                        (setq fmts (cons (ix row 2) fmts))
                        (setq steps (cons (ix row 3) steps))
                        (setq lims (cons (list (ix row 4) (ix row 5)) lims))
                        (setq shown (+ shown 1))
                })
        })

        (setq setting-list-page1 (reverse names))
        (setq setting-label-page1 (reverse labels))
        (setq setting-fmt-page1 (reverse fmts))
        (setq setting-step-page1 (reverse steps))
        (setq setting-lim-page1 (reverse lims))
        (setq setting-num shown)
        (if (>= setting-now shown) (setq setting-now 0))
})

; Views read the pairs, not the flags.
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

; True when an icon should be drawn.
(defun icon-on (n)
    (!= 0 (bitwise-and settings-icon-mask (shl 1 n))))

; Wipe every stored setting and reload. The page calls this.
(defun settings-reset () {
        (restore-settings)
        (settings-load)
        (settings-build)
        (settings-apply-units)
        (settings-apply-pages)
        (setq settings-redraw true)
        (send-cfg)
})

; Reload now so a read back is current, but leave the repaint to the worker.
(defun settings-set (name val) {
        (write-setting name val)
        (settings-load)
        (settings-build)
        (settings-apply-units)
        (settings-apply-pages)
        (setq settings-redraw true)
})

; Everything on screen is now the wrong colour, so redraw the lot.
(defun settings-apply-visual () {
        (setq settings-redraw false)
        (colors-build)
        (disp-clear color-bg)
        (setq view-force-static true)
        (setq view-force-pages true)
        (disp-set-bl (if backlight-dim settings-bl-dim settings-bl-bright))
})

; Preview without storing, for the slider.
(defun bl-preview (v) (disp-set-bl (setting-clamp v 1 7 settings-bl-bright)))

; One framed packet, not seven prints, and no 0.5 s REPL limit.
(defun send-cfg ()
    (send-data (str-merge
            "cfg "
            (str-from-n (if settings-units-metric 1 0) "%d ")
            (str-from-n (if settings-temps-metric 1 0) "%d ")
            (str-from-n settings-batt-hot "%.1f ")
            (str-from-n settings-esc-hot "%.1f ")
            (str-from-n settings-motor-hot "%.1f ")
            (str-from-n settings-bl-bright "%d ")
            (str-from-n settings-bl-dim "%d ")
            (str-from-n drive-mode-num "%d ")
            (str-from-n settings-page-mask "%d ")
            (str-from-n settings-setting-mask "%d ")
            (str-from-n (ix btn-actions-short 0) "%d ")
            (str-from-n (ix btn-actions-short 1) "%d ")
            (str-from-n (ix btn-actions-short 2) "%d ")
            (str-from-n (ix btn-actions-short 3) "%d ")
            (str-from-n (ix btn-actions-long 0) "%d ")
            (str-from-n (ix btn-actions-long 1) "%d ")
            (str-from-n (ix btn-actions-long 2) "%d ")
            (str-from-n (ix btn-actions-long 3) "%d ")
            (str-from-n settings-esc-mode "%d ")
            (str-from-n settings-esc-id "%d ")
            (str-from-n (if standalone-active 1 0) "%d ")
            (str-from-n standalone-esc-id "%d ")
            (str-from-n settings-icon-mask "%d ")
            (str-from-n color-accent "%d ")
            (str-from-n color-text "%d ")
            (str-from-n (ix settings-slots 0) "%d ")
            (str-from-n (ix settings-slots 1) "%d ")
            (str-from-n (ix settings-slots 2) "%d ")
            (str-from-n (ix settings-slots 3) "%d ")
            (str-from-n (ix settings-slot-cols 0) "%d ")
            (str-from-n (ix settings-slot-cols 1) "%d ")
            (str-from-n (ix settings-slot-cols 2) "%d ")
            (str-from-n (ix settings-slot-cols 3) "%d ")
            (str-from-n (ix settings-slot-modes 0) "%d ")
            (str-from-n (ix settings-slot-modes 1) "%d ")
            (str-from-n (ix settings-slot-modes 2) "%d ")
            (str-from-n (ix settings-slot-modes 3) "%d ")
            (str-from-n (ix settings-slot-mins 0) "%.0f ")
            (str-from-n (ix settings-slot-mins 1) "%.0f ")
            (str-from-n (ix settings-slot-mins 2) "%.0f ")
            (str-from-n (ix settings-slot-mins 3) "%.0f ")
            (str-from-n (ix settings-slot-maxs 0) "%.0f ")
            (str-from-n (ix settings-slot-maxs 1) "%.0f ")
            (str-from-n (ix settings-slot-maxs 2) "%.0f ")
            (str-from-n (ix settings-slot-maxs 3) "%.0f ")
            (str-from-n (if settings-batt-ramp 1 0) "%d ")
            (str-from-n (if settings-splash 1 0) "%d")
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

        (write-setting 'whl-active 0)
        (write-setting 'whl-start 20)
        (write-setting 'whl-end 43)
        (write-setting 'whl-kd 0.005)

        (write-setting 'units-metric (if config-metric-speeds 1 0))
        (write-setting 'temps-metric (if config-metric-temps 1 0))
        (write-setting 'batt-hot config-battery-hot)
        (write-setting 'esc-hot config-esc-hot)
        (write-setting 'motor-hot config-motor-hot)
        (write-setting 'bl-bright bl-lvl-bright)
        (write-setting 'bl-dim bl-lvl-dim)

        (write-setting 'drive-modes 5)
        (write-setting 'page-mask 0xF)
        (write-setting 'setting-mask 0xF)

        (write-setting 'btn0-short 1)
        (write-setting 'btn1-short 5)
        (write-setting 'btn2-short 4)
        (write-setting 'btn3-short 6)
        (write-setting 'btn0-long 3)
        (write-setting 'btn1-long 8)
        (write-setting 'btn2-long 0)
        (write-setting 'btn3-long 7)

        (write-setting 'esc-mode 0)
        (write-setting 'esc-id 0)

        (write-setting 'icon-mask 0x3F)
        (write-setting 'batt-ramp 0)
        (write-setting 'splash-en 1)

        (write-setting 'col-accent 0x00C8FF)
        (write-setting 'col-text 0xfbfcfc)

        (write-setting 'slot-0 2)
        (write-setting 'slot-1 6)
        (write-setting 'slot-2 7)
        (write-setting 'slot-3 15)

        (looprange i 0 4 {
                (write-setting (ix '(slot-col-0 slot-col-1 slot-col-2 slot-col-3) i) 0xfbfcfc)
                (write-setting (ix '(slot-mode-0 slot-mode-1 slot-mode-2 slot-mode-3) i) 0)
                (write-setting (ix '(slot-min-0 slot-min-1 slot-min-2 slot-min-3) i) 0.0)
                (write-setting (ix '(slot-max-0 slot-max-1 slot-max-2 slot-max-3) i) 100.0)
        })

        (write-setting 'ver-code settings-version)
        (print "Settings Restored!")
))

; Restore settings if version number does not match
; as that probably means something else is in eeprom
(if (not-eq (read-setting 'ver-code) settings-version) (restore-settings))

; Only runs on the first boot after installing. An error here takes main
; down before the display starts, which looks like a dead screen.
(if (eq (car (trap {
        (settings-load)
        (settings-build)
        (colors-build)
})) 'exit-error)
    (print "Settings failed to load, using defaults"))
