(def tca9534-regs '(
        (addr . 0x20) ; Device address
        (out0 . 0xFF)
        (conf0 . 0xFF)
))

@const-start

(defun tca9534-write-regs () {
        (loopforeach i (rest-args) {
                (var reg (first i))
                (var data (second i))
                (i2c-tx-rx (assoc tca9534-regs 'addr) (list reg data))
        })
})

(defunret tca9534-init (addr) {
        ; For compatibility with old apply
        (match (trap (apply i2c-start (rest-args)))
            ((exit-ok (? a)) nil)
            (_ (apply i2c-start (map eval (rest-args))))
        )

        (if (not (i2c-detect-addr addr)) {
                (print (str-from-n addr "No response from 0x%X"))
                (return false)
        })

        (setassoc tca9534-regs 'addr addr)

        (tca9534-write-regs
            (list 1 (assoc tca9534-regs 'out0))
            (list 2 0)
            (list 3 (assoc tca9534-regs 'conf0))
        )
})

(defun tca9534-set-reg-bit (reg bit val)
    (setassoc tca9534-regs reg
        (bits-enc-int (assoc tca9534-regs reg) bit val 1)
))

(defun tca9534-set-dir () {
        (loopforeach i (rest-args) {
                (var pin (first i))
                (var dir (second i))

                (if (and (>= pin 0) (< pin 8)) {
                        (tca9534-set-reg-bit 'conf0 pin (if (eq dir 'out) 0 1))
                })
        })

        (tca9534-write-regs
            (list 3 (assoc tca9534-regs 'conf0))
        )
})

(defun tca9534-write-pins () {
        (loopforeach i (rest-args) {
                (var pin (first i))
                (var state (second i))

                (if (and (>= pin 0) (< pin 8)) {
                        (tca9534-set-reg-bit 'out0 pin state)
                })
        })

        (tca9534-write-regs
            (list 1 (assoc tca9534-regs 'out0))
        )
})

(defun tca9534-read-pins () {
        (var res (map (fn (x) nil) (rest-args)))

        (var reg0 (bufcreate 1))

        (i2c-tx-rx (assoc tca9534-regs 'addr) '(0) reg0)

        (looprange i 0 (length (rest-args)) {
                (var pin (rest-args i))

                (if (and (>= pin 0) (< pin 8)) {
                        (setix res i (bits-dec-int (bufget-u8 reg0 0) pin 1))
                })
        })

        (if (= (length (rest-args)) 1) (first res) res)
})
