; =========================
; can.lisp (MINIMAL HEAP SAFE)
; =========================
; - No ucl-get-peer-ids
; - No peer signature/debug string builders
; - No peer-find
; - No wrapper functions
; - Keeps: announce, scan, peer upsert/prune, discovery, forwarding, float-command-rx
; =========================

;@const-symbol-strings
@const-start

; --- essential globals used here (others can live in other files) ---
(def can-loop-delay)
(def can-id -1)
(def refloat-can-id -1)

(def discover-running nil)
(def discover-pref-id -1)
(def discover-init-time 0)
(def discover-next-scan-time 0)
(def discover-scan-interval 0.05)
(def discover-max-id 253)
(def discover-ping-next-id 0)
(def discover-inflight-id -1)
(def discover-inflight-time 0)
(def discover-inflight-timeout 0.12)
(def discover-pass-probed 0)
(def discover-pass-budget 254)
(def discover-retry-delay 5.0)
(def discover-next-retry-time 0)
(def discover-last-log-time 0)
(def discover-log-interval 0.5)
(def refloat-quiet-grace 15.0)
(def refloat-stable-since 0)
(def refloat-poll-interval 0.75)
(def refloat-last-poll-time 0)
(def refloat-last-poll-log-time 0)
(def refloat-poll-log-interval 5.0)
(def refloat-last-rx-time 0)
(def refloat-rx-loss-timeout 30.0)
(def refloat-boot-verify-active nil)
(def refloat-boot-verify-id -1)
(def refloat-boot-verify-deadline 0)
(def refloat-boot-verify-timeout 30.0)


(def FLOAT_MAGIC 101)
(def FLOAT_ACCESSORIES_MAGIC 102)


(def refloat-lights-seen nil)
(def last-refloat-lights-flags -1)

(def float-cmds '(
  (COMMAND_GET_INFO . 0)
  (COMMAND_GET_ALLDATA . 10)
  (COMMAND_LIGHTS_CONTROL . 20)
  (COMMAND_REALTIME_DATA . 31)
))

(def float-accessories-cmds '(
  (COMMAND_GET_INFO . 0)
  (COMMAND_RUN_LISP . 1)

  (UCL_ANNOUNCE . 10)
  (UCL_CONFIG_PUSH . 11)
  (UCL_REFLOAT_FWD . 12)
  (UCL_CONFIG_ACK . 13)
))

