;@const-symbol-strings
;Buffers
(def led-status-buffer)
(def led-front-buffer)
(def led-rear-buffer)
(def led-combined-buffer)
@const-start

(def led-loop-delay)
;config vars
(def led-enabled)
(def led-mode)
(def led-mode-idle)
(def led-mode-status)
(def led-mall-grab-enabled)
(def led-brake-light-enabled)
(def led-brake-light-min-amps)
(def idle-timeout)
(def idle-timeout-shutoff)
(def led-status-pin)
(def led-status-num)
(def led-status-type)
(def led-status-reversed)
(def led-front-pin)
(def led-front-num)
(def led-front-type)
(def led-front-reversed)
(def led-front-strip-type)
(def led-rear-pin)
(def led-rear-num)
(def led-rear-type)
(def led-rear-reversed)
(def led-rear-strip-type)
(def led-front-target-id)
(def led-rear-target-id)
(def led-status-target-id)
(def led-max-brightness)
(def led-update-not-running)

(def led-max-blend-count 0.0)  ; how many times to blend before new led buffer
(def led-dim-on-highbeam-ratio 0.0)
(def led-status-strip-type)
;runtime vars
(def led-current-brightness 0.0)
(def led-status-color '())
(def led-front-color '())
(def led-rear-color '())
(def next-run-time)
(def direction)
(def led-mall-grab)
(def prev-led-front-color '())
(def prev-led-rear-color '())
(def target-led-front-color '())
(def target-led-rear-color '())
(def combined-pins nil)
(def led-fix 1)
(def led-show-battery-charging 0)
(def led-front-highbeam-pin)
(def led-rear-highbeam-pin)
(def can-loss-fallback-timeout 10.0)
(def led-rendered-main-mode 0)
(def led-current-brightness-front 0.0)
(def led-current-brightness-rear 0.0)
(def led-current-front-color '())
(def led-current-rear-color '())
(def led-front-highbeam-active nil)
(def led-rear-highbeam-active nil)
(def led-target-debug-last 0)
(def led-init-fail-last 0)

(defunret led-color-u32 (c) {
    ; rgbled-color expects plain numeric args in this runtime.
    (if (eq c nil) {
        0
    } {
        (to-i c)
    })
})

(defun fix-nil-colors (colors) {
    ; Mutate the list in-place: replace nil entries with 0
    (if colors {
        (looprange i 0 (length colors) {
            (if (eq (ix colors i) nil) {
                (setix colors i 0)
            })
        })
    })
    colors
})

(defun rgbled-write-list (buf start colors brightness) {
    (fix-nil-colors colors)
    (var b (to-float brightness))
    (if (< b 0.0) (setq b 0.0))
    (if (> b 1.0) (setq b 1.0))
    (looprange i 0 (length colors) {
        (var c (led-color-u32 (ix colors i)))
        (if (< b 1.0) {
            (if (> b 0.0) {
                (setq c (color-scale c b))
                (setq c (led-color-u32 c))
            } {
                (setq c 0)
            })
        })
        ; Per-pixel write avoids firmware-specific list overload issues.
        (rgbled-color buf (+ start i) c)
    })
})

(defun rgbled-color-safe (buf start colors) {
    (rgbled-write-list buf start colors 1.0)
})

(defun rgbled-color-safe4 (buf start colors brightness) {
    (rgbled-write-list buf start colors brightness)
})
(defunret led-rgb-init-ok (pin) {
    (var init-r (trap (rgbled-init pin)))
    (if (eq (first init-r) 'exit-ok) {
        t
    } {
        (var now (secs-since 0))
        (if (>= (- now led-init-fail-last) 5.0) {
            (setq led-init-fail-last now)
            (print (str-merge "[led] rgbled-init fail pin=" (str-from-n pin "%d")))
        })
        nil
    })
})

(defun led-rgb-update-safe (buf) {
    (var update-r (trap (rgbled-update buf)))
    (if (eq (first update-r) 'exit-ok) {
        t
    } {
        nil
    })
})

(defunret led-active-target-id () {
    (if (= ucl-effective-role 0) {
        -1
    } {
        (can-local-id)
    })
})

(defunret led-target-matches-local (target-id local-target-id) {
    (if (= ucl-effective-role 0) {
        ; Master only runs strips targeted at SELF (-1).
        (= target-id -1)
    } {
        ; Slave only runs strips targeted at its own CAN-ID.
        (= target-id local-target-id)
    })
})

(defun load-led-settings () {
    (setq led-enabled (get-config 'led-enabled))
    (setq led-on (get-config 'led-on))
    (setq led-highbeam-on (get-config 'led-highbeam-on))
    (setq led-mode (get-config 'led-mode))
    (setq led-mode-idle (get-config 'led-mode-idle))
    (setq led-mode-status (get-config 'led-mode-status))
    (setq led-mall-grab-enabled (get-config 'led-mall-grab-enabled))
    (setq led-brake-light-enabled (get-config 'led-brake-light-enabled))
    (setq led-brake-light-min-amps (get-config 'led-brake-light-min-amps))
    (setq idle-timeout (get-config 'idle-timeout))
    (setq idle-timeout-shutoff (get-config 'idle-timeout-shutoff))
    (setq led-brightness (get-config 'led-brightness))
    (setq led-brightness-highbeam (get-config 'led-brightness-highbeam))
    (setq led-brightness-idle (get-config 'led-brightness-idle))
    (setq led-brightness-status (get-config 'led-brightness-status))
    (setq led-status-pin (get-config 'led-status-pin))
    (setq led-status-num (get-config 'led-status-num))
    (setq led-status-type (get-config 'led-status-type))
    (setq led-status-reversed (get-config 'led-status-reversed))
    (setq led-front-pin (get-config 'led-front-pin))
    (setq led-front-num (get-config 'led-front-num))
    (setq led-front-type (get-config 'led-front-type))
    (setq led-front-reversed (get-config 'led-front-reversed))
    (setq led-front-strip-type (get-config 'led-front-strip-type))
    (setq led-rear-pin (get-config 'led-rear-pin))
    (setq led-rear-num (get-config 'led-rear-num))
    (setq led-rear-type (get-config 'led-rear-type))
    (setq led-rear-reversed (get-config 'led-rear-reversed))
    (setq led-rear-strip-type (get-config 'led-rear-strip-type))
    (setq led-front-target-id (get-config 'front-target-id))
    (setq led-rear-target-id (get-config 'rear-target-id))
    (setq led-status-target-id (get-config 'status-target-id))
    (setq led-max-blend-count (get-config 'led-max-blend-count))
    (setq led-dim-on-highbeam-ratio (get-config 'led-dim-on-highbeam-ratio))
    (setq led-status-strip-type (get-config 'led-status-strip-type))
    (setq led-loop-delay (get-config 'led-loop-delay))
    (setq led-fix (get-config 'led-fix))
    (setq led-show-battery-charging (get-config 'led-show-battery-charging))
    (setq led-front-highbeam-pin (get-config 'led-front-highbeam-pin))
    (setq led-rear-highbeam-pin (get-config 'led-rear-highbeam-pin))
    (setq led-max-brightness (get-config 'led-max-brightness))
    (setq led-update-not-running (get-config 'led-update-not-running))

    ; GPIO0 on some Express boards can cause peripheral conflicts when driven as LED.
    ; Keep LEDs disabled on that pin unless user explicitly chooses a non-zero pin.
    (if (and (> led-status-strip-type 0) (= led-status-pin 0)) {
        (setq led-status-pin -1)
    })
    (if (and (> led-front-strip-type 0) (= led-front-pin 0)) {
        (setq led-front-pin -1)
    })
    (if (and (> led-rear-strip-type 0) (= led-rear-pin 0)) {
        (setq led-rear-pin -1)
    })

    ; Guard against corrupted/legacy config that can collapse patterns to 1 pixel.
    (if (and (> led-status-strip-type 0) (or (< led-status-num 1) (> led-status-num 300))) {
        (setq led-status-num 10)
    })
    (if (and (> led-front-strip-type 0) (or (<= led-front-num 1) (> led-front-num 300))) {
        (setq led-front-num 11)
    })
    (if (and (> led-rear-strip-type 0) (or (<= led-rear-num 1) (> led-rear-num 300))) {
        (setq led-rear-num 11)
    })
    (if (< led-max-blend-count 1) {
        (setq led-max-blend-count 1)
    })
})

(defun init-led-vars () {
    (def blend-count led-max-blend-count)
    (setq combined-pins nil)
    (setq led-current-brightness 0.0)
    (setq led-status-color (mklist led-status-num 0))
    (setq led-front-color (mklist led-front-num 0))
    (setq led-rear-color (mklist led-rear-num 0))
    (setq direction 1)
    (setq led-mall-grab 0)
    (setq prev-led-front-color (mklist led-front-num 0))
    (setq prev-led-rear-color (mklist led-rear-num 0))
    (setq target-led-front-color (mklist led-front-num 0))
    (setq target-led-rear-color (mklist led-rear-num 0))

    (if (and (= led-front-strip-type 7) (>= led-front-highbeam-pin 0)) {
        (pwm-start 1000 0.0 0 led-front-highbeam-pin 10)
    })

    (if (and (= led-rear-strip-type 7) (>= led-rear-highbeam-pin 0)) {
        (pwm-start 1000 0.0 1 led-rear-highbeam-pin 10)
    })

    (var front-highbeam-leds 0)
    (var rear-highbeam-leds 0)
    (if (or (= led-front-strip-type 2) (= led-front-strip-type 3) (= led-front-strip-type 8) (= led-front-strip-type 9) (= led-front-strip-type 10)) {
         (setq front-highbeam-leds (+ front-highbeam-leds 1))
    })
    (if (or (= led-rear-strip-type 2) (= led-rear-strip-type 3) (= led-rear-strip-type 8) (= led-rear-strip-type 9) (= led-rear-strip-type 10)) {
         (setq rear-highbeam-leds (+ rear-highbeam-leds 1))
    })
    (if (or (= led-front-strip-type 4) (= led-front-strip-type 5) (= led-front-strip-type 6) (= led-front-strip-type 11)) {
         (setq front-highbeam-leds (+ front-highbeam-leds 4))
    })
    (if (or (= led-rear-strip-type 4) (= led-rear-strip-type 5) (= led-rear-strip-type 6) (= led-rear-strip-type 11)) {
         (setq rear-highbeam-leds (+ rear-highbeam-leds 4))
    })

    (var local-target-id (led-active-target-id))
    (var status-target-active (led-target-matches-local led-status-target-id local-target-id))
    (var front-target-active (led-target-matches-local led-front-target-id local-target-id))
    (var rear-target-active (led-target-matches-local led-rear-target-id local-target-id))

    (if (and status-target-active
             front-target-active
             rear-target-active
             (> led-status-strip-type 0)
             (> led-front-strip-type 0)
             (> led-rear-strip-type 0)
             (>= led-front-pin 0)
             (= led-status-pin led-front-pin)
             (= led-front-pin led-rear-pin)) {
        (var total-leds (+ led-status-num led-front-num front-highbeam-leds led-rear-num rear-highbeam-leds))
        (setq led-combined-buffer (rgbled-buffer total-leds led-status-type))
        (setq combined-pins t)
    } {
        ; LED front/rear are on same pin for this node
        (if (and front-target-active
                 rear-target-active
                 (> led-front-strip-type 0)
                 (> led-rear-strip-type 0)
                 (>= led-front-pin 0)
                 (= led-front-pin led-rear-pin)) {
            (var total-leds (+ led-front-num front-highbeam-leds led-rear-num rear-highbeam-leds))
            (setq led-combined-buffer (rgbled-buffer total-leds led-front-type))
            (setq combined-pins t)
            (if (and status-target-active (> led-status-strip-type 0) (>= led-status-pin 0)) {
                (setq led-status-buffer (rgbled-buffer led-status-num led-status-type))
            })
        } {
            (if (and status-target-active
                     rear-target-active
                     (> led-status-strip-type 0)
                     (> led-rear-strip-type 0)
                     (>= led-status-pin 0)
                     (= led-status-pin led-rear-pin)) {
                (var total-leds (+ led-status-num led-rear-num rear-highbeam-leds))
                (setq led-combined-buffer (rgbled-buffer total-leds led-rear-type))
                (setq combined-pins t)
                (if (and front-target-active (> led-front-strip-type 0) (>= led-front-pin 0)) {
                    (setq led-front-buffer (rgbled-buffer (+ led-front-num front-highbeam-leds) led-front-type))
                })
            } {
                (if (and status-target-active
                         front-target-active
                         (> led-status-strip-type 0)
                         (> led-front-strip-type 0)
                         (>= led-status-pin 0)
                         (= led-status-pin led-front-pin)) {
                    (var total-leds (+ led-status-num led-front-num front-highbeam-leds))
                    (setq led-combined-buffer (rgbled-buffer total-leds led-status-type))
                    (setq combined-pins t)
                    (if (and rear-target-active (> led-rear-strip-type 0) (>= led-rear-pin 0)) {
                        (setq led-rear-buffer (rgbled-buffer (+ led-rear-num rear-highbeam-leds) led-rear-type))
                    })
                } {
                    ; LED strips are on separate pins for this node
                    (if (and status-target-active (> led-status-strip-type 0) (>= led-status-pin 0)) {
                        (setq led-status-buffer (rgbled-buffer led-status-num led-status-type))
                    })
                    (if (and rear-target-active (> led-rear-strip-type 0) (>= led-rear-pin 0)) {
                        (setq led-rear-buffer (rgbled-buffer (+ led-rear-num rear-highbeam-leds) led-rear-type))
                    })
                    (if (and front-target-active (> led-front-strip-type 0) (>= led-front-pin 0)) {
                        (setq led-front-buffer (rgbled-buffer (+ led-front-num front-highbeam-leds) led-front-type))
                    })
                })
            })
        })
    })
})

(defun led-loop () {
    ; Image restore can leave stale LED driver state; force a clean start.
    (rgbled-deinit)
    (load-led-settings)
    (init-led-vars)
    (setq led-heartbeat-time (secs-since 0))
    (var next-run-time (secs-since 0))
    (var loop-start-time 0)
    (var loop-end-time 0)
    (var led-loop-delay-sec (/ 1.0 led-loop-delay))
    (var prev-direction 1)
    (var direction-change-start-time 0)
    (var direction-change-window 0.5)
    (var anim-time 0)
    (var prev-run-state 0)
    (var led-run-start-time 0)
    (var mall-grab-press-start 0)
    (var mall-grab-press-active nil)
    (var led-role-snapshot ucl-effective-role)
    (loopwhile t {
        (setq led-heartbeat-time (secs-since 0))
        (setq loop-start-time (secs-since 0))
        (setq anim-time (+ anim-time led-loop-delay-sec))
        (if (> anim-time 100.0) (setq anim-time 0.0)) ; prevent overflow
		(if led-exit-flag {
			(setq led-exit-flag nil)   ; ACK to settings.lisp that we’re exiting
			(clear-leds)              ; optional but recommended: leave strip off/clean
			(break)
		})

        (if (not-eq ucl-effective-role led-role-snapshot) {
            (setq led-role-snapshot ucl-effective-role)
            (clear-leds)
            (rgbled-deinit)
            (if (and (= led-front-strip-type 7) (>= led-front-highbeam-pin 0)) (pwm-stop 0))
            (if (and (= led-rear-strip-type 7) (>= led-rear-highbeam-pin 0)) (pwm-stop 1))
            (load-led-settings)
            (init-led-vars)
            (setq led-loop-delay-sec (/ 1.0 led-loop-delay))
            (setq next-run-time (secs-since 0))
        })

        ; Keep local runtime off until first valid refloat LIGHTS_CONTROL frame.
        ; After that, can.lisp updates led-on/highbeam from refloat flags.
        (if (not refloat-lights-seen) {
            (setq led-on 0)
            (setq led-highbeam-on 0)
        })

        (var idle-rpm-darkride 100)
        (if (= state 4) ; RUNNING_UPSIDEDOWN
            (setq idle-rpm-darkride (* idle-rpm-darkride -1))
        )
        (if (!= state 3){;Ignore direction changes during wheelslip.
            (var current-direction direction)
            (if (> rpm idle-rpm-darkride) {;deadzone
                (setq current-direction 1)
            })
            (if (< rpm (* idle-rpm-darkride -1)) {
                (setq current-direction -1)
            })
            (if (!= current-direction prev-direction) {
                (if (= direction-change-start-time 0) {
                    ; Start the timer for a new potential direction change
                    (setq direction-change-start-time (systime))
                }{
                    ; Check if the timer has expired
                    (if (>= (secs-since direction-change-start-time) direction-change-window) {
                        ; Timer expired, commit the direction change
                        (setq direction current-direction)
                        (setq prev-direction current-direction)
                        (setq direction-change-start-time 0)
                    })
                })
            })
        })

        (if (and (not (running-state)) (> pitch-angle 70)) {
            (setq led-mall-grab (if (= led-mall-grab-enabled 1) 1 0))
            (if (= switch-state 3) {

                (if (not mall-grab-press-active) {
                    (setq mall-grab-press-start (systime))
                    (setq mall-grab-press-active t)
                })
            }{
                (if mall-grab-press-active {
                    (var press-duration (secs-since mall-grab-press-start))
                    (if (< press-duration 1) {
                        ;; Refloat authoritative: ignore local LED ON/OFF toggles.
                        nil
                    }{
                        ;; Refloat authoritative: ignore local HIGHBEAM toggles.
                        nil
                    })
            (setq mall-grab-press-active nil)
                })
            })
        }{
            (setq led-mall-grab 0)
            (setq mall-grab-press-active nil)
        })

        (if (or (running-state) (= led-mall-grab 1) (display-battery-charging)) {
            (setq led-last-activity-time (systime))
        }{
            (setq direction 1)
        })

        (if (running-state) {
            (if (= prev-run-state 0) {
                ;; Just transitioned from idle → running
                (setq led-run-start-time (systime))
            })
            (setq prev-run-state 1)
        }{
            (setq prev-run-state 0)
        })
        (var dont-freeze-update (not (and (running-state) (= led-update-not-running 1) (> (secs-since led-run-start-time) 1))))
        (update-leds (secs-since led-last-activity-time) anim-time)
        (led-flush-buffers dont-freeze-update)

        (setq loop-end-time (secs-since 0))
        (var actual-loop-time (- loop-end-time loop-start-time))

        (var time-to-wait (- next-run-time (secs-since 0)))
        (if (> time-to-wait 0) {

            (yield (* time-to-wait 1000000))
        } {
            (setq next-run-time (secs-since 0))
        })

        (setq next-run-time (+ next-run-time led-loop-delay-sec))
    })
    (clear-leds)
    (set-led-strip-color led-status-color 0x00)
    (led-flush-buffers t)
    (rgbled-deinit)
    (if (and (= led-front-strip-type 7) (>= led-front-highbeam-pin 0)) (pwm-stop 0))
    (if (and (= led-rear-strip-type 7) (>= led-rear-highbeam-pin 0)) (pwm-stop 1))
    (setq led-heartbeat-time 0.0)
    (setq led-exit-flag nil)
})

(defun reverse-led-strips () {
    (if (= led-status-reversed 1) {
        (setq led-status-color (reverse led-status-color))
    })
    (if (= led-front-reversed 1) {
        (setq led-front-color (reverse led-front-color))
    })
    (if (= led-rear-reversed 1) {
        (setq led-rear-color (reverse led-rear-color))
    })
})

(defun display-battery-charging () {
    ; Charging overlay is removed in the cutdown build.
    nil
})



(defunret led-main-mode-animated (mode) {
    (or (= mode 2) (= mode 3))
})

(defunret led-remap-gap-color (color-list next-ix brightness) {
    (var last-ix (- (length color-list) 1))
    (var left-ix (max 0 (- next-ix 1)))
    (var right-ix (min last-ix next-ix))
    (color-scale (color-mix
        (led-color-u32 (ix color-list left-ix))
        (led-color-u32 (ix color-list right-ix))
        0.5) brightness)
})

(defunret led-collapse-chain-color2 (seg-a active-a seg-b active-b) {
    (var out '())
    (if (= ucl-effective-role 0) {
        ; Master: preserve physical segment order on shared pin.
        (if active-a { (setq out (append out seg-a)) } { (setq out (append out (mklist (length seg-a) 0))) })
        (if active-b { (setq out (append out seg-b)) } { (setq out (append out (mklist (length seg-b) 0))) })
    } {
        ; Slave: compact active segments to the front so a single attached strip still renders.
        (var total-leds (+ (length seg-a) (length seg-b)))
        (if active-a { (setq out (append out seg-a)) })
        (if active-b { (setq out (append out seg-b)) })
        (if (< (length out) total-leds) {
            (setq out (append out (mklist (- total-leds (length out)) 0)))
        })
    })
    out
})

(defunret led-collapse-chain-color3 (seg-a active-a seg-b active-b seg-c active-c) {
    (var out '())
    (if (= ucl-effective-role 0) {
        ; Master: preserve physical segment order on shared pin.
        (if active-a { (setq out (append out seg-a)) } { (setq out (append out (mklist (length seg-a) 0))) })
        (if active-b { (setq out (append out seg-b)) } { (setq out (append out (mklist (length seg-b) 0))) })
        (if active-c { (setq out (append out seg-c)) } { (setq out (append out (mklist (length seg-c) 0))) })
    } {
        ; Slave: compact active segments to the front so a single attached strip still renders.
        (var total-leds (+ (length seg-a) (length seg-b) (length seg-c)))
        (if active-a { (setq out (append out seg-a)) })
        (if active-b { (setq out (append out seg-b)) })
        (if active-c { (setq out (append out seg-c)) })
        (if (< (length out) total-leds) {
            (setq out (append out (mklist (- total-leds (length out)) 0)))
        })
    })
    out
})

(defun led-write-chain-buffer (buf pin colors brightness) {
    (rgbled-color-safe4 buf 0 colors brightness)
    (if (led-rgb-init-ok pin) {
        (yield led-fix)
        (led-rgb-update-safe buf)
    })
})
(defun led-build-front-output (front-target-active led-dim-on-highbeam-brightness) {
    (var out-brightness led-current-brightness)
    (var out-color '())
    (var front-highbeam-on nil)
    (var front-color-highbeam 0x00)

    (if (and (= led-on 1) (= led-highbeam-on 1) (running-state) (!= state 5)
             front-target-active (>= direction 0)) {
        (setq front-color-highbeam 0xFF)
        (if (> led-dim-on-highbeam-brightness 0.0) {
            (setq out-brightness led-dim-on-highbeam-brightness)
        })
        (setq front-highbeam-on t)
    })

    (cond
        ((or (= led-front-strip-type 2) (= led-front-strip-type 3) (= led-front-strip-type 8) (= led-front-strip-type 9) (= led-front-strip-type 10)) {
            (if (and (<= led-dim-on-highbeam-brightness 0.0) (>= direction 0) (= led-on 1) (= led-highbeam-on 1) (running-state) (!= state 5)) {
                (setq out-color (append (list front-color-highbeam) (mklist led-front-num 0)))
            } {
                (setq out-color (append (list front-color-highbeam) (take led-front-color led-front-num)))
            })
        })
        ((or (= led-front-strip-type 4) (= led-front-strip-type 5) (= led-front-strip-type 6)) {
            (var led-tmp (take led-front-color (length led-front-color)))
            (setq out-color (mklist (+ (length led-front-color) 4) 0))
            (var led-tmp-index 0)
            (setq out-brightness (+ 0.6 (* (if (= led-front-strip-type 4) 0.2 0.4) out-brightness)))
            (looprange k 0 (length out-color) {
                (if (or (and (or (= led-front-strip-type 4) (= led-front-strip-type 5)) (or (= k 3) (= k 8) (= k 14) (= k 19)))
                        (and (= led-front-strip-type 6) (or (= k 1) (= k 4) (= k 10) (= k 13)))) {
                    (if (and (= led-rendered-main-mode 2) (not front-highbeam-on)) {
                        (setix out-color k (led-remap-gap-color led-tmp led-tmp-index out-brightness))
                    } {
                        (setix out-color k (color-scale front-color-highbeam out-brightness))
                    })
                } {
                    (if (and (<= led-dim-on-highbeam-brightness 0.0) (>= direction 0) (= led-on 1) (= led-highbeam-on 1) (running-state) (!= state 5)) {
                        (setix out-color k 0)
                    } {
                        (setix out-color k (color-scale (ix led-tmp led-tmp-index) out-brightness))
                    })
                    (setq led-tmp-index (+ led-tmp-index 1))
                })
            })
        })
        ((= led-front-strip-type 11) {
            (var led-tmp (take led-front-color (length led-front-color)))
            (setq out-color (mklist (+ (length led-front-color) 4) 0))
            (var led-tmp-index 0)
            (setq out-brightness (+ 0.4 (* 0.6 out-brightness)))
            (looprange k 0 (length out-color) {
                (if (or (= k 3) (= k 6) (= k 9) (= k 13)) {
                    (if (and (= led-rendered-main-mode 2) (not front-highbeam-on)) {
                        (setix out-color k (led-remap-gap-color led-tmp led-tmp-index out-brightness))
                    } {
                        (setix out-color k (color-scale front-color-highbeam out-brightness))
                    })
                } {
                    (if (and (<= led-dim-on-highbeam-brightness 0.0) (>= direction 0) (= led-on 1) (= led-highbeam-on 1) (running-state) (!= state 5)) {
                        (setix out-color k 0)
                    } {
                        (setix out-color k (color-scale (ix led-tmp led-tmp-index) out-brightness))
                    })
                    (setq led-tmp-index (+ led-tmp-index 1))
                })
            })
        })
        ((and (= led-front-strip-type 7) (>= led-front-highbeam-pin 0)) {
            (if front-highbeam-on {
                (pwm-set-duty (min led-brightness-highbeam led-max-brightness) 0)
                (setq out-brightness led-dim-on-highbeam-brightness)
            } {
                (pwm-set-duty 0.0 0)
                (setq out-brightness led-current-brightness)
            })
            (setq out-color led-front-color)
        })
        (_ {
            (setq out-color led-front-color)
            (setq out-brightness led-current-brightness)
        })
    )

    (if (not front-target-active) {
        (set-led-strip-color out-color 0x00)
        (setq out-brightness 0.0)
        (if (and (= led-front-strip-type 7) (>= led-front-highbeam-pin 0)) {
            (pwm-set-duty 0.0 0)
        })
    })

    (setq led-current-front-color out-color)
    (setq led-current-brightness-front out-brightness)
    (setq led-front-highbeam-active front-highbeam-on)
})

(defun led-build-rear-output (rear-target-active led-dim-on-highbeam-brightness) {
    (var out-brightness led-current-brightness)
    (var out-color '())
    (var rear-highbeam-on nil)
    (var rear-color-highbeam 0x00)

    (if (and (= led-on 1) (= led-highbeam-on 1) (running-state) (!= state 5)
             rear-target-active (< direction 0)) {
        (setq rear-color-highbeam 0xFF)
        (if (> led-dim-on-highbeam-brightness 0.0) {
            (setq out-brightness led-dim-on-highbeam-brightness)
        })
        (setq rear-highbeam-on t)
    })

    (cond
        ((or (= led-rear-strip-type 2) (= led-rear-strip-type 3) (= led-rear-strip-type 8) (= led-rear-strip-type 9) (= led-rear-strip-type 10)) {
            (if (and (<= led-dim-on-highbeam-brightness 0.0) (< direction 0) (= led-on 1) (= led-highbeam-on 1) (running-state) (!= state 5)) {
                (setq out-color (append (list rear-color-highbeam) (mklist led-rear-num 0)))
            } {
                (setq out-color (append (list rear-color-highbeam) (take led-rear-color led-rear-num)))
            })
        })
        ((or (= led-rear-strip-type 4) (= led-rear-strip-type 5) (= led-rear-strip-type 6)) {
            (var led-tmp (take led-rear-color (length led-rear-color)))
            (setq out-color (mklist (+ (length led-rear-color) 4) 0))
            (var led-tmp-index 0)
            (setq out-brightness (+ 0.6 (* (if (= led-rear-strip-type 4) 0.2 0.4) out-brightness)))
            (looprange k 0 (length out-color) {
                (if (or (and (or (= led-rear-strip-type 4) (= led-rear-strip-type 5)) (or (= k 3) (= k 8) (= k 14) (= k 19)))
                        (and (= led-rear-strip-type 6) (or (= k 1) (= k 4) (= k 10) (= k 13)))) {
                    (if (and (= led-rendered-main-mode 2) (not rear-highbeam-on)) {
                        (setix out-color k (led-remap-gap-color led-tmp led-tmp-index out-brightness))
                    } {
                        (setix out-color k (color-scale rear-color-highbeam out-brightness))
                    })
                } {
                    (if (and (<= led-dim-on-highbeam-brightness 0.0) (< direction 0) (= led-on 1) (= led-highbeam-on 1) (running-state) (!= state 5)) {
                        (setix out-color k 0)
                    } {
                        (setix out-color k (color-scale (ix led-tmp led-tmp-index) out-brightness))
                    })
                    (setq led-tmp-index (+ led-tmp-index 1))
                })
            })
        })
        ((= led-rear-strip-type 11) {
            (var led-tmp (take led-rear-color (length led-rear-color)))
            (setq out-color (mklist (+ (length led-rear-color) 4) 0))
            (var led-tmp-index 0)
            (setq out-brightness (+ 0.4 (* 0.6 out-brightness)))
            (looprange k 0 (length out-color) {
                (if (or (= k 3) (= k 6) (= k 9) (= k 13)) {
                    (if (and (= led-rendered-main-mode 2) (not rear-highbeam-on)) {
                        (setix out-color k (led-remap-gap-color led-tmp led-tmp-index out-brightness))
                    } {
                        (setix out-color k (color-scale rear-color-highbeam out-brightness))
                    })
                } {
                    (if (and (<= led-dim-on-highbeam-brightness 0.0) (< direction 0) (= led-on 1) (= led-highbeam-on 1) (running-state) (!= state 5)) {
                        (setix out-color k 0)
                    } {
                        (setix out-color k (color-scale (ix led-tmp led-tmp-index) out-brightness))
                    })
                    (setq led-tmp-index (+ led-tmp-index 1))
                })
            })
        })
        ((and (= led-rear-strip-type 7) (>= led-rear-highbeam-pin 0)) {
            (if rear-highbeam-on {
                (pwm-set-duty (min led-brightness-highbeam led-max-brightness) 1)
                (setq out-brightness led-dim-on-highbeam-brightness)
            } {
                (pwm-set-duty 0.0 1)
                (setq out-brightness led-current-brightness)
            })
            (setq out-color led-rear-color)
        })
        (_ {
            (setq out-color led-rear-color)
            (setq out-brightness led-current-brightness)
        })
    )

    (if (not rear-target-active) {
        (set-led-strip-color out-color 0x00)
        (setq out-brightness 0.0)
        (if (and (= led-rear-strip-type 7) (>= led-rear-highbeam-pin 0)) {
            (pwm-set-duty 0.0 1)
        })
    })

    (setq led-current-rear-color out-color)
    (setq led-current-brightness-rear out-brightness)
    (setq led-rear-highbeam-active rear-highbeam-on)
})

(defun led-flush-buffers (dont-freeze-update) {
    (reverse-led-strips)
    (var local-target-id (led-active-target-id))
    (var status-target-active (led-target-matches-local led-status-target-id local-target-id))
    (var front-target-active (led-target-matches-local led-front-target-id local-target-id))
    (var rear-target-active (led-target-matches-local led-rear-target-id local-target-id))
    (var led-dim-on-highbeam-brightness (* led-current-brightness led-dim-on-highbeam-ratio))

    (led-build-front-output front-target-active led-dim-on-highbeam-brightness)
    (led-build-rear-output rear-target-active led-dim-on-highbeam-brightness)

    (if (not status-target-active) {
        (set-led-strip-color led-status-color 0x00)
    })

    (if (and status-target-active front-target-active rear-target-active
             (> led-status-strip-type 0) (> led-front-strip-type 0) (> led-rear-strip-type 0)
             (>= led-front-pin 0) (= led-status-pin led-front-pin) (= led-front-pin led-rear-pin)) {
        (led-write-chain-buffer led-combined-buffer led-front-pin
            (led-collapse-chain-color3 led-status-color status-target-active
                                      led-current-front-color front-target-active
                                      led-current-rear-color rear-target-active)
            led-current-brightness)
    } {
        (if (and front-target-active rear-target-active
                 (> led-front-strip-type 0) (> led-rear-strip-type 0)
                 (>= led-front-pin 0) (= led-front-pin led-rear-pin)) {
            (led-write-chain-buffer led-combined-buffer led-front-pin
                (led-collapse-chain-color2 led-current-front-color front-target-active
                                          led-current-rear-color rear-target-active)
                led-current-brightness)
            (if (and status-target-active (> led-status-strip-type 0) (>= led-status-pin 0)) {
                (rgbled-color-safe4 led-status-buffer 0 led-status-color (min led-brightness-status led-max-brightness))
                (if (led-rgb-init-ok led-status-pin) {
                    (yield led-fix)
                    (led-rgb-update-safe led-status-buffer)
                })
            })
        } {
            (if (and status-target-active rear-target-active
                     (> led-status-strip-type 0) (> led-rear-strip-type 0)
                     (>= led-status-pin 0) (= led-status-pin led-rear-pin)) {
                (if (!= led-status-type led-rear-type) {
                    (swap-rg led-status-color)
                })
                (led-write-chain-buffer led-combined-buffer led-status-pin
                    (led-collapse-chain-color2 led-status-color status-target-active
                                              led-current-rear-color rear-target-active)
                    led-current-brightness)
                (if (and front-target-active (> led-front-strip-type 0) (>= led-front-pin 0) dont-freeze-update) {
                    (if (or (= led-front-strip-type 4) (= led-front-strip-type 5) (= led-front-strip-type 6) (= led-front-strip-type 11)) {
                        (rgbled-color-safe led-front-buffer 0 led-current-front-color)
                    } {
                        (rgbled-color-safe4 led-front-buffer 0 led-current-front-color led-current-brightness-front)
                    })
                    (if (led-rgb-init-ok led-front-pin) {
                        (yield led-fix)
                        (led-rgb-update-safe led-front-buffer)
                    })
                })
            } {
                (if (and status-target-active front-target-active
                         (> led-status-strip-type 0) (> led-front-strip-type 0)
                         (>= led-status-pin 0) (= led-status-pin led-front-pin)) {
                    (if (!= led-status-type led-front-type) {
                        (swap-rg led-status-color)
                    })
                    (led-write-chain-buffer led-combined-buffer led-status-pin
                        (led-collapse-chain-color2 led-status-color status-target-active
                                                  led-current-front-color front-target-active)
                        led-current-brightness)
                    (if (and rear-target-active (> led-rear-strip-type 0) (>= led-rear-pin 0) dont-freeze-update) {
                        (if (or (= led-rear-strip-type 4) (= led-rear-strip-type 5) (= led-rear-strip-type 6) (= led-rear-strip-type 11)) {
                            (rgbled-color-safe led-rear-buffer 0 led-current-rear-color)
                        } {
                            (rgbled-color-safe4 led-rear-buffer 0 led-current-rear-color led-current-brightness-rear)
                        })
                        (if (led-rgb-init-ok led-rear-pin) {
                            (yield led-fix)
                            (if (not (led-rgb-update-safe led-rear-buffer)) {
                                (if (= ucl-effective-role 1) {
                                    (print (str-merge "[led] rear update fail pin=" (str-from-n led-rear-pin "%d")))
                                })
                            })
                        } {
                            (if (= ucl-effective-role 1) {
                                (print (str-merge "[led] rear init fail pin=" (str-from-n led-rear-pin "%d")))
                            })
                        })
                    })
                } {
                    (if (and status-target-active (> led-status-strip-type 0) (>= led-status-pin 0)) {
                        (rgbled-color-safe4 led-status-buffer 0 led-status-color (min led-brightness-status led-max-brightness))
                        (if (led-rgb-init-ok led-status-pin) {
                            (yield led-fix)
                            (led-rgb-update-safe led-status-buffer)
                        })
                    })
                    (if (and rear-target-active (> led-rear-strip-type 0) (>= led-rear-pin 0) dont-freeze-update) {
                        (if (or (= led-rear-strip-type 4) (= led-rear-strip-type 5) (= led-rear-strip-type 6) (= led-rear-strip-type 11)) {
                            (rgbled-color-safe led-rear-buffer 0 led-current-rear-color)
                        } {
                            (rgbled-color-safe4 led-rear-buffer 0 led-current-rear-color led-current-brightness-rear)
                        })
                        (if (led-rgb-init-ok led-rear-pin) {
                            (yield led-fix)
                            (if (not (led-rgb-update-safe led-rear-buffer)) {
                                (if (= ucl-effective-role 1) {
                                    (print (str-merge "[led] rear update fail pin=" (str-from-n led-rear-pin "%d")))
                                })
                            })
                        } {
                            (if (= ucl-effective-role 1) {
                                (print (str-merge "[led] rear init fail pin=" (str-from-n led-rear-pin "%d")))
                            })
                        })
                    })
                    (if (and front-target-active (> led-front-strip-type 0) (>= led-front-pin 0) dont-freeze-update) {
                        (if (or (= led-front-strip-type 4) (= led-front-strip-type 5) (= led-front-strip-type 6) (= led-front-strip-type 11)) {
                            (rgbled-color-safe led-front-buffer 0 led-current-front-color)
                        } {
                            (rgbled-color-safe4 led-front-buffer 0 led-current-front-color led-current-brightness-front)
                        })
                        (if (led-rgb-init-ok led-front-pin) {
                            (yield led-fix)
                            (led-rgb-update-safe led-front-buffer)
                        })
                    })
                })
            })
        })
    })
})

(defun update-status-leds (can-last-activity-time-sec anim-time) {
    (if (or (= state 15) handtest-mode (>= can-last-activity-time-sec 1) (< can-id 0)) {
        (cond
            (handtest-mode {
                (led-handtest led-status-color switch-state 1 anim-time led-mode-status)
            })
            ((= state 15) {
                (led-float-disabled led-status-color)
            })
            ((>= can-last-activity-time-sec 1) {
                (led-connecting led-status-color anim-time)
            })
        )
    }{
        (if (> rpm 250.0){
            (if (> sat-t 2) {
                (strobe-pattern led-status-color 0x00FF0000 anim-time)
            }{
                (duty-cycle-pattern led-status-color)
            })
        }{
            (if (and (!= switch-state 1) (!= switch-state 2) (!= switch-state 3)){
                ;(if (display-battery-charging) { TODO
                ;    ;Do something
                ;}{
                    (battery-pattern led-status-color nil anim-time)
                ;})
            }{
				(led-handtest led-status-color switch-state 1 anim-time led-mode-status)
            })
        })
    })
})

(defun led-render-main-mode (current-led-mode last-activity-sec can-last-activity-time-sec anim-time) {
    (if (= led-on 1) {
        (if (and (> (length led-front-color) 0) (> (length led-rear-color) 0)) {
            (cond
                ((= state 15) {
                    (clear-leds)
                    (led-float-disabled led-rear-color)
                    (led-float-disabled led-front-color)
                })
                (handtest-mode {
                    (led-handtest led-front-color switch-state 2 anim-time led-mode-status)
                    (led-handtest led-rear-color switch-state 2 anim-time led-mode-status)
                })
                ((and (> last-activity-sec idle-timeout-shutoff) (< can-last-activity-time-sec 1) (!= state 5)) {
                    ; make sure we do not clear if we lose can bus
                    (clear-leds)
                })
                ((and (or (= current-led-mode 1) (= led-mall-grab 1)) (< can-last-activity-time-sec 1)) {
                    (battery-pattern led-front-color nil anim-time)
                    (battery-pattern led-rear-color nil anim-time)
                })
                ((or (= current-led-mode 0)
                     (and (> can-last-activity-time-sec can-loss-fallback-timeout)
                          (running-state))
                     (and (running-state) (= led-update-not-running 1))) {
                    ; Keep white as explicit RGB value to avoid signed-color edge cases.
                    (set-led-strip-color (if (> direction 0) led-front-color led-rear-color) 0x00FFFFFF)
                    (set-led-strip-color (if (< direction 0) led-front-color led-rear-color) 0x00FF0000)
                })
                ((= current-led-mode 2) {
                    (setq led-rendered-main-mode 2)
                    (cylon-pattern-strip led-front-color anim-time led-front-strip-type)
                    (cylon-pattern-strip led-rear-color anim-time led-rear-strip-type)
                })
                ((= current-led-mode 3) {
                    (setq led-rendered-main-mode 3)
                    (rainbow-pattern led-front-color anim-time)
                    (rainbow-pattern led-rear-color anim-time)
                })
            )

            (if (and (= led-brake-light-enabled 1)
                     (running-state)
                     (!= state 5)
                     (<= tot-current led-brake-light-min-amps)
                     (= led-update-not-running 0)) {
                (strobe-pattern (if (>= direction 0) led-rear-color led-front-color) 0x00FF0000 anim-time)
            })

            (if (and (< can-last-activity-time-sec 1.0) (display-battery-charging)) {
                (battery-pattern led-front-color nil anim-time)
                (battery-pattern led-rear-color nil anim-time)
            })
        })
    } {
        (clear-leds)
    })
})

(defun update-leds (last-activity-sec anim-time) {
    (var can-last-activity-time-sec (secs-since can-last-activity-time))
    (var local-target-id (led-active-target-id))
    (var status-target-active (led-target-matches-local led-status-target-id local-target-id))
    (var front-target-active (led-target-matches-local led-front-target-id local-target-id))
    (var rear-target-active (led-target-matches-local led-rear-target-id local-target-id))
    (if (and (> led-status-strip-type 0) (> (length led-status-color) 0)) {
        (if (and status-target-active (or (= led-mode-status 0) (= led-mode-status 1))) {
            (update-status-leds can-last-activity-time-sec anim-time)
        } {
            (set-led-strip-color led-status-color 0x00)
        })
    })
    (var current-led-mode led-mode-idle)
    (setq led-current-brightness (min led-brightness led-brightness led-max-brightness))
    (if (= led-mall-grab 1) {
        (setq led-current-brightness (min led-brightness-status led-max-brightness))
    })
    (if (running-state) {
        (setq current-led-mode led-mode)
    })

    (if (or (and (>= last-activity-sec idle-timeout) (<= can-last-activity-time-sec 1))
            (= state 5)
            (not (running-state))) {
        (setq current-led-mode led-mode-idle)
        (setq led-current-brightness (min led-brightness-idle led-max-brightness))
    })
    (setq led-rendered-main-mode 0)
    (var blend-limit (if (led-main-mode-animated current-led-mode) 1.0 led-max-blend-count))
    (var blend-ratio (min 1.0 (/ blend-count blend-limit)))
    (looprange i 0 (length led-front-color) {
        (setix led-front-color i (color-mix
            (led-color-u32 (ix prev-led-front-color i))
            (led-color-u32 (ix target-led-front-color i))
            blend-ratio))
    })
    (looprange i 0 (length led-rear-color) {
        (setix led-rear-color i (color-mix
            (led-color-u32 (ix prev-led-rear-color i))
            (led-color-u32 (ix target-led-rear-color i))
            blend-ratio))
    })
    (if (not front-target-active) {
        (set-led-strip-color led-front-color 0x00)
    })
    (if (not rear-target-active) {
        (set-led-strip-color led-rear-color 0x00)
    })
    (setq blend-count (+ blend-count 1.0))

    (if (> blend-count blend-limit) {
        (setq prev-led-front-color (take target-led-front-color (length target-led-front-color)))
        (setq prev-led-rear-color (take target-led-rear-color (length target-led-rear-color)))
        (led-render-main-mode current-led-mode last-activity-sec can-last-activity-time-sec anim-time)

        (if (not front-target-active) {
            (set-led-strip-color led-front-color 0x00)
        })
        (if (not rear-target-active) {
            (set-led-strip-color led-rear-color 0x00)
        })

        (setq target-led-front-color (take led-front-color (length led-front-color)))
        (setq target-led-rear-color (take led-rear-color (length led-rear-color)))
        (setq blend-count 1.0)

        (var next-blend-ratio (if (> blend-count 0) (min 1.0 (/ blend-count blend-limit)) 0.0))
        (looprange i 0 (length led-front-color) {
            (setix led-front-color i (color-mix
                (led-color-u32 (ix prev-led-front-color i))
                (led-color-u32 (ix target-led-front-color i))
                next-blend-ratio))
        })
        (looprange i 0 (length led-rear-color) {
            (setix led-rear-color i (color-mix
                (led-color-u32 (ix prev-led-rear-color i))
                (led-color-u32 (ix target-led-rear-color i))
                next-blend-ratio))
        })
    })
})
(defun clear-leds () {
    (set-led-strip-color led-front-color 0x00)
    (set-led-strip-color led-rear-color 0x00)
    (if (and (= led-front-strip-type 7) (>= led-front-highbeam-pin 0)) (pwm-set-duty 0.0 0))
    (if (and (= led-rear-strip-type 7) (>= led-rear-highbeam-pin 0)) (pwm-set-duty 0.0 1))
})
@const-end
