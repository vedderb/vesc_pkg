# TCA9535 Driver

This is a driver for the TCA9535 i2c IO-expander. You can use the following lines to import and load it in your script:

```clj
(import "pkg@://vesc_packages/lib_tca9535/tca9535.vescpkg" 'tca9535)
(read-eval-program tca9535)

(tca9535-init 0x20 'rate-100k 10 9)
```

## Example

```clj
(import "pkg@://vesc_packages/lib_tca9535/tca9535.vescpkg" 'tca9535)
(read-eval-program tca9535)
(tca9535-init 0x20 'rate-100k 10 9)

; Set pit 1 and 2 to outputs and pin 10 and 11 to inputs. This function
; takes an arbitrary number of arguments.
(tca9535-set-dir '(1 out) '(2 out) '(10 in) '(11 in))

; Write 1 to pin 1
(tca9535-write-pins '(1 1))

; Multiple pins can be written to at once with multiple arguments
(tca9535-write-pins '(1 1) '(2 0))

; Read pin10
(def in-10 (tca9535-read-pins 10))

; Multiple pins can be read, then a list with their values
; is returned
(def in-10 (tca9535-read-pins 10 11))

```
