(def bms-show-cells-v false)

@const-start

(defun poll-bms-data () {
    (var bms-current-ic (get-bms-val 'bms-i-in-ic))
    (var bms-temp-ic (get-bms-val 'bms-temp-ic))
    (var bms-cell-count (get-bms-val 'bms-cell-num))

    (var bms-cell-levels (range 0 bms-cell-count))
    (var bms-bal-states (range 0 bms-cell-count))
    (looprange i 0 bms-cell-count {
        (var v-cell (get-bms-val 'bms-v-cell i))
        (var bal-state (get-bms-val 'bms-bal-state i))
        (setix bms-cell-levels i v-cell)
        (setix bms-bal-states i bal-state)
    })

    (var bms-temp-count (get-bms-val 'bms-temp-adc-num))
    (var bms-cell-temps (range 0 bms-temp-count))
    (var bms-temp-count-filtered 0)
    (looprange i 0 bms-temp-count {
        (var temp-sensor (get-bms-val 'bms-temps-adc i))
        ; Filter out 0.0 and <= -50.0C values
        (if (and (!= temp-sensor 0.0) (> temp-sensor -50.0)) {
            (setix bms-cell-temps bms-temp-count-filtered temp-sensor)
            (setq bms-temp-count-filtered (+ bms-temp-count-filtered 1))
        })
    })
    (setq bms-temp-count bms-temp-count-filtered)
    (setq bms-cell-temps (take bms-cell-temps bms-temp-count))

    (list bms-cell-count bms-cell-levels bms-bal-states bms-cell-temps bms-current-ic bms-temp-ic)
})

(defun padded-float (val fmt width) {
    (var res (str-from-n val fmt))
    (looprange i (- (length res) 1) (+ width 1) {
        (setq res (str-merge res " "))
    })
    res
})

(defun view-init-bms () {
    (var view-width 320)
    (def buf-bms-top (img-buffer dm-pool 'indexed4 view-width 82))
    (def buf-bms-center (img-buffer dm-pool 'indexed4 view-width 50))
    (def buf-bms-bottom (img-buffer dm-pool 'indexed4 view-width 82))

    (img-blit buf-bms-center icon-bms-cell-high 0 2 -1)
    (img-blit buf-bms-center icon-bms-cell-low 0 27 -1)

    (img-blit buf-bms-center icon-bms-temp-high 99 2 -1)
    (img-blit buf-bms-center icon-bms-temp-low 99 27 -1)

    (img-blit buf-bms-center icon-bms-charge 204 2 -1)
    (img-blit buf-bms-center icon-bms-chip 204 27 -1)

    (view-init-menu)
    (defun on-btn-0-pressed () (def state-view-next (previous-view)))
    (defun on-btn-2-pressed () (setq bms-show-cells-v (not bms-show-cells-v)))
    (defun on-btn-3-pressed () (def state-view-next (next-view)))
    (view-draw-menu 'arrow-left nil "CELLS" 'arrow-right)
    (view-render-menu)

    (def view-stats-now (poll-bms-data))
    (def view-stats-previous (list 'bms-cell-count 'bms-cell-levels 'bms-bal-states 'bms-cell-temps 'bms-current-ic 'bms-temp-ic))

    (def poll-time (systime))
})

(defun view-draw-bms () {
    (if (> (secs-since poll-time) 0.25) {
        (def poll-time (systime))
        (def view-stats-now (poll-bms-data))
    })

    (if (not-eq (second view-stats-now) (second view-stats-previous))
    {
        (var view-width 320)
        (var cell-min 2.5) ; TODO: Implement config file or get from ESC/BMS
        (var cell-max 4.4) ; TODO: Implement config file or get from ESC/BMS

        (var cell-count (ix view-stats-now 0))
        (var cell-levels (ix view-stats-now 1))
        (var cell-states (ix view-stats-now 2))

        (var cell-temps (ix view-stats-now 3))
        (var current-ic (ix view-stats-now 4))
        (var temp-ic (ix view-stats-now 5))

        (def is-odd (if (eq (mod cell-count 2) 1) true false))
        (def cells-per-row (if is-odd (+ (/ cell-count 2) 1) (/ cell-count 2)))
        (var cells-spacing 2)
        (var cells-width (floor (/ (- view-width (* cells-per-row cells-spacing)) cells-per-row)))

        ; Draw first row
        (img-clear buf-bms-top)
        (looprange i 0 cells-per-row {
            (var x-pos (+ (* i (+ cells-width cells-spacing)) cells-spacing))
            (var fg-color (if (= (ix cell-states i) 1) 3 2))
            (draw-vertical-bar buf-bms-top
                x-pos           ;x
                0               ;y
                cells-width     ;w
                82              ;h
                `(1 ,fg-color)  ;colors
                (map-range-01 (ix cell-levels i) cell-min cell-max) ;pct
                (/ cells-width 12) ; corner rounding
                false ; with-outline
                config-better-bms-view ; invert-direction
            )
            (if bms-show-cells-v {
                (var txt-y (if config-better-bms-view 5 44))
                (var deciaml-y (if config-better-bms-view 16 55))
                (txt-block-v buf-bms-top (list fg-color 1 1 1) fg-color x-pos txt-y 14 36 font15 (str-from-n (to-i (* (ix cell-levels i) 100)) "%d"))
                (img-setpix buf-bms-top (+ x-pos cells-spacing) deciaml-y 1)
                (img-setpix buf-bms-top (+ x-pos cells-spacing) (+ deciaml-y 1) 1)
            })
        })

        ; Draw third row
        (img-clear buf-bms-bottom)
        (looprange i 0 (if is-odd (- cells-per-row 1) cells-per-row) {
            (var idx (+ i cells-per-row))
            (var x-pos (+ (* i (+ cells-width cells-spacing)) cells-spacing))
            (var fg-color (if (= (ix cell-states idx) 1) 3 2))
            (draw-vertical-bar buf-bms-bottom
                x-pos           ;x
                0               ;y
                cells-width     ;w
                82              ;h
                `(1 ,fg-color)  ;colors
                (map-range-01 (ix cell-levels idx) cell-min cell-max) ;pct
                (/ cells-width 12) ; corner rounding
                false ; with-outline
                false ; invert-direction
            )
            (if bms-show-cells-v {
                (txt-block-v buf-bms-bottom (list fg-color 1 1 1) fg-color x-pos 44 14 36 font15 (str-from-n (to-i (* (ix cell-levels idx) 100)) "%d"))
                (img-setpix buf-bms-bottom (+ x-pos cells-spacing) 55 1)
                (img-setpix buf-bms-bottom (+ x-pos cells-spacing) 56 1)
            })
        })

        ; Draw second row
        (img-text buf-bms-center 18 2 '(0 1 2 3) font18 (str-from-n (first (sort > cell-levels)) "%.2fV"))
        (img-text buf-bms-center 18 27 '(0 1 2 3) font18 (str-from-n (first (sort < cell-levels)) "%.2fV"))

        (if (eq (car settings-units-temps) 'celsius) {
            (img-text buf-bms-center 110 2 '(0 1 2 3) font18 (padded-float (first (sort > cell-temps)) "%.1fC" 5))
            (img-text buf-bms-center 110 27 '(0 1 2 3) font18 (padded-float (first (sort < cell-temps)) "%.1fC" 5))
        } {
            (img-text buf-bms-center 110 2 '(0 1 2 3) font18 (padded-float (c-to-f (first (sort > cell-temps))) "%.1fF" 5))
            (img-text buf-bms-center 110 27 '(0 1 2 3) font18 (padded-float (c-to-f (first (sort < cell-temps))) "%.1fF" 5))
        })

        (if (> current-ic 0.0)
            (img-blit buf-bms-center icon-bms-discharge 204 2 -1)
            (img-blit buf-bms-center icon-bms-charge 204 2 -1)
        )
        (img-text buf-bms-center 225 2 '(0 1 2 3) font18 (padded-float (abs current-ic) "%.1fA" 5))

        (if (eq (car settings-units-temps) 'celsius)
            (img-text buf-bms-center 225 27 '(0 1 2 3) font18 (padded-float temp-ic "%.1fC" 5))
            (img-text buf-bms-center 225 27 '(0 1 2 3) font18 (padded-float (c-to-f temp-ic) "%.1fF" 5))
        )
    })
})

(defun view-render-bms () {
    (if (not-eq (second view-stats-now) (second view-stats-previous))
    {
        (disp-render buf-bms-top 0 0 '(0x000000 0xd3d3d3 0x006400 0xff8c00))
        (disp-render buf-bms-center 0 82 colors-white-icon)
        (disp-render buf-bms-bottom 0 132 '(0x000000 0xd3d3d3 0x006400 0xff8c00))
    })

    (def view-stats-previous view-stats-now)
})

(defun view-cleanup-bms () {
    (def buf-bms-top nil)
    (def buf-bms-center nil)
    (def buf-bms-bottom nil)
})
