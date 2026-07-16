;@const-symbol-strings
@const-start

(defun command-rx (data) {
    ; Route to Pubmote BLE RX handler
    (if (and (> (buflen data) 1) (= (bufget-u8 data 0) PUBMOTE_MAGIC)) {
        (pubmote-ble-rx data)
    })

    ; Route to Accessories QML command handler
    (if (and (> (buflen data) 1) (= (bufget-u8 data 0) FLOAT_ACCESSORIES_MAGIC)) {
        (float-accessories-command-rx data)
    })

    ; Route to VESC Float package telemetry handler
    (if (and (> (buflen data) 1) (= (bufget-u8 data 0) FLOAT_MAGIC)) {
        (float-pkg-telemetry-rx data)
    })
})

@const-end
