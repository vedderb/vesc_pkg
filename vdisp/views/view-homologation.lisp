(def view-state-now (list))
(def view-state-previous (list))

@const-start

(def stripe-animation-start nil) ; timestamp
(def stripe-animation-direction nil) ; nil for hiding, true for showing
(def stripe-animation-duration 0.42) ; seconds

(defun update-state-now ()
    (def view-state-now (list
        stats-kmh                           ; 0
        (to-i (* 100 stats-battery-soc))    ; 1
        highbeam-on                         ; 2
        kickstand-down                      ; 3
        drive-mode                          ; 4
        performance-mode                    ; 5
        indicate-l-on                       ; 6
        indicate-r-on                       ; 7
        cruise-control-active               ; 8
        cruise-control-speed                ; 9
        battery-a-charging                  ; 10
        battery-b-charging                  ; 11
        (to-i (* 100 battery-b-soc))        ; 12
        (> stats-temp-battery 80.0)         ; 13
        (> stats-temp-motor 80.0)           ; 14
        battery-b-connected                 ; 15
        (to-i (* stats-odom 10))            ; 16
    ))
)

(defun spooky-light-glitch () {
    (var start-time (systime))
    (loopwhile (< (secs-since start-time) 2.5) {
        (disp-render buf-lights 165 1 colors-dim-icon)
        (sleep (/ (mod (rand) 200) 1000.0))
        (disp-render buf-lights 165 1 colors-green-icon)
        (sleep (/ (mod (rand) 200) 1000.0))
    })
})