(def ucl-peers '())              ; (canid role masterid lastseen)
(def ucl-boot-time 0)
(def ucl-boot-nonce 0)

(def ucl-last-peer-scan-time 0)
(def ucl-peer-scan-interval 0.5)
(def ucl-scan-next-id 0)
(def ucl-scan-chunk 8)
(def ucl-peer-scan-stable-hold 30.0)

(def ucl-last-peer-poke 0)
(def ucl-peer-poke-interval 2.0)

(def ucl-effective-role 1)       ; 0 master, 1 slave
(def ucl-effective-master -1)
(def ucl-role-ready nil)
(def can-last-effective-role 1)
; LED watchdog: lets CAN recover LED loop if image restore leaves it stalled.
(def led-watchdog-timeout 2.5)
(def led-watchdog-restart-cooldown 5.0)
(def led-watchdog-last-restart 0.0)
(def led-watchdog-arm-time 0.0)
(def can-loop-last-now 0.0)

(def ucl-conflict-detected nil)

(def ucl-last-announce-time 0)
(def ucl-announce-interval 3.0)

; forward cache (keep, but lean)
(def ucl-last-refloat-alldata nil)
(def ucl-last-refloat-lights nil)
(def ucl-fwd-refresh-last 0)
(def ucl-fwd-refresh-interval 0.5)
(def ucl-fwd-source-freshness 2.0)
(def ucl-last-refloat-alldata-rx 0)
(def ucl-last-refloat-lights-rx 0)
(def ucl-last-refloat-alldata-fwd 0)
(def ucl-last-refloat-lights-fwd 0)

(def ucl-fwd-seq-alldata 0)
(def ucl-fwd-seq-lights 0)
(def ucl-fwd-last-alldata 0)
(def ucl-fwd-last-lights 0)

(def ucl-fwd-rx-last-time 0)
(def ucl-fwd-rx-last-alldata 0)
(def ucl-fwd-rx-last-lights 0)
(def ucl-fwd-rx-count 0)
(def ucl-fwd-rx-log-time 0)

(def UCL_FWD_MARK 0x55)
(def UCL_FWD_VER  3)

; ---- external functions expected in other files ----
; ucl-config-send-to
; ucl-config-handle-push
; ucl-config-handle-ack
; ucl-config-push-step
; (and constants UCL_CFG_MARK, UCL_CFG_VER if ack is used)

(defun ucl-election-step () {
  (var role-marker (to-i (get-config 'reserved-slot-5)))
  (var r (to-i (get-config 'node-role)))
  (if (or (= role-marker 2) (= role-marker 3)) {
    (setq r (if (= role-marker 3) 0 1))
  } {
    (if (and (!= r 0) (!= r 1)) {
      (setq r 1)
    })
  })

  (if (= r 0) {
    (setq ucl-effective-role 0)
    (setq ucl-effective-master (can-local-id))
  } {
    (setq ucl-effective-role 1)
    (setq ucl-effective-master (get-config 'master-can-id))
  })
})

(defun ucl-peer-upsert (cid role masterid) {
  (var now (secs-since 0))
  (var updated nil)
  (var out '())

  (loopforeach p ucl-peers {
    (if (= (ix p 0) cid) {
      (setq out (cons (list cid role masterid now) out))
      (setq updated t)
    } {
      (setq out (cons p out))
    })
  })

  (if (not updated) {
    (setq out (cons (list cid role masterid now) out))
  })

  (setq ucl-peers (reverse out))
  (not updated)
})

(defun ucl-peer-prune () {
  (var now (secs-since 0))
  (var out '())
  (loopforeach p ucl-peers {
    (if (< (- now (ix p 3)) 20.0) { (setq out (cons p out)) })
  })
  (setq ucl-peers (reverse out))
})

(defun ucl-send-get-info (target-id) {
  (var b (bufcreate 5))
  (bufset-u8 b 0 FLOAT_ACCESSORIES_MAGIC)
  (bufset-u8 b 1 (assoc float-accessories-cmds 'COMMAND_GET_INFO))
  (bufset-u8 b 2 0x55)
  (bufset-u8 b 3 2)
  (bufset-u8 b 4 (to-byte (can-local-id)))
  (send-data b 2 target-id)
  (free b)
})

(defun ucl-scan-step () {
  (var now (secs-since 0))
  (if (>= now (+ ucl-last-peer-scan-time ucl-peer-scan-interval)) {
    (setq ucl-last-peer-scan-time now)

    (var refloat-likely (get-config 'can-id))
    (var count 0)

    (loopwhile (and (< count ucl-scan-chunk) (<= ucl-scan-next-id 253)) {
      (var pid (to-byte ucl-scan-next-id))

      (if (and (not-eq pid (can-local-id))
               (not-eq pid refloat-likely)
               (or (< refloat-can-id 0) (not-eq pid refloat-can-id))) {
        (if (can-ping pid) { (ucl-send-get-info pid) })
      })

      (setq ucl-scan-next-id (+ ucl-scan-next-id 1))
      (setq count (+ count 1))
    })

    (if (> ucl-scan-next-id 253) (setq ucl-scan-next-id 0))
    (ucl-peer-prune)
  })
})

(defun ucl-announce-self () {
  (var now (secs-since 0))
  (if (>= now (+ ucl-last-announce-time ucl-announce-interval)) {
    (setq ucl-last-announce-time now)

    (var reply (bufcreate 10))
    (bufset-u8 reply 0 FLOAT_ACCESSORIES_MAGIC)
    (bufset-u8 reply 1 (assoc float-accessories-cmds 'UCL_ANNOUNCE))
    (bufset-u8 reply 2 0x55)
    (bufset-u8 reply 3 2)

    (bufset-u8 reply 4 (to-byte (can-local-id)))
    (bufset-u8 reply 5 (to-byte ucl-effective-role))

    (var mid (get-config 'master-can-id))
    (bufset-u8 reply 6 (to-byte (if (< mid 0) 255 mid)))

    (bufset-u16 reply 7 ucl-boot-nonce)
    (bufset-u8 reply 9 0)

    (send-data reply) ; local UI
    (free reply)
  })
})

(defun ucl-send-announce (target-id) {
  (var reply (bufcreate 10))
  (bufset-u8 reply 0 FLOAT_ACCESSORIES_MAGIC)
  (bufset-u8 reply 1 (assoc float-accessories-cmds 'UCL_ANNOUNCE))
  (bufset-u8 reply 2 0x55)
  (bufset-u8 reply 3 2)

  (bufset-u8 reply 4 (to-byte (can-local-id)))
  (bufset-u8 reply 5 (to-byte ucl-effective-role))

  (var mid (get-config 'master-can-id))
  (bufset-u8 reply 6 (to-byte (if (< mid 0) 255 mid)))

  (bufset-u16 reply 7 ucl-boot-nonce)
  (bufset-u8 reply 9 0)

  (send-data reply 2 target-id)
  (free reply)
})

(defun ucl-fwd-build (ftype seq data) {
  (var n (buflen data))
  (if (<= n 56) {
    (var out (bufcreate (+ 9 n)))
    (bufset-u8  out 0 FLOAT_ACCESSORIES_MAGIC)
    (bufset-u8  out 1 (assoc float-accessories-cmds 'UCL_REFLOAT_FWD))
    (bufset-u8  out 2 UCL_FWD_MARK)
    (bufset-u8  out 3 UCL_FWD_VER)
    (bufset-u8  out 4 (to-byte (can-local-id)))
    (bufset-u8  out 5 (to-byte ftype))
    (bufset-u16 out 6 seq)
    (bufset-u8  out 8 (to-byte n))
    (bufcpy out 9 data 0 n)
    out
  } { nil })
})

(defun ucl-cache-alldata (data) {
  (var n (buflen data))
  (if (<= n 56) {
    (atomic {
      (if (not-eq ucl-last-refloat-alldata nil) (free ucl-last-refloat-alldata))
      (setq ucl-last-refloat-alldata (bufcreate n))
      (bufcpy ucl-last-refloat-alldata 0 data 0 n)
      (setq ucl-last-refloat-alldata-rx (secs-since 0))
    })
  })
})

(defun ucl-cache-lights (data) {
  (var n (buflen data))
  (if (<= n 56) {
    (atomic {
      (if (not-eq ucl-last-refloat-lights nil) (free ucl-last-refloat-lights))
      (setq ucl-last-refloat-lights (bufcreate n))
      (bufcpy ucl-last-refloat-lights 0 data 0 n)
      (setq ucl-last-refloat-lights-rx (secs-since 0))
    })
  })
})

(defunret ucl-seq-accept (seq last last-rx-time) {
  (var delta (bitwise-and (- seq last) 0xFFFF))
  (or (and (> delta 0) (< delta 32768))
      (and (> (- (secs-since 0) last-rx-time) 1.0) (not-eq seq last))
      (and (< seq 32) (> last 4096)))
})

(defun ucl-forward-refloat-typed-to (peer-id ftype data) {
  (if (and (= ucl-effective-role 0) (>= peer-id 0)) {
    (var seq 0)
    (cond
      ((= ftype (assoc float-cmds 'COMMAND_GET_ALLDATA)) {
        (setq ucl-fwd-seq-alldata (+ ucl-fwd-seq-alldata 1))
        (setq seq ucl-fwd-seq-alldata)
      })
      ((= ftype (assoc float-cmds 'COMMAND_LIGHTS_CONTROL)) {
        (setq ucl-fwd-seq-lights (+ ucl-fwd-seq-lights 1))
        (setq seq ucl-fwd-seq-lights)
      })
      (true {
        (setq ucl-fwd-seq-alldata (+ ucl-fwd-seq-alldata 1))
        (setq seq ucl-fwd-seq-alldata)
      })
    )

    (var out (ucl-fwd-build ftype seq data))
    (if (not-eq out nil) {
      (send-data out 2 peer-id)
      (var now (secs-since 0))
      (if (= ftype (assoc float-cmds 'COMMAND_GET_ALLDATA)) {
        (setq ucl-last-refloat-alldata-fwd now)
      })
      (if (= ftype (assoc float-cmds 'COMMAND_LIGHTS_CONTROL)) {
        (setq ucl-last-refloat-lights-fwd now)
      })
      (free out)
    })
  })
})

(defun ucl-send-refloat-snapshot-to (peer-id) {
  (if (and (= ucl-effective-role 0) (>= peer-id 0)) {
    (var now (secs-since 0))
    (var snap-a nil)
    (var snap-l nil)
    (atomic {
      (if (and (> ucl-last-refloat-alldata-rx 0)
               (<= (- now ucl-last-refloat-alldata-rx) ucl-fwd-source-freshness)
               (not-eq ucl-last-refloat-alldata nil)) {
        (var n (buflen ucl-last-refloat-alldata))
        (setq snap-a (bufcreate n))
        (bufcpy snap-a 0 ucl-last-refloat-alldata 0 n)
      })
      (if (and (> ucl-last-refloat-lights-rx 0)
               (<= (- now ucl-last-refloat-lights-rx) ucl-fwd-source-freshness)
               (not-eq ucl-last-refloat-lights nil)) {
        (var n2 (buflen ucl-last-refloat-lights))
        (setq snap-l (bufcreate n2))
        (bufcpy snap-l 0 ucl-last-refloat-lights 0 n2)
      })
    })
    (if (not-eq snap-a nil) {
      (ucl-forward-refloat-typed-to peer-id (assoc float-cmds 'COMMAND_GET_ALLDATA) snap-a)
      (free snap-a)
    })
    (if (not-eq snap-l nil) {
      (ucl-forward-refloat-typed-to peer-id (assoc float-cmds 'COMMAND_LIGHTS_CONTROL) snap-l)
      (free snap-l)
    })
  })
})

(defun ucl-forward-refloat-typed (ftype data) {
  (if (and (= ucl-effective-role 0) (> (length ucl-peers) 0)) {
    (var seq 0)
    (cond
      ((= ftype (assoc float-cmds 'COMMAND_GET_ALLDATA)) {
        (setq ucl-fwd-seq-alldata (+ ucl-fwd-seq-alldata 1))
        (setq seq ucl-fwd-seq-alldata)
      })
      ((= ftype (assoc float-cmds 'COMMAND_LIGHTS_CONTROL)) {
        (setq ucl-fwd-seq-lights (+ ucl-fwd-seq-lights 1))
        (setq seq ucl-fwd-seq-lights)
      })
      (true {
        (setq ucl-fwd-seq-alldata (+ ucl-fwd-seq-alldata 1))
        (setq seq ucl-fwd-seq-alldata)
      })
    )

    (var out (ucl-fwd-build ftype seq data))
    (if (not-eq out nil) {
      (loopforeach p ucl-peers { (send-data out 2 (ix p 0)) })
      (var now (secs-since 0))
      (if (= ftype (assoc float-cmds 'COMMAND_GET_ALLDATA)) {
        (setq ucl-last-refloat-alldata-fwd now)
      })
      (if (= ftype (assoc float-cmds 'COMMAND_LIGHTS_CONTROL)) {
        (setq ucl-last-refloat-lights-fwd now)
      })
      (free out)
    })
  })
})

(defunret ucl-fwd-age () {
  (if (> ucl-fwd-rx-last-time 0) {
    (- (secs-since 0) ucl-fwd-rx-last-time)
  } {
    9999.0
  })
})

(defunret ucl-fwd-connected () {
  (< (ucl-fwd-age) 1.0)
})

(defun float-cmd (cid cmd) {
  (send-data (append (list FLOAT_MAGIC) cmd) 2 cid)
})

(defunret rt-pow2 (expv) {
  (var e (to-i expv))
  (var v 1.0)
  (if (>= e 0) {
    (looprange i 0 e {
      (setq v (* v 2.0))
    })
  } {
    (looprange i 0 (- 0 e) {
      (setq v (/ v 2.0))
    })
  })
  v
})

(defunret rt-f16 (data idx) {
  (var raw (bufget-u16 data idx))
  (var sign (if (not-eq 0 (bitwise-and raw 0x8000)) -1.0 1.0))
  (var expo (to-i (bitwise-and (shr raw 10) 0x1F)))
  (var mant (bitwise-and raw 0x03FF))
  (if (= expo 0) {
    (if (= mant 0) {
      0.0
    } {
      (* sign (/ (to-float mant) 16777216.0))
    })
  } {
    (* sign
       (+ 1.0 (/ (to-float mant) 1024.0))
       (rt-pow2 (- expo 15)))
  })
})

(defunret refloat-sat-compat (sat) {
  (cond
    ((= sat 1) 0)
    ((= sat 2) 1)
    ((= sat 0) 2)
    ((= sat 6) 3)
    ((= sat 10) 4)
    ((= sat 11) 5)
    ((= sat 12) 6)
    ((= sat 5) 7)
    ((= sat 7) 8)
    (true 0)
  )
})

(defunret refloat-state-compat (run-state run-mode stop-cond charging wheelslip darkride sat) {
  (if charging {
    14
  } {
    (cond
      ((= run-state 0) 15)
      ((= run-state 1) 0)
      ((= run-state 2) {
        (cond
          ((= stop-cond 1) 6)
          ((= stop-cond 2) 7)
          ((= stop-cond 3) 8)
          ((= stop-cond 4) 9)
          ((= stop-cond 5) 12)
          ((= stop-cond 6) 13)
          (true 11)
        )
      })
      ((= run-state 3) {
        (cond
          ((> sat 6) 2)
          (wheelslip 3)
          (darkride 4)
          ((= run-mode 2) 5)
          (true 1)
        )
      })
      (true 0)
    )
  })
})

(def series-cells-detect-armed nil)
(def series-cells-detect-fired nil)

(defunret normalize-series-cells (value) {
  (var out (to-i value))
  (if (= out 0) (setq out -1))
  (if (< out -1) (setq out -1))
  (if (> out 64) (setq out 64))
  out
})

(defunret calc-series-cells-from-batt-voltage (pack-v) {
  ; Estimate integer series count from pack voltage using plausible Li-ion bounds; 3.85V nominal biases toward lower series estimates on high-voltage packs.
  (if (and (> pack-v 10.0) (< pack-v 300.0)) {
    (var n-min-f (/ pack-v 4.25))
    (var n-min (to-i (floor n-min-f)))
    (if (< (to-float n-min) n-min-f) (setq n-min (+ n-min 1)))

    (var n-max (to-i (floor (/ pack-v 2.70))))
    (var n-cand (to-i (round (/ pack-v 3.85))))

    (if (< n-cand n-min) (setq n-cand n-min))
    (if (> n-cand n-max) (setq n-cand n-max))

    (if (and (>= n-cand 6) (<= n-cand 64)) {
      n-cand
    } {
      -1
    })
  } {
    -1
  })
})

(defun maybe-detect-series-cells-once (pack-v) {
  ; Fire once per master session after role switch.
  (if (and series-cells-detect-armed (not series-cells-detect-fired)) {
    (setq series-cells-detect-fired t)

    (var cfg-series (normalize-series-cells (get-config 'series-cells)))
    (if (> cfg-series 0) {
      (setq series-cells-detect-armed nil)
    } {
      (var est (calc-series-cells-from-batt-voltage pack-v))
      (if (> est 0) {
        (set-config 'series-cells est)
        (save-config)
        (apply-battery-config 1 (get-config 'cell-type) est)
        (send-config)
      } {})
      (setq series-cells-detect-armed nil)
    })
  })
})

(defun arm-series-cells-detect-if-needed () {
  (setq series-cells-detect-fired nil)
  (if (> (normalize-series-cells (get-config 'series-cells)) 0) {
    (setq series-cells-detect-armed nil)
  } {
    (setq series-cells-detect-armed t)
  })
})

(defun update-battery-percent-from-voltage (voltage-in) {
  (var cfg-series (normalize-series-cells (get-config 'series-cells)))
  (if (> cfg-series 0) {
    (if (!= cfg-series (to-i series-cells)) {
      (apply-battery-config 1 (get-config 'cell-type) cfg-series)
    })
  } {
    (setq series-cells -1)
  })

  ; Expect pack voltage. If we receive a cell-like value, normalize using known series.
  (var pack-v voltage-in)
  (if (and (> voltage-in 2.0) (< voltage-in 8.0) (> series-cells 0)) {
    (setq pack-v (* voltage-in (to-float series-cells)))
  })

  (if (and (> pack-v 10.0) (< pack-v 300.0)) {
    (maybe-detect-series-cells-once pack-v)

    (var soc-series (if (> series-cells 0) series-cells 15))
    (setq refloat-batt-voltage pack-v)
    (var cell-v (/ pack-v (to-float soc-series)))
    (var soc (/ (estimate-soc cell-v voltage-curve) 100.0))
    (if (< soc 0.0) (setq soc 0.0))
    (if (> soc 1.0) (setq soc 1.0))
    (setq battery-percent-remaining soc)
  })
})

(defunret build-refloat-compat-alldata (state-byte switch-byte fp1 fp2 pitch erpm current batt-v duty) {
  (var out (bufcreate 33))
  (var fp1b (to-byte (max 0 (min 255 (round (* fp1 50.0))))))
  (var fp2b (to-byte (max 0 (min 255 (round (* fp2 50.0))))))
  (var pitch10 (to-i (* pitch 10.0)))
  (var batt10 (to-i (* batt-v 10.0)))
  (var curr10 (to-i (* current 10.0)))
  (var dutyb (to-byte (max 0 (min 255 (+ 128 (round (* duty 100.0)))))))

  (bufset-u8 out 0 FLOAT_MAGIC)
  (bufset-u8 out 1 (assoc float-cmds 'COMMAND_GET_ALLDATA))
  (bufset-u8 out 2 1)
  (bufset-i16 out 3 0)
  (bufset-i16 out 5 0)
  (bufset-i16 out 7 0)
  (bufset-u8 out 9 (to-byte state-byte))
  (bufset-u8 out 10 (to-byte switch-byte))
  (bufset-u8 out 11 fp1b)
  (bufset-u8 out 12 fp2b)
  (bufset-u8 out 13 128)
  (bufset-u8 out 14 128)
  (bufset-u8 out 15 128)
  (bufset-u8 out 16 128)
  (bufset-u8 out 17 128)
  (bufset-u8 out 18 128)
  (bufset-i16 out 19 pitch10)
  (bufset-u8 out 21 128)
  (bufset-i16 out 22 batt10)
  (bufset-i16 out 24 (to-i erpm))
  (bufset-i16 out 26 0)
  (bufset-i16 out 28 curr10)
  (bufset-i16 out 30 0)
  (bufset-u8 out 32 dutyb)
  out
})

(defun parse-refloat-alldata-min (data) {
  ; Keep LED/runtime-critical fields in sync with refloat.
  ; This is intentionally minimal to avoid heap pressure.
  (if (>= (buflen data) 33) {
    (var state-byte (bufget-u8 data 9))
    (setq state (bitwise-and state-byte 0x0F))
    (setq sat-t (shr state-byte 4))

    (var switch-state-byte (bufget-u8 data 10))
    (var switch-base (bitwise-and switch-state-byte 0x07))
    (setq handtest-mode (= (bitwise-and switch-state-byte 0x08) 0x08))

    ; Keep Stage3 switch remap behavior.
    (var fp1 (/ (to-float (bufget-u8 data 11)) 50))
    (var fp2 (/ (to-float (bufget-u8 data 12)) 50))
    (if (= switch-base 2) {
      (setq switch-base 3)
    })
    (if (and (= switch-base 1) (> fp2 fp1)) {
      (setq switch-base 2)
    })
    (setq switch-state switch-base)

    (setq pitch-angle (/ (to-float (bufget-i16 data 19)) 10))
    (update-battery-percent-from-voltage (/ (to-float (bufget-i16 data 22)) 10))
    (setq rpm (/ (to-float (bufget-i16 data 24)) 10))
    (setq tot-current (/ (to-float (bufget-i16 data 28)) 10))
    (setq duty-cycle-now (/ (to-float (- (bufget-u8 data 32) 128)) 100))
  })
})

(defunret parse-refloat-realtime-min (data) {
  ; Parse current refloat REALTIME_DATA (31) and emit a compact compat frame for
  ; slave forwarding. This keeps the master on the current upstream API while
  ; preserving the smaller internal forward payload.
  (if (>= (buflen data) 44) {
    (var state-mode (bufget-u8 data 8))
    (var flags-footpad (bufget-u8 data 9))
    (var stop-sat (bufget-u8 data 10))

    (var run-state (bitwise-and state-mode 0x03))
    (var run-mode (bitwise-and (shr state-mode 4) 0x03))
    (var footpad-state (bitwise-and (shr flags-footpad 6) 0x03))
    (var charging (= (bitwise-and flags-footpad 0x20) 0x20))
    (var darkride (= (bitwise-and flags-footpad 0x02) 0x02))
    (var wheelslip (= (bitwise-and flags-footpad 0x01) 0x01))
    (var stop-cond (bitwise-and stop-sat 0x0F))
    (var sat-raw (bitwise-and (shr stop-sat 4) 0x0F))

    (var motor-erpm (rt-f16 data 14))
    (var motor-current (rt-f16 data 16))
    (var duty (rt-f16 data 22))
    (var batt-v (rt-f16 data 24))
    (var pitch (rt-f16 data 32))
    (var fp1 (rt-f16 data 38))
    (var fp2 (rt-f16 data 40))

    (setq handtest-mode (= run-mode 1))
    (setq sat-t (refloat-sat-compat sat-raw))
    (setq state (refloat-state-compat run-state run-mode stop-cond charging wheelslip darkride sat-raw))
    (setq switch-state footpad-state)
    (setq pitch-angle pitch)
    (setq rpm (/ motor-erpm 10.0))
    (setq tot-current motor-current)
    (setq duty-cycle-now duty)
    (update-battery-percent-from-voltage batt-v)

    (var compat-switch 0)
    (if (= footpad-state 3) {
      (setq compat-switch 2)
    } {
      (if (or (= footpad-state 1) (= footpad-state 2)) {
        (setq compat-switch 1)
      })
    })
    (if handtest-mode {
      (setq compat-switch (bitwise-or compat-switch 0x08))
    })

    (build-refloat-compat-alldata
      (+ state (shl sat-t 4))
      compat-switch
      fp1
      fp2
      pitch
      motor-erpm
      motor-current
      batt-v
      duty)
  } {
    nil
  })
})

(defun discover-stop () {
  (setq discover-running nil)
  (setq discover-inflight-id -1)
  (setq discover-inflight-time 0)
})

(defun discover-schedule-retry () {
  (discover-stop)
  (setq discover-next-retry-time (+ (secs-since 0) discover-retry-delay))
})

(defun refloat-health-reset () {
  nil
})

(defun discover-start () {
  (setq discover-running t)
  (setq discover-init-time (secs-since 0))
  (setq discover-next-scan-time 0)
  (setq discover-next-retry-time 0)
  (setq discover-last-log-time 0)
  (setq discover-pass-probed 0)
  (setq discover-pass-budget (+ discover-max-id 1))
  (if (and (>= (can-local-id) 0) (<= (can-local-id) discover-max-id)) {
    (setq discover-pass-budget discover-max-id)
  })

  (if (or (< discover-pref-id 0) (> discover-pref-id discover-max-id) (= discover-pref-id (can-local-id))) {
    (setq discover-pref-id (get-config 'can-id))
  })
  (if (or (< discover-pref-id 0) (> discover-pref-id discover-max-id) (= discover-pref-id (can-local-id))) {
    (setq discover-pref-id -1)
  })

  (if (>= discover-pref-id 0) {
    (setq discover-ping-next-id (+ discover-pref-id 1))
    (if (> discover-ping-next-id discover-max-id) (setq discover-ping-next-id 0))
  } {
    (setq discover-ping-next-id 0)
  })
  (setq discover-inflight-id -1)
  (setq discover-inflight-time 0)
})

(defun ucl-master-enter () {
  (var now (secs-since 0))
  ; Always kick peer scan immediately on master entry.
  (setq ucl-last-peer-scan-time 0)
  (setq ucl-scan-next-id 0)
  (setq refloat-stable-since 0)
  (setq refloat-lights-seen nil)
  ; Keep LEDs off until first LIGHTS_CONTROL response in this master session.
  (setq led-on 0)
  (setq led-highbeam-on 0)
  (set-config 'led-on 0)
  (set-config 'led-highbeam-on 0)
  (var candidate refloat-can-id)
  (if (or (< candidate 0) (> candidate discover-max-id) (= candidate (can-local-id))) {
    (setq candidate (get-config 'can-id))
  })
  (if (or (< candidate 0) (> candidate discover-max-id) (= candidate (can-local-id))) {
    (setq candidate -1)
  })

  ; Prefer stored id immediately (single-refloat setup), and only rescan
  ; if it stays silent for a longer boot window.
  (setq refloat-last-rx-time 0)
  (refloat-health-reset)
    (if (>= candidate 0) {
    (setq refloat-can-id candidate)
    (setq can-id candidate)
    (setq discover-pref-id -1)
    (discover-stop)
    (setq refloat-boot-verify-active t)
    (setq refloat-boot-verify-id candidate)
    (setq refloat-boot-verify-deadline (+ now refloat-boot-verify-timeout))
    (setq refloat-last-poll-time (- now refloat-poll-interval))
    (var candidateb (to-byte candidate))
    (float-cmd candidateb (list (assoc float-cmds 'COMMAND_REALTIME_DATA)))
    (float-cmd candidateb (list (assoc float-cmds 'COMMAND_LIGHTS_CONTROL)))
  } {
    (setq refloat-can-id -1)
    (setq can-id -1)
    (setq refloat-boot-verify-active nil)
    (setq refloat-boot-verify-id -1)
    (setq refloat-boot-verify-deadline 0)
    (setq discover-pref-id -1)
    (discover-start)
  })
})


(defunret ucl-peer-scan-active (now) {
  ; Scan peers during startup/recovery only. Once refloat has remained online
  ; for the hold window, stop full-ID background probing to reduce bus load.
  (if (or (< refloat-can-id 0)
          discover-running
          (<= refloat-last-rx-time 0)
          (<= refloat-stable-since 0)) {
    t
  } {
    (< (- now refloat-stable-since) ucl-peer-scan-stable-hold)
  })
})

(defun discover-step () {
  (var now (secs-since 0))
  (var issue-probe t)

  (if (>= refloat-can-id 0) {
    (discover-stop)
    (setq issue-probe nil)
  })

  (if (and issue-probe (>= discover-inflight-id 0)) {
    (if (< (- now discover-inflight-time) discover-inflight-timeout) {
      (setq issue-probe nil)
    } {
      (setq discover-inflight-id -1)
      (setq discover-inflight-time 0)
    })
  })

  (if (and issue-probe (< now discover-next-scan-time)) {
    (setq issue-probe nil)
  })

  ; Re-check in case refloat was found asynchronously during this step.
  (if (and issue-probe (>= refloat-can-id 0)) {
    (discover-stop)
    (setq issue-probe nil)
  })

  ; One complete pass over all remote ids -> stop and backoff.
  (if (and issue-probe (>= discover-pass-probed discover-pass-budget)) {
    (discover-schedule-retry)
    (setq issue-probe nil)
  })

  (if issue-probe {
    (if (>= refloat-can-id 0) {
      (discover-stop)
      (setq issue-probe nil)
    })
  })

  (if issue-probe {
    (setq discover-next-scan-time (+ now discover-scan-interval))

    (var pid -1)
    (if (>= discover-pref-id 0) {
      (setq pid discover-pref-id)
      (setq discover-pref-id -1)
    } {
      (setq pid discover-ping-next-id)
      (setq discover-ping-next-id (+ discover-ping-next-id 1))
      (if (> discover-ping-next-id discover-max-id) (setq discover-ping-next-id 0))
    })

    (if (= pid (can-local-id)) {
      (setq pid (+ pid 1))
      (if (> pid discover-max-id) (setq pid 0))
    })

    (setq discover-inflight-id pid)
    (setq discover-inflight-time now)
    (setq discover-pass-probed (+ discover-pass-probed 1))

    (if (>= (- now discover-last-log-time) discover-log-interval) {
      (setq discover-last-log-time now)
    })

    (var pidb (to-byte pid))
    (if (can-ping pidb) {
      (float-cmd pidb (list (assoc float-cmds 'COMMAND_REALTIME_DATA)))
      (float-cmd pidb (list (assoc float-cmds 'COMMAND_LIGHTS_CONTROL)))
    } {
      (setq discover-inflight-id -1)
      (setq discover-inflight-time 0)
    })
  })
})

(defun can-loop-boot-enter () {
  (ucl-election-step)
  ; Safe boot default: off until first valid lights frame.
  (setq refloat-lights-seen nil)
  (setq led-on 0)
  (setq led-highbeam-on 0)
  (set-config 'led-on 0)
  (set-config 'led-highbeam-on 0)
  (if (= ucl-effective-role 0) {
    (arm-series-cells-detect-if-needed)
    (ucl-master-enter)
  } {
    (discover-stop)
    (refloat-health-reset)
    (setq refloat-last-rx-time 0)
    (setq refloat-lights-seen nil)
    (setq refloat-boot-verify-active nil)
    (setq refloat-boot-verify-id -1)
    (setq refloat-boot-verify-deadline 0)
  })
  (setq can-last-effective-role ucl-effective-role)
  (setq led-watchdog-arm-time (+ (secs-since 0) 3.0))
})

(defun can-loop-role-transition-step () {
  (ucl-election-step)
  (if (not-eq ucl-effective-role can-last-effective-role) {
    (if (= ucl-effective-role 0) {
      (arm-series-cells-detect-if-needed)
      (ucl-master-enter)
    } {
      (setq series-cells-detect-armed nil)
      (setq series-cells-detect-fired nil)
      (discover-stop)
      (refloat-health-reset)
      (setq refloat-stable-since 0)
      (setq refloat-lights-seen nil)
      (setq refloat-last-rx-time 0)
      (setq refloat-boot-verify-active nil)
      (setq refloat-boot-verify-id -1)
      (setq refloat-boot-verify-deadline 0)
    })
    (setq can-last-effective-role ucl-effective-role)
    ; Force watchdog to re-evaluate quickly after role changes.
    (setq led-heartbeat-time 0.0)
    (setq led-watchdog-arm-time (+ (secs-since 0) 2.0))
  })
})

(defun can-loop-led-watchdog-step (loop-now) {
  ; If heartbeat is in the future after image restore, invalidate it now.
  (if (> led-heartbeat-time (+ loop-now 0.5)) {
    (setq led-heartbeat-time 0.0)
  })

  ; Skip while settings is intentionally stopping LED loop for reconfigure.
  (if (and (= ucl-effective-role 0)
           (= (to-i (get-config 'led-enabled)) 1)
           (not led-exit-flag)
           (>= loop-now led-watchdog-arm-time)
           (or (<= led-heartbeat-time 0.0)
               (>= (- loop-now led-heartbeat-time) led-watchdog-timeout))
           (>= (- loop-now led-watchdog-last-restart) led-watchdog-restart-cooldown)) {
    (setq led-watchdog-last-restart loop-now)
    (setq led-watchdog-arm-time (+ loop-now 2.0))
    (if (>= led-context-id 0) {
      (trap (kill led-context-id nil))
    })
    (setq led-exit-flag nil)
    (setq led-context-id (spawn led-loop))
  })
})

(defun can-loop-time-reset-step (loop-now) {
  ; If uptime goes backwards, a board reboot happened while image resumed runtime.
  ; Re-run boot role/discovery state and force a fresh LED loop immediately.
  (if (and (> can-loop-last-now 2.0)
           (< loop-now (- can-loop-last-now 1.0))) {
    (setq led-heartbeat-time 0.0)
    (setq led-watchdog-last-restart 0.0)
    (setq led-watchdog-arm-time (+ loop-now 0.5))
    (if (>= led-context-id 0) {
      (trap (kill led-context-id nil))
    })
    (setq led-exit-flag nil)
    (setq led-context-id (spawn led-loop))
    (can-loop-boot-enter)
    (setq ucl-role-ready t)
  })
})

(defun can-loop-master-step (loop-now) {
  (if (= ucl-effective-role 0) {
    (if discover-running {
      (discover-step)
    } {
      (if (and (< refloat-can-id 0) (>= loop-now discover-next-retry-time)) {
        (discover-start)
      })
    })

    (if refloat-boot-verify-active {
      (if (> refloat-last-rx-time 0) {
        (setq refloat-boot-verify-active nil)
      } {
        (if (>= loop-now refloat-boot-verify-deadline) {
          (setq refloat-boot-verify-active nil)
          (setq refloat-boot-verify-id -1)
          (setq refloat-boot-verify-deadline 0)
          (setq discover-pref-id -1)
          (setq refloat-can-id -1)
          (setq can-id -1)
          (refloat-health-reset)
          (discover-start)
        })
      })
    })

    (if (and (>= refloat-can-id 0)
             (not discover-running)
             (>= (- loop-now refloat-last-poll-time) refloat-poll-interval)) {
      (setq refloat-last-poll-time loop-now)
      (var rid (to-byte refloat-can-id))
      (float-cmd rid (list (assoc float-cmds 'COMMAND_REALTIME_DATA)))
      (float-cmd rid (list (assoc float-cmds 'COMMAND_LIGHTS_CONTROL)))
    })

    (if (and (>= refloat-can-id 0)
             (not discover-running)
             (> refloat-last-rx-time 0)
             (>= (- loop-now refloat-last-rx-time) refloat-rx-loss-timeout)) {
      (setq refloat-can-id -1)
      (setq can-id -1)
      (setq refloat-stable-since 0)
      (setq refloat-lights-seen nil)
      ; No fresh refloat state: fail-safe off until next lights frame.
      (setq led-on 0)
      (setq led-highbeam-on 0)
      (set-config 'led-on 0)
      (set-config 'led-highbeam-on 0)
      (setq refloat-last-rx-time 0)
      (setq discover-pref-id (get-config 'can-id))
      (discover-start)
    })
  })
})

(defun can-loop-master-config-step () {
  (if (and (= ucl-effective-role 0) (not discover-running) (> (length ucl-peers) 0)) {
    (ucl-config-push-step)
  })
})

(defun can-loop-peer-poke-step () {
  (var now (secs-since 0))
  (if (>= (- now ucl-last-peer-poke) ucl-peer-poke-interval) {
    (setq ucl-last-peer-poke now)
    (if (= ucl-effective-role 1) {
      (if (>= ucl-effective-master 0) { (ucl-send-announce ucl-effective-master) })
    })
    (if (= ucl-effective-role 0) {
      (loopforeach p ucl-peers { (ucl-send-announce (ix p 0)) })
    })
  })
})

(defun can-loop-master-forward-refresh-step (now) {
  (if (and (= ucl-effective-role 0) (> (length ucl-peers) 0)) {
    (if (and (> ucl-last-refloat-lights-rx 0)
             (<= (- now ucl-last-refloat-lights-rx) ucl-fwd-source-freshness)
             (>= (- now ucl-last-refloat-lights-fwd) ucl-fwd-refresh-interval)) {
      (var snap-l nil)
      (atomic {
        (if (not-eq ucl-last-refloat-lights nil) {
          (var n2 (buflen ucl-last-refloat-lights))
          (setq snap-l (bufcreate n2))
          (bufcpy snap-l 0 ucl-last-refloat-lights 0 n2)
        })
      })
      (if (not-eq snap-l nil) {
        (ucl-forward-refloat-typed (assoc float-cmds 'COMMAND_LIGHTS_CONTROL) snap-l)
        (free snap-l)
      })
    })
  })
})

(defun can-loop-sleep-step (can-loop-delay-sec) {
  (var sleep-sec can-loop-delay-sec)
  (if (and (= ucl-effective-role 0) discover-running (> sleep-sec discover-scan-interval)) {
    (setq sleep-sec discover-scan-interval)
  })
  (yield (* 1000000 sleep-sec))
})

(defun can-loop () {
  (setq ucl-role-ready nil)
  (setq can-loop-delay (get-config 'can-loop-delay))
  (if (< can-loop-delay 1) { (setq can-loop-delay 1) })
  ; Tie forward lights replay cadence to CAN loop frequency.
  ; Example: can-loop-delay=2 => 0.5s, can-loop-delay=4 => 0.25s.
  (setq ucl-fwd-refresh-interval (/ 1.0 can-loop-delay))
  (setq ucl-boot-time (secs-since 0))
  (setq ucl-boot-nonce (bitwise-and (systime) 0xFFFF))
  ; Fresh runtime markers at real boot/parse start.
  (setq led-heartbeat-time 0.0)
  (setq led-context-id -1)
  (setq can-loop-last-now (secs-since 0))
  (can-loop-boot-enter)
  (setq ucl-role-ready t)
  

  (var can-loop-delay-sec (/ 1.0 can-loop-delay))
  (loopwhile t {
    (ucl-announce-self)
    (can-loop-role-transition-step)

    (var loop-now (secs-since 0))
    (can-loop-time-reset-step loop-now)
    (can-loop-led-watchdog-step loop-now)
    (if (and (= ucl-effective-role 0)
             (not discover-running)
             (ucl-peer-scan-active loop-now)) {
      (ucl-scan-step)
    })
    (can-loop-master-step loop-now)
    (can-loop-master-config-step)
    (can-loop-peer-poke-step)
    (can-loop-master-forward-refresh-step loop-now)
    (setq can-loop-last-now loop-now)
    (can-loop-sleep-step can-loop-delay-sec)
  })
})

; ---------------------
; float-command-rx (kept, but no prev checks)
; ---------------------

(defun float-command-rx-accessories (data) {
  (if (and (> (buflen data) 1) (= (bufget-u8 data 0) FLOAT_ACCESSORIES_MAGIC)) {
    (match (cossa float-accessories-cmds (bufget-u8 data 1))

      (COMMAND_GET_INFO {
        (if (and (>= (buflen data) 5) (= (bufget-u8 data 2) 0x55) (= (bufget-u8 data 3) 2)) {
          (var reply (bufcreate 10))
          (bufset-u8 reply 0 FLOAT_ACCESSORIES_MAGIC)
          (bufset-u8 reply 1 (assoc float-accessories-cmds 'UCL_ANNOUNCE))
          (bufset-u8 reply 2 0x55)
          (bufset-u8 reply 3 2)
          (bufset-u8 reply 4 (to-byte (can-local-id)))
          (bufset-u8 reply 5 (to-byte ucl-effective-role))
          (var mid (get-config 'master-can-id))
          (bufset-u8 reply 6 (to-byte (if (< mid 0) 255 mid)))
          (bufset-u16 reply 7 ucl-boot-nonce)
          (bufset-u8 reply 9 0)
          (var req (bufget-u8 data 4))
          (send-data reply 2 req)
          (free reply)
        })
      })

      (UCL_ANNOUNCE {
        (if (and (>= (buflen data) 10) (= (bufget-u8 data 2) 0x55) (= (bufget-u8 data 3) 2)) {
          (var sender-id (bufget-u8 data 4))
          (var role (bufget-u8 data 5))
          (var masterid (bufget-u8 data 6))
          (var nonce (bufget-u16 data 7))
          (if (not-eq role 0) (setq role 1))

          (if (= masterid 255) (setq masterid -1))

          (if (and (= sender-id (can-local-id)) (not-eq nonce ucl-boot-nonce)) {
            (if (not ucl-conflict-detected) {
              (setq ucl-conflict-detected t)
              (print "[UCL] CAN-ID conflict detected")
            })
          })

          (if (not-eq sender-id (can-local-id)) {
            (if (and (= ucl-effective-role 1)
                     (= (get-config 'master-can-id) -1)
                     (= role 0)) {
              (atomic {
                (set-config 'master-can-id sender-id)
                (write-val-eeprom 'master-can-id sender-id)
                (write-val-eeprom 'crc (config-crc cfg-len))
              })
            })

            (var is-new-peer (ucl-peer-upsert sender-id role masterid))
            (if (and (= ucl-effective-role 0) (= role 1)) {
              (ucl-send-refloat-snapshot-to sender-id)
              (if is-new-peer {
                (ucl-config-send-to-tracked sender-id)
              })
            })
          })
        })
      })

      (UCL_REFLOAT_FWD {
        (if (not-eq ucl-effective-role 0) {
          (if (and (>= (buflen data) 9)
                   (= (bufget-u8 data 2) UCL_FWD_MARK)
                   (= (bufget-u8 data 3) UCL_FWD_VER)) {

            (var src (bufget-u8 data 4))
            (var ftype (bufget-u8 data 5))
            (var seq (bufget-u16 data 6))
            (var n (bufget-u8 data 8))
            (var cfg-master (get-config 'master-can-id))

            (if (and (or (< cfg-master 0) (= src cfg-master))
                     (> n 0) (<= n 56) (>= (buflen data) (+ 9 n))) {
              (var accept nil)
              (cond
                ((= ftype (assoc float-cmds 'COMMAND_GET_ALLDATA)) {
                  (if (ucl-seq-accept seq ucl-fwd-last-alldata ucl-fwd-rx-last-alldata) {
                    (setq ucl-fwd-last-alldata seq)
                    (setq ucl-fwd-rx-last-alldata (secs-since 0))
                    (setq accept t)
                  })
                })
                ((= ftype (assoc float-cmds 'COMMAND_LIGHTS_CONTROL)) {
                  (if (ucl-seq-accept seq ucl-fwd-last-lights ucl-fwd-rx-last-lights) {
                    (setq ucl-fwd-last-lights seq)
                    (setq ucl-fwd-rx-last-lights (secs-since 0))
                    (setq accept t)
                  })
                })
                (true { (setq accept t) })
              )

              (if accept {
                (setq ucl-fwd-rx-count (+ ucl-fwd-rx-count 1))
                (setq ucl-fwd-rx-last-time (secs-since 0))
                (if (>= (- ucl-fwd-rx-last-time ucl-fwd-rx-log-time) 5.0) {
                  (setq ucl-fwd-rx-log-time ucl-fwd-rx-last-time)
                })

                (var f (bufcreate n))
                (bufcpy f 0 data 9 n)
                (float-command-rx f)
                (free f)
              })
            })
          })
        })
      })

      (UCL_CONFIG_PUSH { (if (= ucl-effective-role 1) { (ucl-config-handle-push data) }) })
      (UCL_CONFIG_ACK  { (ucl-config-handle-ack data) })

      (COMMAND_RUN_LISP {
        (bufcpy data 0 data 2 (-(buflen data) 2))
        (buf-resize data -2)
        (eval (read data))
      })

      (_ nil)
    )
  })
})

(defun float-command-rx-refloat (data) {
  (if (and (> (buflen data) 1) (= (bufget-u8 data 0) FLOAT_MAGIC)) {
    (match (cossa float-cmds (bufget-u8 data 1))

      (COMMAND_GET_ALLDATA {
          (if (> (buflen data) 3) {
          (var rx-now (secs-since 0))
          (setq refloat-last-rx-time rx-now)
          (if (<= refloat-stable-since 0) { (setq refloat-stable-since rx-now) })
          (setq can-last-activity-time (systime))
          (if (= ucl-effective-role 0) { (ucl-cache-alldata data) })
          (ucl-forward-refloat-typed (assoc float-cmds 'COMMAND_GET_ALLDATA) data)
          (parse-refloat-alldata-min data)

          (if (and (= ucl-effective-role 0) (< refloat-can-id 0) (>= discover-inflight-id 0)) {
            (setq refloat-can-id discover-inflight-id)
            (setq can-id refloat-can-id)
                        (setq refloat-stable-since (secs-since 0))
            (setq refloat-last-poll-time 0)
            (setq refloat-boot-verify-active nil)
            (setq refloat-boot-verify-id -1)
            (setq refloat-boot-verify-deadline 0)
            (refloat-health-reset)

            (if (not-eq refloat-can-id (get-config 'can-id)) {
              (atomic {
                (set-config 'can-id refloat-can-id)
                (write-val-eeprom 'can-id refloat-can-id)
                (write-val-eeprom 'crc (config-crc cfg-len))
              })
              (send-config)
            })

            (discover-stop)
          })
        })
      })

      (COMMAND_REALTIME_DATA {
        (if (>= (buflen data) 44) {
          (var rx-now (secs-since 0))
          (setq refloat-last-rx-time rx-now)
          (if (<= refloat-stable-since 0) { (setq refloat-stable-since rx-now) })
          (setq can-last-activity-time (systime))
          (var compat (parse-refloat-realtime-min data))
          (if (and (= ucl-effective-role 0) (not-eq compat nil)) {
            (ucl-cache-alldata compat)
            (ucl-forward-refloat-typed (assoc float-cmds 'COMMAND_GET_ALLDATA) compat)
          })

          (if (and (= ucl-effective-role 0) (< refloat-can-id 0) (>= discover-inflight-id 0)) {
            (setq refloat-can-id discover-inflight-id)
            (setq can-id refloat-can-id)
                        (setq refloat-stable-since (secs-since 0))
            (setq refloat-last-poll-time 0)
            (setq refloat-boot-verify-active nil)
            (setq refloat-boot-verify-id -1)
            (setq refloat-boot-verify-deadline 0)
            (refloat-health-reset)

            (if (not-eq refloat-can-id (get-config 'can-id)) {
              (atomic {
                (set-config 'can-id refloat-can-id)
                (write-val-eeprom 'can-id refloat-can-id)
                (write-val-eeprom 'crc (config-crc cfg-len))
              })
              (send-config)
            })

            (discover-stop)
          })

          (if (not-eq compat nil) {
            (free compat)
          })
        })
      })

      (COMMAND_LIGHTS_CONTROL {
        (if (>= (buflen data) 3) {
          (var rx-now (secs-since 0))
          (setq refloat-last-rx-time rx-now)
          (if (<= refloat-stable-since 0) { (setq refloat-stable-since rx-now) })
          (setq refloat-lights-seen t)
          (setq can-last-activity-time (systime))
          (if (= ucl-effective-role 0) { (ucl-cache-lights data) })
          (ucl-forward-refloat-typed (assoc float-cmds 'COMMAND_LIGHTS_CONTROL) data)
          (var flags (bufget-u8 data 2))
          (if (not-eq flags last-refloat-lights-flags) {
            (setq last-refloat-lights-flags flags)
          })
          (setq led-on (if (not-eq 0 (bitwise-and flags 0x01)) 1 0))
          (setq led-highbeam-on (if (not-eq 0 (bitwise-and flags 0x02)) 1 0))
          (set-config 'led-on led-on)
          (set-config 'led-highbeam-on led-highbeam-on)
        })
      })


      (_ nil)
    )
  })
})

(defun float-command-rx (data) {
  (float-command-rx-accessories data)
  (float-command-rx-refloat data)
})

@const-end
