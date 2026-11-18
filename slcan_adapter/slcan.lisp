;; Copyright 2026 Joel Svensson
;;
;; This file is part of the VESC Package slcan Adapter.
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;; slcan Adapter
;;
;; Coded with help from Claude model claude-opus-5-5
;;
;; Turns a VESC Express based device (for example the Nanolog) into a
;; serial-line CAN adapter speaking the Lawicel / slcan ASCII protocol
;; on a UART. On Linux the UART (through a USB-serial adapter) is
;; attached to SocketCAN with slcand:
;;
;;   slcand -o -c -s6 -S 921600 /dev/ttyUSB0 can0
;;   ip link set up can0
;;
;; Supported commands: O L C Sn t T V N F Z0 M m X
;;  O  - Open
;;  L  - Open (Listen only)
;;  C  - Close
;;  Sn - set bitrate
;;  t  - Send standard frame
;;  T  - Send extended frame
;;  V  - Version
;;  N  - Serial Number
;;  F  - Status Flags
;;  Z0 - Timestamps off
;;  M  - No effect
;;  m  - No effect
;;  X  - No effect
;; Not supported (answered with BELL): r R (remote frames), sxxyy
;; (custom bit timing), S7 (800 kbit/s) and Z1 (timestamps).

;;; ------------------------------------------------------------------
;;; Configuration
;;; ------------------------------------------------------------------

; Nanolog: UART pins 20 (RX) and 21 (TX).
(def uart-num 1)
(def uart-rx-pin 20)
(def uart-tx-pin 21)
(def uart-baud 921600)

; The device is still a normal VESC that you can reach over CAN.
(def use-vesc-decoder t)

;;; ------------------------------------------------------------------
;;; State and buffers
;;; ------------------------------------------------------------------

(def is-open nil)
(def listen-only nil)

(def line-max 32)
(def line-buf (bufcreate line-max))

;; One buffer per size of frame pre allocated.
;; Will end up in the image if the image is saved, then restored
;; on the image boot.
(def sid-out (map (fn (n) (bufcreate (+ 6 (* 2 n)))) (range 9)))
(def eid-out (map (fn (n) (bufcreate (+ 11 (* 2 n)))) (range 9)))

; Payload buffers for frames to transmit, indexed by dlc. dlc 0 is
; sent as the empty list.
(def tx-data (map (fn (n) (if (= n 0) nil (bufcreate n))) (range 9)))

@const-start

;;; ------------------------------------------------------------------
;;; Constants
;;; ------------------------------------------------------------------

(def char-cr 13)
(def char-lf 10)
(def char-bell 7)

