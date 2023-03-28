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