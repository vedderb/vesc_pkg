;@const-symbol-strings

@const-start
(def rainbow-colors '(0x00FF0000 0x00FFFF00 0x0000FF00 0x0000FFFF 0x000000FF 0x00FF00FF))

(defun led-float-disabled (color-list) {
    (var led-num (length color-list))
    (var lit-width (floor (/ led-num 1.8)))
    (if (!= (mod led-num 2.0) (mod lit-width 2.0)) {
        (setq lit-width (- lit-width 1))
    })
    (var unlit-gutter (floor (/ (- led-num lit-width) 2.0)))
    (var start unlit-gutter)
    (var end (+ start lit-width))
    ; Single loop for LEDs
    (looprange i 0 led-num {
        (if (and (>= i start) (< i end)) {
            (if (or (= i start) (= i (- end 1))) {
                (setix color-list i 0x007F0000)  ; Dimmed red for first and last
            }{
                (setix color-list i 0x00FF0000)  ; Full red for center
            })
        }{
            (setix color-list i 0x00000000)  ; Black for outer LEDs
        })
    })
})

(defun led-handtest (color-list switch-state switch-led-count time led-mode-status) {
    (var led-num (length color-list))
    (var left-color  (if (or (= switch-state 1) (= switch-state 3)) 0xFF 0x00))
    (var right-color (if (or (= switch-state 2) (= switch-state 3)) 0xFF 0x00))

    (if (!= led-mode-status 0) {
        (var tmp left-color)
        (setq left-color right-color)
        (setq right-color tmp)
    })

    (var pulse-speed 0.5)
    (var pulse-index (floor (mod (* time 255 pulse-speed) 255)))
    (var center-color (color-make 255 pulse-index 0))

    (looprange i 0 led-num {
        (cond
            ((< i switch-led-count)
                (setix color-list i left-color)
            )
            ((>= i (- led-num switch-led-count))
                (setix color-list i right-color)
            )
            ((or (= i switch-led-count) (= i (- led-num switch-led-count 1)))
                (setix color-list i 0)
            )
            ((and (> i switch-led-count) (< i (- led-num switch-led-count 1)))
                (setix color-list i center-color)
            )
        )
    })
})

(defun led-connecting (color-list time) {
    (var led-num (length color-list))
    (var speed 4.0)
    (var index (floor (mod (* time speed) (+ led-num 1))))
    (looprange i 0 led-num {
        (if (< i index)
            (setix color-list i (color-make 255 0 0))
            (setix color-list i 0)
        )
    })
})

(defun cylon-pattern-strip (color-list time strip-type) {
    (var n (length color-list))

    (if (> n 0) {
        (var span (- n 1))
        (if (< span 1) {
            (setix color-list 0 0x00FF0000)
        } {
            ; 2003 BSG style: narrow red scanner with a visible trailing smear.
            ; Use cosine easing so the eye naturally dwells at the ends instead
            ; of hard-reversing.
            (var sweep-rate 3.2)
            (var raw-phase (mod (* time sweep-rate) 2.0))
            (var scan-phase raw-phase)
            (var dir 1.0)
            (if (> scan-phase 1.0) {
                (setq scan-phase (- 2.0 scan-phase))
                (setq dir -1.0)
            })

            (var eased-phase (* 0.5 (- 1.0 (cos (* scan-phase 3.14159265)))))
            (var x (* eased-phase span))

            (var core-width 0.72)
            (var tail-len 2.3)
            (var tail-gain 0.46)
            (var lead-len 0.65)
            (var lead-gain 0.16)

            ; JetFleet H4 / GT / GTFO style remaps insert extra physical slots in
            ; led-flush-buffers. Tighten the core slightly and lengthen the smear
            ; so the scan still reads as one visor instead of isolated pixels.
            (if (or (= strip-type 4) (= strip-type 5) (= strip-type 6) (= strip-type 11)) {
                (setq core-width 0.82)
                (setq tail-len 2.8)
                (setq tail-gain 0.52)
                (setq lead-len 0.85)
            })

            (looprange i 0 n {
                (var d (- (to-float i) x))
                (var core (max 0.0 (- 1.0 (/ (abs d) core-width))))

                (var behind (if (> dir 0.0) (<= d 0.0) (>= d 0.0)))
                (var smear 0.0)
                (if behind {
                    (var td (abs d))
                    (setq smear (max 0.0 (- 1.0 (/ td tail-len))))
                    (setq smear (* smear smear))
                    (setq smear (* tail-gain smear))
                } {
                    (var ld (abs d))
                    (setq smear (max 0.0 (- 1.0 (/ ld lead-len))))
                    (setq smear (* lead-gain smear smear))
                })

                (var k (max core smear))
                (if (> k 1.0) (setq k 1.0))
                (var r8 (to-i (floor (* k 255.0))))
                (setix color-list i (shl r8 16))
            })
        })
    })
})

(defun cylon-pattern (color-list time) {
    (cylon-pattern-strip color-list time 0)
})

(defun battery-pattern (color-list charging time) {
    (var led-num (length color-list))
    (var soc battery-percent-remaining)
    (if (> refloat-batt-voltage 0.0) {
        (setq soc (/ (estimate-soc (/ refloat-batt-voltage (to-float series-cells)) voltage-curve) 100.0))
    })
    (if (< soc 0.0) (setq soc 0.0))
    (if (> soc 1.0) (setq soc 1.0))
    (var num-lit-leds (round (* led-num soc)))

    ; Optional pulse factor if charging
    (var pulse-factor (if charging
       (+ 0.55 (* 0.45 (cos (* time 3.14159)))) ; Pulses between 0.0 and 1.0
        1.0))

    (looprange led-index 0 led-num {
        (var color
            (if (or (< led-index num-lit-leds)
                   (and (= led-index 0) (<= num-lit-leds 1))) {
                ; LED should be lit
                (if (or (< soc 0.2)
                       (and (= led-index 0) (<= num-lit-leds 1))) {
                    ; Low battery - red color
                    (color-make (floor (* 255 pulse-factor)) 0 0)
                } {
                    ; Normal battery - gradient from green to yellow to red
                    (let ((red-ratio (- 1 (/ soc 0.8)))
                          (green-ratio (/ soc 0.8))) {
                        (color-make
                            (floor (* 255 red-ratio pulse-factor))
                            (floor (* 255 green-ratio pulse-factor))
                            0)
                    })
                })
            } {
                ; LED should be off
                (color-make 0 0 0)
            }))
        (setix color-list led-index color)
    })
})

(defun rainbow-pattern (color-list time) {
    (var num-leds (length color-list))
    (var speed 0.5)         ; scroll speed
    (var rainbows 1.0)      ; how many rainbows fit on the strip
    (var base-hue (* time speed)) ; how fast it scrolls
    (var per-pixel-offset (/ rainbows num-leds))
    (looprange i 0 num-leds {
        (var hue (mod (+ base-hue (* i per-pixel-offset)) 1.0))
        (setix color-list i (hue-to-color hue))
    })
})

(defun hue-to-color (hue) {
    ; hue: 0.0 .. 1.0 (wraps)
    ; returns packed 0x00RRGGBB

    (var hh (mod hue 1.0))
    (var h (* hh 6.0))
    (var i (to-i32 (floor h)))
    (var f (- h (to-float i)))

    (var r 0.0)
    (var g 0.0)
    (var b 0.0)

    (if (= i 0) {
        (setq r 1.0) (setq g f)         (setq b 0.0)
    }{
        (if (= i 1) {
            (setq r (- 1.0 f)) (setq g 1.0) (setq b 0.0)
        }{
            (if (= i 2) {
                (setq r 0.0) (setq g 1.0) (setq b f)
            }{
                (if (= i 3) {
                    (setq r 0.0) (setq g (- 1.0 f)) (setq b 1.0)
                }{
                    (if (= i 4) {
                        (setq r f) (setq g 0.0) (setq b 1.0)
                    }{
                        ; i = 5
                        (setq r 1.0) (setq g 0.0) (setq b (- 1.0 f))
                    })
                })
            })
        })
    })

    (var r8 (to-i (floor (* r 255.0))))
    (var g8 (to-i (floor (* g 255.0))))
    (var b8 (to-i (floor (* b 255.0))))

    (+ (shl r8 16) (shl g8 8) b8)
})

(defun duty-cycle-pattern (color-list) {
    (var scaled-duty-cycle (* (abs duty-cycle-now) 1.1112))
    (var clamped-duty-cycle 0.0)

    (if (< scaled-duty-cycle 1.0) {
        (setq clamped-duty-cycle scaled-duty-cycle)
    } {
        (setq clamped-duty-cycle 1.0)
    })
    (var led-num (length color-list))
    (var duty-leds (floor (* clamped-duty-cycle led-num)))

    (var duty-color 0x00FFFF00)

    (if (> (abs duty-cycle-now) 0.85) {
        (setq duty-color 0x00FF0000)
    } {
        (if (> (abs duty-cycle-now) 0.7) {
            (setq duty-color 0x00FF8800)
        })
    })

    (looprange led-index 0 led-num {
        (setix color-list led-index (if (< led-index duty-leds) duty-color 0x00000000))
    })
})

(defun strobe-pattern (color-list color time) {
    (var freq 5.0) ; flashes per second
    (var phase (mod (floor (* time freq)) 2)) ; toggle 0/1
    (var led-color (if (= phase 0) color 0x00000000))
    (set-led-strip-color color-list led-color)
})

(defun set-led-strip-color (color-list color) {
    (var c (if (eq color nil) 0 (to-i color)))
    (looprange led-index 0 (length color-list) {
        (setix color-list led-index c)
    })
})
@const-end
