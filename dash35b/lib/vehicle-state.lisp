
(def indicate-l-on nil)
(def indicate-r-on nil)
(def indicate-ms 0)
(def indicator-timestamp 0)
(def highbeam-on false)

(def kickstand-down false)
(def drive-mode 1)
(def drive-mode-num 5)
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
(def setting-num 4)
(def setting-list-page1 '(
        whl-active
        whl-start
        whl-end
        whl-kd
))
(def setting-step-page1 '(
        1
        0.5
        0.5
        0.001
))
(def setting-lim-page1 '(
        (0 1)
        (0.0 55.0)
        (0.0 55.0)
        (0.0 0.2)
))

(def light-on light-on-default)
(def backlight-dim false)

(def temp-ambient 0.0)
(def temp-ambient-rx false)

(def date-time nil)
(def date-time-rx false)
