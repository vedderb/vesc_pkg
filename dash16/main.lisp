@const-start

; Assets
(import "assets/sym_vesc_37x34.bin" 'img-vesc)
(import "assets/batt_level_167x30.bin" 'img-batt-level)
(import "assets/highbeam_32x24.bin" 'img-highbeam)
(import "assets/lowbeam_32x24.bin" 'img-lowbeam)
(import "assets/indicator_l_35x27.bin" 'img-indicator-l)
(import "assets/indicator_r_35x27.bin" 'img-indicator-r)
(import "assets/kickstand_26x29.bin" 'img-kickstand)
(import "assets/temp_b_37x38.bin" 'img-temp-b)
(import "assets/temp_e_37x38.bin" 'img-temp-e)
(import "assets/temp_m_37x38.bin" 'img-temp-m)
(import "assets/warning_28x24.bin" 'img-warning)
(import "assets/cruise_40x36.bin" 'img-cruise)
(import "assets/charging_160x61.bin" 'img-charging)
(import "assets/page-clear_172x100.bin" 'img-page-clear)

; Fonts
(import "font/roboto-bold-12-4c.bin" 'font-12)
(import "font/roboto-bold-16-4c.bin" 'font-16)
(import "font/roboto-bold-24-4c.bin" 'font-24)
(import "font/roboto-bold-32-4c.bin" 'font-32)
(import "font/roboto-bold-48-4c.bin" 'font-48)
(import "font/roboto-bold-16-2c.bin" 'font-16-2c)
(import "font/roboto-bold-90-2c.bin" 'font-90)

(import "pkg@://vesc_packages/lib_code_server/code_server.vescpkg" 'code-server)
(read-eval-program code-server)

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

(def thr-volts 0.0)
(def thr-pos 0.0)

(defun lpf (val sample filter-const)
    (- val (* filter-const (- val sample)))
)

; Button actions. dash16 has two buttons and no settings page, so the list is
; shorter than dash35b's and the ids do not match it.
;
; Selecting reverse flips the throttle on the controller, so it is only
; allowed at a standstill, the way a car will not take R while rolling.
(def reverse-max-kmh 3.0)

; 0 nothing        1 next page      2 previous page   3 drive mode up
; 4 drive mode down 5 lights        6 cruise control  7 reverse
(defun btn-do-action (a)
    (cond
        ((= a 1) (setq page-now (mod (+ page-now 1) page-num)))
        ((= a 2) (setq page-now (mod (+ page-now (- page-num 1)) page-num)))
        ((= a 3) (if (< drive-mode (- drive-mode-num 1)) (setq drive-mode (+ drive-mode 1))))
        ((= a 4) (if (> drive-mode 0) (setq drive-mode (- drive-mode 1))))
        ((= a 5) (setq light-on (not light-on)))
        ((= a 6) (comm-send-event 0))
        ((= a 7) (if (< (abs stats-kmh) reverse-max-kmh) (setq drive-mode 0)))
        (t nil)
))

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

        (settings-apply-units)

        (if config-code-server (start-code-server)) ; Enable remote code execution

        ; Offset X = 34
        (disp-init)
        (ext-disp-orientation 0)
        (pwm-start 2000 settings-bl-bright 0 2)

        (event-register-handler (spawn event-handler))
        (event-enable 'event-can-sid)
        (event-enable 'event-data-rx)

        ;(if config-boot-animation-enable (start-boot-animation))

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

        (setq thr-volts (get-adc 0))
        (defun thr-read () {
                (setq thr-volts (lpf thr-volts (get-adc 0) 0.2))
                (setq thr-pos (trunc01 (/ (- thr-volts settings-lever-min)
                                          (- settings-lever-max settings-lever-min))))
                (sleep 0.003)
        })

        (loopwhile-thd ("Thr Filter" 150) t {
                (thr-read)
        })

        (loopwhile-thd ("CommTX" 200) t {
                (print "Starting CommTX-thread")

                (match (trap (comm-tx-thread))
                    ((exit-ok (? a)) (print "CommTX-thread exit"))
                    (_ (print "CommTX-thread crashed"))
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
                (if battery-a-charging (setq drive-mode 1)) ; Put in neutral when charging
                (if kickstand-down (setq drive-mode 1)) ; Put in neutral when kickstand is down
                (sleep 0.1)
        })

        (def init-complete true)

        (def on-btn-0-pressed (fn () (btn-do-action (ix btn-actions-short 0))))
        (def on-btn-1-pressed (fn () (btn-do-action (ix btn-actions-short 1))))

        (def on-btn-0-long-pressed (fn () (btn-do-action (ix btn-actions-long 0))))
        (def on-btn-1-long-pressed (fn () (btn-do-action (ix btn-actions-long 1))))

        (def on-btn-0-repeat-press nil)
        (def on-btn-1-repeat-press nil)
})

@const-end

(image-save)
(main)
