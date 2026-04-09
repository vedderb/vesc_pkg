# TCA9534 Driver

This is a driver for the TCA9534 i2c IO-expander. You can use the following lines to import and load it in your script:

```clj
(import "pkg@://vesc_packages/lib_tca9534/tca9534.vescpkg" 'tca9534)
(read-eval-program tca9534)

(tca9534-init 0x20 'rate-100k 10 9)
```

## Example

```clj
(import "pkg@://vesc_packages/lib_tca9534/tca9534.vescpkg" 'tca9534)
(read-eval-program tca9534)
(tca9534-init 0x20 'rate-100k 10 9)

; Set pit 1 and 2 to outputs and pin 4 and 5 to inputs. This function
; takes an arbitrary number of arguments.
(tca9534-set-dir '(1 out) '(2 out) '(4 in) '(5 in))

; Write 1 to pin 1
(tca9534-write-pins '(1 1))

; Multiple pins can be written to at once with multiple arguments
(tca9534-write-pins '(1 1) '(2 0))

; Read pin5
(def in-10 (tca9534-read-pins 5))

; Multiple pins can be read, then a list with their values
; is returned
(def in-45 (tca9534-read-pins 4 5))

```