(defun view-init-homologation  () {
    (def buf-stripe-bg icon-stripe)
    (def buf-stripe-fg (img-buffer dm-pool 'indexed16 141 19))
    (def buf-stripe-top icon-stripe-top)
    (def buf-arrow-l icon-arrow-l)
    (def buf-arrow-r icon-arrow-r)
    (img-blit buf-stripe-fg buf-stripe-top 0 0 -1)

    (def buf-warning-icon icon-warning)
    (def buf-hot-battery icon-hot-battery)
    (def buf-hot-motor icon-hot-motor)

    (def buf-battery-a-sm (img-buffer dm-pool 'indexed4 20 62))
    (def buf-battery-b-sm (img-buffer dm-pool 'indexed4 20 62))
    (def buf-battery-a-sm-soc (img-buffer dm-pool 'indexed4 20 50))
    (def buf-battery-b-sm-soc (img-buffer dm-pool 'indexed4 20 50))
    
    (def buf-speed (img-buffer dm-pool 'indexed16 179 90))
    (def buf-units (img-buffer dm-pool 'indexed4 50 15))

    (def buf-blink-left icon-blinker-left)
    (def buf-blink-right icon-blinker-right)
    (def buf-indicate-l-anim (img-buffer dm-pool 'indexed4 62 18))
    (def buf-indicate-r-anim (img-buffer dm-pool 'indexed4 62 18))
    (def buf-cruise-control icon-cruise-control)
    (def buf-cruise-speed (img-buffer dm-pool 'indexed4 65 32))
    (def buf-lights icon-lights)
    (def buf-highbeam icon-highbeam)
    (def buf-kickstand icon-kickstand)
    (def buf-neutral-mode icon-neutral)
    (def buf-drive-mode icon-drive)
    (def buf-reverse-mode icon-reverse)
    (def buf-performance-mode (img-buffer dm-pool 'indexed4 50 20))
    (def buf-charge-bolt icon-charge-bolt)
    (def buf-odom (img-buffer dm-pool 'indexed4 140 15))
    (def buf-high-low-beam (img-buffer dm-pool 'indexed4 55 39))
    (def buf-lowbeam icon-lowbeam)
    (def buf-start-motor icon-start-motor)
    (def buf-start-msg icon-start-msg)

    (disp-render buf-blink-left 1 1 colors-dim-icon)
    (disp-render buf-blink-right (- 319 (first (img-dims buf-blink-right))) 1 colors-dim-icon)
    (disp-render buf-cruise-control 10 44 colors-dim-icon)
    (disp-render buf-lights 165 1 colors-green-icon)
    (img-blit buf-high-low-beam buf-lowbeam 0 0 -1)
    (disp-render buf-high-low-beam 104 1 colors-green-icon)
    (disp-render buf-kickstand 270 116 colors-red-icon)
    (disp-render buf-hot-motor 124 50 colors-dim-icon-16c)
    (disp-render buf-warning-icon 167 50 colors-dim-icon)
    (disp-render buf-hot-battery 215 50 colors-dim-icon-16c)
    (disp-render buf-neutral-mode 270 172 colors-green-icon)

    (if btn-3-pressed (spooky-light-glitch))

    (view-init-menu)
    (defun on-btn-0-long-pressed () {
        (hw-sleep)
    })
    (defun on-btn-2-pressed () {
        (setting-units-cycle)
        (setix view-state-previous 0 'stats-kmh) ; Re-draw units

    })
    (defun on-btn-2-long-pressed () {
        (setting-units-cycle-temps)

    })
    (defun on-btn-3-pressed () (def state-view-next (next-view)))

    (update-state-now)
    (def view-state-previous (list
        'stats-kmh
        'stats-battery-soc
        'highbeam-on
        'kickstand-down
        'drive-mode
        'performance-mode
        'indicate-l-on
        'indicate-r-on
        'cruise-control-active
        'cruise-control-speed
        'battery-a-charging
        'battery-b-charging
        'battery-b-soc
        'hot-battery
        'hot-motor
        'battery-b-connected
        'stats-odom
    ))

    (disp-render buf-stripe-bg 5 93 colors-stripes-16c)
})

(defun view-draw-homologation () {

    ; Update state before buffering new content
    (update-state-now)

    ; Ensure re-draw between kickstand states
    (if (not-eq (ix view-state-now 3) (ix view-state-previous 3)) {
        (setix view-state-previous 0 'update-speed)
        (setix view-state-previous 1 'update-battery-soc)
        (setix view-state-previous 16 'update-odom)
    })

    ; Ensure re-draw when changing drive mode
    (if (not-eq (ix view-state-now 4) (ix view-state-previous 4)) {
        (setix view-state-previous 0 'update-speed)
    })

    ; Draw Speed or Large Batteries
    (if (not-eq (ix view-state-now 0) (first view-state-previous)) {
        ; Draw Speed Units
        (img-clear buf-units)
        (draw-units buf-units 0 0 (list 0 1 2 3) font15)

        (img-clear buf-speed)
        (if (eq (ix view-state-now 4) 'neutral) {
            ; Draw Press to Start
            (img-blit buf-speed buf-start-motor 20 10 -1)
            (img-blit buf-speed buf-start-msg (+ (first (img-dims buf-start-motor)) 25) 10 -1)
        } {
            ; Draw Speed
            (var speed-now (match (car settings-units-speeds)
                (kmh (ix view-state-now 0))
                (mph (* (ix view-state-now 0) km-to-mi))
                (_ (print "Unexpected settings-units-speeds value"))
            ))
            (txt-block-c buf-speed (list 0 1 2 3) 87 0 font88 (str-from-n speed-now "%0.0f"))
        })

        ; Update Speed Arrow
        (var arrow-x-max (- 141 24))
        (var arrow-x (if (> stats-kmh-max 0.0)
            (* arrow-x-max (/ (ix view-state-now 0) stats-kmh-max))
            0
        ))
        (img-blit buf-stripe-fg buf-stripe-top 0 0 -1)
        (if (> arrow-x 0) {
            ; Fill area behind arrow
            (img-rectangle buf-stripe-fg 0 0 arrow-x 19 1 '(filled))
        })
        (img-blit buf-stripe-fg buf-arrow-l arrow-x 0 -1)
        (img-blit buf-stripe-fg buf-arrow-r (+ arrow-x 12) 0 -1)
    })

    ; Draw Batteries
    (if (or
        (not-eq (ix view-state-now 1) (ix view-state-previous 1))
        (not-eq (ix view-state-now 10) (ix view-state-previous 10))
        (not-eq (ix view-state-now 11) (ix view-state-previous 11))
        (not-eq (ix view-state-now 12) (ix view-state-previous 12))
        (not-eq (ix view-state-now 15) (ix view-state-previous 15))
        (not-eq (ix view-state-now 16) (ix view-state-previous 16))
    ) {
        ; Update Battery %
        (img-clear buf-battery-a-sm)
        (img-clear buf-battery-b-sm)
        (var bat-a-soc (/ (ix view-state-now 1) 100.0))
        (var bat-a-soc-i (ix view-state-now 1))
        (if (< bat-a-soc-i 0) (setq bat-a-soc-i 0))

        (var bat-b-soc (/ (ix view-state-now 12) 100.0))
        (var bat-b-soc-i (ix view-state-now 12))
        (if (< bat-b-soc-i 0) (setq bat-b-soc-i 0))

        ; Battery A
        (draw-battery-vertical buf-battery-a-sm (first (img-dims buf-battery-a-sm)) (second (img-dims buf-battery-a-sm)) bat-a-soc 1)
        (img-clear buf-battery-a-sm-soc)
        (txt-block-v buf-battery-a-sm-soc (list 0 1 2 3) -1 0 0 (first (img-dims buf-battery-a-sm-soc)) (second (img-dims buf-battery-a-sm-soc)) font15 (str-merge "%" (str-from-n bat-a-soc-i "%d")))

        ; Battery B Value
        (if (ix view-state-now 15) {
            ; Battery B is connected
            (draw-battery-vertical buf-battery-b-sm (first (img-dims buf-battery-b-sm)) (second (img-dims buf-battery-b-sm)) bat-b-soc 1)
            (img-clear buf-battery-b-sm-soc)
            (txt-block-v buf-battery-b-sm-soc (list 0 1 2 3) -1 0 0 (first (img-dims buf-battery-b-sm-soc)) (second (img-dims buf-battery-b-sm-soc)) font15 (str-merge "%" (str-from-n bat-b-soc-i "%d")))
        } {
            (img-clear buf-battery-b-sm)
            (img-clear buf-battery-b-sm-soc)
        })

        ; Large batteries
        (if (ix view-state-now 3) {
            (img-clear buf-speed)
            (draw-battery-horizontal buf-speed 18 0 130 27 bat-a-soc 1 1 4)
            (if (ix view-state-now 15)
                (draw-battery-horizontal buf-speed 18 47 130 27 bat-b-soc 1 1 5)
            )

            (if (ix view-state-now 10) {
                ; Battery A is Charging
                (img-blit buf-speed buf-charge-bolt 55 4 0)
                ; TODO: Provide charge time estimate
                (if (< bat-a-soc-i 100) (txt-block-r buf-speed '(0 1 2 3) 160 28 font18 (str-merge "2h10m")))
            })

            (if (and
                    (ix view-state-now 11) ; Battery B charging
                    (ix view-state-now 15) ; Battery B connected
                ) {
                    ; Battery B is Charging
                    (img-blit buf-speed buf-charge-bolt 55 51 0)
                    ; TODO: Provide charge time estimate
                    (if (< bat-b-soc-i 100) (txt-block-r buf-speed '(0 1 2 3) 160 74 font18 (str-merge "1h28m")))
            })

            ; SOC
            (txt-block-l buf-speed '(0 1 2 3) 20 28 font18 (str-merge (str-from-n bat-a-soc-i "%d") "%"))
            (if (ix view-state-now 15) (txt-block-l buf-speed '(0 1 2 3) 20 74 font18 (str-merge (str-from-n bat-b-soc-i "%d") "%")))
        })
    })

    ; Indicators
    (var anim-pct 1.0)
    (if (> indicate-ms 0)
        (setq anim-pct (clamp01 (/ (secs-since indicator-timestamp) (/ indicate-ms 1000.0))))
    )
    (if (ix view-state-now 6) (draw-turn-animation buf-indicate-l-anim 'left anim-pct))
    (if (ix view-state-now 7) (draw-turn-animation buf-indicate-r-anim 'right anim-pct))

    ; Indicator Left Completed
    (if (not-eq (ix view-state-now 6) (ix view-state-previous 6)) {
        (if (not (ix view-state-now 6)) (draw-turn-animation buf-indicate-l-anim 'left 1.0))
    })

    ; Indicator Right Completed
    (if (not-eq (ix view-state-now 7) (ix view-state-previous 7)) {
        (if (not (ix view-state-now 7)) (draw-turn-animation buf-indicate-r-anim 'right 1.0))
    })

    ; Highbeam
    (if (not-eq (ix view-state-now 2) (third view-state-previous)) {
        (img-clear buf-high-low-beam)
        (if (ix view-state-now 2)
            (img-blit buf-high-low-beam buf-highbeam 0 0 -1)
            (img-blit buf-high-low-beam buf-lowbeam 0 0 -1)
        )
    })

    ; Performance Mode
    (if (not-eq (ix view-state-now 5) (ix view-state-previous 5)) {
        (match (ix view-state-now 5)
            (eco (txt-block-c buf-performance-mode (list 0 1 2 3) (/ (first (img-dims buf-performance-mode)) 2) 0 font18 (to-str "ECO")))
            (normal (txt-block-c buf-performance-mode (list 0 1 2 3) (/ (first (img-dims buf-performance-mode)) 2) 0 font18 (to-str "NML")))
            (sport (txt-block-c buf-performance-mode (list 0 1 2 3) (/ (first (img-dims buf-performance-mode)) 2) 0 font18 (to-str "SPT")))
        )
    })

    ; Cruise Control
    (if (or (not-eq (ix view-state-now 8) (ix view-state-previous 8)) (not-eq (ix view-state-now 9) (ix view-state-previous 9))) {
        (img-clear buf-cruise-speed)
        (var cruise-speed (match (car settings-units-speeds)
            (kmh (ix view-state-now 9))
            (mph (* (ix view-state-now 9) km-to-mi))
            (_ 0.0)
        ))
        (txt-block-l buf-cruise-speed (list 0 1 2 3) 0 0 font32 (str-from-n (to-float cruise-speed) "%.0f"))
    })

    ; Draw odometer
    (if (not-eq (ix view-state-now 16) (ix view-state-previous 16)) {
        (img-clear buf-odom)
        (var odom (match (car settings-units-speeds)
            (kmh (str-merge (str-from-n (* (ix view-state-now 16) 0.1) "%0.1f") "km"))
            (mph (str-merge (str-from-n (* (ix view-state-now 16) km-to-mi 0.1) "%0.1f") "mi"))
        ))
        (txt-block-c buf-odom (list 0 1 2 3) (/ (first (img-dims buf-odom)) 2) 0 font15 odom)
    })
})

(defun view-render-homologation () {

    (var colors-anim '(0x000000 0x000000 0x171717 0x00ff00))

    ; Indicator Left
    (if (ix view-state-now 6) (disp-render buf-indicate-l-anim 38 11 colors-anim))
    (if (not-eq (ix view-state-now 6) (ix view-state-previous 6)) {
        (if (ix view-state-now 6)
            (disp-render buf-blink-left 1 1 colors-green-icon)
            {
                (disp-render buf-blink-left 1 1 colors-dim-icon)
                (disp-render buf-indicate-l-anim 38 11 colors-anim)
            }
        )
    })

    ; Indicator Right
    (if (ix view-state-now 7) (disp-render buf-indicate-r-anim 218 11 colors-anim))
    (if (not-eq (ix view-state-now 7) (ix view-state-previous 7)) {
        (if (ix view-state-now 7)
            (disp-render buf-blink-right (- 319 (first (img-dims buf-blink-right))) 1 colors-green-icon)
            {
                (disp-render buf-blink-right (- 319 (first (img-dims buf-blink-right))) 1 colors-dim-icon)
                (disp-render buf-indicate-r-anim 218 11 colors-anim)
            }
        )
    })

    ; Highbeam
    (if (not-eq (ix view-state-now 2) (third view-state-previous)) {
        (if (ix view-state-now 2)
            (disp-render buf-high-low-beam 104 1 colors-blue-icon)
            (disp-render buf-high-low-beam 104 1 colors-green-icon)
        )
    })

    ; Cruise Control
    (if (or (not-eq (ix view-state-now 8) (ix view-state-previous 8)) (not-eq (ix view-state-now 9) (ix view-state-previous 9))) {
        ; Clear speed units from previous position
        (if (ix view-state-now 8) {
            (disp-render buf-cruise-control 10 44 colors-green-icon)
            (disp-render buf-cruise-speed 55 58 colors-white-icon)
            ; TODO: Units offset if 1, 2, 3 digit cruise speed: (disp-render buf-units 120 75 colors-white-icon)
        } {
            (disp-render buf-cruise-control 10 44 colors-dim-icon)
            (disp-render buf-cruise-speed 55 58 colors-dim-icon)
            ; TODO: Units offset if 1, 2, 3 digit cruise speed: (disp-render buf-units 120 75 colors-dim-icon)
        })
    })

    ; Kickstand
    (if (not-eq (ix view-state-now 3) (ix view-state-previous 3)) {
        (if (ix view-state-now 3) {
            ; Clear small batteries
            (disp-render buf-battery-a-sm 262 92 '(0x0 0x0 0x0 0x0))
            (disp-render buf-battery-a-sm-soc 262 40 '(0x0 0x0 0x0 0x0))
            (disp-render buf-battery-b-sm 288 92 '(0x0 0x0 0x0 0x0))
            (disp-render buf-battery-b-sm-soc 288 40 '(0x0 0x0 0x0 0x0))

            ; Show kickstand down icon
            (disp-render buf-kickstand 270 116 colors-red-icon)

            ; Hide Stripes
            (def stripe-animation-direction nil)
            (def stripe-animation-start (systime))
            ; TODO: (rcode-run-noret config-can-id-esc '(alert-descend))
        } {
            (disp-render buf-kickstand 270 116 '(0x0 0x0 0x0 0x0)) ; Hide kickstand
            (disp-render buf-units 175 222 colors-white-icon) ; Show Speed Units

            ; Show Stripes
            (def stripe-animation-direction true)
            (def stripe-animation-start (systime))
            ; TODO: (rcode-run-noret config-can-id-esc '(alert-ascend))
        })

        (setix view-state-previous 0 'update-speed)
        (setix view-state-previous 1 'update-battery-soc)
        (setix view-state-previous 16 'update-odom)
    })

    ; Stripes Show/Hide Animation
    (loopwhile stripe-animation-start {
        (var pct (clamp01 (/ (secs-since stripe-animation-start) stripe-animation-duration)))

        (if stripe-animation-direction {
            ; Showing stripes (grow up)
            (disp-render buf-stripe-bg 5 93 (list
                (img-color 'gradient_y (color-mix 0x000000 (ix colors-stripes-16c 0)  (ease-in-sine pct)) (ix colors-stripes-16c 0)  147 0)
                (img-color 'gradient_y (color-mix 0x000000 (ix colors-stripes-16c 1)  (ease-in-sine pct)) (ix colors-stripes-16c 1)  147 0)
                (img-color 'gradient_y (color-mix 0x000000 (ix colors-stripes-16c 2)  (ease-in-sine pct)) (ix colors-stripes-16c 2)  147 0)
                (img-color 'gradient_y (color-mix 0x000000 (ix colors-stripes-16c 3)  (ease-in-sine pct)) (ix colors-stripes-16c 3)  147 0)
                (img-color 'gradient_y (color-mix 0x000000 (ix colors-stripes-16c 4)  (ease-in-sine pct)) (ix colors-stripes-16c 4)  147 0)
                (img-color 'gradient_y (color-mix 0x000000 (ix colors-stripes-16c 5)  (ease-in-sine pct)) (ix colors-stripes-16c 5)  147 0)
                (img-color 'gradient_y (color-mix 0x000000 (ix colors-stripes-16c 6)  (ease-in-sine pct)) (ix colors-stripes-16c 6)  147 0)
                (img-color 'gradient_y (color-mix 0x000000 (ix colors-stripes-16c 7)  (ease-in-sine pct)) (ix colors-stripes-16c 7)  147 0)
                (img-color 'gradient_y (color-mix 0x000000 (ix colors-stripes-16c 8)  (ease-in-sine pct)) (ix colors-stripes-16c 8)  147 0)
                (img-color 'gradient_y (color-mix 0x000000 (ix colors-stripes-16c 9)  (ease-in-sine pct)) (ix colors-stripes-16c 9)  147 0)
                (img-color 'gradient_y (color-mix 0x000000 (ix colors-stripes-16c 10) (ease-in-sine pct)) (ix colors-stripes-16c 10) 147 0)
                (img-color 'gradient_y (color-mix 0x000000 (ix colors-stripes-16c 11) (ease-in-sine pct)) (ix colors-stripes-16c 11) 147 0)
                (img-color 'gradient_y (color-mix 0x000000 (ix colors-stripes-16c 12) (ease-in-sine pct)) (ix colors-stripes-16c 12) 147 0)
                (img-color 'gradient_y (color-mix 0x000000 (ix colors-stripes-16c 13) (ease-in-sine pct)) (ix colors-stripes-16c 13) 147 0)
                (img-color 'gradient_y (color-mix 0x000000 (ix colors-stripes-16c 14) (ease-in-sine pct)) (ix colors-stripes-16c 14) 147 0)
            ))
        } {
            ; Hiding stripes (grow down)
            (disp-render buf-stripe-bg 5 93 (list
                (img-color 'gradient_y 0x000000 (color-mix (ix colors-stripes-16c 0)  0x000000 (ease-out-sine pct)) 147 0)
                (img-color 'gradient_y 0x000000 (color-mix (ix colors-stripes-16c 1)  0x000000 (ease-out-sine pct)) 147 0)
                (img-color 'gradient_y 0x000000 (color-mix (ix colors-stripes-16c 2)  0x000000 (ease-out-sine pct)) 147 0)
                (img-color 'gradient_y 0x000000 (color-mix (ix colors-stripes-16c 3)  0x000000 (ease-out-sine pct)) 147 0)
                (img-color 'gradient_y 0x000000 (color-mix (ix colors-stripes-16c 4)  0x000000 (ease-out-sine pct)) 147 0)
                (img-color 'gradient_y 0x000000 (color-mix (ix colors-stripes-16c 5)  0x000000 (ease-out-sine pct)) 147 0)
                (img-color 'gradient_y 0x000000 (color-mix (ix colors-stripes-16c 6)  0x000000 (ease-out-sine pct)) 147 0)
                (img-color 'gradient_y 0x000000 (color-mix (ix colors-stripes-16c 7)  0x000000 (ease-out-sine pct)) 147 0)
                (img-color 'gradient_y 0x000000 (color-mix (ix colors-stripes-16c 8)  0x000000 (ease-out-sine pct)) 147 0)
                (img-color 'gradient_y 0x000000 (color-mix (ix colors-stripes-16c 9)  0x000000 (ease-out-sine pct)) 147 0)
                (img-color 'gradient_y 0x000000 (color-mix (ix colors-stripes-16c 10) 0x000000 (ease-out-sine pct)) 147 0)
                (img-color 'gradient_y 0x000000 (color-mix (ix colors-stripes-16c 11) 0x000000 (ease-out-sine pct)) 147 0)
                (img-color 'gradient_y 0x000000 (color-mix (ix colors-stripes-16c 12) 0x000000 (ease-out-sine pct)) 147 0)
                (img-color 'gradient_y 0x000000 (color-mix (ix colors-stripes-16c 13) 0x000000 (ease-out-sine pct)) 147 0)
                (img-color 'gradient_y 0x000000 (color-mix (ix colors-stripes-16c 14) 0x000000 (ease-out-sine pct)) 147 0)
            ))
        })

        ; Mark as complete
        (if (>= pct 1.0) (def stripe-animation-start nil))
    })

    ; Speed Now
    (if (not (ix view-state-now 3))
        (if (not-eq (ix view-state-now 0) (first view-state-previous)) {
            (disp-render buf-speed 0 125 colors-white-icon)
            (disp-render buf-units 175 222 colors-white-icon)

            (disp-render buf-stripe-fg 5 93
                '(
                    0x000000
                    0x1d9af7 ; top fg
                    0x1574b6 ; 2
                    0x0e5179 ; 3
                    0x143e59 ; 4
                    0x0e222f ; 5
                    0x00c7ff ; bottom fg
                    0x10b2e6 ; 7
                    0x1295bf ; 8
                    0x0984ac ; 9
                    0x007095 ; a
                    0x0e5179 ; b
                    0x08475c ; c
                    0x143e59 ; d
                    0x0e222f ; e
                ))
        })
    )

    ; Batteries (after processing kickstand-down)
    (if (or
        (not-eq (ix view-state-now 1) (ix view-state-previous 1))
        (not-eq (ix view-state-now 10) (ix view-state-previous 10))
        (not-eq (ix view-state-now 11) (ix view-state-previous 11))
        (not-eq (ix view-state-now 12) (ix view-state-previous 12))
        (not-eq (ix view-state-now 15) (ix view-state-previous 15))
        (not-eq (ix view-state-now 16) (ix view-state-previous 16))
    ) {
        (var bat-a-color 0x7f9a0d)
        (var bat-b-color 0x7f9a0d)
        (if (< stats-battery-soc 0.5)
            (setq bat-a-color (color-mix 0xe70000 0xffff00 (ease-in-sine (* stats-battery-soc 2))))
            (setq bat-a-color (color-mix 0xffff00 0x00ff00 (ease-out-sine (* (- stats-battery-soc 0.5) 2))))
        )
        (if (< battery-b-soc 0.5)
            (setq bat-b-color (color-mix 0xe70000 0xffff00 (ease-in-sine (* battery-b-soc 2))))
            (setq bat-b-color (color-mix 0xffff00 0x00ff00 (ease-out-sine (* (- battery-b-soc 0.5) 2))))
        )

        (if (ix view-state-now 3)
            ; Render speed buffer containing large battiers when parked
            (disp-render buf-speed 0 130 `(0x000000 0x4f514f 0x929491 0xfbfcfc ,bat-a-color ,bat-b-color))
            ; Render small batteries
            {
                (disp-render buf-battery-a-sm 262 92 `(0x000000 0xfbfcfc ,bat-a-color 0x0000ff))
                (disp-render buf-battery-a-sm-soc 259 40 colors-white-icon)

                (disp-render buf-battery-b-sm 288 92 `(0x000000 0xfbfcfc ,bat-b-color 0x0000ff))
                (disp-render buf-battery-b-sm-soc 285 40 colors-white-icon)
            }
        )
    })

    ; Drive Mode
    (if (not-eq (ix view-state-now 4) (ix view-state-previous 4)) {
        (match (ix view-state-now 4)
           (neutral (disp-render buf-neutral-mode 270 172 colors-green-icon))
           (drive (disp-render buf-drive-mode 270 172 colors-white-icon))
           (reverse (disp-render buf-reverse-mode 270 172 colors-white-icon))
        )
    })

    ; Performance Mode
    (if (not-eq (ix view-state-now 5) (ix view-state-previous 5)) {
        (disp-render buf-performance-mode 262 220 colors-white-icon)
    })

    ; Hot Battery
    (if (not-eq (ix view-state-now 13) (ix view-state-previous 13)) {
        (if (ix view-state-now 13)
            (disp-render buf-hot-battery 215 50 '(
                0x0
                0x350202
                0x600000
                0x7c0001
                0x1e201d
                0xa90000
                0xd40000
                0xef0003
                0xfd0000
                0x3f413e
                0x7f817e
                0x919390
                0xa2a4a1
                0xabadaa
                0xb4b6b3
                0xc7c9c6
            ))
            (disp-render buf-hot-battery 215 50 colors-dim-icon-16c)
        )
    })

    ; Hot Motor
    (if (not-eq (ix view-state-now 14) (ix view-state-previous 14)) {
        (if (ix view-state-now 14)
            (disp-render buf-hot-motor 124 50 '(
                0x0
                0x370002
                0x4b0000
                0x232522
                0x720002
                0xa30100
                0xda0000
                0xfd0000
                0x494b49
                0xb83c37
                0x666865
                0xb37577
                0x848683
                0xa4a4a1
                0xb9b9b7
                0xc9ccc8
            ))
            (disp-render buf-hot-motor 124 50 colors-dim-icon-16c)
        )
    })

    ; Render Odometer
    (if (not-eq (ix view-state-now 16) (ix view-state-previous 16))
        (disp-render buf-odom 20 222 colors-white-icon)
    )

    ; Update stats for improved performance
    (def view-state-previous (list
        (ix view-state-now 0)
        (ix view-state-now 1)
        (ix view-state-now 2)
        (ix view-state-now 3)
        (ix view-state-now 4)
        (ix view-state-now 5)
        (ix view-state-now 6)
        (ix view-state-now 7)
        (ix view-state-now 8)
        (ix view-state-now 9)
        (ix view-state-now 10)
        (ix view-state-now 11)
        (ix view-state-now 12)
        (ix view-state-now 13)
        (ix view-state-now 14)
        (ix view-state-now 15)
        (ix view-state-now 16)
    ))

    ; Render Warning Icon
    (if (> (length stats-fault-codes-observed) 0) {
        (disp-render buf-warning-icon 167 50 '(0x000000 0xff0000 0x929491 0xfbfcfc))
    })
})

(defun view-cleanup-homologation () {
    (def buf-stripe-bg nil)
    (def buf-stripe-fg nil)
    (def buf-stripe-top nil)
    (def buf-arrow-l nil)
    (def buf-arrow-r nil)
    
    (def buf-warning-icon nil)
    (def buf-hot-battery nil)
    (def buf-hot-motor nil)

    (def buf-battery-a-sm nil)
    (def buf-battery-a-sm-soc nil)

    (def buf-battery-b-sm nil)
    (def buf-battery-b-sm-soc nil)

    (def buf-speed nil)
    (def buf-units nil)

    (def buf-blink-left nil)
    (def buf-blink-right nil)
    (def buf-indicate-l-anim nil)
    (def buf-indicate-r-anim nil)
    (def buf-cruise-control nil)
    (def buf-cruise-speed nil)
    (def buf-lights nil)
    (def buf-highbeam nil)
    (def buf-kickstand nil)
    (def buf-neutral-mode nil)
    (def buf-drive-mode nil)
    (def buf-reverse-mode nil)
    (def buf-performance-mode nil)
    (def buf-charge-bolt nil)
    (def buf-odom nil)
    (def buf-high-low-beam nil)
    (def buf-lowbeam nil)
    (def buf-start-motor nil)
    (def buf-start-msg nil)
})
