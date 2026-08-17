; Configuration script for MT6701 encoder. It uses the hall sensor pins configured
; for i2c to upload the configuration.

(def mt6701-addr 0x06)

(defun read-reg (reg) {
        (var buf (bufcreate 1))
        (i2c-tx-rx mt6701-addr (list reg) buf)
        (bufget-u8 buf 0)
})

(defun write-reg (reg val) {
        (i2c-tx-rx mt6701-addr (list reg val))
})

(defun store-config() {
        (i2c-tx-rx mt6701-addr (list 0x09 0xB3))
        (i2c-tx-rx mt6701-addr (list 0x0A 0x05))
})

(defun mt6701-set-uvw-res (poles) {
        (setq poles (- poles 1))
        (var p4 (bitwise-and poles 15))
        (write-reg 0x30 (bits-enc-int (read-reg 0x30) 4 p4 4))
})

(defun mt6701-read-uvw-res () {
        (+ (shr (read-reg 0x30) 4) 1)
})

(defun mt6701-set-abz-res (v) {
        (var v10   (bitwise-and v 1023))
        (var low8  (bitwise-and v10 255))
        (var high2 (bitwise-and (shr v10 8) 3))

        (write-reg 0x31 low8)
        (write-reg 0x30 (bits-enc-int (read-reg 0x30) 0 high2 2))
})

(defun mt6701-set-hyst (h) {
        (var h3 (bitwise-and h 7))
        (var hyst2 (bitwise-and (shr h3 2) 1))
        (var hyst10 (bitwise-and h3 3))

        (write-reg 0x32 (bits-enc-int (read-reg 0x32) 7 hyst2 1))
        (write-reg 0x34 (bits-enc-int (read-reg 0x34) 6 hyst10 2))
})

(defun mt6701-set-z-pulse-width (w) {
        (var w3 (bitwise-and w 7))
        (write-reg 0x32 (bits-enc-int (read-reg 0x32) 4 w3 3))
})

(defun mt6701-set-zero (z) {
        (var z12 (bitwise-and z 4095))
        (var low8 (bitwise-and z12 255))
        (var high4 (bitwise-and (shr z12 8) 15))

        (write-reg 0x33 low8)
        (write-reg 0x32 (bits-enc-int (read-reg 0x32) 0 high4 4))
})

;(loopwhile-thd 100 t {
        ;(var buf (bufcreate 2))
        ;(i2c-tx-rx mt6701-addr '(3) buf)
        ;(def angle (bufget-u16 buf 0))
        ;(sleep 0.1)
;})

(defun conf-basics () {
        (write-reg 0x38 (bits-enc-int (read-reg 0x38) 5 3 2)) ; PWM out, inverted polarity
        (write-reg 0x25 (bits-enc-int (read-reg 0x25) 7 0 1)) ; bit 7  0 = UVW, 1= -A-B-Z (differential ABI support)
        (write-reg 0x29 (bits-enc-int (read-reg 0x29) 6 0 1)) ; bit 6  0 = ABZ, 1= UVW
        (write-reg 0x29 (bits-enc-int (read-reg 0x29) 1 0 1)) ; bit 1  0 = CCW, 1= CW
        (sleep 1.0)
})

(defun try-i2c (sda scl) {
        (i2c-start 'rate-100k sda scl)
        (var res (i2c-detect-addr mt6701-addr))

        (if (not res) {
                (gpio-configure sda 'pin-mode-in)
                (gpio-configure scl 'pin-mode-in)
        })

        res
})

(defun debug-print (msg) {
        (print msg)
        (send-data (to-str msg))
})

(defun connect-encoder () {
        ; We need these set to prevent the ADC voltage divider from pulling down the
        ; pull-up on the hall lines. Use trap as not all hardware has these.
        (trap {
                (gpio-configure 'pin-adc3 'pin-mode-out)
                (gpio-configure 'pin-adc4 'pin-mode-out)
                (gpio-write 'pin-adc3 1)
                (gpio-write 'pin-adc4 1)
        })

        (or
            (try-i2c 'pin-hall1 'pin-hall2)
            (try-i2c 'pin-hall2 'pin-hall1)
            (try-i2c 'pin-rx 'pin-tx)
            (try-i2c 'pin-tx 'pin-rx)
        )
})

(defunret config-encoder (pole-pairs) {
        (if (not (connect-encoder)) {
                (debug-print "No response from encoder")
                (return)
        })

        (debug-print "Encoder responded on I2C")

        (conf-basics)

        ; 0-1023 allowed, Encoder counts will be (abz-res + 1) * 4
        ; Example (255 + 1) * 4 = 1024
        ; 255 is a good tradeoff. Good enough resolution and
        ; not too high frequency on high RPM.
        (mt6701-set-abz-res 255)

        ; Pole pairs, 1 - 16
        (mt6701-set-uvw-res pole-pairs)

        ; ABZ Hysteresis Filter
        ; 0: 1 LSB
        ; 1: 2 LSB
        ; 2: 4 LSB
        ; 3: 8 LSB
        ; 4: 0 LSB
        ; 5: 0.25 LSB
        ; 6: 0.5 LSB
        ; 7: 1 LSB
        (mt6701-set-hyst 0)

        ; Z Pulse Width
        ; 0: 1 LSB
        ; 1: 2 LSB
        ; 2: 4 LSB
        ; 3: 8 LSB
        ; 4: 12 LSB
        ; 5: 16 LSB
        ; 6: 180 Degrees
        ; 7: 1 LSB
        (mt6701-set-z-pulse-width 1)

        ; ABZ Zero Offset
        ; 0-4096 maps to 0-360 degrees
        (mt6701-set-zero 0)

        ; Store configuration to non-volatile memory
        (store-config)

        (debug-print "Done!")
})

(defunret read-encoder () {
        (if (not (connect-encoder)) {
                (debug-print "No response from encoder")
                (return)
        })

        (debug-print (list "Pole Pairs" (mt6701-read-uvw-res)))
})

(defun event-handler ()
    (loopwhile t
        (recv
            ((event-data-rx . (? data)) (trap (eval (read data))))
            (_ nil)
)))

(defun main () {
        (event-register-handler (spawn event-handler))
        (event-enable 'event-data-rx)
})

(image-save)
(main)

;(config-encoder 4)
