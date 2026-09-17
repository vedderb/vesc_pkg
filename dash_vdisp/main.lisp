@const-start

(import "pkg@://vesc_packages/lib_code_server/code_server.vescpkg" 'code-server)
(read-eval-program code-server)

(import "version.lisp" 'code-version)
(read-eval-program code-version)

(import "config.lisp" 'code-config)
(read-eval-program code-config)

; Lib
(import "lib/vehicle-state.lisp" 'code-vehicle-state)
(read-eval-program code-vehicle-state)

(import "lib/colors.lisp" 'code-colors)
(read-eval-program code-colors)

(import "lib/user-settings.lisp" 'code-user-settings)
(read-eval-program code-user-settings)

(import "lib/persistent-settings.lisp" 'code-persistent-settings)
(read-eval-program code-persistent-settings)

(import "lib/statistics.lisp" 'code-statistics)
(read-eval-program code-statistics)

(import "lib/draw-utils.lisp" 'code-draw-utils)
(read-eval-program code-draw-utils)

(import "lib/input.lisp" 'code-input)
(read-eval-program code-input)

(import "lib/communication.lisp" 'code-communication)
(read-eval-program code-communication)

; Views
(import "lib/standalone.lisp" 'code-standalone)
(read-eval-program code-standalone)

(import "views/view_static.lbm" 'code-view-static)
(read-eval-program code-view-static)

(import "views/view_pages.lbm" 'code-view-pages)
(read-eval-program code-view-pages)

; Assets
(import "assets/sym_vesc_28x26.bin" 'img-vesc)
(import "assets/logo-16c.bin" 'img-logo)
(import "assets/batt_level_36x150.bin" 'img-batt-level)
(import "assets/highbeam_24x18.bin" 'img-highbeam)
(import "assets/lowbeam_24x18.bin" 'img-lowbeam)
(import "assets/indicator_l_26x22.bin" 'img-indicator-l)
(import "assets/indicator_r_26x22.bin" 'img-indicator-r)
(import "assets/kickstand_20x22.bin" 'img-kickstand)
(import "assets/temp_b_28x28.bin" 'img-temp-b)
(import "assets/temp_e_28x28.bin" 'img-temp-e)
(import "assets/temp_m_28x28.bin" 'img-temp-m)
(import "assets/warning_26x28.bin" 'img-warning)
(import "assets/cruise_30x28.bin" 'img-cruise)
(import "assets/charging_120x46.bin" 'img-charging)

; Fonts
(import "font/roboto-bold-16-4c.bin" 'font-16)
(import "font/roboto-bold-32-4c.bin" 'font-32)
(import "font/roboto-bold-12-4c.bin" 'font-12)
(import "font/roboto-bold-36-4c.bin" 'font-36)
(import "font/roboto-bold-64-2c.bin" 'font-64)
(import "font/roboto-bold-16-2c.bin" 'font-16-2c)

(defun setting-update (op) {
        (if (> setting-num 0) {
                (var setting (ix setting-list-page1 setting-now))
                (var lim (ix setting-lim-page1 setting-now))
                (var step (ix setting-step-page1 setting-now))

                (write-setting setting
                    (clamp
                        (eval (list op (read-setting setting) step))
                        (first lim)
                        (second lim)
                ))

                (settings-load)
                (settings-apply-units)
                (bl-set (if backlight-dim settings-bl-dim settings-bl-bright))
        })
})

; Stored in eeprom, so these keep their meaning.
; 0 none  1 page+  2 page-  3 settings  4 mode+  5 mode-
; 6 lights  7 backlight dim  8 cruise
(defun btn-do-action (a)
    (cond
        ((= a 1) (setq page-now (mod (+ page-now 1) page-num)))
        ((= a 2) (setq page-now (mod (+ page-now (- page-num 1)) page-num)))
        ((= a 3) (setq page-now (if (= page-now page-num) 0 page-num)))
        ((= a 4) (if (< drive-mode (- drive-mode-num 1)) (mode-set (+ drive-mode 1))))
        ((= a 5) (if (> drive-mode 0) (mode-set (- drive-mode 1))))
        ((= a 6) (setq light-on (not light-on)))
        ((= a 7) {
                (setq backlight-dim (not backlight-dim))
                (bl-set (if backlight-dim settings-bl-dim settings-bl-bright))
        })
        ((= a 8) (comm-send-event 0))
        ; Button 0 is this display's power button and is also the wake source,
        ; so a long press on it is the natural place for sleep.
        ((= a 9) (comm-send-event 2)) ; start or stop logging on the controller
        ((= a 11) (hw-sleep))
        (t nil)
))

; On the settings page short presses always navigate it
(defun btn-short (idx)
    (if (= page-now page-num)
        (cond
            ((= idx 0) (if (> setting-num 0)
                          (setq setting-now (mod (+ setting-now 1) setting-num))))
            ((= idx 1) (setting-update -))
            ((= idx 2) (setting-update +))
            (t (btn-do-action (ix btn-actions-short idx)))
        )
        (btn-do-action (ix btn-actions-short idx))
))

; Shown once at boot, so a dead panel looks different from a blank one.
; The backlight is a plain GPIO on this hardware, so there is no brightness
; control, only on and off. bl-bright and bl-dim are carried by the settings
; layer but only their zero/non-zero distinction can be honoured here.
(defun bl-set (level) (set-io 3 (if (> level 0) 1 0)))

; A short-lived banner over the normal views, used for things the controller
; reports back such as logging starting and stopping. Cleared by forcing the
; views to redraw rather than by repainting what was underneath.
(def notify-txt nil)
(def notify-ts 0)

(defun notify (txt) {
        (setq notify-txt txt)
        (setq notify-ts (systime))
})

(defun notify-draw (txt) {
        (var imgbuf (img-buffer dm-pool 'indexed4 200 30))
        (img-clear imgbuf)
        (img-rectangle imgbuf 0 0 200 30 1 '(rounded 6))
        (ttf-txt-center txt font-16 imgbuf)
        (disp-render imgbuf 60 105 colors-text-aa)
})

(defun notify-thread () {
        (var service-last false)

        (loopwhile t {
                ; Leaving service mode uncovers whatever the banner sat on
                (if (and service-last (not (or service-mode motor-bad))) {
                        (setq view-force-static true)
                        (setq view-force-pages true)
                })
                (setq service-last (or service-mode motor-bad))

                (cond
                    ; The motor will not run at all in this state, so this
                    ; outranks everything else on screen.
                    (motor-bad (notify-draw "MOTOR CONFIG BAD"))

                    ; With the drive profile suspended the mode on screen means
                    ; nothing and neutral no longer holds the throttle shut, so
                    ; say so, and keep saying it until it is switched back.
                    (service-mode (notify-draw "SERVICE"))

                    (notify-txt
                        (if (> (secs-since notify-ts) 2.5) {
                                (setq notify-txt nil)
                                (setq view-force-static true)
                                (setq view-force-pages true)
                        }
                        (notify-draw notify-txt)))
                )

                (sleep 0.2)
        })
})

(defun show-splash () {
        (print "Splash")

        ; The logo is a 16-colour image whose palette is revealed in stages:
        ; one blue stripe, then the second, then the wordmark fades up. This is
        ; how the original VDisp package animated its boot screen.
        (var (logo-w logo-h) (img-dims img-logo))
        (var logo-x (- 160 (/ logo-w 2)))
        (var logo-y (- 120 (/ logo-h 2)))

        (var stripe-1 '(0x000000 0x009edf 0x007dc4 0x005684 0x012e47 0x191c1c))
        (var stripe-2 (append stripe-1 '(0x007dc4 0x005684 0x012e47 0x191c1c)))

        (bl-set 1)

        (disp-render img-logo logo-x logo-y stripe-1)
        (sleep 0.5)

        (disp-render img-logo logo-x logo-y stripe-2)
        (sleep 0.5)

        (var fade-time 2.0)
        (var start-time (systime))
        (loopwhile (< (secs-since start-time) fade-time) {
                (var pct (/ (secs-since start-time) fade-time))
                (disp-render img-logo logo-x logo-y (append stripe-2 (list
                    (color-mix 0x000000 0xd9dee1 pct)
                    (color-mix 0x000000 0xc5c9cc pct)
                    (color-mix 0x000000 0xa6aaab pct)
                    (color-mix 0x000000 0x7e8283 pct)
                    (color-mix 0x000000 0x575a59 pct)
                    (color-mix 0x000000 0x272928 pct)
                )))
                (sleep 0.04)
        })
        (disp-render img-logo logo-x logo-y (append stripe-2
            '(0xd9dee1 0xc5c9cc 0xa6aaab 0x7e8283 0x575a59 0x272928)))

        (var imgbuf (img-buffer dm-pool 'indexed4 200 22))
        (img-clear imgbuf)
        (ttf-txt-center splash-version font-16 imgbuf)
        (disp-render imgbuf 60 200 colors-text-aa)

        (sleep 1.0)
        (disp-clear color-bg)
})

(defun main () {
        (if (and
                (> (conf-get 'wifi-mode) 0)
                (> (conf-get 'ble-mode) 0)
                ) {
                (print "WiFi and BLE enabled, not enough memory to run UI. Disabling wifi...")
                (conf-set 'wifi-mode 0)
                (conf-set 'controller-id 4)
                (conf-store)
                (sleep 5)
                (reboot)
        })

        (def dm-pool (dm-create 25600))

        (set-print-prefix "DISP-")

        (def init-complete nil)
        (def rx-cnt-can 0)

        (if (eq (car (trap {
                            (settings-load)
                            (settings-build)
                            (colors-build)
                })) 'exit-error) {
                (print "Settings failed to load, using defaults")

                (trap {
                        (restore-settings)
                        (settings-load)
                        (settings-build)
                        (colors-build)
                })
        })

        (settings-apply-units)

        (if config-code-server (start-code-server)) ; Enable remote code execution

        (disp-load-st7789 7 6 10 20 8 40) ; sda clock cs reset dc mhz
        (bl-set 0)
        (disp-reset)
        (ext-disp-orientation 3)
        (disp-clear color-bg)

        ; Trapped: the backlight is off at this point, so a splash that throws
        ; would leave a dark unresponsive panel that looks like a dead unit.
        (if settings-splash (trap (show-splash)))
        (bl-set settings-bl-bright)

        (event-register-handler (spawn event-handler))
        (event-enable 'event-can-sid)
        (event-enable 'event-data-rx)

        (loopwhile-thd ("Stats" 200) t {
                (print "Starting stats-thread")

                (match (trap (stats-thread))
                    ((exit-ok (? a)) (print "Stats-thread exit"))
                    (_ (print "Stats-thread crashed"))
                )

                (sleep 5.0)
        })

        (input-cleanup-on-pressed)
        (loopwhile-thd ("Input" 200) t {
                (print "Starting Input-thread")

                (match (trap (input-thread))
                    ((exit-ok (? a)) (print "Input-thread exit"))
                    (_ (print "Input-thread crashed"))
                )

                (sleep 5.0)
        })

        (loopwhile-thd ("CommTX" 200) t {
                (print "Starting CommTX-thread")

                (match (trap (comm-tx-thread))
                    ((exit-ok (? a)) (print "CommTX-thread exit"))
                    (_ (print "CommTX-thread crashed"))
                )

                (sleep 5.0)
        })

        (loopwhile-thd ("Notify" 120) t {

                (print "Starting Notify-thread")


                (match (trap (notify-thread))

                    ((exit-ok (? a)) (print "Notify-thread exit"))

                    (_ (print "Notify-thread crashed"))

                )


                (sleep 5.0)

        })


        (loopwhile-thd ("ViewStatic" 200) t {
                (print "Starting ViewStatic-thread")

                (match (trap (view-static-thread))
                    ((exit-ok (? a)) (print "ViewStatic-thread exit"))
                    (_ (print "ViewStatic-thread crashed"))
                )

                (sleep 5.0)
        })

        (loopwhile-thd ("ViewPages" 200) t {
                (print "Starting ViewPages-thread")

                (match (trap (view-pages-thread))
                    ((exit-ok (? a)) (print "ViewPages-thread exit"))
                    (_ (print "ViewPages-thread crashed"))
                )

                (sleep 5.0)
        })

        (loopwhile-thd ("Standalone" 200) t {
                (print "Starting Standalone-thread")

                (match (trap (standalone-thread))
                    ((exit-ok (? a)) (print "Standalone-thread exit"))
                    (_ (print "Standalone-thread crashed"))
                )

                (sleep 5.0)
        })

        (loopwhile-thd ("Worker" 150) t {
                (if settings-redraw (trap (settings-apply-visual)))
                (if battery-a-charging (mode-set 1)) ; Put in neutral when charging
                (if kickstand-down (mode-set 1)) ; Put in neutral when kickstand is down
                (sleep 0.1)
        })

        (def init-complete true)

        (def on-btn-0-pressed (fn () (btn-short 0)))
        (def on-btn-1-pressed (fn () (btn-short 1)))
        (def on-btn-2-pressed (fn () (btn-short 2)))
        (def on-btn-3-pressed (fn () (btn-short 3)))

        (def on-btn-0-long-pressed (fn () (btn-do-action (ix btn-actions-long 0))))
        (def on-btn-1-long-pressed (fn () (btn-do-action (ix btn-actions-long 1))))
        (def on-btn-2-long-pressed (fn () (btn-do-action (ix btn-actions-long 2))))
        (def on-btn-3-long-pressed (fn () (btn-do-action (ix btn-actions-long 3))))

        (def on-btn-0-repeat-press nil)
        (def on-btn-1-repeat-press nil)
        (def on-btn-2-repeat-press nil)
        (def on-btn-3-repeat-press nil)
})

@const-end

(image-save)
(main)

