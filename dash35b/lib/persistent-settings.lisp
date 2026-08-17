@const-start

; Persistent settings
; Format: (label . (offset type))
(def eeprom-addrs '(
    (ver-code  . (0 i))
    (pf1-speed . (1 f))
    (pf1-brake . (2 f))
    (pf1-accel . (3 f))
    (pf2-speed . (4 f))
    (pf2-brake . (5 f))
    (pf2-accel . (6 f))
    (pf3-speed . (7 f))
    (pf3-brake . (8 f))
    (pf3-accel . (9 f))
    (pf-active . (10 i))

    (whl-active . (11 i))
    (whl-start . (12 f))
    (whl-end . (13 f))
    (whl-kd . (14 f))
))

(defun print-settings ()
    (loopforeach it eeprom-addrs
        (print (list (first it) (read-setting (first it))))
))

; Settings version
(def settings-version 43i32)

(defun read-setting (name)
    (let (
            (addr (first (assoc eeprom-addrs name)))
            (type (second (assoc eeprom-addrs name)))
        )
        (cond
            ((eq type 'i) (eeprom-read-i addr))
            ((eq type 'f) (eeprom-read-f addr))
            ((eq type 'b) (!= (eeprom-read-i addr) 0))
)))

(defun write-setting (name val)
    (let (
            (addr (first (assoc eeprom-addrs name)))
            (type (second (assoc eeprom-addrs name)))
        )
        (cond
            ((eq type 'i) (eeprom-store-i addr val))
            ((eq type 'f) (eeprom-store-f addr val))
            ((eq type 'b) (eeprom-store-i addr (if val 1 0)))
)))

(defun restore-settings ()
    (progn
        (write-setting 'pf1-speed 39.3)
        (write-setting 'pf1-brake 1.0)
        (write-setting 'pf1-accel 1.0)
        (write-setting 'pf2-speed 18.8)
        (write-setting 'pf2-brake 0.4)
        (write-setting 'pf2-accel 0.6)
        (write-setting 'pf3-speed 11.2)
        (write-setting 'pf3-brake 0.2)
        (write-setting 'pf3-accel 0.4)
        (write-setting 'pf-active 0)

        (write-setting 'whl-active 0)
        (write-setting 'whl-start 20)
        (write-setting 'whl-end 43)
        (write-setting 'whl-kd 0.005)

        (write-setting 'ver-code settings-version)
        (print "Settings Restored!")
))

; Restore settings if version number does not match
; as that probably means something else is in eeprom
(if (not-eq (read-setting 'ver-code) settings-version) (restore-settings))
