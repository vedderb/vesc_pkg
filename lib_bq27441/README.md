# BQ27441 Driver

This is a driver for the BQ27441 i2c battery fuel gauge. You can use the following lines to import and load it in your script:

```clj
(import "pkg@://vesc_packages/lib_bq27441/bq27441.vescpkg" 'bq27441)
(read-eval-program bq27441)

(bq27441-init 0x20 'rate-100k 10 9)
```

## Example

```clj
(import "pkg@://vesc_packages/lib_bq27441/bq27441.vescpkg" 'bq27441)
(read-eval-program bq27441)

; i2c-rate 100k, pin7 is SDA, pin8 is SCL
(bq-init 'rate-100k 7 8)

(defun bq-config () {
        (bq-set-sealed false) ; Make sure that device is not sealed
        (bq-set-cfgupdate t) ; Enter configuration update mode
        (bq-set-capacity 4500) ; 4500 mAh capacity
        (bq-set-energy (* 4500 3.7)) ; 4500 * 3.7 mWh energy
        (bq-set-terminate-voltage 3.0) ; 3.0 V is 0% SOC
        (bq-soft-reset) ; Reset after applying configuration
})

; Apply configuration
(bq-config)

; Print cell voltage in volts
(print (bq-v))

; Print current now in A
(print (bq-i-avg))

; Print standby current in A (not quite sure how this is calculated...)
(print (bq-i-stb))

; Print maximum current A
(print (bq-i-max))

; Print power now W
(print (bq-pwr-avg))

; Print SOC in %
(print (bq-soc))

; Print SOH. Returns (soh-percent status) where status can be 1, 2 or 3.
; Status 3 means that the estimation is done.
(print (bq-soh))

; Print chip temperature in degC
(print (bq-temp))

; Print flags register
(print (bq-flags))

; Print opconfig register
(print (bq-opconfig))

; Print capacity left in mAh
(print (bq-cap-nom))

; Print capacity when full in mAh
(print (bq-cap-full))

; Print device type register. Should be 1057
(print (bq-devicetype))

; Print status register
(print (bq-status))

; Print t if device is in sealed stat, nil if not
; Sealed means that a set of registers are locked
; so that they can't be changed by accident
(print (bq-is-sealed))

; Print t if configuration update is enabled, nil if it is not
(print (bq-is-cfgupdate))

; Seal device
(bq-set-sealed true)

; Unseal device
(bq-set-sealed false)
```
