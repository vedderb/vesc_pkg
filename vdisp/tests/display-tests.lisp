(import "pkg::font_16_26@://vesc_packages/lib_files/files.vescpkg" 'font26)

; Test disp-text && font
(def img (img-buffer 'indexed2 200 200))
(txt-block-c img 1 100 100 font26 '("First Line" "Another Line"))
(disp-render img 10 10 '(0x00FF00 0xFF0000))
(sleep 0.1) (def img nil) (gc)

; Test img-line
(def img (img-buffer 'indexed2 100 100))
(img-line img 10 10 90 90 1)
(disp-render img 10 10 '(0x00FF00 0xFF0000))
(sleep 0.1) (setq img nil) (gc)

; Test button-simple
(def img (img-buffer 'indexed2 128 64))
(btn-simple img 0 1 5 5 128 64 font26 "butt-on") ;btn-simple (img col-bg col-txt ofs-x ofs-y w h font txt)
(disp-render img 10 10 '(0xff0000 0xffffff))
(sleep 0.1) (setq img nil) (gc)

; Test gauge-simple
(def img (img-buffer 'indexed4 220 220))
(gauge-simple img 0 1 2 104 104 104 90 font26 "gauge") ;gauge-simple (img col-bg col-bar col-txt cx cy rad val font txt)
(disp-render img 0 0 '(0x000000 0x00ff00 0xffffff))
(sleep 0.1) (setq img nil) (gc)

; Preview UI Loop
(defun preview-ui-loop () {
    (def preview-ui true)
    (loopwhile preview-ui {
        (disp-render-jpg preview-left 0 0)
        (sleep 5.5)
        (disp-render-jpg preview-right 0 0)
        (sleep 5.5)
    })
})

; img = image buffer
; cx = X center position
; cy = Y center position
; radius = gauge radius
; color = index of color used for gauge
; color-bg = (optional) index of background color
; thickness = width of gauge arc
; quadrant = 0-3 index starting in upper left rotating clockwise
; value = 0-1.0 value for gauge
; reversed = true makes the arc run counter clockwise
; with-arrow = true draws an arrow at the current value
; value-peak = (optional) 0-1.0 value for peak
; color-peak = (optional) index of peak value color
;(defun draw-gauge-quadrant (img cx cy radius color color-bg thickness quadrant value reversed with-arrow value-peak color-peak) {
;    (def angle-start (match quadrant
;        (0 (if reversed 270 180))
;        (1 (if reversed 360 270))
;        (2 (if reversed 90 360))
;        (3 (if reversed 180 90))
;        (_ (if reversed 270 180))
;    ))
;
;    ; Optionally draw background color for quadrant
;    (if (eq (type-of color-bg) 'type-i) {
;        (print (list (to-str quadrant) (to-str angle-start) (to-str (if reversed (- angle-start 90) (+ angle-start 90)))))
;        (if reversed {
;            (img-arc img cx cy radius (- angle-start 90) angle-start color-bg '(thickness 17))
;        } {
;            (img-arc img cx cy radius angle-start (+ angle-start 90) color-bg '(thickness 17))
;        })
;    })
;
;    (def angle-end (if reversed (- angle-start (* 90 value)) (+ angle-start (* 90 value))))
;
;    (if reversed {
;        (var temp angle-end)
;        (setq angle-end angle-start)
;        (setq angle-start temp)
;    })
;
;    ; Optionally draw peak value
;    (if (and (eq (type-of value-peak) 'type-float) (eq (type-of color-peak) 'type-i)) {
;        (if reversed {
;            (def angle-end-peak (- angle-end (* 90 value-peak)))
;            (print (list "reversed" (to-i angle-end-peak) (to-i angle-end)))
;            (img-arc img cx cy radius angle-end-peak angle-end color-peak '(thickness 17))
;        } {
;            (def angle-end-peak (+ angle-start (* 90 value-peak)))
;            (print (list "fwd" (to-i angle-start) (to-i angle-end-peak)))
;            (img-arc img cx cy radius angle-start angle-end-peak color-peak '(thickness 17))
;        })
;
;    })
;
;    ; Arc
;    (img-arc img cx cy radius angle-start angle-end color '(thickness 17))
;
;    (if with-arrow {
;        ; Draw Arrow at end Position, same color
;        (def pos-inner (rot-point-origin radius 0 (if reversed angle-start angle-end)))
;        (def pos-outer-l (rot-point-origin (+ radius 9) 0 (if reversed (- angle-start 2) (+ angle-end 2))))
;        (def pos-outer-h (rot-point-origin (+ radius 9) 0 (if reversed (+ angle-start 2) (- angle-end 2))))
;        (img-triangle img
;            (+ (ix pos-inner 0) cx)
;            (+ (ix pos-inner 1) cy)
;            (+ (ix pos-outer-l 0) cx)
;            (+ (ix pos-outer-l 1) cy)
;            (+ (ix pos-outer-h 0) cx)
;            (+ (ix pos-outer-h 1) cy)
;            color '(filled))
;    })
;})
;
;(defun create-quad-guage (img cx cy radius color color-bg) {
;    (var gauge (draw-gauge-quadrant))
;    (list
;        (cons 'gauge buf)
;        (cons 'x x)
;        (cons 'y y)
;        (cons 'w width)
;        (cons 'h height)
;        (cons 'changed false)
;    )
;})

(def fake-value 0.5)
(defun on-btn-0-pressed () {
    (if (> fake-value 0.0) (setq fake-value (- fake-value 0.1)))
    (draw-test-gauges)
    (draw-menu "BACK" nil "SETUP" "ENTER")
})
(defun on-btn-3-pressed () {
    (if (< fake-value 1.0) (setq fake-value (+ fake-value 0.1)))
    (draw-test-gauges)
    (draw-menu "BACK" "MODE" nil "ENTER")
})

(defun draw-test-gauges () {
    (disp-clear)
    ; Test draw-gauge-quadrant
    (var radius 104)
    (var padding 6)
    (var x-offs 10)
    (var y-offs 10)

    ; Draw gauge background
    (var img (img-buffer 'indexed2 208 2))
    (img-line img 0 0 208 0 1 '(thickness 2))
    (disp-render img x-offs (+ (+ y-offs radius) 2) '(0x000000 0x1b1b1b))
    (var img (img-buffer 'indexed2 2 208))
    (img-line img 0 0 0 208 1 '(thickness 2))
    (disp-render img (+ (+ x-offs radius) 2) y-offs '(0x000000 0x1b1b1b))

    ; Quarter guage buffer (re-used for each quadrant to save memory)
    (var img (img-buffer 'indexed16 radius radius))

    (draw-gauge-quadrant img radius radius radius 1 2 17 0 fake-value true true 0.8 4)
    (txt-block-r img 3 radius 52 font18 '("-030A" "-060A"))
    (disp-render img x-offs y-offs '(0x000000 0x0000ff 0x1b1b1b 0xfbfcfc 0x4f4f4f))
    (img-clear img)

    (draw-gauge-quadrant img 0 radius radius 1 2 17 1 fake-value nil true 0.8 4)
    (txt-block-l img 3 4 52 font18 '("190A" "280A"))
    (disp-render img (+ padding (+ x-offs radius)) y-offs '(0x000000 0x00d8ff 0x1b1b1b 0xfbfcfc 0x4f4f4f))
    (img-clear img)

    (draw-gauge-quadrant img 0 0 radius 1 2 17 2 fake-value true nil nil nil)
    (txt-block-l img 3 4 4 font18 '("1200Wh"))
    (disp-render img (+ padding (+ x-offs radius)) (+ padding (+ y-offs radius)) '(0x000000 0xfbd00a 0x1b1b1b 0xfbfcfc))
    (img-clear img)

    (draw-gauge-quadrant img radius 0 radius 1 2 17 3 (/ fake-value 2) nil nil nil nil)
    (txt-block-r img 3 radius 4 font18 '("600Wh"))
    (disp-render img x-offs (+ padding (+ y-offs radius)) '(0x000000 0x97bf0d 0x1b1b1b 0xfbfcfc))

    (setq img nil)
    (gc)
})

(draw-test-gauges)

;(sleep 3)
;(preview-ui-loop)

(defun draw-triangle-left (img x y w h color) {
    (var x1 x)
    (var y1 (+ y (/ h 2)))

    (var x2 (+ x w))
    (var x3 (+ x w))

    (var y2 y)
    (var y3 (+ y h))

    ;(img-triangle img x1 y1 x2 y2 x3 y3 color '(thickness 1)) ; TODO: Does not draw the shape I desire
    (img-line img x1 y1 x2 y2 1 '(thickness 1))
    (img-line img x2 y2 x3 y3 1 '(thickness 1))
    (img-line img x1 y1 x3 y3 1 '(thickness 1)) ; TODO: x1 y1 x3 y3 is not the same as x3 y3 x1 y1
})

(defun draw-arrow-left (img x y w h color) {
    (var x1 x)
    (var y1 (+ y (/ h 2)))

    (var x2 (+ x w))
    (var x3 (+ x w))

    (var y2 y)
    (var y3 (+ y h))

    (var x4 (+ x (* w 0.68)))
    (var y4 y1)

    (img-line img x1 y1 x2 y2 1 '(thickness 1))

    (img-line img x2 y2 x4 y4 1 '(thickness 1))
    (img-line img x3 y3 x4 y4 1 '(thickness 1))
    
    (img-line img x1 y1 x3 y3 1 '(thickness 1))
})

(defun draw-arrow-right (img x y w h color) {
    (var x1 x)
    (var y1 (+ y (/ h 2)))

    (var x2 (- x w))
    (var x3 (- x w))

    (var y2 y)
    (var y3 (+ y h))

    (var x4 (- x (* w 0.68)))
    (var y4 y1)

    (img-line img x1 y1 x2 y2 1 '(thickness 1))

    (img-line img x2 y2 x4 y4 1 '(thickness 1))
    (img-line img x3 y3 x4 y4 1 '(thickness 1))
    
    (img-line img x1 y1 x3 y3 1 '(thickness 1))
})

(defun draw-menu (button-0 button-1 button-2 button-3) {
    (var btn-1-center 115)
    (var btn-2-center 200)
    (var width 320)
    (var height 25)
    (var img (img-buffer 'indexed2 width height))
    (img-line img 0 0 width 0 1 '(thickness 2))

    ;(txt-block-l img 1 0            5 font15 button-0)
    (draw-arrow-left img 10 6 18 14 1)
    (txt-block-c img 1 btn-1-center 6 font15 button-1)
    (txt-block-c img 1 btn-2-center 6 font15 button-2)
    ;(txt-block-r img 1 320          6 font15 button-3)
    (draw-arrow-right img 310 6 18 14 1)

    (disp-render img 0 (- 240 height) '(0x000000 0x0000ff)) ; alt menu bar color 0x898989
})

; TODO: Front from vesc_pkg:font_16_26.bin is not the same as Roboto Mono that I can find

(draw-menu "BACK" "MODE" "SETUP" "ENTER")

(defun test-rest-args (a b c) {
    (var test (rest-args 0))
    (var test2 (rest-args 1))
    (print (list a b c test2 test))
})

(test-rest-args "aa" "bb" "cc" "dd" "ee")

; arc above big arc is 8 px larger radius ; thickness is 4px ; color is 65d7f5
; big arc 750px wide
; +/- 25 degree from top (270)
(defun on-btn-1-pressed () {
    (draw-big-arc)
})

(defun draw-big-number () {
    (var img (img-buffer 'indexed2 240 128))
    (var y 62)
    (txt-block-c img 1 120 0 font128 "111")
    (disp-render img 40 y '(0x000000 0xfbfcfc))
})

(defun draw-big-arc () {
    (var img (img-buffer 'indexed2 320 50))
    (var y 25)
    (var radius 375)
    (var top-center-angle 270)
    (img-arc img 160 radius radius (- top-center-angle 30) (+ top-center-angle 30) 1 '(thickness 12)) ;'(dotted 15 15)

    (disp-render img 0 y '(0x000000 0x1e9af3))

    (draw-big-number)
})

(draw-big-arc)

(defun draw-big-arc-double () {
    (var img (img-buffer 'indexed4 320 58))
    (var y 20)
    (var radius 375)
    (var top-center-angle 270)

    ; Upper Arc
    (var angle-limit 50)
    (var angle-start (- top-center-angle 30))
    (var angle-end (+ angle-start (* angle-limit fake-value)))
    (img-arc img 160 radius radius angle-start (+ angle-start angle-limit) 3 '(thickness 4)) ; BG
    (img-arc img 160 radius radius angle-start angle-end 2 '(thickness 4)) ; FG

    ; Lower Arc
    (img-arc img 160 (+ radius 8) radius angle-start (+ top-center-angle 30) 1 '(thickness 12))

    (disp-render img 0 y '(0x000000 0x1e9af3 0x65d7f5 0x444444))
})

(draw-big-arc-double)

(defun draw-units (img x y color font) {
    (txt-block-l img color x y font (symbol-string settings-units-speeds))
})

(def stats-top-speed 129)
(defun draw-top-speed (img x y color font) {
    (txt-block-r img color x y font (str-from-n stats-top-speed "%d"))
})

(defun draw-big-view () {
    (var img (img-buffer 'indexed2 50 25))
    (draw-units img 0 0 1 font15)
    (disp-render img 0 0 '(0x000000 0xf4f7f9))

    (var img (img-buffer 'indexed2 50 25))
    (draw-top-speed img 50 0 1 font18)
    (disp-render img (- 320 50) 0 '(0x000000 0xf4f7f9))

    (draw-big-arc-double)

    (draw-big-number)

    (draw-menu "BACK" "MODE" "SETUP" "ENTER")
})

(disp-clear)
(draw-big-view)