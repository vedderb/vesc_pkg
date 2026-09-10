; Send a VESC command packet to another node over CAN.
;
; dash_esc reaches its own command processor through a native library, which a
; Lisp package cannot do for itself. Going out over CAN needs no such thing:
; FILL_RX_BUFFER followed by PROCESS_RX_BUFFER hands the packet to the target's
; command processor, which is the same path VESC Tool uses to configure a
; controller through a CAN bridge. So the display can drive a stock controller
; with nothing installed on it.

@const-start

(def can-packet-fill-rx-buffer 5)
(def can-packet-process-rx-buffer 7)

; Fill the target's receive buffer, then ask it to process what was sent.
;
; The offset byte is a u8, so this tops out at 255 bytes. A mode profile is 37,
; well inside that, and the long-offset variant is not worth carrying for it.
(defunret can-fwd-cmd (id payload) {
        (var len (buflen payload))
        (if (> len 255) (return nil))

        (var sent 0)
        (loopwhile (< sent len) {
                (var chunk (if (> (- len sent) 7) 7 (- len sent)))
                (var frame (bufcreate (+ chunk 1)))
                (bufset-u8 frame 0 sent)
                (looprange i 0 chunk
                    (bufset-u8 frame (+ i 1) (bufget-u8 payload (+ sent i)))
                )
                (can-send-eid
                    (bitwise-or (shl can-packet-fill-rx-buffer 8) id)
                    frame
                )
                (free frame)
                (setq sent (+ sent chunk))
        })

        ; [sender id][send mode][len hi][len lo][crc hi][crc lo]
        ; Send mode 0 means the reply, if any, goes back the way it came. The
        ; profile packet is sent with ack off, so nothing comes back.
        (var done (bufcreate 6))
        (var crc (crc16 payload))
        (bufset-u8 done 0 255)
        (bufset-u8 done 1 0)
        (bufset-u16 done 2 len)
        (bufset-u16 done 4 crc)
        (can-send-eid
            (bitwise-or (shl can-packet-process-rx-buffer 8) id)
            done
        )
        (free done)
        true
})

; Apply a drive profile to a stock controller over CAN.
;
; This is COMM_SET_MCCONF_TEMP_SETUP, the same packet dash_esc builds locally.
; The setup variant takes speed in m/s and lets the controller convert using
; its own wheel diameter, gearing and pole count, so the display never needs
; to know any of that. Getting those wrong is what makes an ERPM-based speed
; limit silently do nothing.
;
; Store is off, so everything here lives in RAM and a power cycle undoes it.
;
; The duty and watt fields have to carry something, and the display has no way
; to read what the controller currently uses. They are sent as the values in
; config.lisp, which default to non-limiting.
(defun set-profile-can (id i-min i-max s-min s-max) {
        (var txb (bufcreate 37))
        (bufset-u8 txb 0 49) ; COMM_SET_MCCONF_TEMP_SETUP
        (bufset-u8 txb 1 0) ; Store
        (bufset-u8 txb 2 1) ; Forward to CAN
        (bufset-u8 txb 3 0) ; Ack
        (bufset-u8 txb 4 0) ; Divide by controllers
        (bufset-f32 txb 5 i-min)
        (bufset-f32 txb 9 i-max)
        (bufset-f32 txb 13 s-min)
        (bufset-f32 txb 17 s-max)
        (bufset-f32 txb 21 config-sa-duty-min)
        (bufset-f32 txb 25 config-sa-duty-max)
        (bufset-f32 txb 29 config-sa-watt-min)
        (bufset-f32 txb 33 config-sa-watt-max)

        (var ok (can-fwd-cmd id txb))
        (free txb)
        ok
})
