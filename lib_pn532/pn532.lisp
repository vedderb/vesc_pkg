(def pn532-addr 0x24)

(def bufadd-u8 (macro (buf ind num)
    `(bufset-u8 ,buf (- (setq ,ind (+ ,ind 1)) 1) ,num))
)

(defun pn532-cmd (cmd) {
        (setq cmd (cons 0xd4 cmd)) ; Prepend host-to-pn532
        (var cmdlen (length cmd))
        (var buffer (array-create (+ cmdlen 7)))
        (var ind 0)
        
        (bufadd-u8 buffer ind 0) ; Preamble
        (bufadd-u8 buffer ind 0) ; Startcode 1
        (bufadd-u8 buffer ind 0xFF) ; Startcode 2
        (bufadd-u8 buffer ind cmdlen)
        (bufadd-u8 buffer ind (+ (bitwise-not cmdlen) 1))
        
        (var sum 0)
        (loopforeach c cmd {
                (bufadd-u8 buffer ind c)
                (setq sum (+ sum c))
        })
        
        (bufadd-u8 buffer ind (+ (bitwise-not sum) 1)) ; Checksum
        (bufadd-u8 buffer ind 0) ; Postamble
        
        (i2c-tx-rx pn532-addr buffer)
        (free buffer)
})

(defun pn532-read (n) {
        (var rbuf (array-create (+ n 1)))
        (i2c-tx-rx pn532-addr nil rbuf)
        (var res (map (fn (x) (bufget-u8 rbuf x)) (range 1 (+ n 1))))
        (free rbuf)
        res
})

(def pn532-readybuf (array-create 1))
(defun pn532-isready () {
        (i2c-tx-rx pn532-addr nil pn532-readybuf)
        (= (bufget-u8 pn532-readybuf 0) 1)
})

(defun pn532-waitready (tout) {
        (var start (systime))
        (loopwhile t {
                (if (pn532-isready) (break true))
                (if (> (secs-since start) tout) (break false))
                (sleep 0.05)
        })
})

(defun pn532-readack () {
        (eq (pn532-read 6) '(0x00 0x00 0xff 0x00 0xff 0x00))
})

(defunret pn532-cmd-check-ack (cmd tout) {
        (pn532-cmd cmd)
        (sleep 0.001)
        (if (not (pn532-waitready tout)) (return false))
        (if (not (pn532-readack)) (return false))
        (sleep 0.001)
        (pn532-waitready tout)
})

(defun pn532-read-fwversion ()
    (if (pn532-cmd-check-ack '(0x02) 1) {
            (var data (pn532-read 13))
            (map (fn (x) (ix data x)) '(7 8 9 10))
    })
    false
)

; Configure Secure Access Module
(defun pn532-sam ()
    (if (pn532-cmd-check-ack '(0x14 0x01 0x14 0x01) 1) {
            (var data (pn532-read 9))
            (= (ix data 6) 0x15)
    })
    false
)

(defun pn532-read-target-id (tout)
    (if (pn532-cmd-check-ack '(0x4A 1 0) tout) {
            (var data (pn532-read 20))
            (var uuid-len (ix data 12))
            (var uuid (map (fn (x) (ix data x)) (range 13 (+ 13 uuid-len))))
            (list uuid-len uuid)
    })
    false
)

(defun pn532-authenticate-block (uuid block keynum key)
    (if (pn532-cmd-check-ack `(0x40 1 ,(if (= keynum 0) 0x60 0x61) ,block ,@key ,@uuid) 1) {
            (var data (pn532-read 12))
            (= (ix data 7) 0)
    })
    false
)

(defun pn532-mifareclassic-read-block (block)
    (if (pn532-cmd-check-ack `(0x40 1 0x30 ,block) 1) {
            (var data (pn532-read 26))
            (if (= (ix data 7) 0)
                (map (fn (x) (ix data x)) (range 8 24))
                false
            )
    })
    false
)

(defun pn532-mifareclassic-write-block (block data)
    (if (pn532-cmd-check-ack `(0x40 1 0xA0 ,block ,@data) 1) {
            (pn532-read 26)
            true
    })
    false
)

(defun pn532-mifareul-read-page (page)
    (if (pn532-cmd-check-ack `(0x40 1 0x30 ,page) 1) {
            (var data (pn532-read 26))
            (if (= (ix data 7) 0)
                (map (fn (x) (ix data x)) (range 8 12))
                false
            )
    })
    false
)

(defun pn532-mifareul-write-page (page data)
    (if (pn532-cmd-check-ack `(0x40 1 0xA2 ,page ,@data) 1) {
            (pn532-read 26)
            true
    })
    false
)

(defun pn532-init (pins) {
        (apply i2c-start (append '('rate-400k) pins))
        (i2c-tx-rx pn532-addr '(0)) ; Required on the ESP for some reason
        (pn532-sam)
})
