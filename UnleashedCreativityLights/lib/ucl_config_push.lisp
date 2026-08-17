;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; UCL_CONFIG_PUSH (chunked, CRC’d, versioned)
;;
;; Goal:
;;  - Master is source of truth for settings
;;  - Master pushes settings to slaves (boot + on change + on new peer)
;;  - Slave validates (mark/ver + CRC16), applies runtime config, writes EEPROM,
;;    then ACKs master (optional but strongly recommended).
;;
;; Transport constraints:
;;  - Keep each CAN payload <= 64 bytes (your existing safe cap)
;;  - Chunk large configs across multiple UCL_CONFIG_PUSH frames
;;
;; Wire format (each CAN frame):
;;  [0]  FLOAT_ACCESSORIES_MAGIC (102)
;;  [1]  UCL_CONFIG_PUSH (cmd id)
;;  [2]  UCL_CFG_MARK (0x55)
;;  [3]  UCL_CFG_VER  (1)
;;  [4]  src_id (can-local-id of sender)
;;  [5]  flags (bit0=FIRST, bit1=LAST)
;;  [6..7] total_len (u16)   ; total bytes of config payload
;;  [8..9] offset    (u16)   ; offset of this chunk into payload
;;  [10..11] crc16   (u16)   ; CRC of *entire* payload (same on every chunk)
;;  [12] chunk_len (u8)      ; bytes in this chunk
;;  [13..] chunk bytes
;;
;; Config payload format (TLV):
;;  Repeated entries:
;;    [id:u8][type:u8][len:u8][value...]
;;
;; Types:
;;  0 = i32 (len=4)
;;  1 = u8  (len=1)
;;  2 = f32 (len=4)
;;  3 = bool (len=1, 0/1)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; 1) Add ACK command (optional but useful)
;; Extend your command table:
;; (def float-accessories-cmds '((...)(UCL_CONFIG_ACK . 13)))

(def UCL_CFG_MARK 0x55)
(def UCL_CFG_VER  2)
(def UCL_CFG_HDR_LEN 13)

(def UCL_CFG_F_FIRST 0x01)
(def UCL_CFG_F_LAST  0x02)

(def UCL_T_I32  0)
(def UCL_T_U8   1)
(def UCL_T_F32  2)
(def UCL_T_BOOL 3)

(def ucl-cfg-seq 0)

(defunret ucl-is-accessory-frame (data) {
  (and (> (buflen data) 1)
       (= (bufget-u8 data 0) FLOAT_ACCESSORIES_MAGIC))
})

(defun ucl-send-accessory (payload can-if target-id) {
  (send-data payload can-if target-id)
})

(def ucl-config-spec '(
  ;; addr 3..75 (minus anything you choose to exclude)
  (3  reserved-slot-3           UCL_T_BOOL)
  (4  led-enabled               UCL_T_BOOL)
  (5  reserved-slot-5               UCL_T_BOOL)
  (6  led-on                    UCL_T_BOOL)
  (7  led-highbeam-on           UCL_T_BOOL)
  (8  led-mode                  UCL_T_I32)
  (9  led-mode-idle             UCL_T_I32)
  (10 led-mode-status           UCL_T_I32)
  (12 led-mall-grab-enabled     UCL_T_BOOL)
  (13 led-brake-light-enabled   UCL_T_BOOL)
  (14 led-brake-light-min-amps  UCL_T_F32)
  (15 idle-timeout              UCL_T_I32)
  (16 idle-timeout-shutoff      UCL_T_I32)
  (17 led-brightness            UCL_T_F32)
  (18 led-brightness-highbeam   UCL_T_F32)
  (19 led-brightness-idle       UCL_T_F32)
  (20 led-brightness-status     UCL_T_F32)
  (21 led-status-pin            UCL_T_I32)
  (22 led-status-num            UCL_T_I32)
  (23 led-status-type           UCL_T_I32)
  (24 led-status-reversed       UCL_T_BOOL)
  (25 led-front-pin             UCL_T_I32)
  (26 led-front-num             UCL_T_I32)
  (27 led-front-type            UCL_T_I32)
  (28 led-front-reversed        UCL_T_BOOL)
  (29 led-front-strip-type      UCL_T_BOOL)
  (30 led-rear-pin              UCL_T_I32)
  (31 led-rear-num              UCL_T_I32)
  (32 led-rear-type             UCL_T_I32)
  (33 led-rear-reversed         UCL_T_BOOL)
  (34 led-rear-strip-type       UCL_T_BOOL)
  (35 reserved-slot-35      UCL_T_I32)
  (36 reserved-slot-36      UCL_T_I32)
  (37 reserved-slot-37       UCL_T_I32)   ; optional: include/exclude
  (38 reserved-slot-38          UCL_T_I32)
  (39 reserved-slot-39          UCL_T_I32)
  (40 reserved-slot-40        UCL_T_I32)
  (41 reserved-slot-41            UCL_T_I32)
  (42 reserved-slot-42          UCL_T_I32)
  (43 reserved-slot-43            UCL_T_BOOL)
  (44 reserved-slot-44                 UCL_T_I32)   ; optional: include/exclude
  (45 reserved-slot-45                 UCL_T_I32)
  (46 reserved-slot-46                 UCL_T_I32)
  (47 reserved-slot-47                 UCL_T_I32)
  (48 reserved-slot-48             UCL_T_I32)
  (49 reserved-slot-49             UCL_T_I32)
  (50 reserved-slot-50             UCL_T_I32)
  (51 reserved-slot-51             UCL_T_I32)
  (52 led-loop-delay            UCL_T_I32)
  (53 reserved-slot-53            UCL_T_I32)
  (54 can-loop-delay            UCL_T_I32)
  (55 led-max-blend-count       UCL_T_I32)
  (57 led-dim-on-highbeam-ratio UCL_T_F32)
  (58 reserved-slot-58                  UCL_T_I32)
  (59 led-status-strip-type     UCL_T_I32)
  (60 reserved-slot-60           UCL_T_BOOL)
  (61 led-fix                   UCL_T_I32)
  (62 led-show-battery-charging UCL_T_BOOL)
  (63 led-front-highbeam-pin    UCL_T_I32)
  (64 led-rear-highbeam-pin     UCL_T_I32)
  (65 reserved-slot-65             UCL_T_I32)
  (66 led-max-brightness        UCL_T_F32)
  (67 soc-type                  UCL_T_I32)
  (68 cell-type                 UCL_T_I32)
  (69 led-update-not-running    UCL_T_BOOL)
  (70 reserved-slot-70          UCL_T_BOOL)
  (71 series-cells              UCL_T_I32)
  (72 reserved-slot-72          UCL_T_I32)
  (73 front-target-id           UCL_T_I32)
  (74 rear-target-id            UCL_T_I32)
  (75 status-target-id          UCL_T_I32)
))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; CRC16-CCITT (0x1021), init 0xFFFF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun ucl-crc16-step (crc byte) {
  (var c (bitwise-xor crc (shl (bitwise-and byte 0xFF) 8)))
  (var i 0)
  (loopwhile (< i 8) {
    (if (not-eq 0 (bitwise-and c 0x8000)) {
      (setq c (bitwise-xor (shl c 1) 0x1021))
    } {
      (setq c (shl c 1))
    })
    (setq c (bitwise-and c 0xFFFF))
    (setq i (+ i 1))
  })
  c
})

