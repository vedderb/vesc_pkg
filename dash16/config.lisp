@const-start

(def config-can-id-esc (list 116 117)) ; A list of one or many ESC can-ids

(def config-metric-speeds true)
(def config-metric-temps true)

(def config-gnss-use-speed false) ; Prefer GPS speed over ESC speed

(def config-boot-animation-enable false) ; Enable VESC logo animation
(def config-code-server true) ; Enable remote code execution

(def config-battery-hot 55.0) ; Displays warning indicator, Degrees C
(def config-esc-hot 80.0) ; Degrees C
(def config-motor-hot 80.0) ; Displays warning indicator, Degrees C

; Current limits for animation above speed dial
(def config-curr-accel 80.0)
(def config-curr-brake 60.0)

; Sent with the mode profile when running without dash_esc. The display has no
; way to read what the controller currently uses for these, so non-limiting
; values are sent rather than a guess that could quietly cap the bike.
(def config-sa-duty-min 0.005)
(def config-sa-duty-max 0.95)
(def config-sa-watt-min -1500000.0)
(def config-sa-watt-max 1500000.0)

; Backlight levels
(def bl-lvl-bright 1.0)
(def bl-lvl-dim 0.2)

; Default light state
(def light-on-default false)

; Light-on means high beam, low beam otherwise
(def light-on-is-highbeam false)
