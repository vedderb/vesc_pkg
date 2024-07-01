; Persistent settings
; Format: (label . (offset type))
(def eeprom-addrs '(
    (ver-code  . (0 i))
    (pf1-speed . (1 f))
    (pf1-break . (2 f))
    (pf1-accel . (3 f))
    (pf2-speed . (4 f))
    (pf2-break . (5 f))
    (pf2-accel . (6 f))
    (pf3-speed . (7 f))
    (pf3-break . (8 f))
    (pf3-accel . (9 f))
    (pf-active . (10 i))
))

(defun print-settings ()
    (loopforeach it eeprom-addrs
        (print (list (first it) (read-setting (first it))))
))

(defun save-settings (  pf1-speed pf1-break pf1-accel
                        pf2-speed pf2-break pf2-accel
                        pf3-speed pf3-break pf3-accel
                        pf-active
)
    (progn
        (write-setting 'pf1-speed pf1-speed)
        (write-setting 'pf1-break pf1-break)
        (write-setting 'pf1-accel pf1-accel)
        (write-setting 'pf2-speed pf2-speed)
        (write-setting 'pf2-break pf2-break)
        (write-setting 'pf2-accel pf2-accel)
        (write-setting 'pf3-speed pf3-speed)
        (write-setting 'pf3-break pf3-break)
        (write-setting 'pf3-accel pf3-accel)
        (write-setting 'pf-active pf-active)
        (print "Settings Saved!")
))

; Settings version
(def settings-version 42i32)

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
        (write-setting 'pf1-break 1.0)
        (write-setting 'pf1-accel 1.0)
        (write-setting 'pf2-speed 18.8)
        (write-setting 'pf2-break 0.4)
        (write-setting 'pf2-accel 0.6)
        (write-setting 'pf3-speed 11.2)
        (write-setting 'pf3-break 0.2)
        (write-setting 'pf3-accel 0.4)
        (write-setting 'pf-active 0)
        (write-setting 'ver-code settings-version)
        (print "Settings Restored!")
))

; Restore settings if version number does not match
; as that probably means something else is in eeprom
(if (not-eq (read-setting 'ver-code) settings-version) (restore-settings))
