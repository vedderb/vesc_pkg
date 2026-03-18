@const-start

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
(import "views/view_static.lbm" 'code-view-static)
(read-eval-program code-view-static)

(import "views/view_pages.lbm" 'code-view-pages)
(read-eval-program code-view-pages)

; Assets
(import "assets/sym_vesc_37x34.bin" 'img-vesc)
(import "assets/batt_level_50x210.bin" 'img-batt-level)
(import "assets/highbeam_32x24.bin" 'img-highbeam)
(import "assets/lowbeam_32x24.bin" 'img-lowbeam)
(import "assets/indicator_l_34x30.bin" 'img-indicator-l)
(import "assets/indicator_r_34x30.bin" 'img-indicator-r)
(import "assets/kickstand_26x29.bin" 'img-kickstand)
(import "assets/temp_b_37x38.bin" 'img-temp-b)
(import "assets/temp_e_37x38.bin" 'img-temp-e)
(import "assets/temp_m_37x38.bin" 'img-temp-m)
(import "assets/warning_35x38.bin" 'img-warning)
(import "assets/cruise_40x36.bin" 'img-cruise)
(import "assets/charging_160x61.bin" 'img-charging)
(import "assets/page-clear_400x160.bin" 'img-page-clear)

; Fonts
(import "font/roboto-bold-12-4c.bin" 'font-12)
(import "font/roboto-bold-16-4c.bin" 'font-16)
(import "font/roboto-bold-32-4c.bin" 'font-32)
(import "font/roboto-bold-48-4c.bin" 'font-48)
(import "font/roboto-bold-16-2c.bin" 'font-16-2c)
(import "font/roboto-bold-90-2c.bin" 'font-90)

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

        (if config-metric-speeds
            (def settings-units-speeds '(kmh . "km/h"))
            (def settings-units-speeds '(mph . "MPH"))
        )

        (if config-metric-temps
            (def settings-units-temps '(celsius . "C"))
            (def settings-units-temps '(fahrenheit . "F"))
        )

        (if config-code-server (start-code-server)) ; Enable remote code execution

        (disp-init)
        (ext-disp-orientation 0)

        (pwm-start 2000 0.8 0 2)
        (gpio-configure 8 'pin-mode-in-pu)
        (gpio-configure 10 'pin-mode-in-pu)

        (defun lpf (val sample)
            (- val (* 0.1 (- val sample)))
        )

        (def thr (get-adc 0))
        (defun update-in () {
                (def bt1 (gpio-read 8))
                (def bt2 (gpio-read 10))
                (def thr (lpf thr (get-adc 0)))
        })

        (loopwhile-thd 200 t {
                (update-in)
                (sleep 0.002)
        })

        (def imgbuf (img-buffer dm-pool 'indexed4 130 300))
        (defun draw () {
                (img-clear imgbuf)

                (var ofs 30.0)

                (ttf-text imgbuf 0 (+ ofs 0) '(0 1 2 3) font-16 "Button 1")
                (ttf-text imgbuf 0 (+ ofs 32) '(0 1 2 3) font-32 (if (= bt1 0) "1" "0"))
                (setq ofs (+ ofs 62))

                (ttf-text imgbuf 0 (+ ofs 0) '(0 1 2 3) font-16 "Button 2")
                (ttf-text imgbuf 0 (+ ofs 32) '(0 1 2 3) font-32 (if (= bt2 0) "1" "0"))
                (setq ofs (+ ofs 62))

                (ttf-text imgbuf 0 (+ ofs 0) '(0 1 2 3) font-16 "Throttle Volts")
                (ttf-text imgbuf 0 (+ ofs 32) '(0 1 2 3) font-32 (str-from-n (* thr 2.0) "%.2f"))
                (setq ofs (+ ofs 62))

                (if (> stats-vin 0.1) {
                        (ttf-text imgbuf 0 (+ ofs 0) '(0 1 2 3) font-16 "CAN Battery Volts")
                        (ttf-text imgbuf 0 (+ ofs 32) '(0 1 2 3) font-32 (str-from-n stats-vin "%.2f"))
                        (setq ofs (+ ofs 62))
                })

                (disp-render imgbuf 34 0 colors-text-aa)
        })

        (loopwhile-thd 200 t {
                (draw)
                (sleep 0.05)
        })

        (event-register-handler (spawn event-handler))
        (event-enable 'event-can-sid)

        ;(if config-boot-animation-enable (start-boot-animation))

        (loopwhile-thd ("Stats" 200) t {
                (print "Starting stats-thread")

                (match (trap (stats-thread))
                    ((exit-ok (? a)) (print "Stats-thread exit"))
                    (_ (print "Stats-thread crashed"))
                )

                (sleep 5.0)
        })

        (def init-complete true)
})

@const-end

(image-save)
(main)

