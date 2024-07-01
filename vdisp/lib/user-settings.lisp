(def settings-units-speeds '(kmh . "Km/h"))
(def settings-units-temps '(celsius . "C"))

@const-start

(def user-settings-version 42)

(def ms-to-kph 3.6)
(def km-to-mi 0.621371)
(defun c-to-f (c)
  (+ (* c 1.8) 32))

; Speeds and temps change together
(defun setting-units-cycle () {
    (match (car settings-units-speeds)
        (kmh {
            (def settings-units-speeds '(mph . "MPH"))
            (def settings-units-temps '(fahrenheit . "F"))
        })
        (mph {
            (def settings-units-speeds '(kmh . "Km/h"))
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

; TODO: Wear leveling would be a nice addition
(defun settings-save-to-flash () {
    (var all-settings (list user-settings-version settings-units-speeds settings-units-temps))
    (var to-write (flatten all-settings))
    (var settings-len (buflen to-write))

    (var write-size-buf (array-create 4))
    (bufset-u32 write-size-buf 0 settings-len)

    (fw-erase (+ (buflen write-size-buf) settings-len))

    (fw-write-raw 0 write-size-buf)
    (fw-write-raw 4 to-write)
})

(defunret settings-load-from-flash () {
    (var settings-len-buf (fw-data 0 4))
    (var settings-len (bufget-u32 settings-len-buf 0))
    (if (or (< settings-len 32) (> settings-len 2048)) {
        ;(print (str-from-n settings-len "%d is an invalid settings length. Nothing to load."))
        (return nil)
    })

    (var flat-settings (fw-data 4 settings-len))
    (var all-settings (unflatten flat-settings))
    (if (not-eq (type-of all-settings) 'type-list) {
        ;(print (str-merge "Unable to load settings due to an unexpected type: " (to-str (type-of all-settings))))
        (return nil)
    })

    (var version (first all-settings))
    (if (eq version user-settings-version) {
        (setq settings-units-speeds (ix all-settings 1))
        (setq settings-units-temps (ix all-settings 2))
        (print "User settings loaded successfully")
    } (print (str-from-n version "%d is an invalid settings version. Nothing to load.")))

    (eq version user-settings-version)
})

(spawn settings-load-from-flash)