(defun ucl-crc16 (buf len) {
  (var crc 0xFFFF)
  (var i 0)
  (loopwhile (< i len) {
    (setq crc (bitwise-xor crc (bufget-u8 buf i)))
    (var b 0)
    (loopwhile (< b 8) {
      (if (not-eq 0 (bitwise-and crc 1)) {
        (setq crc (bitwise-xor (shr crc 1) 0xA001))
      } {
        (setq crc (shr crc 1))
      })
      (setq b (+ b 1))
    })
    (setq i (+ i 1))
  })
  crc
})

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; TLV builder / parser
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun ucl-tlv-write (out idx id type val) {
  (bufset-u8 out idx (to-byte id))         (setq idx (+ idx 1))
  (bufset-u8 out idx (to-byte type))       (setq idx (+ idx 1))

  (cond
    ((eq type UCL_T_I32) {
      (bufset-u8 out idx 4)                (setq idx (+ idx 1))
      (bufset-i32 out idx val)             (setq idx (+ idx 4))
    })
    ((eq type UCL_T_U8) {
      (bufset-u8 out idx 1)                (setq idx (+ idx 1))
      (bufset-u8 out idx (to-byte val))    (setq idx (+ idx 1))
    })
    ((eq type UCL_T_F32) {
      (bufset-u8 out idx 4)                (setq idx (+ idx 1))
      (bufset-f32 out idx val)             (setq idx (+ idx 4))
    })
    ((eq type UCL_T_BOOL) {
      (bufset-u8 out idx 1)                (setq idx (+ idx 1))
      (bufset-u8 out idx (if val 1 0))     (setq idx (+ idx 1))
    })
    (true {
      ;; unknown type: write zero-len entry (skip)
      (bufset-u8 out idx 0)                (setq idx (+ idx 1))
    })
  )
  idx
})

