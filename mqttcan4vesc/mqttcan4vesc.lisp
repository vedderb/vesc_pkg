; MQTTCAN4VESC -- CAN -> MQTT telemetry bridge for VESC Express, configured from
; a QML panel inside VESC Tool (via custom app data). Runs ON THE VESC EXPRESS.
;
; TELEMETRY: decodes VESC CAN status messages 1-6 from controller `cfg-vesc-id`
; and publishes them over MQTT (JSON on one topic by default).
;
; CONFIGURATION: all settings live in EEPROM and are edited from the package's
; panel in VESC Tool over BLE/USB. The panel talks to this script with a small
; text protocol (GET / SET / SAVE / TEL / TEST / DETECT / DEFAULTS / REBOOT).
;
; One-time device settings (reboot after writing): WiFi Mode = Station;
; CAN baud = 500k; controller broadcasts statuses 1-6. Firmware 6.05+.

; Read all definitions into flash (const heap) to save RAM cons cells -- see the
; note at @const-end. Everything from here to @const-end lives in flash.
@const-start

(def pkg-version "mqttcan4vesc 1.6.1")
(def proto-version 2)

;;; ================= WiFi ====================================================
; WiFi is NOT configured here. The Express firmware owns it: set WiFi Mode =
; Station + Station Mode SSID/Key in VESC Tool -> VESC Express -> WiFi. The
; firmware auto-connects on boot and auto-reconnects on drop. This script only
; observes (wifi-status) and waits.
;
; Do NOT call (wifi-connect ...) here: it would override the stored station
; config at runtime. Do NOT call (wifi-disconnect): the firmware sets
; wifi_reconnect_disabled = true on disconnect, which kills auto-reconnect
; until reboot.

;;; ================= Defaults (used when EEPROM is empty/invalid) =============
(def def-mqtt-host "broker.emqx.io")
(def def-mqtt-port 1883)
(def def-mqtt-user "")            ; empty -> no MQTT auth
(def def-mqtt-pass "")
(def def-topic-prefix "vesc/telemetry/")
(def def-pub-mode 0)             ; 0 json | 1 topics | 2 both
(def def-pub-interval 0.2)       ; seconds between publishes (0.1 - 5.0)
(def def-vesc-id 111)
(def def-speed-div 4.0)          ; eRPM / speed-div  (pole pairs)
(def def-torque-k 0.01176)       ; Nm per raw 0.1 A unit
(def def-keepalive 60)           ; MQTT keepalive seconds
; 0 raw  — VESC protocol OFF; status 1-6 decoded from event-can-eid
; 1 vesc — VESC protocol ON (VESC Tool CAN bridging works); status 1-6 are
;          STILL decoded from event-can-eid (the firmware hands every frame to
;          lisp before its own decoder), canget-* polling only as fallback
; 2 sim  — fake data, no VESC needed
(def def-can-mode 1)

;;; ================= Working configuration (RAM) =============================
(def cfg-mqtt-host def-mqtt-host)
(def cfg-mqtt-port def-mqtt-port)
(def cfg-mqtt-user def-mqtt-user)
(def cfg-mqtt-pass def-mqtt-pass)
(def cfg-topic-prefix def-topic-prefix)
(def cfg-pub-mode def-pub-mode)
(def cfg-pub-interval def-pub-interval)
(def cfg-vesc-id def-vesc-id)
(def cfg-speed-div def-speed-div)
(def cfg-torque-k def-torque-k)
(def cfg-keepalive def-keepalive)
(def cfg-can-mode def-can-mode)

;;; ================= VESC CAN status command numbers =========================
(def cmd-status-1 9) (def cmd-status-2 14) (def cmd-status-3 15)
(def cmd-status-4 16) (def cmd-status-5 27) (def cmd-status-6 28)

;;; ================= Runtime state ===========================================
(def sock nil)
(def last-tx (systime))
(def last-pub (systime))
(def new-data false)
(def reconnect-req false)        ; set by SAVE/DEFAULTS -> main loop reconnects
(def mqtt-err "none")            ; last connection failure reason (for panel)
(def events-on false)            ; event-enable succeeded (retried on boot until CAN ready)
(def can-frames 0)               ; total CAN status frames decoded (is CAN alive?)
(def last-frame 0)               ; systime of last decoded status frame (vesc-mode fallback)
(def last-seen-node -1)          ; node id of last status-1 frame seen (for Detect)
(def cfg-src "defaults")         ; "eeprom" once a valid saved record loads
(def save-fail -1)               ; slot number of the first failed eeprom write

; Raw, as the controller reports them: erpm is ELECTRICAL rpm, current-motor is
; motor phase current in amps. motor-speed and motor-torque are derived from
; these two via cfg-speed-div / cfg-torque-k, and depend on those constants
; being right. Publish both so a consumer can re-derive if a constant changes.
(def erpm 0.0) (def current-motor 0.0)
(def motor-speed 0.0) (def motor-torque 0.0) (def duty 0.0)
(def ah-used 0.0) (def ah-charged 0.0)
(def wh-used 0.0) (def wh-charged 0.0)
(def temp-fet 0.0) (def temp-motor 0.0) (def current-in 0.0) (def pid-pos 0.0)
(def tacho 0.0) (def v-in 0.0)
(def adc1 0.0) (def adc2 0.0) (def adc3 0.0) (def ppm 0.0)

