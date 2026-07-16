;@const-symbol-strings
@const-start

(defun crypt (nonce-high nonce-low data start-offset len) {
    (var restore-byte (bufget-u8 counter 15))
    (bufset-u8 counter 0 nonce-high)
    (bufset-u8 counter 1 nonce-low)
    (aes-ctr-crypt key counter data start-offset len)
    (bufset-u8 counter 15 restore-byte)
})

(defunret checksum (data start-offset len) {
    (var sum 0)
    (looprange k start-offset len {
        (setq sum (+ sum (bufget-u8 data k)))
    })
    (return sum)
})

(defunret set-charge-state (nonce-high nonce-low charge-state) {
    (if (>= bms-charge-state 0){
        (def payload (bufcreate 2))
        (bufset-u8 payload 0 0x64)
        (bufset-u8 payload 1 (if (= charge-state 0x1) 0x00 0x01))
        (def packet (construct-packet nonce-high nonce-low payload))
        (free payload)
        (gpio-write bms-rs485-dere-pin 1)
        (uart-write packet)
        (sleep 0.005)
        (gpio-write bms-rs485-dere-pin 0)
        (sleep 0.005)
        (var ret (recv-packets 0x15 -1))
        (free packet)
        (return ret)
    }{
        (print "Haven't received current bms-charge-state yet")
        (return false)
    })
})

(defunret factory-init-accept () {
    (var init-payload2 (bufcreate 2))
    (bufset-u8 init-payload2 0 0x03)
    (bufset-u8 init-payload2 1 0x01)
    (def init-packet2 (construct-packet 0x00 0x01 init-payload2))
    (free init-payload2)
    (gpio-write bms-rs485-dere-pin 1)
    (uart-write init-packet2)
    (sleep 0.005)
    (gpio-write bms-rs485-dere-pin 0)
    (sleep 0.005)
    (var ret (recv-packets 0x0e 1))
    (free init-packet2)
    (return ret)
})

(defunret factory-init () {
    (var init-payload (bufcreate 4))
    (bufset-u8 init-payload 0 0x05)
    (bufset-u8 init-payload 1 0x52)
    (bufset-u8 init-payload 2 0x4d)
    (bufset-u8 init-payload 3 0x41);05RMA
    (def init-packet (construct-packet 0x00 0x01 init-payload))
    (free init-payload)
    (gpio-write bms-rs485-dere-pin 1)
    (uart-write init-packet)
    (sleep 0.005)
    (gpio-write bms-rs485-dere-pin 0)
    (sleep 0.005)
    (var ret (recv-packets 0x0e 0))
    (free init-packet)
    (return ret)
})
(defunret process-packet (data) {
    (if (!=(bufget-u8 data 2) (bufget-u8 magic 2)){
        (return false)
    })
    (var packet-checksum (bufget-u16 data (- (buflen data) 2)))
    (var calc-checksum (checksum data 0 (- (buflen data) 2)))
    (if (not-eq packet-checksum calc-checksum){
        (return false)
    })
    (if bms-use-crypto {
        (return (crypt (bufget-u8 data 3) (bufget-u8 data 4) data 5 (- (buflen data) 7)))
    })
    (return true)
})

(defunret construct-packet (nonce-high nonce-low payload) {
    (var packet (bufcreate (+ (buflen payload) 7)))
    (bufcpy packet 0 magic 0 (buflen magic))
    (bufset-u8 packet 3 nonce-high)
    (bufset-u8 packet 4 nonce-low)
    (crypt nonce-high nonce-low payload 0 (buflen payload))
    (bufcpy packet 5 payload 0 (buflen payload))
    (var calc-checksum  (checksum packet 0 (- (buflen packet) 2)))
    (bufset-u8 packet (+ (buflen payload) 5) (shr calc-checksum 8))
    (bufset-u8 packet (+ (buflen payload) 6) (bitwise-and calc-checksum 0xFF))
    (return packet)
})

