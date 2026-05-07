@const-start

(def config-can-id-esc (list 116 117)) ; A list of one or many ESC can-ids

(def config-metric-speeds true)
(def config-metric-temps true)

(def config-gnss-use-speed false) ; Prefer GPS speed over ESC speed
(def config-utc-offset-sec (to-i (* 60 60 2.0))) ; CST is -21600 seconds

(def config-boot-animation-enable false) ; Enable VESC logo animation
(def config-code-server true) ; Enable remote code execution
(def config-units-switching-enable false) ; Eable UNITS menu option and button
(def config-profiles-enable false) ; Enable profile selection and editing

(def config-battery-hot 55.0) ; Displays warning indicator, Degrees C
(def config-esc-hot 80.0) ; Degrees C
(def config-motor-hot 80.0) ; Displays warning indicator, Degrees C

; Current limits for animation above speed dial
(def config-curr-accel 80.0)
(def config-curr-brake 60.0)

; Backlight levels
(def bl-lvl-bright 5)
(def bl-lvl-dim 1)

; Default light state
(def light-on-default false)

; Light-on means high beam, low beam otherwise
(def light-on-is-highbeam false)
