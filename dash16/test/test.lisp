(import "Frame 38.jpg" 'img1)

(disp-init)
(ext-disp-orientation 0)

;(pwm-start 2000 0.1 0 2)
(pwm-start 2000 0.9 0 2)

(disp-render-jpg img1 34 0)

(gpio-configure 8 'pin-mode-in-pu)
(gpio-configure 10 'pin-mode-in-pu)

(loopwhile-thd 200 t {
        (def bt1 (gpio-read 8))
        (def bt2 (gpio-read 10))
        (def thr (get-adc 0))
        (sleep 0.05)
})