(defun parse-voltage (data){
    ;(set-bms-val 'bms-v-tot (/ (bufget-u8 data (if bms-use-crypto 6 4)) 100.0))
    ;(print data)
})

(defun parse-cell-voltage (data){
    (var cell-index 0)
    (var total-voltage 0)
    (var v-cell-min (/ (bufget-u16 data (if bms-use-crypto 6 4)) (if bms-use-crypto 10000.0 1000.0)))
    (var v-cell-max v-cell-min)
    (if cell-count-uninit {
        (set-bms-val 'bms-cell-num (/ (- (buflen data) 8) 2))
        (setq cell-count-uninit false)
    })

    (looprange k (if bms-use-crypto 6 4) (- (buflen data) (+ (if bms-use-crypto 0 2) 3)) { ;Need to leave off end 16th cell for 15s BMS
        (if (eq (mod k 2) 0) {
            (var current-cell (/ (bufget-u16 data k) (if bms-use-crypto 10000.0 1000.0)))
            (if (and (= cell-index 0) (= bms-override-soc 1)) {
                (set-bms-val 'bms-soc (/ (estimate-soc current-cell voltage-curve) 100))
            })
            (set-bms-val 'bms-v-cell cell-index current-cell)
            (setq cell-index (+ cell-index 1))
            (setq total-voltage (+ total-voltage current-cell))
            (if (> current-cell v-cell-max) (setq v-cell-max current-cell))
            (if (< current-cell v-cell-min) (setq v-cell-min current-cell))
        })
    })
    (set-bms-val 'bms-v-tot total-voltage)
    (if (>= fw-num 6.06){
        (set-bms-val 'bms-v-cell-min v-cell-min)
        (set-bms-val 'bms-v-cell-max v-cell-max)
    })
})

(defun parse-soc (data){
    (if (= bms-override-soc 0) {
        (var soc (/ (bufget-u8 data (if bms-use-crypto 6 4)) 100.0))
        (if (> soc 1.0) (setq soc 1.0))
        (if (< soc 0.01) (setq soc 0.01))
        (set-bms-val 'bms-soc soc)
    })
})

(defun parse-current (data) {
    (var current-scaler (if bms-use-crypto 0.0366 0.055)); Current scaler. 0.0366 or 0.0378 not sure...
    ;maybe look at tot-current from controller and then calculate scaler and take average to see which is closer?
    (var current-limit (if bms-use-crypto 32.0 30.0)) ;Limit 32A or 32.7A, not sure.
    (var current (* (bufget-i16 data (if bms-use-crypto 6 4)) current-scaler))

    (if (and (not bms-charge-only) (>= current current-limit)) {
        (setq is-current-over-limit 1)
    }{
        (setq is-current-over-limit 0)
    })
    (set-bms-val 'bms-i-in-ic current)
})

(defun parse-status (data) {
    (setq bms-status (bufget-u8 data (if bms-use-crypto 6 4)))
    (setq is-charging (if (= (bitwise-and bms-status 0x20) 0) 0 1))
    (setq is-battery-empty (if (= (bitwise-and bms-status 0x4) 0) 0 1))
    (setq is-battery-temp-out-of-range (if (= (bitwise-and bms-status 0x3) 0) 0 1))
    (setq is-battery-overcharged (if (= (bitwise-and bms-status 0x8) 0) 0 1))
    (var is-soc-calculating (if (= (bitwise-and bms-status 0x40) 0) 0 1)) ;maybe or could be if balancing? Not sure cuz it came on while riding
    ;well also observed -128 but have no clue what that means
    (if (= is-charging 1) (if (<= (get-bms-val 'bms-i-in-ic) -0.5) (set-bms-val 'bms-v-charge (get-bms-val 'bms-v-tot) ) ) )
})

(defun parse-temp (data) {
    (set-bms-val 'bms-temp-ic (bufget-i8 data (- (buflen data) 3)))
    (var t-cell-max (bufget-i8 data (if bms-use-crypto 6 4)))
    (looprange k (if bms-use-crypto 6 4) (- (buflen data) 3) {
        (var temp-val (bufget-i8 data k))
        (if (> temp-val t-cell-max) (setq t-cell-max temp-val))
        (set-bms-val 'bms-temps-adc (- k (if bms-use-crypto 6 4)) temp-val)
    })
    (set-bms-val 'bms-temp-cell-max t-cell-max)
})

(defun parse-serial (data) {
    (setq serial (bufget-u16 data (if bms-use-crypto 6 4)))
})

(defun parse-charger (data) {
    (setq bms-charge-state (bufget-u8 data (if bms-use-crypto 6 4)))
})

(defun parse-battery-type (data) {
    ;(var battery-types '((UNDEFINED . 0) (A123_LiFePO4 . 1) (VTC6 . 1) (HG2 . 3) (30Q . 4) (VTC5A . 5) (VTC5D . 6) (30Q6 . 7) (P28A . 8) (VTC6A . 9) (P42A . 10) (40T3 . 11) ))
    (setq bms-battery-type (bufget-u8 data (if bms-use-crypto 6 4)))
})

(defun parse-cycles-health (data) {
    (setq bms-battery-cycles (bufget-u16 data (if bms-use-crypto 6 4)))
    ;TODO No way to set SoH in Lisp?
    (var soh (/ (bufget-u8 data (if bms-use-crypto 8 6)) 100.0))
    (if (> soh 1.0) (setq soh 1.0))
    (if (< soh 0.01) (setq soh 0.01))
    (set-bms-val 'bms-soh soh)
})

(defunret process-cmd (command data ack handshake) {
    (cond
        ((= command 0x00) {
            (parse-status data)
        })
        ;((= command 0x01) {
            ;(parse-voltage data);donno why this doesn't get emmited sometimes
        ;})
        ((= command 0x02) {
            (parse-cell-voltage data)
        })
        ((= command 0x03) {
            (parse-soc data)
        })
        ((= command 0x04) {
            (parse-temp data)
        })
        ((= command 0x05) {
            (parse-current data)
        })
        ((= command 0x06) {
            (parse-serial data)
        })
        ;((= command 0x07) { ; acknowleged as valid packet by controller but no processing ;Emitted by BMS
            ;static maybe these next bytes have to do with firmware build or hardware?
        ;})
        ((= command 0x08) {
            (parse-battery-type data)
        })
        ;((= command 0x09) { ;looked at by controller
        ;})
        ;((= command 0x0A) { ; acknowleged as valid packet by controller but no processing. Sent during bms startup?
        ;})
        ;((= command 0x0B) { ;Emitted by BMS
            ;static
        ;})
        ;((= command 0x0C) { ; acknowleged as valid packet by controller but no processing ;Emitted by BMS. Seems to be all 0 unless on charger.
        ;})
        ((= command 0x0D) {
            (parse-cycles-health data)
        })
        ((= command 0x0E) {
            (if ack {
                (if (= handshake 0) {
                ;(print "first ack");
                    (return (factory-init-accept))
                })
                (if (= handshake 1) {
                (print "second ack")
                    (if (!= (bufget-u16 data (if bms-use-crypto 6 4)) 1) { (return false)})
                    (send-msg "Success")
                    (return true)
                })

            })
        })
        ;((= command 0x0F) { ; Looked at by controller ;Emitted by BMS
        ;    ;error?
        ;})
        ;((= command 0x10) { ; looked at by controller ;Emitted by BMS
        ;    ;unknown maybe error code logs?
        ;})
        ;((= command 0x11) { ; looked at by controller
        ;})
        ;((= command 0x12) { ; acknowleged as valid packet by controller but no processing ;Emitted by BMS
        ;})
        ;((= command 0x13) { ;Emitted by BMS
        ;})
        ;((= command 0x14) { ;Emitted by BMS
        ;})
        ((= command 0x15) {
            (if (and ack (= (bufget-u8 data (if bms-use-crypto 6 4)) bms-charge-state)) {(parse-charger data) (return false)})
            (parse-charger data)
        })
        ;((= command 0x16) { ; looked at by controller ;Emitted by BMS
            ;unknown last byte changes
        ;})
        ;So in bms recv we know there's no valid commands above 0x16 (command 0x64 is special and gets sent from controller to BMS)
        ;((= command 0x64) { ;Sent by controller. Should be recieved by BMS and update 0x15
            ;bms-charge-state cmd
            ;(print "charge state cmd")
        ;})
        (t {
            ;(print (str-from-n command "Unknown Command: 0x%0x"))
            (return false)
        })
        )
    (return true)
})

(defun load-keys () {
    (var key-list (append (unpack-uint32-to-bytes (get-config 'bms-key-a)) (unpack-uint32-to-bytes (get-config 'bms-key-b)) (unpack-uint32-to-bytes (get-config 'bms-key-c)) (unpack-uint32-to-bytes (get-config 'bms-key-d))))
    (var counter-list (append (unpack-uint32-to-bytes (get-config 'bms-counter-a)) (unpack-uint32-to-bytes (get-config 'bms-counter-b)) (unpack-uint32-to-bytes (get-config 'bms-counter-c)) (unpack-uint32-to-bytes (get-config 'bms-counter-d))))
    (looprange i 0  (length key-list){
        (bufset-u8 key i (ix key-list i))
    })
    (looprange i 0  (length counter-list){
        (bufset-u8 counter i (ix counter-list i))
    })
})

(defunret verify-keys (key counter key-crc counter-crc) {
    (var key-crc-calc (crc32 key 0))
    (var counter-crc-calc (crc32 counter 0))
    (looprange i 0 (length key-crc) {
        (if (and (= (ix key-crc i) key-crc-calc) (= (ix counter-crc i) counter-crc-calc)) (return true))
    })
    (print key)
    (return false)
})

(defunret recv-packets (cmd-ack handshake) {
    (var read-timeout (if (= cmd-ack 0x0e)
        1.0  ; 1 second for factory init
        0.5)) ; 500ms for other commands like charge state
    (var bytes-read (uart-read bms-buf (buflen bms-buf) nil nil read-timeout))
    ;(print bms-buf)
    (var found-packet nil)
    (var start 0)
    (loopwhile (>= (- bytes-read start) (if bms-use-crypto 12 10)) {  ; Check against minimum packet size
        ; Look for magic bytes
        (if (and (= (bufget-u8 bms-buf start) (bufget-u8 magic 0))
                 (= (bufget-u8 bms-buf (+ start 1)) (bufget-u8 magic 1))
                 (= (bufget-u8 bms-buf (+ start 2)) (bufget-u8 magic 2))) {
            (setq bms-last-activity-time (systime)) ; Update after we see magic
            (setq found-packet t)
            ; Find the end of the packet (next magic bytes or end of buffer)
            (var packet-end start)
            (looprange j (+ start 3) (- bytes-read 2) {
                (if (and (= (bufget-u8 bms-buf j) (bufget-u8 magic 0))
                         (= (bufget-u8 bms-buf (+ j 1)) (bufget-u8 magic 1))
                         (= (bufget-u8 bms-buf (+ j 2)) (bufget-u8 magic 2))) {
                    (setq packet-end j)
                    (break)
                })
            })
            (if (= packet-end start) {
                (setq packet-end bytes-read) ; If no end found, process to end of buffer
            })

            ; Create a new buffer for the packet
            (var packet-length (- packet-end start))
            (var packet (bufcreate packet-length))
            (bufcpy packet 0 bms-buf start packet-length)
            ; Process the packet
            (if (process-packet packet) {
                (var command (bufget-u8 packet (if bms-use-crypto 5 3))) ; Adjust for crypto/non-crypto

                (print (str-from-n command "Command: %0x"))
                (if (and (>= cmd-ack 0) (= command cmd-ack)) {
                    (var result (process-cmd command packet t handshake))
                    (free packet)
                    (return result)
                })
                (process-cmd command packet nil -1)
            })
            (free packet)
            (setq start packet-end) ; Move start to the end of the processed packet
        } {
            (setq start (+ start 1)) ; Move to the next byte if magic bytes not found
        })
    })
    (if found-packet (send-bms-can))
    (return (< cmd-ack 0));if we're looking for an ack we failed to find one
})

(defunret init-bms () {
    (uart-stop)
    (sleep 1)
    (if bms-use-crypto{
        (if (< fw-num 6.06){
            (send-msg "hw-express needs to be running 6.06")
            (return false)
        })
        (load-keys)
        (if (eq (verify-keys key counter key-crc counter-crc) false){
            (send-msg "Invalid keys")
            (return false)
        } {

        })
        (if (= bms-rs485-chip 1){
            (if (or (< bms-rs485-di-pin 0) (not-eq (first (trap (gpio-configure bms-rs485-di-pin 'pin-mode-out))) 'exit-ok)){
                (send-msg "Invalid Pin: bms-rs485-di-pin")
                (return false)
            })
            (if (or (< bms-rs485-dere-pin 0) (not-eq (first (trap (gpio-configure bms-rs485-dere-pin 'pin-mode-out))) 'exit-ok)){
                (send-msg "Invalid Pin: bms-rs485-dere-pin")
                (return false)
            })
        (gpio-write bms-rs485-dere-pin 0); disable transit mode
        })
    })
    (if (>= bms-rs485-ro-pin 0){
        (var ret)
        (if (= bms-rs485-chip 1) {
            (setq ret (first (trap (gpio-configure bms-rs485-ro-pin 'pin-mode-in))))
        }{
            (setq ret (first (trap (gpio-configure bms-rs485-ro-pin 'pin-mode-in-pu))))
        })
        (if (not-eq ret 'exit-ok) {
            (send-msg "Invalid Pin: rs485-ro-pin")
            (return false)
        })
    }{
        (send-msg "Invalid Pin: rs485-ro-pin")
        (return false)
    })
    (if (and (= bms-charge-only 1) (>= bms-wakeup-pin 0)){
        (if (not-eq (first (trap (gpio-configure bms-wakeup-pin 'pin-mode-out))) 'exit-ok) {
            (send-msg "Invalid Pin: bms-wakeup-pin")
            (return false)
        })
        (gpio-write bms-wakeup-pin 0)
    })

    (uart-start 1 bms-rs485-ro-pin (if (= bms-rs485-chip 1) bms-rs485-di-pin -1) 115200);If GNSS is connected UART 1 must be used
    (set-bms-val 'bms-temp-adc-num 4)
    (bufset-u8 magic 2 (if bms-use-crypto 0xbb 0xaa))
    (yield 100000);Gotta make sure uart is ready
    ;now we're cookin'
    (return true)
})

(defun load-bms-settings (){
    (setq bms-rs485-di-pin (get-config 'bms-rs485-di-pin))
    (setq bms-rs485-ro-pin (get-config 'bms-rs485-ro-pin))
    (setq bms-rs485-dere-pin (get-config 'bms-rs485-dere-pin))
    (setq bms-wakeup-pin (get-config 'bms-wakeup-pin))
    (setq bms-override-soc (get-config 'bms-override-soc))
    (setq bms-type (get-config 'bms-type))
    (setq bms-use-crypto nil)
    (if (> bms-type 1) (setq bms-use-crypto t))
    (setq bms-rs485-chip (get-config 'bms-rs485-chip))
    (setq bms-loop-delay (get-config 'bms-loop-delay))
    (setq bms-charge-only (get-config 'bms-charge-only))
})

(defunret bms-loop () {
    (load-bms-settings)
    (if (and (> bms-type 0) (init-bms)) {

        (var next-run-time (secs-since 0))  ; Set first run time
        (var loop-start-time 0)
        (var loop-end-time 0)
        (def bms-buf (bufcreate (get-config 'bms-buff-size)))
        (var bms-loop-delay-sec (/ 1.0 bms-loop-delay))
        (loopwhile t{
        (setq loop-start-time (secs-since 0))

            (if bms-exit-flag {
                (break)
            })
            ;lets check if there's a user command
            (if (!= bms-user-cmd -1) {
                 (if (and (= bms-rs485-chip 1) bms-use-crypto (< (secs-since bms-last-activity-time) 1)) {
                    (loopwhile (not (if (= bms-user-cmd 0x0e) (factory-init) (set-charge-state 0x00 0x01 bms-charge-state))) {(sleep 0.01)})
                 }{
                    ;error
                    (send-msg "BMS not connected")
                 })
                 (setq bms-user-cmd -1)
            }{
                (recv-packets -1 -1)
            })
            (if (and (= bms-charge-only 1) (>= bms-wakeup-pin 0)) {
                (if (and (> (secs-since bms-last-activity-time) bms-timeout) (< (secs-since can-last-activity-time) 1) (not (running-state))) { ;also check can bus has fresh data and float pacakge state is not running just incase someone with discharge enabled configures the bms-wakeup-button for some reason.
                    (gpio-write bms-wakeup-pin 1)
                    (yield 10000)
                    (gpio-write bms-wakeup-pin 0)
                })
            })
            (setq loop-end-time (secs-since 0))
            (var actual-loop-time (- loop-end-time loop-start-time))

            (var time-to-wait (- next-run-time (secs-since 0)))
            (if (> time-to-wait 0) {
                (yield (* time-to-wait 1000000))
            }{
                (setq next-run-time (secs-since 0))
            })
            (setq next-run-time (+ next-run-time bms-loop-delay-sec))
        })
        (free bms-buf)
        (setq bms-exit-flag nil)
    })
})
@const-end