
(def tca9535-regs '(
        (addr . 0x20) ; Device address
        (out0 . 0xFF)
        (out1 . 0xFF)
        (conf0 . 0xFF)
        (conf1 . 0xFF)
))

(defunret tca9535-init (addr) {
        (apply i2c-start (rest-args))

        (if (not (i2c-detect-addr addr)) {
                (print (str-from-n addr "No response from 0x%X"))
                (return false)
        })

        (setassoc tca9535-regs 'addr addr)

        (i2c-tx-rx addr (list 2
                (assoc tca9535-regs 'out0)
                (assoc tca9535-regs 'out1)
                0x00
                0x00
                (assoc tca9535-regs 'conf0)
                (assoc tca9535-regs 'conf1)
        ))
})

(defun tca9535-set-reg-bit (reg bit val)
    (setassoc tca9535-regs reg
        (bits-enc-int (assoc tca9535-regs reg) bit val 1)
))

(defun tca9535-set-dir () {
        (loopforeach i (rest-args) {
                (var pin (first i))
                (var dir (second i))

                (if (and (>= pin 0) (< pin 8)) {
                        (tca9535-set-reg-bit 'conf0 pin (if (eq dir 'out) 0 1))
                })

                (if (and (>= pin 10) (< pin 18)) {
                        (tca9535-set-reg-bit 'conf1 (- pin 10) (if (eq dir 'out) 0 1))
                })
        })

        (i2c-tx-rx (assoc tca9535-regs 'addr)
            (list 6
                (assoc tca9535-regs 'conf0)
                (assoc tca9535-regs 'conf1)
        ))
})

(defun tca9535-write-pins () {
        (loopforeach i (rest-args) {
                (var pin (first i))
                (var state (second i))

                (if (and (>= pin 0) (< pin 8)) {
                        (tca9535-set-reg-bit 'out0 pin state)
                })

                (if (and (>= pin 10) (< pin 18)) {
                        (tca9535-set-reg-bit 'out0 (- pin 10) state)
                })
        })

        (i2c-tx-rx (assoc tca9535-regs 'addr)
            (list 2
                (assoc tca9535-regs 'out0)
                (assoc tca9535-regs 'out1)
        ))
})

(defun tca9535-read-pins () {
        (var regs (bufcreate 2))
        (i2c-tx-rx (assoc tca9535-regs 'addr) '(2) regs)
        (var res (map (fn (x) nil) (rest-args)))

        (looprange i 0 (length (rest-args)) {
                (var pin (rest-args i))

                (if (and (>= pin 0) (< pin 8)) {
                        (setix res i (bits-dec-int (bufget-u8 regs 0) pin 1))
                })

                (if (and (>= pin 10) (< pin 18)) {
                        (setix res i (bits-dec-int (bufget-u8 regs 1) (- pin 10) 1))
                })
        })

        (free regs)

        (if (= (length (rest-args)) 1) (first res) res)
})