;;; ================= EEPROM layout (v2) ======================================
; Numeric slots (i = eeprom-store-i, f = eeprom-store-f):
;   0 i magic   1 i mqtt-port   2 i vesc-id   3 i pub-mode   4 i keepalive
;   5 i pub-interval-ms   6 f speed-div   7 f torque-k   (8,9 reserved)
; String blocks (len word + packed data words, 4 chars/word):
;   [10-36 legacy ssid/pass — no longer written or read; WiFi lives in the
;    firmware's own config now. Slots kept reserved so the layout is stable.]
;   host  len@40 data 41-56 (64 B)    user  len@60 data 61-68 (32 B)
;   mpass len@70 data 71-78 (32 B)    prefix len@80 data 81-92 (48 B)
; Magic differs from the old v3 value (0x1234ABCD) so pre-panel devices fall
; back to defaults safely instead of misreading the old layout. The layout is
; unchanged by dropping ssid/pass, so the magic stays "STR2" and every other
; saved parameter survives the upgrade.
; NOTE the i32 suffix, and do not remove it. Two traps live here:
;   1. eeprom-read-i returns a boxed i32. LispBM `eq` (struct_eq) demands
;      IDENTICAL types, so comparing it against a default-typed literal is
;      always false -- the saved record would never be accepted and every
;      setting would silently revert to defaults on each boot.
;   2. 0x53545232 does not fit LispBM's 28-bit fixnum: written without a
;      suffix it encodes to 0x03545232, i.e. the constant is truncated.
; Hence: an explicit i32 literal, and a NUMERIC (=) comparison in magic-ok.
; Bumped to "STR3" in 1.6.1: records written before the eep-store-str fix hold
; corrupted strings (every 4th character). A new magic makes those records fail
; the check, so a device loads clean defaults instead of a mangled broker host.
(def eep-magic 0x53545233i32)    ; "STR3"

(def A-MAGIC 0) (def A-PORT 1) (def A-VESCID 2) (def A-PUBMODE 3)
(def A-KEEPALIVE 4) (def A-PUBMS 5) (def A-SPEEDDIV 6) (def A-TORQUE 7)
(def A-CANMODE 8)                ; (9 still reserved; 10-36 legacy ssid/pass)
(def A-HOST 40)
(def A-USER 60) (def A-MPASS 70) (def A-PREFIX 80)

; eeprom-store-i/-f return nil on failure instead of throwing. Silently
; discarding that is how a whole config could fail to persist while the panel
; reported success. Record the first failing slot so SAVE can name it.
(defun st-i (a v) {
        (if (not (eq (eeprom-store-i a v) t))
            (if (< save-fail 0) (setq save-fail a)))
})
(defun st-f (a v) {
        (if (not (eq (eeprom-store-f a v) t))
            (if (< save-fail 0) (setq save-fail a)))
})

; Pack a string into EEPROM starting at `addr`: addr = length, then `maxwords`
; data words (4 chars each, zero padded).
; NOTE the 0i32 accumulator and the (to-i32 ch) cast, and do not remove them.
; A default fixnum is only 28 bits, so packing the 4th byte of a word --
; (shl ch 24) -- overflowed it and the top nibble wrapped into the sign. Every
; character at index%4 == 3 came back mangled ('k' -> 251, 'e' -> 5, '.' ->
; 254), which corrupted mqtt_host, topic_prefix, user and password on reload.
; Invisible until a reboot, because the typed values live in RAM until then.
(defun eep-store-str (addr maxwords s) {
        (var len (str-len s))
        (st-i addr len)
        (looprange w 0 maxwords {
                (var v 0i32)
                (looprange b 0 4 {
                        (var idx (+ (* w 4) b))
                        (var ch (if (< idx len) (bufget-u8 s idx) 0))
                        (setq v (bitwise-or v (shl (to-i32 ch) (* b 8))))
                })
                (st-i (+ addr 1 w) v)
        })
})

; Read a string previously packed with eep-store-str. Returns a null-terminated
; byte-array (usable as a string) or nil if the stored length is invalid.
(defun eep-read-str (addr maxlen) {
        (var len (eeprom-read-i addr))
        (if (or (not (eq (type-of len) (type-of 1i32))) (< len 0) (> len maxlen))
            nil
            {
                (var s (bufcreate (+ len 1)))
                (looprange i 0 len {
                        (var v (eeprom-read-i (+ addr 1 (/ i 4))))
                        (bufset-u8 s i (bitwise-and (shr v (* (mod i 4) 8)) 0xFF))
                })
                s
        })
})

(defun save-config () {
        (setq save-fail -1)
        (st-i A-PORT      cfg-mqtt-port)
        (st-i A-VESCID    cfg-vesc-id)
        (st-i A-PUBMODE   cfg-pub-mode)
        (st-i A-KEEPALIVE cfg-keepalive)
        (st-i A-PUBMS     (to-i (* cfg-pub-interval 1000.0)))
        (st-i A-CANMODE   cfg-can-mode)
        (st-f A-SPEEDDIV  cfg-speed-div)
        (st-f A-TORQUE    cfg-torque-k)
        (eep-store-str A-HOST   16 cfg-mqtt-host)
        (eep-store-str A-USER   8  cfg-mqtt-user)
        (eep-store-str A-MPASS  8  cfg-mqtt-pass)
        (eep-store-str A-PREFIX 12 cfg-topic-prefix)
        (st-i A-MAGIC eep-magic)   ; magic last -> only valid when whole record written
})

(defun load-defaults () {
        (setq cfg-mqtt-host    def-mqtt-host)
        (setq cfg-mqtt-port    def-mqtt-port)
        (setq cfg-mqtt-user    def-mqtt-user)
        (setq cfg-mqtt-pass    def-mqtt-pass)
        (setq cfg-topic-prefix def-topic-prefix)
        (setq cfg-pub-mode     def-pub-mode)
        (setq cfg-pub-interval def-pub-interval)
        (setq cfg-vesc-id      def-vesc-id)
        (setq cfg-speed-div    def-speed-div)
        (setq cfg-torque-k     def-torque-k)
        (setq cfg-keepalive    def-keepalive)
        (setq cfg-can-mode     def-can-mode)
})

; Load config from EEPROM. Returns t if a valid saved record was found,
; nil if defaults were used.
(defun load-config () {
        (load-defaults)
        (setq cfg-src "defaults")
        (if (magic-ok)
            {
                (var p (eeprom-read-i A-PORT))
                (var v (eeprom-read-i A-VESCID))
                (var m (eeprom-read-i A-PUBMODE))
                (var k (eeprom-read-i A-KEEPALIVE))
                (var pi (eeprom-read-i A-PUBMS))
                (var cm (eeprom-read-i A-CANMODE))
                (var sd (eeprom-read-f A-SPEEDDIV))
                (var tk (eeprom-read-f A-TORQUE))
                (var ho (eep-read-str A-HOST   64))
                (var us (eep-read-str A-USER   32))
                (var mp (eep-read-str A-MPASS  32))
                (var pf (eep-read-str A-PREFIX 48))
                (if p  (setq cfg-mqtt-port p))
                (if v  (setq cfg-vesc-id v))
                (if m  (setq cfg-pub-mode m))
                (if k  (setq cfg-keepalive k))
                (if pi (setq cfg-pub-interval (/ (to-float pi) 1000.0)))
                (if cm (setq cfg-can-mode cm))
                (if sd (setq cfg-speed-div sd))
                (if tk (setq cfg-torque-k tk))
                (if ho (setq cfg-mqtt-host ho))
                (if us (setq cfg-mqtt-user us))
                (if mp (setq cfg-mqtt-pass mp))
                (if pf (setq cfg-topic-prefix pf))
                (setq cfg-src "eeprom")
                t
            }
            nil)
})

(defun clear-config () (eeprom-store-i A-MAGIC 0)) ; invalidate -> defaults on next boot

; Is a valid saved record present? Compare numerically: eeprom-read-i yields an
; i32, and returns nil when the slot was never written.
(defun magic-ok () {
        (var m (eeprom-read-i A-MAGIC))
        (if (eq (type-of m) (type-of 1i32)) (= m eep-magic) nil)
})

;;; ================= Minimal MQTT 3.1.1 client (QoS 0, publish only) =========

; CONNECT with optional username/password auth (flags 0x80/0x40).
(defun mqtt-send-connect (s client-id) {
        (var idlen (str-len client-id))
        (var ulen  (str-len cfg-mqtt-user))
        (var plen  (str-len cfg-mqtt-pass))
        (var has-user (> ulen 0))
        (var has-pass (and has-user (> plen 0)))
        (var flags (bitwise-or 0x02
                     (bitwise-or (if has-user 0x80 0) (if has-pass 0x40 0))))
        (var rem (+ 10 2 idlen
                    (if has-user (+ 2 ulen) 0)
                    (if has-pass (+ 2 plen) 0)))
        (var pkt (bufcreate (+ 2 rem)))     ; rem < 128 (creds are length-capped)
        (bufset-u8  pkt 0 0x10)
        (bufset-u8  pkt 1 rem)
        (bufset-u16 pkt 2 4)
        (bufset-u8  pkt 4 77) (bufset-u8 pkt 5 81)
        (bufset-u8  pkt 6 84) (bufset-u8 pkt 7 84)
        (bufset-u8  pkt 8 4)
        (bufset-u8  pkt 9 flags)
        (bufset-u16 pkt 10 cfg-keepalive)
        (bufset-u16 pkt 12 idlen)
        (bufcpy pkt 14 client-id 0 idlen)
        (var off (+ 14 idlen))
        (if has-user {
                (bufset-u16 pkt off ulen)
                (bufcpy pkt (+ off 2) cfg-mqtt-user 0 ulen)
                (setq off (+ off 2 ulen))
        })
        (if has-pass {
                (bufset-u16 pkt off plen)
                (bufcpy pkt (+ off 2) cfg-mqtt-pass 0 plen)
                (setq off (+ off 2 plen))
        })
        (tcp-send s pkt)
})

(defun mqtt-wait-connack (s) {
        (var resp (tcp-recv s 4 5.0 false))
        (if (or (eq resp 'no-data) (eq resp 'disconnected) (eq resp nil))
            nil
            (and (>= (buflen resp) 4)
                 (= (bufget-u8 resp 0) 0x20)
                 (= (bufget-u8 resp 3) 0)))
})

(defun mqtt-publish (s topic payload) {
        (var tlen (str-len topic))
        (var plen (str-len payload))
        (var rem-len (+ 2 tlen plen))
        (var hdr (if (< rem-len 128) 2 3))
        (var pkt (bufcreate (+ hdr rem-len)))
        (bufset-u8 pkt 0 0x30)
        (if (< rem-len 128)
            (bufset-u8 pkt 1 rem-len)
            {
                (bufset-u8 pkt 1 (bitwise-or (bitwise-and rem-len 0x7F) 0x80))
                (bufset-u8 pkt 2 (shr rem-len 7))
        })
        (bufset-u16 pkt hdr tlen)
        (bufcpy pkt (+ hdr 2) topic 0 tlen)
        (bufcpy pkt (+ hdr 2 tlen) payload 0 plen)
        (tcp-send s pkt)
})

(defun mqtt-ping (s) (tcp-send s [0xC0 0x00]))

(defun mqtt-disconnect-local () {
        (if sock (tcp-close sock))
        (setq sock nil)
})

(defun mqtt-connect () {
        (mqtt-disconnect-local)
        (var s (tcp-connect cfg-mqtt-host cfg-mqtt-port))
        (if (or (eq s nil) (eq s 'unknown_host) (eq s 'unknown-host))
            { (setq mqtt-err "tcp-connect failed") (print "TCP connect to broker failed") }
            {
                (var cid (str-merge "mqttcan4vesc-" (str-from-n (mod (rand) 65536))))
                ; trap: on early boot the network stack may not be ready and
                ; tcp-send can throw -- catch it, close the socket, and let the
                ; main loop retry instead of killing the thread.
                (match (trap {
                        (mqtt-send-connect s cid)
                        (mqtt-wait-connack s)
                    })
                    ((exit-ok (? ok))
                        (if ok
                            {
                                (setq sock s)
                                (setq last-tx (systime))
                                (setq mqtt-err "none")
                                (print "MQTT connected")
                            }
                            {
                                (tcp-close s)
                                (setq mqtt-err "CONNACK rejected/auth")
                                (print "MQTT CONNACK failed")
                            }))
                    ((exit-error (? e))
                        {
                            (tcp-close s)
                            (setq mqtt-err "connect send error (retrying)")
                            (print "MQTT connect send error (retrying)")
                        }))
        })
})

; Drain any bytes the broker sent (PINGRESP etc.); detect a dropped link.
(defun mqtt-drain (s) {
        (var r (tcp-recv s 64 nil false))
        (if (eq r 'disconnected) (mqtt-disconnect-local))
})

(defun pub (topic payload)
    (if sock {
            (var r (mqtt-publish sock (str-merge cfg-topic-prefix topic) payload))
            (if (eq r t) (setq last-tx (systime)) (mqtt-disconnect-local))
    }))
(defun pubf (topic val) (pub topic (str-from-n val "%.4f")))

;;; ================= CAN handling ============================================

(defun proc-can-eid (id data)
    (if (>= (buflen data) 8) {
            (var node (bitwise-and id 0xFFu32))
            (var cmd (shr id 8))
            (if (= cmd cmd-status-1) (setq last-seen-node node)) ; for Detect
            (if (= node cfg-vesc-id) {
            (cond
                ((= cmd cmd-status-1) {
                    ; bytes 0-3 = eRPM (i32), 4-5 = current * 10 (i16), 6-7 = duty * 1000
                    (var raw-i (to-float (bufget-i16 data 4)))   ; amps * 10
                    (setq erpm          (to-float (bufget-i32 data 0)))
                    (setq current-motor (/ raw-i 10.0))
                    (setq motor-speed   (/ erpm cfg-speed-div))
                    (setq motor-torque  (* raw-i cfg-torque-k))
                    (setq duty          (/ (to-float (bufget-i16 data 6)) 1000.0))
                })
                ((= cmd cmd-status-2) {
                    (setq ah-used    (/ (to-float (bufget-i32 data 0)) 10000.0))
                    (setq ah-charged (/ (to-float (bufget-i32 data 4)) 10000.0))
                })
                ((= cmd cmd-status-3) {
                    (setq wh-used    (/ (to-float (bufget-i32 data 0)) 10000.0))
                    (setq wh-charged (/ (to-float (bufget-i32 data 4)) 10000.0))
                })
                ((= cmd cmd-status-4) {
                    (setq temp-fet   (/ (to-float (bufget-i16 data 0)) 10.0))
                    (setq temp-motor (/ (to-float (bufget-i16 data 2)) 10.0))
                    (setq current-in (/ (to-float (bufget-i16 data 4)) 10.0))
                    (setq pid-pos    (/ (to-float (bufget-i16 data 6)) 50.0))
                })
                ((= cmd cmd-status-5) {
                    (setq tacho (to-float (bufget-i32 data 0)))
                    (setq v-in  (/ (to-float (bufget-i16 data 4)) 10.0))
                })
                ((= cmd cmd-status-6) {
                    (setq adc1 (/ (to-float (bufget-i16 data 0)) 1000.0))
                    (setq adc2 (/ (to-float (bufget-i16 data 2)) 1000.0))
                    (setq adc3 (/ (to-float (bufget-i16 data 4)) 1000.0))
                    (setq ppm  (/ (to-float (bufget-i16 data 6)) 1000.0))
                })
                (t nil))
            (setq can-frames (+ can-frames 1))
            (setq last-frame (systime))
            (setq new-data true)
            })
    }))

;;; ================= Telemetry publishing ====================================

(defun jf (name val last)
    (str-merge "\"" name "\":" (str-from-n val "%.4f") (if last "}" ",")))

(defun telemetry-json ()
    (str-merge "{"
        ; raw, straight off the bus
        (jf "erpm" erpm nil)
        (jf "current_motor" current-motor nil)
        ; derived from the two above (speed-div / torque-k)
        (jf "motor_speed" motor-speed nil)
        (jf "motor_torque" motor-torque nil)
        (jf "duty" duty nil)
        (jf "amp_hours" ah-used nil)
        (jf "amp_hours_charged" ah-charged nil)
        (jf "watt_hours" wh-used nil)
        (jf "watt_hours_charged" wh-charged nil)
        (jf "temp_fet" temp-fet nil)
        (jf "temp_motor" temp-motor nil)
        (jf "current_in" current-in nil)
        (jf "pid_pos" pid-pos nil)
        (jf "tachometer" tacho nil)
        (jf "v_in" v-in nil)
        (jf "adc1" adc1 nil)
        (jf "adc2" adc2 nil)
        (jf "adc3" adc3 nil)
        (jf "ppm" ppm true)))

(defun publish-topics () {
        (pubf "erpm" erpm)                (pubf "current_motor" current-motor)
        (pubf "motor_speed" motor-speed)  (pubf "motor_torque" motor-torque)
        (pubf "duty" duty)
        (pubf "amp_hours" ah-used)        (pubf "amp_hours_charged" ah-charged)
        (pubf "watt_hours" wh-used)       (pubf "watt_hours_charged" wh-charged)
        (pubf "temp_fet" temp-fet)        (pubf "temp_motor" temp-motor)
        (pubf "current_in" current-in)    (pubf "pid_pos" pid-pos)
        (pubf "tachometer" tacho)         (pubf "v_in" v-in)
        (pubf "adc1" adc1) (pubf "adc2" adc2) (pubf "adc3" adc3) (pubf "ppm" ppm)
})

(defun publish-telemetry () {
        (if (or (= cfg-pub-mode 0) (= cfg-pub-mode 2)) (pub "telemetry" (telemetry-json)))
        (if (or (= cfg-pub-mode 1) (= cfg-pub-mode 2)) (publish-topics))
})

; vesc-mode FALLBACK ONLY: if no status frames are being decoded (statuses
; disabled on the ESC, or a firmware that hides them from lisp), pull what the
; firmware's own VESC-protocol decoder cached via canget-* (real-unit floats).
; Fewer fields than the event decode: amp_hours / watt_hours / tachometer /
; pid_pos have no canget-* and stay 0. Does NOT bump can-frames — that counter
; means "real status frames decoded", so a frozen can_frames + moving telemetry
; on the panel is the signature of running on this fallback.
(defun poll-vesc () {
        (var id cfg-vesc-id)
        (setq erpm          (canget-rpm id))          ; electrical rpm
        (setq current-motor (canget-current id))      ; amps
        (setq motor-speed   (/ erpm cfg-speed-div))
        ; torque-k is per raw 0.1 A unit, so scale amps back up by 10
        (setq motor-torque  (* current-motor (* 10.0 cfg-torque-k)))
        (setq duty         (canget-duty id))
        (setq v-in         (canget-vin id))
        (setq temp-fet     (canget-temp-fet id))
        (setq temp-motor   (canget-temp-motor id))
        (setq current-in   (canget-current-in id))
        (setq adc1 (canget-adc id 0)) (setq adc2 (canget-adc id 1)) (setq adc3 (canget-adc id 2))
        (setq ppm  (canget-ppm id))
})

;;; ================= Simulation (can_mode = 2) ===============================
; Bench/demo mode: no VESC on the CAN bus. Each publish tick fills the
; telemetry globals with a plausible random walk so the full MQTT/dashboard
; chain can be tested end to end. can_frames counts sim ticks in this mode.

(defun frand () (/ (to-float (bitwise-and (rand) 0x7FFF)) 32767.0)) ; 0.0 - 1.0
(defun clampf (v lo hi) (if (< v lo) lo (if (> v hi) hi v)))
(defun walk (v lo hi step) (clampf (+ v (* (- (frand) 0.5) 2.0 step)) lo hi))

(defun sim-telemetry () {
        (var dt cfg-pub-interval)
        ; walk the RAW signals, then derive exactly as the real decoder does, so
        ; sim output stays self-consistent with speed-div / torque-k.
        (setq erpm          (walk erpm 0.0 10000.0 480.0))
        (setq current-motor (walk current-motor 0.0 60.0 4.0))
        (setq motor-speed   (/ erpm cfg-speed-div))
        (setq motor-torque  (* current-motor (* 10.0 cfg-torque-k)))
        (setq duty         (clampf (/ motor-speed 2600.0) 0.0 0.95))
        (setq current-in   (clampf (+ (* current-motor duty) (* (frand) 2.0)) 0.0 60.0))
        (setq v-in         (walk v-in 42.0 54.4 0.2))
        (setq temp-fet     (walk temp-fet 25.0 85.0 0.5))
        (setq temp-motor   (walk temp-motor 25.0 95.0 0.5))
        (setq pid-pos      (walk pid-pos 0.0 360.0 15.0))
        (setq adc1 (walk adc1 0.0 3.3 0.1))
        (setq adc2 (walk adc2 0.0 3.3 0.1))
        (setq adc3 (walk adc3 0.0 3.3 0.1))
        (setq ppm  (walk ppm 0.0 1.0 0.05))
        ; integrators: consumed charge/energy and distance follow the sim load
        (setq ah-used (+ ah-used (/ (* current-in dt) 3600.0)))
        (setq wh-used (+ wh-used (/ (* (* current-in v-in) dt) 3600.0)))
        (setq tacho   (+ tacho (* motor-speed dt)))
        (setq can-frames (+ can-frames 1))
})

;;; ================= WiFi helper =============================================
; The firmware connects and auto-reconnects on its own (station config in
; VESC Tool). We only read the status; `wifi-status` errors if WiFi Mode is
; Disabled, so trap it and report 'disabled rather than dying.

(defun wifi-state ()
    (match (trap (wifi-status))
        ((exit-ok (? s)) s)
        ((exit-error (? e)) 'disabled)))

(defun wifi-up () (eq (wifi-state) 'connected))

;;; ================= Panel protocol (custom app data) ========================
; QML sends null-terminated ASCII commands; we reply with null-terminated
; ASCII. Dispatch on the first whitespace-delimited token. See docs/qml-panel.md.

(defun streq (a b) (= (str-cmp a b) 0))

; NOTE: `str-find` is absent on older Express firmware (it is the last
; extension added in lbm_string_extensions_init, so it is the first to drop
; off an older build). Strings are byte arrays, so scan for the char code
; ourselves. Returns the index of the first byte == c, or -1.
(defun str-idx (s c) {
        (var n (str-len s))
        (var i 0)
        (var res -1)
        (loopwhile (and (< i n) (< res 0))
            (if (= (bufget-u8 s i) c)
                (setq res i)
                (setq i (+ i 1))))
        res
})

(defun first-token (s) {
        (var i (str-idx s 32))
        (if (< i 0) s (str-part s 0 i))
})
(defun rest-after (s) {
        (var i (str-idx s 32))
        ; guard: newer firmware's str-part errors when start >= len, so return
        ; "" when there is no space OR nothing follows it (e.g. "SET key " with
        ; an empty value like a blank wifi/mqtt password).
        (if (or (< i 0) (>= (+ i 1) (str-len s)))
            ""
            (str-part s (+ i 1)))
})

(defun mode-name (m) (cond ((= m 1) "topics") ((= m 2) "both") (t "json")))
(defun mode-code (s) (cond ((streq s "topics") 1) ((streq s "both") 2) (t 0)))
(defun can-mode-name (m) (cond ((= m 1) "vesc") ((= m 2) "sim") (t "raw")))
(defun can-mode-code (s) (cond ((streq s "vesc") 1) ((streq s "sim") 2) (t 0)))

; Comma-join a list of ints (for DETECT scan results); "none" if empty.
(defun join-ids (lst) {
        (var s "")
        (loopwhile lst {
                (setq s (if (= (str-len s) 0)
                            (str-from-n (car lst))
                            (str-merge s "," (str-from-n (car lst)))))
                (setq lst (cdr lst))
        })
        (if (= (str-len s) 0) "none" s)
})

; Detect the controller id. vesc mode: can-scan the bus. raw mode: report the
; node id of the last status-1 frame sniffed. sim mode: report the Express's
; OWN can id -- a real controller can never share it, so a vesc_id equal to the
; bridge's own id is an unambiguous "this data is simulated" marker. It is also
; a plain number in 0..254, so unlike the old literal reply "sim" it passes the
; panel's field validation and survives a Save.
(defun do-detect ()
    (cond
        ((= cfg-can-mode 2) (str-merge "DETECT " (str-from-n (can-local-id))))
        ((= cfg-can-mode 1) {
            ; active scan; if nothing answers, fall back to the last node
            ; whose status-1 frame we sniffed
            (var ids (join-ids (can-scan)))
            (str-merge "DETECT "
                (if (and (streq ids "none") (>= last-seen-node 0))
                    (str-from-n last-seen-node) ids))
        })
        (t (str-merge "DETECT " (if (>= last-seen-node 0)
                                    (str-from-n last-seen-node) "none")))))

(defun kv (k v) (str-merge k "=" v "\n"))
(defun kvn (k v) (str-merge k "=" (str-from-n v) "\n"))
(defun kvf (k v) (str-merge k "=" (str-from-n v "%.4f") "\n"))

(defun build-cfg ()
    (str-merge "CFG\n"
        (kvn "ver" proto-version)
        (kv  "mqtt_host" cfg-mqtt-host)
        (kvn "mqtt_port" cfg-mqtt-port)
        (kv  "mqtt_user" cfg-mqtt-user)
        (kv  "mqtt_pass" cfg-mqtt-pass)
        (kv  "topic_prefix" cfg-topic-prefix)
        (kv  "pub_mode" (mode-name cfg-pub-mode))
        (kvf "pub_interval" cfg-pub-interval)
        (kv  "can_mode" (can-mode-name cfg-can-mode))
        (kvn "vesc_id" cfg-vesc-id)
        (kvf "speed_div" cfg-speed-div)
        (kvf "torque_k" cfg-torque-k)
        (kvn "keepalive" cfg-keepalive)))

(defun build-tel ()
    (str-merge "TEL\n"
        (kv  "wifi_state" (to-str (wifi-state)))
        (kv  "mqtt_state" (if sock "connected" "disconnected"))
        (kv  "mqtt_err" mqtt-err)
        (kv  "cfg_src" cfg-src)
        (kv  "can_mode" (can-mode-name cfg-can-mode))
        (kvf "motor_speed" motor-speed)
        (kvf "motor_torque" motor-torque)
        (kvf "duty" duty)
        (kvf "v_in" v-in)
        (kvf "temp_fet" temp-fet)
        (kvf "temp_motor" temp-motor)
        (kvf "current_in" current-in)
        (kvn "can_frames" can-frames)
        (kv  "pkg_ver" pkg-version)))

; Validate + apply one SET. Returns nil ok, or an error string.
(defun apply-set (key val) {
        (var vlen (str-len val))
        (cond
            ; wifi_ssid / wifi_pass are deliberately absent: WiFi is configured
            ; in VESC Tool -> VESC Express -> WiFi, not from this panel.
            ((streq key "mqtt_host")
                (if (or (< vlen 1) (> vlen 63)) "host len 1-63"
                    (progn (setq cfg-mqtt-host val) nil)))
            ((streq key "mqtt_port") {
                (var p (str-to-i val))
                (if (or (< p 1) (> p 65535)) "port 1-65535"
                    (progn (setq cfg-mqtt-port p) nil)) })
            ((streq key "mqtt_user")
                (if (> vlen 32) "user len <=32"
                    (progn (setq cfg-mqtt-user val) nil)))
            ((streq key "mqtt_pass")
                (if (> vlen 32) "mpass len <=32"
                    (progn (setq cfg-mqtt-pass val) nil)))
            ((streq key "topic_prefix")
                (if (> vlen 48) "prefix len <=48"
                    (progn (setq cfg-topic-prefix val) nil)))
            ((streq key "pub_mode")
                (progn (setq cfg-pub-mode (mode-code val)) nil))
            ((streq key "can_mode")
                (progn (setq cfg-can-mode (can-mode-code val)) nil))
            ((streq key "pub_interval") {
                (var f (str-to-f val))
                (if (or (< f 0.1) (> f 5.0)) "interval 0.1-5.0"
                    (progn (setq cfg-pub-interval f) nil)) })
            ((streq key "vesc_id") {
                (var v (str-to-i val))
                (if (or (< v 0) (> v 254)) "id 0-254"
                    (progn (setq cfg-vesc-id v) nil)) })
            ((streq key "speed_div") {
                (var f (str-to-f val))
                (if (<= f 0.0) "speed_div >0"
                    (progn (setq cfg-speed-div f) nil)) })
            ((streq key "torque_k")
                (progn (setq cfg-torque-k (str-to-f val)) nil))
            ((streq key "keepalive") {
                (var k (str-to-i val))
                (if (or (< k 10) (> k 300)) "keepalive 10-300"
                    (progn (setq cfg-keepalive k) nil)) })
            (t (str-merge "unknown key " key)))
})

(defun do-set (r) {
        (var key (first-token r))
        (var val (rest-after r))
        (var err (apply-set key val))
        (if err (send-data (str-merge "ERR SET " key " " err))
                (send-data (str-merge "ACK SET " key)))
})

(defun handle-cmd (data) {
        (var cmd (first-token data))
        (cond
            ((streq cmd "GET")  (send-data (build-cfg)))
            ((streq cmd "TEL")  (send-data (build-tel)))
            ((streq cmd "SET")  (do-set (rest-after data)))
            ((streq cmd "DETECT") (send-data (do-detect)))
            ((streq cmd "SAVE") {
                ; Write, then READ BACK the magic to prove the record took. A
                ; bare (save-config) is not evidence: handle-cmd traps errors,
                ; so a throwing eeprom write used to vanish without a reply and
                ; looked exactly like a working save that failed to persist.
                (match (trap (save-config))
                    ((exit-ok (? v))
                        (if (>= save-fail 0)
                            (send-data (str-merge "ERR SAVE eeprom-write-rejected slot="
                                                  (str-from-n save-fail)))
                            (if (magic-ok)
                                {
                                    (setq reconnect-req true)
                                    (send-data "ACK SAVE")
                                }
                                (send-data (str-merge "ERR SAVE verify-failed magic-read="
                                                      (to-str (eeprom-read-i A-MAGIC)))))))
                    ((exit-error (? e))
                        (send-data (str-merge "ERR SAVE threw: " (to-str e))))) })
            ((streq cmd "TEST")
                (send-data
                    (if (and (wifi-up) sock)
                        "TEST ok"
                        (str-merge "TEST fail wifi=" (to-str (wifi-state))
                                   " mqtt=" (if sock "up" mqtt-err)))))
            ((streq cmd "DEFAULTS") {
                (clear-config)
                (load-defaults)
                (setq reconnect-req true)
                (send-data (build-cfg)) })
            ((streq cmd "REBOOT") {
                (send-data "ACK REBOOT")
                (sleep 0.3)
                (reboot) })
            (t (send-data (str-merge "ERR unknown " cmd))))
})

;;; ================= Event handler (CAN + panel, single thread) ==============

(defun event-handler ()
    (loopwhile t
        (recv
            ; trap each handler so one bad frame / panel command can't kill the thread
            ((event-can-eid . ((? id) . (? data))) (trap (proc-can-eid id data)))
            ((event-data-rx . (? data)) (trap (handle-cmd data)))
            (_ nil))))

;;; ================= Main loop ===============================================

(defun main-loop ()
    (loopwhile t {
            ; self-healing: catch any transient error (e.g. tcp-send/tcp-recv
            ; before the network stack is ready) so it can't kill this thread;
            ; drop the socket and retry on the next iteration.
            (match (trap {
            ; SAVE/DEFAULTS: only the MQTT session is ours to restart. Never
            ; touch WiFi here -- (wifi-disconnect) would disable the firmware's
            ; auto-reconnect until reboot.
            (if reconnect-req {
                    (setq reconnect-req false)
                    (mqtt-disconnect-local)
                    (sleep 0.5)
            })
            (if (not (wifi-up))
                ; the firmware connects and reconnects on its own; just wait
                {
                    (mqtt-disconnect-local)
                    (sleep 1)
                }
                (if (not sock)
                    { (mqtt-connect) (if (not sock) (sleep 3)) }
                    {
                        (cond
                            ; sim mode: generate fake data on the interval
                            ((= cfg-can-mode 2)
                                (if (>= (secs-since last-pub) cfg-pub-interval) {
                                        (setq last-pub (systime))
                                        (sim-telemetry)
                                        (publish-telemetry)
                                }))
                            ; raw AND vesc mode: publish decoded status data,
                            ; throttled to the interval. The firmware delivers
                            ; every CAN frame to event-can-eid even with the
                            ; VESC decoder on, so vesc mode gets the full
                            ; status 1-6 decode too.
                            ((and new-data (>= (secs-since last-pub) cfg-pub-interval)) {
                                    (setq new-data false)
                                    (setq last-pub (systime))
                                    (publish-telemetry)
                            })
                            ; vesc mode, no status frames for 3 s (disabled on
                            ; the ESC?): fall back to polling the firmware's
                            ; canget-* cache so telemetry keeps flowing.
                            ((and (= cfg-can-mode 1)
                                  (> (secs-since last-frame) 3.0)
                                  (>= (secs-since last-pub) cfg-pub-interval)) {
                                    (setq last-pub (systime))
                                    (poll-vesc)
                                    (publish-telemetry)
                            })
                            (t nil))
                        (if (> (secs-since last-tx) (/ cfg-keepalive 2)) {
                                (if (eq (mqtt-ping sock) t)
                                    (setq last-tx (systime))
                                    (mqtt-disconnect-local))
                        })
                        (if sock (mqtt-drain sock))
                    }))
            })
                ((exit-error (? e)) (mqtt-disconnect-local))
                ((exit-ok (? v)) nil))
            (sleep 0.1)
    }))

;;; ================= Entry point =============================================
; Newer LispBM `image-save` requires a global closure named `main`, and the
; firmware auto-runs (main) on boot. Keep ALL runtime startup here so it re-runs
; every boot (image-save saves the code/env, not running threads/registrations).
(defun main () {
        ; Let the firmware's WiFi / CAN / network subsystems finish coming up
        ; before we use them. On a cold boot the LBM VM starts very early; using
        ; the network too soon throws (e.g. tcp-send) and, without the traps
        ; below, would leave the script dead until a manual restart.
        (sleep 3)
        (load-config)                ; sets cfg-can-mode from EEPROM (needed next)
        ; The firmware hands every CAN frame to event-can-eid BEFORE (and
        ; regardless of) its own VESC-protocol decoder, so status sniffing
        ; works with the protocol on. vesc/sim -> protocol ON (VESC Tool CAN
        ; bridging + canget-* fallback work). raw -> protocol OFF; only needed
        ; if a firmware build ever stops delivering events with it on.
        (can-use-vesc (if (= cfg-can-mode 0) false true))
        (print (str-merge "MQTTCAN4VESC config from " cfg-src))
        (print (str-merge "MQTTCAN4VESC loaded. mode=" (can-mode-name cfg-can-mode)
                          " wifi=" (to-str (wifi-state)) " broker=" cfg-mqtt-host))
        (if (eq (wifi-state) 'disabled)
            (print "WiFi is disabled/AP-mode. Set WiFi Mode = Station + SSID/Key in VESC Tool -> VESC Express -> WiFi."))
        (event-register-handler (spawn event-handler))
        (event-enable 'event-can-eid)
        (event-enable 'event-data-rx)
        (main-loop)
})

@const-end
; ^ everything above is read into flash (const heap), not the RAM cons heap.
; This is required on the ESP32-C3 Express: when BOTH WiFi and BLE are enabled
; the LispBM RAM heap is halved (~4096 cons cells / 32 KB), and the script would
; otherwise hit "eval: out of memory" on upload. Keep the runtime startup below
; OUTSIDE the const region.

;;; ================= Start ====================================================
; Save the flat image (requires the `main` closure above), then run it. On every
; boot the firmware auto-runs (main); calling it here starts it for this session.
(image-save)
(main)
