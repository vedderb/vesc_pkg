(def live-chart-values (list))
(def chart-value-index 0)

@const-start

; Pop from front of list, push to back of list
(define append-value
    (lambda (lst new-val max-length)
      (let ((updated-list (append lst (list new-val))))
        (if (> (length updated-list) max-length)
            (cdr updated-list)
            updated-list))))

(defun view-init-chart () {
    (def view-counter 0)
    (def value-avg 0)
    (def values-per-point-previous 1)
    (def view-updated true)
    (def buf-chart-title (img-buffer 'indexed4 240 30))
    (def buf-chart-value (img-buffer 'indexed4 120 25))
    (def buf-chart-value-min (img-buffer 'indexed4 120 25))
    (def buf-chart-value-max (img-buffer 'indexed4 120 25))

    (def buf-chart (img-buffer 'indexed2 240 128))
    (var chart-value-max 5)
    (var chart-labels (list "Duty Cycle" "Speed" "KW" "Angle" "Amps" "Battery SOC"))
    (txt-block-c buf-chart-title (list 0 1 2 3) 120 0 font24 (to-str (ix chart-labels chart-value-index)))
    (disp-render buf-chart-title 40 4 '(0x000000 0x4f514f 0x929491 0xfbfcfc))

    (view-init-menu)
    (defun on-btn-0-pressed () (def state-view-next (previous-view)))
    (defun on-btn-1-pressed () (if (> chart-value-index 0) {
        (def live-chart-values (list))
        (def view-counter 0)
        (def value-avg 0)
        (setq chart-value-index (- chart-value-index 1))
        (img-clear buf-chart-title)
        (txt-block-c buf-chart-title (list 0 1 2 3) 120 0 font24 (to-str (ix chart-labels chart-value-index)))
        (disp-render buf-chart-title 40 4 '(0x000000 0x4f514f 0x929491 0xfbfcfc))
    }))
    (defun on-btn-2-pressed () (if (< chart-value-index chart-value-max) {
        (def live-chart-values (list))
        (def view-counter 0)
        (def value-avg 0)
        (setq chart-value-index (+ chart-value-index 1))
        (img-clear buf-chart-title)
        (txt-block-c buf-chart-title (list 0 1 2 3) 120 0 font24 (to-str (ix chart-labels chart-value-index)))
        (disp-render buf-chart-title 40 4 '(0x000000 0x4f514f 0x929491 0xfbfcfc))
    }))
    (defun on-btn-3-pressed () (def state-view-next (next-view)))
    (view-draw-menu 'arrow-left 'arrow-down 'arrow-up 'arrow-right)
    (view-render-menu)
})

(defun view-draw-chart () {
    (var chart-items (list
        stats-duty
        (match (car settings-units-speeds)
            (mph (* stats-kmh km-to-mi))
            (_ stats-kmh)
        )
        stats-kw
        stats-angle-pitch
        stats-amps-now
        stats-battery-soc))

    (var value-now (ix chart-items chart-value-index))

    (def values-per-point (if (< view-counter 45) 1 16))
    (if (eq (mod view-counter values-per-point) 0) {
        (def view-updated true)
        (setq value-avg (+ value-avg value-now))
        ; Adjust value-avg when value-per-point changes
        (if (not-eq values-per-point-previous values-per-point) {
            (def value-avg (* value-now values-per-point))
            (def values-per-point-previous values-per-point)
        })
        (setq live-chart-values (append-value live-chart-values (/ value-avg values-per-point) 45))
        (def value-avg 0)

        (if (> (length live-chart-values) 10) {
            ; Update chart buffer
            (img-clear buf-chart)
            (var val-min-max (draw-live-chart buf-chart 0 0 240 128 1 1 live-chart-values))

            ; Update legend buffers
            (img-clear buf-chart-value)
            (img-clear buf-chart-value-min)
            (img-clear buf-chart-value-max)
            (txt-block-r buf-chart-value (list 0 1 2 3) 100 0 font18 (str-from-n value-now "%0.1f"))
            (txt-block-l buf-chart-value-min (list 0 1 2 3) 0 0 font18 (str-from-n (first val-min-max) "%0.1f"))
            (txt-block-l buf-chart-value-max (list 0 1 2 3) 0 0 font18 (str-from-n (second val-min-max) "%0.1f"))
        })
    } {
        (setq value-avg (+ value-avg value-now))
    })

    (setq view-counter (+ view-counter 1))
})

(defun view-render-chart () {
    (if view-updated {
        (def view-updated false)
        (disp-render buf-chart 40 60 '(0x000000 0x0000ff))

        (disp-render buf-chart-value 200 35 colors-text-aa)
        (disp-render buf-chart-value-min 0 188 colors-text-aa)
        (disp-render buf-chart-value-max 0 35 colors-text-aa)
    })
})

(defun view-cleanup-chart () {
    (def buf-chart-value nil)
    (def buf-chart-value-min nil)
    (def buf-chart-value-max nil)
    (def buf-chart-title nil)
    (def buf-chart nil)
    (def live-chart-values (list))
})