(defun ucl-config-push-eligible (name) {
  (and (not-eq name 'magic)
       (not-eq name 'crc)
       (not-eq name 'reserved-slot-3)
       (not-eq name 'led-mode-startup)
       (not-eq name 'led-startup-timeout)
       (not-eq name 'reserved-slot-5)
       (not-eq name 'reserved-slot-38)
       (not-eq name 'reserved-slot-39)
       (not-eq name 'reserved-slot-40)
       (not-eq name 'reserved-slot-41)
       (not-eq name 'reserved-slot-42)
       (not-eq name 'reserved-slot-43)
       (not-eq name 'reserved-slot-44)
       (not-eq name 'reserved-slot-45)
       (not-eq name 'reserved-slot-46)
       (not-eq name 'reserved-slot-47)
       (not-eq name 'reserved-slot-48)
       (not-eq name 'reserved-slot-49)
       (not-eq name 'reserved-slot-50)
       (not-eq name 'reserved-slot-51)
       (not-eq name 'reserved-slot-53)
       (not-eq name 'reserved-slot-58)
       (not-eq name 'reserved-slot-60)
       (not-eq name 'reserved-slot-65)
       (not-eq name 'led-show-battery-charging)
       (not-eq name 'reserved-slot-70)
       (not-eq name 'reserved-slot-72)
       (not-eq name 'node-role)
       (not-eq name 'master-can-id)
       (not-eq name 'peers-cache))
})

(defun ucl-config-pack () {
  ; Pack raw values in the SAME ORDER as eeprom-addrs (excluding magic/crc).
  ; Receiver must unpack using the same eeprom-addrs list.

  (var total 0)

  ; 1) compute total length
  (loopforeach setting eeprom-addrs {
    (var name (car setting))
    (var meta (second setting))      ; (addr type default)
    (var typ    (ix meta 1))

    (if (ucl-config-push-eligible name) {
      (cond
        ((eq typ 'b) { (setq total (+ total 1)) })
        ((eq typ 'i) { (setq total (+ total 4)) })
        ((eq typ 'f) { (setq total (+ total 4)) })
        (true     { (setq total (+ total 4)) })
      )
    })
  })

  (var out (bufcreate total))
  (var off 0)

  ; 2) write values
  (loopforeach setting eeprom-addrs {
    (var name (car setting))
    (var meta (second setting))
    (var typ    (ix meta 1))

    (if (ucl-config-push-eligible name) {
      (cond
        ((eq typ 'b) {
          (bufset-u8 out off (to-byte (get-config name)))
          (setq off (+ off 1))
        })
        ((eq typ 'i) {
          (bufset-i32 out off (get-config name))
          (setq off (+ off 4))
        })
        ((eq typ 'f) {
          (bufset-f32 out off (to-float (get-config name)))
          (setq off (+ off 4))
        })
        (true {
          (bufset-i32 out off (get-config name))
          (setq off (+ off 4))
        })
      )
    })
  })

  out
})

(defun ucl-config-apply (buf) {
  ; Unpack buf (created by ucl-config-pack) into runtime config.
  ; NOTE: does not write EEPROM here - caller decides.

  (var off 0)
  (var n   (buflen buf))

  (loopforeach setting eeprom-addrs {
    (var name (car setting))
    (var meta (second setting))
    (var typ    (ix meta 1))

    (if (ucl-config-push-eligible name) {

      (cond
        ((eq typ 'b) {
          (if (<= (+ off 1) n) {
            (set-config name (bufget-u8 buf off))
          })
          (setq off (+ off 1))
        })

        ((eq typ 'i) {
          (if (<= (+ off 4) n) {
            (set-config name (bufget-i32 buf off))
          })
          (setq off (+ off 4))
        })

        ((eq typ 'f) {
          (if (<= (+ off 4) n) {
            (set-config name (bufget-f32 buf off))
          })
          (setq off (+ off 4))
        })

        (true {
          (if (<= (+ off 4) n) {
            (set-config name (bufget-i32 buf off))
          })
          (setq off (+ off 4))
        })
      )
    })
  })
})

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Master: send config to one slave (chunked)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun ucl-config-send-to (target-id) {
  (if (not-eq target-id (can-local-id)) {
    (var payload (ucl-config-pack))
    (var total (buflen payload))
    (var crc (ucl-crc16 payload total))

    ;; bump sequence (optional; not on wire in this draft)
    (setq ucl-cfg-seq (+ ucl-cfg-seq 1))

    (var off 0)
    (loopwhile (< off total) {
      ;; max chunk that keeps frame <= 64 bytes
      ;; header is 13 bytes before chunk bytes
      (var max-chunk 40)
      (var clen (min max-chunk (- total off)))

      (var flags 0)
      (if (= off 0) (setq flags (bitwise-or flags 0x01))) ; FIRST
      (if (= (+ off clen) total) (setq flags (bitwise-or flags 0x02))) ; LAST

      (var out (bufcreate (+ 13 clen)))
      (bufset-u8  out 0 FLOAT_ACCESSORIES_MAGIC)
      (bufset-u8  out 1 (assoc float-accessories-cmds 'UCL_CONFIG_PUSH))
      (bufset-u8  out 2 UCL_CFG_MARK)
      (bufset-u8  out 3 UCL_CFG_VER)
      (bufset-u8  out 4 (to-byte (can-local-id)))
      (bufset-u8  out 5 (to-byte flags))
      (bufset-u16 out 6 total)
      (bufset-u16 out 8 off)
      (bufset-u16 out 10 crc)
      (bufset-u8  out 12 (to-byte clen))
      (bufcpy out 13 payload off clen)

      (ucl-send-accessory out 2 target-id)
      (free out)

      (setq off (+ off clen))
      ;; tiny yield helps avoid burst-lockstep on busy buses
      (yield 8000) ; 8ms
    })

    (free payload)
  })
})

(defun ucl-config-broadcast-to-peers () {
  (if (= ucl-effective-role 0) {
    (ucl-cfg-start-sync-all)
  })
})

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Slave: receive accumulator + commit/apply
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(def ucl-cfg-rx-from 255)
(def ucl-cfg-rx-total 0)
(def ucl-cfg-rx-crc 0)
(def ucl-cfg-rx-buf nil)
(def ucl-cfg-rx-got 0)
(def ucl-cfg-rx-last-time 0)
(def ucl-cfg-rx-timeout 1.5)

(defun ucl-cfg-rx-reset () {
  (if (not-eq ucl-cfg-rx-buf nil) {
    (free ucl-cfg-rx-buf)
    (setq ucl-cfg-rx-buf nil)
  })
  (setq ucl-cfg-rx-total 0)
  (setq ucl-cfg-rx-crc 0)
  (setq ucl-cfg-rx-got 0)
  (setq ucl-cfg-rx-from 255)
  (setq ucl-cfg-rx-last-time 0)
})

(def ucl-cfg-tx-last 0)
(def ucl-cfg-tx-interval 2.0) ; only when needed
(def ucl-cfg-tx-buf nil)
(def ucl-cfg-tx-crc 0)
(def ucl-cfg-retry-max 4)         ; total send attempts per peer
(def ucl-cfg-retry-base 0.4)      ; seconds
(def ucl-cfg-retry-max-delay 4.0) ; seconds
(def ucl-cfg-pending '())         ; (peer-id attempt due-time)

(defunret ucl-cfg-peer-live (peer-id) {
  (var live nil)
  (loopforeach p ucl-peers {
    (if (= (ix p 0) peer-id) { (setq live t) })
  })
  live
})

(defunret ucl-cfg-peer-role (peer-id) {
  (var role -1)
  (loopforeach p ucl-peers {
    (if (= (ix p 0) peer-id) { (setq role (ix p 1)) })
  })
  role
})

(defunret ucl-cfg-next-delay (attempt) {
  (var d ucl-cfg-retry-base)
  (var i 1)
  (loopwhile (< i attempt) {
    (setq d (* d 2.0))
    (setq i (+ i 1))
  })
  (if (> d ucl-cfg-retry-max-delay) { (setq d ucl-cfg-retry-max-delay) })
  d
})

(defun ucl-cfg-pending-upsert (peer-id attempt due-time) {
  (var out '())
  (var found nil)
  (loopforeach e ucl-cfg-pending {
    (if (= (ix e 0) peer-id) {
      (setq out (cons (list peer-id attempt due-time) out))
      (setq found t)
    } {
      (setq out (cons e out))
    })
  })
  (if (not found) {
    (setq out (cons (list peer-id attempt due-time) out))
  })
  (setq ucl-cfg-pending (reverse out))
})

(defun ucl-cfg-pending-remove (peer-id) {
  (var out '())
  (loopforeach e ucl-cfg-pending {
    (if (not-eq (ix e 0) peer-id) {
      (setq out (cons e out))
    })
  })
  (setq ucl-cfg-pending (reverse out))
})

(defunret ucl-cfg-pending-get (peer-id) {
  (var found nil)
  (loopforeach e ucl-cfg-pending {
    (if (= (ix e 0) peer-id) { (setq found e) })
  })
  found
})

(defun ucl-cfg-pending-touch-now (peer-id) {
  (var e (ucl-cfg-pending-get peer-id))
  (if (not-eq e nil) {
    (ucl-cfg-pending-upsert peer-id (ix e 1) (secs-since 0))
  })
})

(defun ucl-cfg-send-attempt (peer-id attempt) {
  (if (and (not-eq peer-id (can-local-id))
           (ucl-cfg-peer-live peer-id)) {
    (ucl-config-send-to peer-id)
    (var due (+ (secs-since 0) (ucl-cfg-next-delay attempt)))
    (ucl-cfg-pending-upsert peer-id attempt due)
  })
})

(defun ucl-cfg-start-sync-all () {
  (setq ucl-cfg-pending '())
  (loopforeach p ucl-peers {
    (ucl-cfg-send-attempt (ix p 0) 1)
  })
})

(defun ucl-config-send-to-tracked (peer-id) {
  (ucl-cfg-send-attempt peer-id 1)
})

(defun ucl-config-push-step () {
  (if (= ucl-effective-role 0) {
    (if (and ucl-cfg-dirty
             (> (length ucl-peers) 0)) {
      (setq ucl-cfg-dirty nil)
      (ucl-cfg-start-sync-all)
    })

    (if (> (length ucl-cfg-pending) 0) {
      (var now (secs-since 0))
      (var pending-now ucl-cfg-pending)
      (setq ucl-cfg-pending '())

      (loopforeach e pending-now {
        (var pid (ix e 0))
        (var attempt (ix e 1))
        (var due (ix e 2))

        (if (ucl-cfg-peer-live pid) {
          (if (>= now due) {
            (if (>= attempt ucl-cfg-retry-max) {
              (ucl-log (str-merge "push timeout peer=" (str-from-n pid "%d")))
            } {
              (ucl-cfg-send-attempt pid (+ attempt 1))
            })
          } {
            (setq ucl-cfg-pending (cons e ucl-cfg-pending))
          })
        })
      })

      (setq ucl-cfg-pending (reverse ucl-cfg-pending))
    })
  })
})

(defun ucl-config-ack (dest ok) {
  ;; Optional ACK (define UCL_CONFIG_ACK in your cmd table)
  (var b (bufcreate 6))
  (bufset-u8 b 0 FLOAT_ACCESSORIES_MAGIC)
  (bufset-u8 b 1 (assoc float-accessories-cmds 'UCL_CONFIG_ACK))
  (bufset-u8 b 2 UCL_CFG_MARK)
  (bufset-u8 b 3 UCL_CFG_VER)
  (bufset-u8 b 4 (to-byte (can-local-id)))
  (bufset-u8 b 5 (if ok 1 0))
  (ucl-send-accessory b 2 dest)
  (free b)
})

(defun ucl-config-handle-ack (data) {
  (if (and (ucl-is-accessory-frame data)
           (>= (buflen data) 6)
           (= (bufget-u8 data 2) UCL_CFG_MARK)
           (= (bufget-u8 data 3) UCL_CFG_VER)) {
    (var src (bufget-u8 data 4))
    (var ok (bufget-u8 data 5))
    (if (= ok 1) {
      (ucl-cfg-pending-remove src)
      (ucl-log (str-merge "ack ok from " (str-from-n src "%d")))
    } {
      (ucl-cfg-pending-touch-now src)
      (ucl-log (str-merge "ack fail from " (str-from-n src "%d")))
    })
  })
})

(defun ucl-config-push-to (peer-id) {
  (ucl-config-send-to peer-id)
})

(defun ucl-log (s) { nil })

(defun ucl-config-handle-push (data) {

  ;; data is full FLOAT_ACCESSORIES_MAGIC frame

  (if (and (ucl-is-accessory-frame data)
           (>= (buflen data) 13)
           (= (bufget-u8 data 2) UCL_CFG_MARK)
           (= (bufget-u8 data 3) UCL_CFG_VER)) {

    ; Drop stale partial assembly if sender stopped mid-transfer.
    (if (and (not-eq ucl-cfg-rx-buf nil)
             (> (- (secs-since 0) ucl-cfg-rx-last-time) ucl-cfg-rx-timeout)) {
      (ucl-cfg-rx-reset)
    })

    (var src   (bufget-u8 data 4))
    (var flags (bufget-u8 data 5))
    (var total (bufget-u16 data 6))
    (var off   (bufget-u16 data 8))
    (var crc   (bufget-u16 data 10))
    (var clen  (bufget-u8 data 12))

    (var cfg-master (get-config 'master-can-id))
    (var src-role (ucl-cfg-peer-role src))
    (var source-ok (or (and (>= cfg-master 0) (= src cfg-master))
                       (and (< cfg-master 0) (= src-role 0))))
    (if (and (<= clen 64)
             (>= (buflen data) (+ 13 clen))
             (> total 0)
             (<= total 2048)
             source-ok) {

      ;; Reset on FIRST flag or if sender/total/crc changed
        (if (or (not-eq 0 (bitwise-and flags 0x01))
              (not-eq src ucl-cfg-rx-from)
              (not-eq total ucl-cfg-rx-total)
              (not-eq crc ucl-cfg-rx-crc)) {

        (ucl-cfg-rx-reset)
        (setq ucl-cfg-rx-from src)
        (ucl-log (str-merge "start src=" (str-from-n src "%d ")))
        (setq ucl-cfg-rx-total total)
        (setq ucl-cfg-rx-crc crc)
        (setq ucl-cfg-rx-buf (bufcreate total))
        (setq ucl-cfg-rx-got 0)
      })

      ;; Bounds check before copy
      (if (and (not-eq ucl-cfg-rx-buf nil)
               (<= (+ off clen) ucl-cfg-rx-total)) {

        ;; Copy chunk into reassembly buffer
        (bufcpy ucl-cfg-rx-buf off data 13 clen)
        (setq ucl-cfg-rx-last-time (secs-since 0))

        ;; If LAST flag set, validate and apply
        (if (not-eq 0 (bitwise-and flags 0x02)) {

          (var gotcrc (ucl-crc16 ucl-cfg-rx-buf ucl-cfg-rx-total))
          (if (= gotcrc ucl-cfg-rx-crc) {

            ;; Apply runtime config
            (ucl-config-apply ucl-cfg-rx-buf)

            ;; Apply through normal runtime path, but do not emit a local
            ;; send-config frame from the slave. That can hijack the master UI
            ;; when VESC Tool is attached to the master node.
            (setq ucl-suppress-send-config t)
            (var apply-r (trap (apply-config-from-runtime)))
            (setq ucl-suppress-send-config nil)

            (if (eq (first apply-r) 'exit-ok) {
              (ucl-config-ack src t)
            } {
              (ucl-log "apply failed")
              (ucl-config-ack src nil)
            })

          } {

            (print "[UCL] CONFIG_PUSH CRC mismatch; ignoring")
            (ucl-config-ack src nil)
          })

          (ucl-cfg-rx-reset)
        })
      })
    } {
      (if (not source-ok) {
        (ucl-log (str-merge "reject push src=" (str-from-n src "%d")
                            " cfg-master=" (str-from-n cfg-master "%d")
                            " peer-role=" (str-from-n src-role "%d")))
      })
    })
  })
})

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Hook points
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; A) In your FLOAT_ACCESSORIES_MAGIC handler:
;;   add:
;;     (UCL_CONFIG_PUSH { (if (= ucl-effective-role 1) (ucl-config-handle-push data)) })
;;     (UCL_CONFIG_ACK  { ... optional debug/telemetry on master ... })

;; B) When to send from master:
;;  - On boot after peers appear + after refloat connected (or after a short delay)
;;  - On *UI Save* (call ucl-config-broadcast-to-peers)
;;  - On “new peer discovered” inside UCL_ANNOUNCE rx (master side):
;;      if prev=nil then (ucl-config-send-to sender-id)

;; Example “new peer discovered” addition (master side, in UCL_ANNOUNCE handler):
;; (if (and (= ucl-effective-role 0) (eq prev nil)) { (ucl-config-send-to sender-id) })

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; IMPORTANT POLICY NOTES (so you don’t brick yourself elegantly)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; - Do NOT push node-role or can-local-id; those are device identity/local policy.
;; - master-can-id is runtime UI convenience; generally don’t EEPROM it on slaves.
;; - Keep total payload <= 2048 unless you *really* need more.
;; - If you want “master proves it’s master”, add ucl-boot-nonce + elected master id
;;   into the push header and have slaves reject pushes from non-master senders.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
