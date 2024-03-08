(import "pkg::font_16_26@://vesc_packages/lib_files/files.vescpkg" 'font)
(import "../text.lisp" 'disp-text)
(import "../button.lisp" 'disp-button)
(import "../symbols.lisp" 'disp-symbols)
(import "../gauges.lisp" 'disp-gauges)

(read-eval-program disp-text)
(read-eval-program disp-button)
(read-eval-program disp-symbols)
(read-eval-program disp-gauges)

(hw-init)

(def bt1 0)
(def bt2 0)
(def bt3 0)
(def bt4 0)

(def page-now 1)
(def page-num 4)
(def page-now-menu 1)
(def page-num-menu 2)
(def is-menu false)

(def btn-cnt 4)

(loopwhile-thd 120 t {
        (def btn-adc (v-btn))

        (var new-bt1 (and (> btn-adc 0.2) (< btn-adc 0.4)))
        (var new-bt2 (and (> btn-adc 0.55) (< btn-adc 0.7)))
        (var new-bt3 (and (> btn-adc 0.95) (< btn-adc 1.15)))
        (var new-bt4 (and (> btn-adc 0.7) (< btn-adc 0.9)))

        (def bt1 (if new-bt1 (+ bt1 1) 0))
        (def bt2 (if new-bt2 (+ bt2 1) 0))
        (def bt3 (if new-bt3 (+ bt3 1) 0))
        (def bt4 (if new-bt4 (+ bt4 1) 0))

        ; Regular press

        (if (= bt1 btn-cnt) {

        })

        (if (= bt2 btn-cnt) {
                (if is-menu
                    (setq page-now-menu (if (= page-now-menu 1) page-num-menu (- page-now-menu 1)))
                    (setq page-now (if (= page-now 1) page-num (- page-now 1)))
                )
        })

        (if (= bt3 btn-cnt) {
                (if is-menu
                    (setq page-now-menu (if (= page-now-menu page-num-menu) 1 (+ page-now-menu 1)))
                    (setq page-now (if (= page-now page-num) 1 (+ page-now 1)))
                )
        })

        (if (= bt4 btn-cnt) {
                (setq is-menu (not is-menu))
        })

        ; Long press

        (if  (and (= bt1 100) (not is-menu)) {
                (gpio-write pin-bl 0)
                (loopwhile (< (v-btn) 2.0) (sleep 0.1))
                (sleep-config-wakeup-pin 3 0)
                (sleep-deep -1)
        })

        (sleep 0.015)
})

(def img-data (img-buffer 'indexed4 320 190))
(def img-btn (img-buffer 'indexed4 320 50))

(defun draw-btn (pressed offset txt) {
        (btn-simple img-btn (if pressed 2 1) 3 (+ 5 offset) 5 76 40 font txt)
})

(def bt-before (list -1 -1 -1 -1))

(loopwhile-thd 100 t {
        (var bt-now (list bt1 bt2 bt3 bt4))
        (var changed (not-eq bt-now bt-before))
        (def bt-before bt-now)

        (if changed
            (if is-menu
                {
                    (img-clear img-btn)
                    (btn-bar img-btn 2 3 (/ bt1 100.0) 5 5 76 40 font "Run")
                    (draw-btn (>= bt2 2) 80 "<")
                    (draw-btn (>= bt3 2) 160 ">")
                    (draw-btn (>= bt4 2) 240 "Exit")
                    (disp-render img-btn 0 190 '(0 0x252525 0x004488 0xFFFF00))
                }
                {
                    (img-clear img-btn)
                    (sym-pwr img-btn (if (>= bt1 2) 2 3) 40 20 20 (/ bt1 100.0))
                    (draw-btn (>= bt2 2) 80 "<")
                    (draw-btn (>= bt3 2) 160 ">")
                    (draw-btn (>= bt4 2) 240 "Menu")
                    (disp-render img-btn 0 190 '(0 0x252525 0x004488 0xFFFF00))
                }
        ))

        (sleep 0.1)
})

(defun txt-page (str)
    (txt-block-c img-data 2 160 175 font
        (str-merge (str-from-n page-now) "/" (str-from-n page-num) str)
))

(defun dual-gauges (t1 v1 t2 v2) {
        ; disp-gauge (img col-bg col-bar col-txt cx cy rad val txt)
        (gauge-simple img-data 1 2 3 80 90 75 v1 font t1)
        (gauge-simple img-data 1 2 3 240 90 75 v2 font t2)
})

(loopwhile-thd 100 t {
        (img-clear img-data)

        (if is-menu
            {
                (match page-now-menu
                    (1 {
                            (txt-block-c img-data 2 160 95 font (list
                                "SurRon Setup"
                                ""
                                "This will setup a"
                                "SurRon bike. Hold"
                                "Run to proceed."
                            ))
                    })

                    (2 {
                            (txt-block-c img-data 2 160 95 font (list
                                "Talaria Setup"
                                ""
                                "This will setup a"
                                "Talaria bike. Hold"
                                "Run to proceed."
                            ))
                    })

                    (_ nil)
                )
            }
            {
                (var soc (get-bms-val 'bms-soc))
                (var pwr (* (get-bms-val 'bms-i-in-ic) (get-bms-val 'bms-v-tot)))

                (match page-now
                    (1 {
                            (txt-page ": SoC & PWR")
                            (dual-gauges
                                (list "Bat" (str-from-n (* soc 100.0) "%.1f")) soc
                                (list "Pwr" (str-from-n (* pwr 0.001) "%.1f")) (/ pwr 5000.0)
                            )
                    })

                    (2 {
                            (txt-page ": Speed & Current")
                            (dual-gauges
                                (list "km/h" (str-from-n (* soc 100.0) "%.1f")) soc
                                (list "Amps" (str-from-n (* pwr 0.001) "%.1f")) (/ pwr 5000.0)
                            )
                    })

                    (_ nil)
                )
            }
        )

        (disp-render img-data 0 0 '(0 0x444444 0x009900 0xffffff))
        (sleep 0.05)
})
