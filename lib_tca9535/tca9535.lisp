
(def tca9535-regs '(
        (addr . 0x20) ; Device address
        (out0 . 0xFF)
        (out1 . 0xFF)
        (conf0 . 0xFF)
        (conf1 . 0xFF)
))

(defun tca9535-write-regs () {
        (loopforeach i (rest-args) {
                (var reg (first i))
                (var data (second i))
                (i2c-tx-rx (assoc tca9535-regs 'addr) (list reg data))
        })
})

(defunret tca9535-init (addr) {
        (apply i2c-start (rest-args))

        (if (not (i2c-detect-addr addr)) {
                (print (str-from-n addr "No response from 0x%X"))
                (return false)
        })

        (setassoc tca9535-regs 'addr addr)

        (tca9535-write-regs
            (list 2 (assoc tca9535-regs 'out0))
            (list 3 (assoc tca9535-regs 'out1))
            (list 4 0)
            (list 5 0)
            (list 6 (assoc tca9535-regs 'conf0))
            (list 7 (assoc tca9535-regs 'conf1))
        )
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
        
        (tca9535-write-regs
            (list 6 (assoc tca9535-regs 'conf0))
            (list 7 (assoc tca9535-regs 'conf1))
        )
})

(defun tca9535-write-pins () {
        (loopforeach i (rest-args) {
                (var pin (first i))
                (var state (second i))

                (if (and (>= pin 0) (< pin 8)) {
                        (tca9535-set-reg-bit 'out0 pin state)
                })

                (if (and (>= pin 10) (< pin 18)) {
                        (tca9535-set-reg-bit 'out1 (- pin 10) state)
                })
        })
        
        (tca9535-write-regs
            (list 2 (assoc tca9535-regs 'out0))
            (list 3 (assoc tca9535-regs 'out1))
        )
})

(defun tca9535-read-pins () {
        (var res (map (fn (x) nil) (rest-args)))
        
        (var reg0 (bufcreate 1))
        (var reg1 (bufcreate 1))
        
        (i2c-tx-rx (assoc tca9535-regs 'addr) '(0) reg0)
        (i2c-tx-rx (assoc tca9535-regs 'addr) '(1) reg1)

        (looprange i 0 (length (rest-args)) {
                (var pin (rest-args i))

                (if (and (>= pin 0) (< pin 8)) {
                        (setix res i (bits-dec-int (bufget-u8 reg0 0) pin 1))
                })

                (if (and (>= pin 10) (< pin 18)) {
                        (setix res i (bits-dec-int (bufget-u8 reg1 0) (- pin 10) 1))
                })
        })
        
        (free reg0)
        (free reg1)

        (if (= (length (rest-args)) 1) (first res) res)
})

