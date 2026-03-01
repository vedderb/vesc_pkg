@const-start

(def bq27441-addr 0x55)

(defunret bq-init () {
        (apply i2c-start (rest-args))
})

(defun bq-read-word (addr) {
        (var data (bufcreate 2))
        (i2c-tx-rx bq27441-addr (list addr) data)
        (bufget-i16 data 0 'little-endian)
})

(defun bq-read-control-word (func) {
        (var tx (bufcreate 3))
        (var rx (bufcreate 2))
        (bufset-u8 tx 0 0)
        (bufset-u16 tx 1 func 'little-endian)
        (i2c-tx-rx bq27441-addr tx)
        (i2c-tx-rx bq27441-addr (list 0) rx)
        (bufget-i16 rx 0 'little-endian)
})

(defun bq-run-control-cmd (cmd) {
        (var tx (bufcreate 3))
        (bufset-u8 tx 0 0)
        (bufset-u16 tx 1 cmd 'little-endian)
        (i2c-tx-rx bq27441-addr tx)
})

(defun bq-set-cfgupdate (is-set) {
        (if is-set
            {
                (bq-run-control-cmd 0x13)
                (loopwhile (not (bq-is-cfgupdate)) {
                        (sleep 0.01)
                })
            }
            {
                (bq-run-control-cmd 0x43)
            }
        )
        (bq-is-cfgupdate)
})

(defun bq-set-sealed (sealed) {
        (if sealed
            {
                (bq-read-control-word 0x20)
            }
            {
                (bq-read-control-word 0x8000)
                (bq-read-control-word 0x8000)
            }
        )
})

(defun calc-block-checksum () {
        (var rx (bufcreate 32))
        (i2c-tx-rx bq27441-addr (list 0x40) rx)

        (var csum 0b)
        (looprange i 0 32 {
                (setq csum (+ csum (to-byte (bufget-u8 rx i))))
        })

        (- 255b csum)
})

(defun read-checksum () {
        (var rx (bufcreate 1))
        (i2c-tx-rx bq27441-addr (list 0x60) rx)
        (bufget-u8 rx 0)
})

(defun bq-write-extended (class-id offset data) {
        (i2c-tx-rx bq27441-addr (list 0x61 0)) ; enable block data memory control
        (i2c-tx-rx bq27441-addr (list 0x3E class-id))
        (i2c-tx-rx bq27441-addr (list 0x3F (/ offset 32)))
        (calc-block-checksum)
        (read-checksum)
        (looprange i 0 (buflen data) {
                (i2c-tx-rx bq27441-addr (list (+ 0x40 (mod offset 32) i) (bufget-u8 data i)))
        })
        (i2c-tx-rx bq27441-addr (list 0x60 (calc-block-checksum)))
})

(defun bq-set-capacity (mah) {
        (var tx (bufcreate 2))
        (bufset-u16 tx 0 mah)
        (bq-write-extended 82 10 tx)
})

(defun bq-set-energy (mwh) {
        (var tx (bufcreate 2))
        (bufset-u16 tx 0 mwh)
        (bq-write-extended 82 12 tx)
})

(defun bq-set-terminate-voltage (volts) {
        (var tx (bufcreate 2))
        (bufset-u16 tx 0 (to-u (* volts 1000.0)))
        (bq-write-extended 82 16 tx)
})

; Unit: 0.1h
(defun bq-set-taper-rate (rate) {
        (var tx (bufcreate 2))
        (bufset-u16 tx 0 rate)
        (bq-write-extended 82 27 tx)
})

(defun bq-soft-reset () (bq-run-control-cmd 0x42))

(defun bq-is-cfgupdate () (= (bits-dec-int (bq-flags) 4 1) 1))
(defun bq-is-sealed () (= (bits-dec-int (bq-status) 13 1) 1))

(defun bq-v () (* 0.001 (bq-read-word 0x04)))
(defun bq-i-avg () (* 0.001 (bq-read-word 0x10)))
(defun bq-i-stb () (* 0.001 (bq-read-word 0x12)))
(defun bq-i-max () (* 0.001 (bq-read-word 0x14)))
(defun bq-pwr-avg () (* 0.001 (bq-read-word 0x18)))
(defun bq-soc () (bq-read-word 0x1C))

(defun bq-soh () {
        (var data (bufcreate 2))
        (i2c-tx-rx bq27441-addr (list 0x20) data)
        (list (bufget-u8 data 0) (bufget-u8 data 1))
})

(defun bq-temp () (- (* 0.1 (bq-read-word 0x1E)) 273.15))
(defun bq-flags () (bq-read-word 0x06))
(defun bq-opconfig () (bq-read-word 0x3A))

(defun bq-cap-nom () (bq-read-word 0x08))
(defun bq-cap-full () (bq-read-word 0x0A))

(defun bq-devicetype () (bq-read-control-word 1))
(defun bq-status () (bq-read-control-word 0))
