# PN532 Driver

This is a i2c-driver for the PN532 NFC-controller. It requires firmware 6.05 or later and works on ESC and Express hardware. So far there is authentication, read and write support for MiFare Classic tags as well as read and write support for MiFare Ultralight tags.

The driver is tested with the Adafruit PN532-board which also has a good introduction to NFC and MiFare:

[https://cdn-learn.adafruit.com/downloads/pdf/adafruit-pn532-rfid-nfc.pdf](https://cdn-learn.adafruit.com/downloads/pdf/adafruit-pn532-rfid-nfc.pdf)

## Functions

### pn532-init

```clj
(pn532-init '(pins))
```

Initialize and start the driver on the i2c-pins pins. If the pins are nil (an empty list) the default pins will be used. Example:

```clj
(pn532-init nil) ; Initialize using default pins
(pn532-init '(3 2)) ; Initialize using pin 3 for SDA and 2 for SCL on the express firmware
(pn532-init '('pin-swdio 'pin-swclk)) ; Initialize using pin swdio for SDA and swclk for SCL on the ESC-firmware
```

The function return true if initialization was successful and false otherwise.

### pn532-read-fwversion

```clj
(pn532-read-fwversion)
```

Read the firmware version of the PN532 chip. Returns the firmware version as a list on success and nil otherwise.

### pn532-read-target-id

```clj
(pn532-read-target-id timeout)
```

Read the id of a tag. This functions blocks up to timeout seconds and returns the ID on success and nil of a timeout occurred. If the id has length 4 it is most likely a MiFare Classic tag and if it has length 7 it is most likely a MiFare Ultralight tag.

### pn532-authenticate-block

```clj
(pn532-authenticate-block uuid block keynum key)
```

Authenticate block on MiFare Classic tag. UUID is the id of the card, which is returned from pn532-read-target-id, block is the block number (0 to 63 for 1k cards), keynum is the key number (0 or 1) and key is the key (a list with 6 numbers from 0 to 255). This function returns true on success and false otherwise. Each sector which contains 4 blocks has to be authenticated before it can be read or written.

### pn532-mifareclassic-read-block

```clj
(pn532-mifareclassic-read-block block)
```

Read block from MiFare Classic tag. Returns a list of 16 bytes on success or nil on failure.

### pn532-mifareclassic-write-block

```clj
(pn532-mifareclassic-write-block block data)
```

Write data to block. Data must be a list with 16 numbers where each number is 0 to 255. Returns true on success and nil on failure.

### pn532-mifareul-read-page

```clj
(pn532-mifareul-read-page page)
```

Read page from MiFare Ultralight tag. Returns a list of 4 bytes on success or nil on failure.

### pn532-mifareul-write-page

```clj
(pn532-mifareul-write-page page data)
```

Write data to page. Data must be a list with 4 numbers where each number is 0 to 255. Returns true on success and nil on failure.

## Example

```clj
(import "pkg@://vesc_packages/lib_pn532/pn532.vescpkg" 'pn532)
(eval-program (read-program pn532))

(def is-esp false)

(def pins nil)
(if is-esp {
        (def pins '(3 2))
        (rgbled-init 8 1)
})

(defun led-on () (if is-esp (rgbled-color 0 0x00ff00)))
(defun led-off () (if is-esp (rgbled-color 0 0)))

(if (pn532-init pins)
    (loopwhile t {
            (var res (pn532-read-target-id 2))
            (if res {
                    (led-on)
                    (var uuid-len (first res))
                    (var uuid (second res))
                    (print " ")
                    (print (list "UUID:" uuid))
                    (cond
                        ((= uuid-len 4) {
                                (print "Most likely Mifare Classic")
                                (var block 21)
                                (print (list "Reading block" block))
                                (if (pn532-authenticate-block uuid block 0 '(0xff 0xff 0xff 0xff 0xff 0xff))
                                    {
                                        (print "Authentication OK!")
                                        (print (list "Data:" (pn532-mifareclassic-read-block block)))
                                    }
                                    (print "Authentication failed, most likely the wrong key")
                                )
                        })
                        ((= uuid-len 7) {
                                (print "Most likely Mifare Ultralight or NTAG")
                                (var page 4)
                                (print (list "Reading page" page))
                                (print (list "Data:" (pn532-mifareul-read-page page)))
                        })
                        (t (print (str-from-n uuid-len "No idea, UUID len: %d")))
                    )
                    
                    (led-off)
                    (sleep 1)
            })
    })
    (print "Init Failed")
)
```