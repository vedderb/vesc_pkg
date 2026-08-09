(gpio-configure 3 'pin-mode-out) ; LED Blue
(gpio-configure 2 'pin-mode-out) ; LED Red

(print "scanning..")
(gpio-write 3 0)
(gpio-write 2 1)

(defun avl nil
    (progn
        (print "X1 available")
        (gpio-write 3 1)
        (gpio-write 2 0)
    )
)

(conf-set 'can-baud-rate 1)
(can-send-eid 0x00D431FF (list 0x14 0x78 0x00 0x00 0x00 0x00 0x00 0x00))
(if (can-scan) (avl)
    (progn
        (conf-set 'can-baud-rate 2)
        (can-send-eid 0x00D431FF (list 0x14 0x78 0x00 0x00 0x00 0x00 0x00 0x00))
        (if (can-scan) (avl)
            (progn
                (print "not found")
            )
        )
    )
)


