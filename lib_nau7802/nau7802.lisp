(def nau-i2c-addr 0x2A)

(def nau-reg-pu-ctrl '(
    0x00 ; Address
    1    ; Length
    (
    ; Name Offset Bits Value
    (RR    0 1 0) ; Register reset
    (PUD   1 1 0) ; Power up digital circuit
    (PUA   2 1 0) ; Power up analog circuit
    (PUR   3 1 0) ; Power up ready (read only)
    (CS    4 1 0) ; Cycle start (read only)
    (CR    5 1 0) ; Cycle ready (read only)
    (OSCS  6 1 0) ; System clock source select
    (AVDDS 7 1 0) ; AVDD source select
)))

(def nau-reg-ctrl1 '(
    0x01 ; Address
    1    ; Length
    (
    ; Name Offset Bits Value
    (GAINS    0 3 0) ; Gain select
    (VLDO     3 3 0) ; LDO voltage
    (DRDY-SEL 6 1 0) ; DRDY pin function
    (CRP      7 1 0) ; Conversion ready pin polarity
)))

(def nau-reg-ctrl2 '(
    0x02 ; Address
    1    ; Length
    (
    ; Name Offset Bits Value
    (CALMOD   0 2 0) ; Select calibration
    (CALS     2 1 0) ; Write 1 to start calibration
    (CAL-ERR  3 1 0) ; Calibration error (read only)
    (CRS      4 3 0) ; Conversion rate select
    (CHS      7 1 0) ; Analog input channel select
)))

(def nau-reg-ocal1 '(
    0x03 ; Address
    3    ; Length
    (
    ; Name Offset Bits Value
    (OFFSET 0 23 0) ; Offset
    (NEG    23 1 0) ; Is negative
)))

(def nau-reg-gcal1 '(
    0x06 ; Address
    4    ; Length
    (
    ; Name Offset Bits Value
    (gain 0 32 0) ; Gain
)))

(def nau-reg-ocal2 '(
    0x0A ; Address
    3    ; Length
    (
    ; Name Offset Bits Value
    (OFFSET 0 23 0) ; Offset
    (NEG    23 1 0) ; Is negative
)))

(def nau-reg-gcal2 '(
    0x0D ; Address
    4    ; Length
    (
    ; Name Offset Bits Value
    (gain 0 32 0) ; Gain
)))

(def nau-reg-i2c '(
    0x11 ; Address
    1    ; Length
    (
    ; Name Offset Bits Value
    (BGPCP    0 1 0) ; Disable bandgap chopper
    (TS       1 1 0) ; Switch PGA to temperature sensor
    (BOPGA    2 1 0) ; Enable burnout current source
    (SI       3 1 0) ; Short inputs, measure offset
    (WPD      4 1 0) ; Disable weak pull-up
    (SPE      5 1 0) ; Enable strong pull-up
    (FRD      6 1 0) ; Enable fast non-standard i2c
    (CRSD     7 1 0) ; Enable pull sda low on conversion complete
)))

(def nau-reg-adc '(
    0x12 ; Address
    3    ; Length
    (
    ; Name Offset Bits Value
    (ADC 0 24 0) ; ADC conversion result
)))

(def nau-reg-pga '(
    0x1B ; Address
    1    ; Length
    (
    ; Name Offset Bits Value
    (CHPDIS  0 1 0) ; Disable chopper
    (RES     1 1 0) ; Reserved
    (RES     2 1 0) ; Reserved
    (PGAINV  3 1 0) ; Invert input phase
    (BYPASS  4 1 0) ; Enable PGA bypass
    (OUTBUF  5 1 0) ; Enable output buffer
    (LDOMODE 6 1 0) ; Improve stability, lower gain
    (RD-SEL  7 1 0) ; 0: 0x15 reads adc, 1: 0x15 reads OTP
)))

(def nau-reg-pwr '(
    0x1C ; Address
    1    ; Length
    (
    ; Name Offset Bits Value
    (PGACURR 0 2 0) ; PGA current
    (ADCCURR 2 2 0) ; ADC current
    (BIAS    4 3 0) ; Bias current
    (CAPEN   7 1 0) ; Enable pga output cap
)))