; Replies are byte lists rather than strings, as strings carry a
; terminating zero that uart-write would send.
(def reply-cr      '(13))
(def reply-bell    '(7))
(def reply-sid-ok  '(122 13))             ; z\r
(def reply-eid-ok  '(90 13))              ; Z\r
(def reply-version '(86 49 48 49 51 13))  ; V1013\r
(def reply-serial  '(78 86 69 83 67 13))  ; NVESC\r
(def reply-status  '(70 48 48 13))        ; F00\r

; slcan S0..S8 to the CAN_BAUD enum used by conf 'can-baud-rate.
; S7 (800 kbit/s) has no counterpart.
;            10k 20k 50k 100k 125k 250k 500k 800k 1M
(def bitrates '(4  5   6   8    0    1    2    -1   3))

;;; ------------------------------------------------------------------
;;; Hex helpers
;;; ------------------------------------------------------------------

(defun hex-val (c)
  (cond ((and (>= c 48) (<= c 57)) (- c 48))   ; 0-9
        ((and (>= c 65) (<= c 70)) (- c 55))   ; A-F
        ((and (>= c 97) (<= c 102)) (- c 87))  ; a-f
        (t -1)))

(defun hex-char (d)
  (if (< d 10) (+ d 48) (+ d 55)))

; Parse n hex digits from buf at pos. Returns a u32, or nil if a
; character is not a hex digit. u32 since extended ids do not fit
; in a 28 bit fixnum on 32 bit platforms.
(defun parse-hex (buf pos n)
  (let ((acc 0u32)
        (ok t))
    (progn
      (looprange i 0 n
        (let ((d (hex-val (bufget-u8 buf (+ pos i)))))
          (if (< d 0)
              (setq ok nil)
            (setq acc (+ (* acc 16u32) d)))))
      (if ok acc nil))))

; Write val as ndig hex digits, most significant first, into buf at pos.
(defun put-hex (buf pos val ndig)
  (looprange i 0 ndig
    (bufset-u8 buf (+ pos i)
               (hex-char (bitwise-and (shr val (* 4 (- ndig i 1))) 0xF)))))

;;; ------------------------------------------------------------------
;;; CAN -> UART
;;; ------------------------------------------------------------------

(defun send-frame (ext id data)
  (let ((dlc (buflen data))
        (id-len (if ext 8 3))
        (buf (ix (if ext eid-out sid-out) dlc)))
    (progn
      (bufset-u8 buf 0 (if ext 84 116)) ; T or t
      (put-hex buf 1 id id-len)
      (bufset-u8 buf (+ 1 id-len) (hex-char dlc))
      (looprange i 0 dlc
        (put-hex buf (+ 2 id-len (* 2 i)) (bufget-u8 data i) 2))
      (bufset-u8 buf (+ 2 id-len (* 2 dlc)) char-cr)
      (uart-write buf))))

(defun event-handler ()
  (loopwhile t
    (recv
     ((event-can-sid . ((? id) . (? data))) (if is-open (send-frame nil id data)))
     ((event-can-eid . ((? id) . (? data))) (if is-open (send-frame t id data)))
     (_ nil))))

;;; ------------------------------------------------------------------
;;; UART -> CAN: commands
;;; ------------------------------------------------------------------

; Each command gets the line buffer, the index s of the command
; character and the line length len (excluding the terminating CR).

; tiiiLdd... / TiiiiiiiiLdd...
(defun cmd-transmit (line s len ext)
  (let ((id-len (if ext 8 3))
        (dlc (if (> len (+ id-len 1))
                 (hex-val (bufget-u8 line (+ s id-len 1)))
               -1)))
    (if (or (not is-open) listen-only
            (< dlc 0) (> dlc 8)
            (not (= len (+ 2 id-len (* 2 dlc)))))
        (uart-write reply-bell)
      (let ((id (parse-hex line (+ s 1) id-len)))
        (if (or (eq id nil)
                (> id (if ext 0x1FFFFFFFu32 0x7FFu32)))
            (uart-write reply-bell)
          (let ((data (ix tx-data dlc))
                (ok t))
            (progn
              (looprange i 0 dlc
                (let ((b (parse-hex line (+ s id-len 2 (* 2 i)) 2)))
                  (if (eq b nil)
                      (setq ok nil)
                    (bufset-u8 data i b))))
              (if (not ok)
                  (uart-write reply-bell)
                (progn
                  (if ext (can-send-eid id data) (can-send-sid id data))
                  (uart-write (if ext reply-eid-ok reply-sid-ok)))))))))))

; Sn
(defun cmd-bitrate (line s len)
  (if (or is-open (not (= len 2)))
      (uart-write reply-bell)
    (let ((n (hex-val (bufget-u8 line (+ s 1)))))
      (if (or (< n 0) (> n 8) (< (ix bitrates n) 0))
          (uart-write reply-bell)
        (progn
          ; Only changes the running config, it is not stored.
          (conf-set 'can-baud-rate (ix bitrates n))
          (uart-write reply-cr))))))

; O and L
(defun cmd-open (lo)
  (if is-open
      (uart-write reply-bell)
    (progn
      (setq listen-only lo)
      (setq is-open t)
      (uart-write reply-cr))))

; C. Closing an already closed channel is accepted; slcand sends C
; before configuring the bitrate.
(defun cmd-close ()
  (progn
    (setq is-open nil)
    (setq listen-only nil)
    (uart-write reply-cr)))

; Zn. Timestamps are not supported, only Z0 is accepted.
(defun cmd-timestamp (line s len)
  (if (and (not is-open) (= len 2) (= (bufget-u8 line (+ s 1)) 48))
      (uart-write reply-cr)
    (uart-write reply-bell)))

; end is the index of the terminating CR. A leading LF, left over from
; a CR LF line ending, is skipped.
(defun handle-line (line end)
  (let ((s (if (and (> end 0) (= (bufget-u8 line 0) char-lf)) 1 0))
        (len (- end s)))
    (if (= len 0)
        (uart-write reply-cr)
      (let ((c (bufget-u8 line s)))
        (cond
         ((= c 116) (cmd-transmit line s len nil))  ; t
         ((= c 84)  (cmd-transmit line s len t))    ; T
         ((= c 79)  (cmd-open nil))                 ; O
         ((= c 76)  (cmd-open t))                   ; L
         ((= c 67)  (cmd-close))                    ; C
         ((= c 83)  (cmd-bitrate line s len))       ; S
         ((= c 86)  (uart-write reply-version))     ; V
         ((= c 78)  (uart-write reply-serial))      ; N
         ((= c 70)  (uart-write reply-status))      ; F
         ((= c 90)  (cmd-timestamp line s len))     ; Z
         ; Acceptance code/mask and auto poll: accepted, no effect.
         ((or (= c 77) (= c 109) (= c 88)) (uart-write reply-cr)) ; M m X
         (t (uart-write reply-bell)))))))

;;; ------------------------------------------------------------------
;;; UART -> CAN: line reader
;;; ------------------------------------------------------------------

; uart-read returns when a CR arrives, the buffer is full, or no byte
; has arrived within the timeout. Partial lines are kept across calls.
; Over-long lines are answered with one BELL and discarded up to the
; next CR.
(defun uart-reader ()
  (let ((pos 0)
        (discard nil))
    (loopwhile t
      (progn
        (setq pos (+ pos (uart-read line-buf (- line-max pos) pos char-cr 1.0)))
        (cond
         ((and (> pos 0) (= (bufget-u8 line-buf (- pos 1)) char-cr))
          (progn
            (if (not discard) (handle-line line-buf (- pos 1)))
            (setq pos 0)
            (setq discard nil)))
         ((>= pos line-max)
          (progn
            (if (not discard) (uart-write reply-bell))
            (setq pos 0)
            (setq discard t))))))))

;;; ------------------------------------------------------------------
;;; Start
;;; ------------------------------------------------------------------

(defun main ()
  (progn
    (uart-start uart-num uart-rx-pin uart-tx-pin uart-baud)
    (can-use-vesc use-vesc-decoder)
    (event-register-handler (spawn event-handler))
    (event-enable 'event-can-sid)
    (event-enable 'event-can-eid)
    (spawn uart-reader)))

@const-end

;;(image-save) ;; if you want to
(main)
