(def settings-units-speeds '(kmh . "km/h"))
(def settings-units-temps '(celsius . "C"))

@const-start

(def ms-to-kph 3.6)
(def km-to-mi 0.621371)
(defun c-to-f (c)
  (+ (* c 1.8) 32))

; Everything arrives as km/h, km and C. Units are applied only here.
(defun u-speed (kmh)
    (if (eq (car settings-units-speeds) 'mph) (* kmh km-to-mi) kmh))

(defun u-dist (km)
    (if (eq (car settings-units-speeds) 'mph) (* km km-to-mi) km))

(defun u-temp (c)
    (if (eq (car settings-units-temps) 'fahrenheit) (c-to-f c) c))

(defun u-speed-str () (cdr settings-units-speeds))
(defun u-temp-str () (cdr settings-units-temps))
(defun u-dist-str ()
    (if (eq (car settings-units-speeds) 'mph) "mi" "km"))
(defun u-eff-str ()
    (if (eq (car settings-units-speeds) 'mph) "Wh/mi" "Wh/km"))

; Speeds and temps change together
(defun setting-units-cycle () {
    (match (car settings-units-speeds)
        (kmh {
            (def settings-units-speeds '(mph . "MPH"))
            (def settings-units-temps '(fahrenheit . "F"))
        })
        (mph {
            (def settings-units-speeds '(kmh . "km/h"))
            (def settings-units-temps '(celsius . "C"))
        })
        (_ (print "Unexpected settings-units-speeds value"))
    )
})

; Alternatively a user can change only temps
(defun setting-units-cycle-temps () {
    (match (car settings-units-temps)
        (celsius (def settings-units-temps '(fahrenheit . "F")))
        (fahrenheit (def settings-units-temps '(celsius . "C")))
        (_ (print "Unexpected settings-units-temps value"))
    )
})
