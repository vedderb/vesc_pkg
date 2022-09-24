# NAU7802 Driver

This is a driver for the NAU7802 24-bit ADC. You can use the following lines to import and load it in your script:

```clj
(import "pkg@://vesc_packages/lib_nau7802/nau7802.vescpkg" 'nau7802)
(eval-program (read-program nau7802))
(nau-init)
```

Now you can read the ADC with

```clj
(nau-read-adc)
```

By default the init-function sets the PGA-gain to 1.0, the LDO to 3.0V and the conversion rate to 80 Hz. You can change all register values from the datasheet with this driver too. For example, to change the sample rate you can use

```clj
(nau-reg-update-write nau-reg-ctrl2 'CRS 7) ; 320 SPS
```

You can read and list all register values from the repl with

```clj
(nau-reg-read-print-all)
```

That will print all register names and their current values in the following format:

```
Reg Name : nau-reg-pu-ctrl
Address  : 0x00
Length   : 1 bytes
------FIELDS------
RR       : 0 (1 bit, offset 0)
PUD      : 1 (1 bit, offset 1)
PUA      : 1 (1 bit, offset 2)
PUR      : 1 (1 bit, offset 3)
CS       : 0 (1 bit, offset 4)
CR       : 1 (1 bit, offset 5)
OSCS     : 0 (1 bit, offset 6)
AVDDS    : 1 (1 bit, offset 7)
 
Reg Name : nau-reg-ctrl1
Address  : 0x01
Length   : 1 bytes
------FIELDS------
GAINS    : 0 (3 bit, offset 0)
VLDO     : 5 (3 bit, offset 3)
DRDY-SEL : 0 (1 bit, offset 6)
CRP      : 0 (1 bit, offset 7)
 
Reg Name : nau-reg-ctrl2
Address  : 0x02
Length   : 1 bytes
------FIELDS------
CALMOD   : 0 (2 bit, offset 0)
CALS     : 0 (1 bit, offset 2)
CAL-ERR  : 0 (1 bit, offset 3)
CRS      : 3 (3 bit, offset 4)
CHS      : 0 (1 bit, offset 7)
 
Reg Name : nau-reg-ocal1
Address  : 0x03
Length   : 3 bytes
------FIELDS------
OFFSET   : 0 (23 bit, offset 0)
NEG      : 0 (1 bit, offset 23)
 
Reg Name : nau-reg-gcal1
Address  : 0x06
Length   : 4 bytes
------FIELDS------
GAIN     : 8388608 (32 bit, offset 0)
 
Reg Name : nau-reg-ocal2
Address  : 0x0A
Length   : 3 bytes
------FIELDS------
OFFSET   : 0 (23 bit, offset 0)
NEG      : 0 (1 bit, offset 23)
 
Reg Name : nau-reg-gcal2
Address  : 0x0D
Length   : 4 bytes
------FIELDS------
GAIN     : 8388608 (32 bit, offset 0)
 
Reg Name : nau-reg-i2c
Address  : 0x11
Length   : 1 bytes
------FIELDS------
BGPCP    : 0 (1 bit, offset 0)
TS       : 0 (1 bit, offset 1)
BOPGA    : 0 (1 bit, offset 2)
SI       : 0 (1 bit, offset 3)
WPD      : 0 (1 bit, offset 4)
SPE      : 0 (1 bit, offset 5)
FRD      : 0 (1 bit, offset 6)
CRSD     : 0 (1 bit, offset 7)
 
Reg Name : nau-reg-adc
Address  : 0x12
Length   : 3 bytes
------FIELDS------
ADC      : 16768606 (24 bit, offset 0)
 
Reg Name : nau-reg-pga
Address  : 0x1B
Length   : 1 bytes
------FIELDS------
CHPDIS   : 0 (1 bit, offset 0)
RES      : 0 (1 bit, offset 1)
RES      : 0 (1 bit, offset 2)
PGAINV   : 0 (1 bit, offset 3)
BYPASS   : 0 (1 bit, offset 4)
OUTBUF   : 0 (1 bit, offset 5)
LDOMODE  : 0 (1 bit, offset 6)
RD-SEL   : 0 (1 bit, offset 7)
 
Reg Name : nau-reg-pwr
Address  : 0x1C
Length   : 1 bytes
------FIELDS------
PGACURR  : 0 (2 bit, offset 0)
ADCCURR  : 0 (2 bit, offset 2)
BIAS     : 0 (3 bit, offset 4)
CAPEN    : 0 (1 bit, offset 7)
```

The function

```clj
(nau-reg-update-write register field value)
```

can be used to change any value of any of the registers above. Note that the field name is a symbol, you you must use a single quote on it (e.g. 'BIAS)

## Example

The following example imports the driver, loads it and reads the ADC at 100 Hz to a binding that shows up in the binding table. You can click on it and go to the plot to see the voltage in real-time if poll status is active in VESC Tool.

```clj
(import "pkg@://vesc_packages/lib_nau7802/nau7802.vescpkg" 'nau7802)
(eval-program (read-program nau7802))
(nau-init)

(loopwhile t
    (progn
        (def adc (nau-read-adc))
        (sleep 0.01)
))
```