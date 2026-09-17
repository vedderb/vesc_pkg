
(def indicate-l-on nil)
(def indicate-r-on nil)
(def indicate-ms 0)
(def indicator-timestamp 0)
(def highbeam-on false)

(def kickstand-down false)
(def drive-mode 1)

; systime of the last mode this display asserted itself. While that is recent
; the controller's reported mode is not followed, so a button press, the
; kickstand or charging cannot be undone by the controller echoing back a mode
; it has not been told about yet.
(def mode-cmd-ts 0)

; The controller has suspended its drive profile for servicing
(def service-mode false)

; The controller's stored motor parameters cannot describe a real motor
(def motor-bad false)

(defun mode-set (m) {
        (setq drive-mode m)
        (setq mode-cmd-ts (systime))
})

(def performance-mode 'eco) ; 'eco 'normal 'sport UNUSED!

(def cruise-control-active false)
(def cruise-control-speed 0.0)

(def battery-a-charging false)
(def battery-a-chg-time 0)
(def battery-a-connected false) ; Has received msg from BMS A

(def battery-b-soc 0.0)
(def battery-b-charging false)
(def battery-b-chg-time 0)
(def battery-b-connected false) ; Has received msg from BMS B

(def page-now 0)
(def page-num 3)

(def light-on light-on-default)
(def backlight-dim false)

; Set when something changes that the per-field change detection cannot see,
; such as a unit switch that alters a label without altering the value.
; The view threads clear these after one full pass.
(def view-force-static false)
(def view-force-pages false)

(def temp-ambient 0.0)
(def temp-ambient-rx false)

(def date-time nil)
(def date-time-rx false)