(defun nau-reg-read (reg)
    (let (
        (addr (ix reg 0))
        (len (ix reg 1))
        (data (ix reg 2))
        (number 0u32)
        (buffer (array-create len))
        (buffer2 (array-create 4)))
        (progn
            (i2c-tx-rx nau-i2c-addr (list addr) buffer)
            (bufclear buffer2)
            (bufcpy buffer2 (- 4 len) buffer 0 len)
            (setvar 'number (bufget-u32 buffer2 0))
            (loopforeach i data
                (setix i 3 (bits-dec-int number (ix i 1) (ix i 2)))
            )
            t ; Return true
)))

(defun nau-reg-write (reg)
    (let (
        (addr (ix reg 0))
        (len (ix reg 1))
        (data (ix reg 2))
        (number 0u32)
        (buffer (array-create (+ len 1)))
        (buffer2 (array-create 4)))
        (progn
            (loopforeach i data
                (progn
                    (setvar 'number (bits-enc-int number (ix i 1) (ix i 3) (ix i 2)))
            ))
            (bufclear buffer2)
            (bufset-u32 buffer2 0 number)
            (bufset-u8 buffer 0 addr)
            (bufcpy buffer 1 buffer2 (- 4 len) len)
            (i2c-tx-rx nau-i2c-addr buffer)
            t ; Return true
)))

; Note: This function is very slow
(defun nau-pad-str (s n ch)
    (if (>= (str-len s) n)
        s
        (nau-pad-str (str-merge s ch) n ch)
))

(defun nau-reg-print (reg)
    (progn
        (print (str-from-n (ix reg 0) "Address  : 0x%02X"))
        (print (str-from-n (ix reg 1) "Length   : %d bytes"))
        (print "------FIELDS------")
        (loopforeach i (ix reg 2)
            (print (str-merge
                        (nau-pad-str (str-to-upper (sym2str (ix i 0))) 9 " ")
                        ": "
                        (str-from-n (ix i 3))
                        " (" (str-from-n (ix i 2)) " bit, offset " (str-from-n (ix i 1)) ")")
))))

(defun nau-reg-read-print (reg)
    (progn
        (nau-reg-read reg)
        (nau-reg-print reg)
))

(def nau-regs '(
    nau-reg-pu-ctrl
    nau-reg-ctrl1
    nau-reg-ctrl2
    nau-reg-ocal1
    nau-reg-gcal1
    nau-reg-ocal2
    nau-reg-gcal2
    nau-reg-i2c
    nau-reg-adc
    nau-reg-pga
    nau-reg-pwr
))

(defun nau-reg-read-print-all ()
    (loopforeach r nau-regs
        (progn
            (print (str-merge "Reg Name : " (sym2str r)))
            (nau-reg-read-print (eval r))
            (print " ")
)))

(defun nau-reg-update (reg field value)
    (loopforeach i (ix reg 2)
        (if (eq (ix i 0) field)
            (progn
                (setix i 3 value)
                (break t)
))))

(defun nau-reg-update-write (reg field value)
    (progn
        (nau-reg-update reg field value)
        (nau-reg-write reg)
))

(defun nau-init ()
    (progn
        (i2c-start)
        
        ; Reset sequence
        (nau-reg-update-write nau-reg-pu-ctrl 'RR 1)
        (sleep 0.001)
        (nau-reg-update-write nau-reg-pu-ctrl 'RR 0)
        (sleep 0.001)
        (nau-reg-update nau-reg-pu-ctrl 'PUD 1)
        (nau-reg-update nau-reg-pu-ctrl 'PUA 1)
        (nau-reg-write nau-reg-pu-ctrl)
        (sleep 0.001)
        
        ; Configuration
        (nau-reg-update-write nau-reg-pu-ctrl 'AVDDS 1)
        
        (nau-reg-update nau-reg-ctrl1 'GAINS 0) ; 1x gain
        (nau-reg-update nau-reg-ctrl1 'VLDO 5) ; 3.0V LDO
        (nau-reg-write nau-reg-ctrl1)
        
        (nau-reg-update-write nau-reg-ctrl2 'CRS 3) ; 80 SPS
))

(def adc-buf (array-create 3))
(def adc-buf2 (array-create 4))
(bufclear adc-buf2)

(defun nau-read-adc ()
    (progn
        (i2c-tx-rx nau-i2c-addr (list 0x12) adc-buf)
        (bufcpy adc-buf2 0 adc-buf 0 3)
        (/ (bufget-i32 adc-buf2 0) 2147483648.0)    
))
