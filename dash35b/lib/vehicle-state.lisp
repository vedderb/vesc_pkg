
(def indicate-l-on nil)
(def indicate-r-on nil)
(def indicate-ms 0)
(def indicator-timestamp 0)
(def highbeam-on false)

(def kickstand-down false)
(def drive-mode 1)
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

(def setting-now 0)
(def setting-num 0)

; setting-list-page1 etc are built by settings-build.

(def light-on light-on-default)
(def backlight-dim false)

; For changes per-field detection cannot see, e.g. a unit label swap.
(def view-force-static false)
(def view-force-pages false)

(def temp-ambient 0.0)
(def temp-ambient-rx false)

(def date-time nil)
(def date-time-rx false)
