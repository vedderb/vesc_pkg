(import "pkg@://vesc_packages/lib_code_server/code_server.vescpkg" 'code-server)
(read-eval-program code-server)

(def light-on 0)
(def drive-mode 1)

(def cruise-on 0)
(def cruise-ts 0)

(def battery-a-charging false)
(def battery-a-chg-time 0.0)
(def stats-battery-ah 0.0)

@const-start

(defmacro run-m2 (code) `(atomic {
            (var res nil)
            (select-motor 2)
            (setq res ,code)
            (select-motor 1)
            res
}))

(defun has-dual-motors () {
        (atomic
            (var motor-before (get-selected-motor))
            (select-motor 2)
            (var res (= (get-selected-motor) 2))
            (select-motor motor-before)
            res
        )
})

(def dual-motors (has-dual-motors))

(defun proc-sid (id data) {
        (cond
            ((= id 35) {
                    (setq battery-a-charging (= (bufget-u8 data 2) 1))
                    (setq battery-a-chg-time (bufget-u16 data 3))
                    (setq stats-battery-ah (/ (bufget-u16 data 5) 10.0))
            })

            ((= id 201) {
                    (var drive-mode-new (bufget-u8 data 0))
                    (setq light-on (bufget-u8 data 1))

                    (if (!= drive-mode drive-mode-new) (setq cruise-on 0))

                    (setq drive-mode drive-mode-new)

                    (match drive-mode
                        (0 { ; Reverse
                                (conf-set 'l-current-max-scale 0.4)
                                (conf-set 'min-speed (/ -10.0 3.6))
                                (if dual-motors {
                                        (run-m2 (conf-set 'l-current-max-scale 0.8))
                                        (run-m2 (conf-set 'max-speed (/ 10.0 3.6)))
                                })
                        })
                        (1 { ; Neutral
                                (conf-set 'l-current-max-scale 0.8)
                                (if dual-motors {
                                        (run-m2 (conf-set 'l-current-max-scale 0.8))
                                })
                        })
                        (2 { ; 1
                                (conf-set 'l-current-max-scale 0.5)
                                (conf-set 'max-speed (/ 20.0 3.6))
                                (if dual-motors {
                                        (run-m2 (conf-set 'l-current-max-scale 0.5))
                                        (run-m2 (conf-set 'max-speed (/ 20.0 3.6)))
                                })
                        })
                        (3 { ; 2
                                (conf-set 'l-current-max-scale 0.6)
                                (conf-set 'max-speed (/ 25.0 3.6))
                                (if dual-motors {
                                        (run-m2 (conf-set 'l-current-max-scale 0.6))
                                        (run-m2 (conf-set 'max-speed (/ 25.0 3.6)))
                                })
                        })
                        (4 { ; 3
                                (conf-set 'l-current-max-scale 1.0)
                                (conf-set 'max-speed (/ 200.0 3.6))
                                (if dual-motors {
                                        (run-m2 (conf-set 'l-current-max-scale 1.0))
                                        (run-m2 (conf-set 'max-speed (/ 200.0 3.6)))
                                })
                        })
                    )

                    (if (= light-on 1)
                        {
                            (set-aux 1 1)
                            (set-aux 2 1)
                        }
                        {
                            (set-aux 1 0)
                            (set-aux 2 0)
                        }
                    )
            })

            ; Event
            ((= id 250) {
                    (cond
                        ((= (bufget-u8 data 0) 0) { ; Toggle cruise control
                                (setq cruise-on (if (= cruise-on 0) 1 0))
                                (if (= cruise-on 1) (setq cruise-ts (systime)))
                        })

                        ((= (bufget-u8 data 0) 1) { ; About to turn off
                                ; store-backup is very new, so fall back to conf-store
                                ; if it does not exist using trap
                                (match (trap (store-backup))
                                    ((exit-ok (? a)) t)
                                    (_ (conf-store))
                                )
                        })
                    )
            })
        )
})

(defun event-handler ()
    (loopwhile t
        (recv
            ((event-can-sid . ((? id) . (? data))) (proc-sid id data))
            (_ nil)
)))

(defun main () {
        (set-print-prefix "ESC-")

        (event-register-handler (spawn event-handler))
        (event-enable 'event-can-sid)

        (var buf-can (array-create 8))

        (loopwhile-thd ("Send CAN" 100) t {
                (bufclear buf-can)
                (bufset-i16 buf-can 0 (* (get-batt) 1000))
                (bufset-i16 buf-can 2 (* (abs (get-duty)) 1000))
                (bufset-i16 buf-can 4 (* (abs (get-speed)) 3.6 10))
                (if dual-motors
                    {
                        (bufset-i16 buf-can 6 (* (+ (get-current-in) (run-m2 (get-current-in))) (get-vin) 0.1))
                    }
                    {
                        (bufset-i16 buf-can 6 (* (get-current-in) (get-vin) 0.1))
                    }
                )
                (can-send-sid 20 buf-can)

                (bufclear buf-can)
                (if (> (get-bms-val 'bms-temp-adc-num) 2)
                    (bufset-i16 buf-can 0 (* (get-bms-val 'bms-temps-adc 2) 10))
                    (bufset-i16 buf-can 0 0)
                )
                (bufset-i16 buf-can 2 (* (get-temp-fet) 10))
                (bufset-i16 buf-can 4 (* (get-temp-mot) 10))
                (bufset-i16 buf-can 6 (* (ix (get-imu-rpy) 1) 100))
                (can-send-sid 21 buf-can)

                (bufclear buf-can)
                (if dual-motors
                    {
                        (bufset-u16 buf-can 0 (* (+ (get-wh) (run-m2 (get-wh))) 10.0))
                        (bufset-u16 buf-can 2 (* (+ (get-wh-chg) (run-m2 (get-wh-chg))) 10.0))
                    }
                    {
                        (bufset-u16 buf-can 0 (* (get-wh) 10.0))
                        (bufset-u16 buf-can 2 (* (get-wh-chg) 10.0))
                    }
                )
                (bufset-u16 buf-can 4 (* (/ (get-dist-abs) 1000.0) 10))
                (bufset-u16 buf-can 6 (get-fault))
                (can-send-sid 22 buf-can)

                (bufclear buf-can)
                (if dual-motors
                    {
                        (bufset-u16 buf-can 0 (to-i (+ (stats 'stat-current-avg) (run-m2 (stats 'stat-current-avg)))))
                        (bufset-u16 buf-can 2 (to-i (+ (stats 'stat-current-max) (run-m2 (stats 'stat-current-max)))))
                        (bufset-i16 buf-can 4 (to-i (+ (get-current) (run-m2 (get-current)))))
                    }
                    {
                        (bufset-u16 buf-can 0 (to-i (stats 'stat-current-avg)))
                        (bufset-u16 buf-can 2 (to-i (stats 'stat-current-max)))
                        (bufset-i16 buf-can 4 (to-i (get-current)))
                    }
                )
                (bufset-u16 buf-can 6 (to-i (conf-get 'si-battery-ah)))
                (can-send-sid 23 buf-can)

                (bufclear buf-can)
                (bufset-u16 buf-can 0 (* (get-vin) 10))
                (bufset-u32 buf-can 2 (* (/ (sysinfo 'odometer) 1000.0) 10))
                (bufset-u16 buf-can 6 (* (abs (get-speed-set)) 3.6 10)) ; Cruise control speed
                ; Reserved space
                (can-send-sid 24 buf-can)

                (bufclear buf-can)
                (bufset-u8 buf-can 0 cruise-on)
                (can-send-sid 202 buf-can)

                (if (and (> (secs-since cruise-ts) 1) (< (* (abs (get-speed-set)) 3.6) 5.0)) {
                        (setq cruise-on 0)
                })

                (sleep 0.1) ; 10 Hz
        })

        (start-code-server)
})

@const-end

(image-save)
(main)
