;@const-symbol-strings

@const-start

; LED state. Rendering is done by the espled_strip native lib; this module
; only keeps the configuration cache and the state-machine variables the
; LED loop uses to drive it.

; espled effect / palette / type / timing / turn-mode ids are defined once in
; the espled_strip library (../lib_espled_strip/espled_defs.lisp) and imported
; by float_accessories.lisp before this module, so they cannot drift from the
; lib's C enums.

(def led-loop-delay)
;config vars
(def led-enabled)
(def led-mode)
(def led-mode-idle)
(def led-mode-status)
(def led-mode-startup)
(def led-mode-button)
(def led-mode-footpad)
(def led-mall-grab-enabled)
(def led-brake-light-enabled)
(def led-brake-light-min-amps)
(def idle-timeout)
(def idle-timeout-shutoff)
(def led-status-pin)
(def led-status-num)
(def led-status-type)
(def led-status-reversed)
(def led-status-timing)
(def led-front-pin)
(def led-front-num)
(def led-front-type)
(def led-front-reversed)
(def led-front-timing)
(def led-front-highbeam-mode)
(def led-front-highbeam-pos)
(def led-front-highbeam-min)
(def led-front-highbeam-max)
(def led-rear-pin)
(def led-rear-num)
(def led-rear-type)
(def led-rear-reversed)
(def led-rear-timing)
(def led-rear-highbeam-mode)
(def led-rear-highbeam-pos)
(def led-rear-highbeam-min)
(def led-rear-highbeam-max)
(def led-button-pin)
(def led-button-timing)
(def led-footpad-pin)
(def led-footpad-num)
(def led-footpad-type)
(def led-footpad-reversed)
(def led-footpad-timing)
(def led-startup-timeout)
(def led-dim-on-highbeam-ratio 0.0)
(def led-max-brightness)
(def led-update-not-running)
(def led-show-battery-charging 0)
(def led-front-highbeam-pin)
(def led-rear-highbeam-pin)

;runtime vars
(def led-current-brightness 0.0)
(def direction 1)
(def led-mall-grab 0)

; espled segment index per strip, -1 when the strip is not present
(def seg-front -1)
(def seg-rear -1)
(def seg-status -1)
(def seg-footpad -1)
(def seg-button -1)

@const-end
