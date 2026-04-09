;@const-symbol-strings
@const-start
; Magic header
(def magic-header 544i32)
; Persistent settings

; Format: (label . (offset type default-value current-value))
(def eeprom-addrs '(
    (magic                     . (0 i magic-header))
    (crc                       . (1 i 61381))
    (can-id                    . (2  i -1))  ; if can-id < 0 then it will scan for one and pick the first.
    (reserved-slot-3           . (3 b 0))
    (led-enabled               . (4 b 1))
    (reserved-slot-5               . (5 b 2))
    (led-on                    . (6 b 1))
    (led-highbeam-on           . (7 b 1))
    (led-mode                  . (8 i 0))
    (led-mode-idle             . (9 i 2))
    (led-mode-status           . (10 i 0))
    (led-mode-startup          . (11 i 1))
    (led-mall-grab-enabled     . (12 b 1))
    (led-brake-light-enabled   . (13 b 1))
    (led-brake-light-min-amps  . (14 f -4.0))
    (idle-timeout              . (15 i 1))
    (idle-timeout-shutoff      . (16 i 600))
    (led-brightness            . (17 f 0.8))
    (led-brightness-highbeam   . (18 f 0.8))
    (led-brightness-idle       . (19 f 0.5))
    (led-brightness-status     . (20 f 0.2))
    (led-status-pin            . (21 i 7))
    (led-status-num            . (22 i 10))
    (led-status-type           . (23 i 0))
    (led-status-reversed       . (24 b 1))
    (led-front-pin             . (25 i 5))
    (led-front-num             . (26 i 11))
    (led-front-type            . (27 i 0))
    (led-front-reversed        . (28 b 1))
    (led-front-strip-type      . (29 b 0))
    (led-rear-pin              . (30 i 6))
    (led-rear-num              . (31 i 11))
    (led-rear-type             . (32 i 0))
    (led-rear-reversed         . (33 b 1))
    (led-rear-strip-type       . (34 b 0))
    (reserved-slot-35      . (35 i -1))
    (reserved-slot-36      . (36 i -1))
    (reserved-slot-37       . (37 i -1))
    (reserved-slot-38          . (38 i 16))
    (reserved-slot-39          . (39 i 8))
    (reserved-slot-40        . (40 i 17))
    (reserved-slot-41            . (41 i -1))
    (reserved-slot-42          . (42 i 0))
    (reserved-slot-43            . (43 b 1))
    (reserved-slot-44                 . (44 i -1))
    (reserved-slot-45                 . (45 i -1))
    (reserved-slot-46                 . (46 i -1))
    (reserved-slot-47                 . (47 i -1))
    (reserved-slot-48             . (48 i -1))
    (reserved-slot-49             . (49 i -1))
    (reserved-slot-50             . (50 i -1))
    (reserved-slot-51             . (51 i -1))
    (led-loop-delay            . (52 i 40))
    (reserved-slot-53            . (53 i 8))
    (can-loop-delay            . (54 i 2))
    (led-max-blend-count       . (55 i 8))
    (led-startup-timeout       . (56 i 10))
    (led-dim-on-highbeam-ratio . (57 f 0.2))
    (reserved-slot-58                  . (58 i 0))
    (led-status-strip-type     . (59 i 0))
    (reserved-slot-60           . (60 b 0))
    (led-fix                   . (61 i 100))
    (led-show-battery-charging . (62 b 0))
    (led-front-highbeam-pin    . (63 i -1))
    (led-rear-highbeam-pin     . (64 i -1))
    (reserved-slot-65             . (65 i 128))
    (led-max-brightness        . (66 f 0.8))
    (soc-type                  . (67 i 1))
    (cell-type                 . (68 i 4))
    (led-update-not-running    . (69 b 0))
    (reserved-slot-70          . (70 b 0))
    (series-cells             . (71 i -1))
    (reserved-slot-72          . (72 i -1))
    (front-target-id		   . (73 i -1))
    (rear-target-id		   	   . (74 i -1))
    (status-target-id          . (75 i -1))
    (node-role                 . (76 i 1))   ; 0=master, 1=slave
    (master-can-id             . (77 i -1))  ; slave: who I obey
    (peers-cache               . (78 i 0))   ; optional: bump when peer list changes (UI refresh hint)
))
(def ui-config-keys '(
    magic
    led-enabled
    led-on
    led-highbeam-on
    led-mode
    led-mode-idle
    led-mode-status
    led-mall-grab-enabled
    led-brake-light-enabled
    led-brake-light-min-amps
    idle-timeout
    idle-timeout-shutoff
    led-brightness
    led-brightness-highbeam
    led-brightness-idle
    led-brightness-status
    led-status-pin
    led-status-num
    led-status-type
    led-status-reversed
    led-front-pin
    led-front-num
    led-front-type
    led-front-reversed
    led-front-strip-type
    led-rear-pin
    led-rear-num
    led-rear-type
    led-rear-reversed
    led-rear-strip-type
    led-loop-delay
    can-loop-delay
    led-max-blend-count
    led-dim-on-highbeam-ratio
    led-status-strip-type
    led-fix
    led-front-highbeam-pin
    led-rear-highbeam-pin
    led-max-brightness
    cell-type
    led-update-not-running
    series-cells
    front-target-id
    rear-target-id
    status-target-id
    node-role
    master-can-id
    peers-cache
))
(def runtime-vals)
(setq runtime-vals (mklist (length eeprom-addrs) -1))

(def cfg-len (length eeprom-addrs))
(def read-cfg-len 0)
(def wifi-enabled-on-boot nil)
(def led-context-id -1)
(def led-exit-flag nil)
(def led-heartbeat-time 0.0)
(def led-last-activity-time (systime))
(def can-context-id -1)
(def can-last-activity-time (systime))

; LED settings used by settings.lisp - needed otherwise they will be unbound
(def led-on)
(def led-highbeam-on)
(def led-brightness 0.0)
(def led-brightness-highbeam 0.0)
(def led-brightness-idle 0.0)
(def led-brightness-status 0.0)



(def hum 0)
(def hum-temp 0)

(def ucl-cfg-dirty nil)
(def ucl-suppress-send-config nil)

; Shared motion/state defaults used across LED and CAN logic before first refloat frame.
(def state 0)
(def rpm 0.0)
(def battery-percent-remaining 0.0)
(def refloat-batt-voltage 0.0)
(def pitch-angle 0.0)
(def switch-state 0)
(def handtest-mode nil)
(def tot-current 0.0)
(def sat-t 0)
(def duty-cycle-now 0.0)
(def soc-type 1)
(def cell-type 4)
(def series-cells -1)
(def voltage-curve '(4.14 4.08 4.00 3.91 3.82 3.73 3.64 3.56 3.45 3.23 2.90))

(defunret running-state () {
    (or (= state 1) (= state 2) (= state 3) (= state 4))
})

(defun recv-control (in-led-on in-led-highbeam-on in-led-brightness in-led-brightness-highbeam in-led-brightness-idle in-led-brightness-status in-legacy-charge-state) {
    ; Refloat is authoritative for light on/highbeam state.
    ; Ignore control-channel on/highbeam fields to avoid stale UI writes overriding refloat.
    (setq led-brightness (to-float in-led-brightness))
    (setq led-brightness-highbeam (to-float in-led-brightness-highbeam))
    (setq led-brightness-idle (to-float in-led-brightness-idle))
    (setq led-brightness-status (to-float in-led-brightness-status))

    (set-config 'led-brightness (to-float in-led-brightness))
    (set-config 'led-brightness-highbeam (to-float in-led-brightness-highbeam))
    (set-config 'led-brightness-idle (to-float in-led-brightness-idle))
    (set-config 'led-brightness-status (to-float in-led-brightness-status))

})

(defun deprecated-feature-trigger () {
    (send-msg "Deprecated feature removed in this build")
})

(defun send-control () {
    (var config-string "control ")

    (setq config-string (
        str-merge
        config-string
        (str-from-n (to-i led-on) "%d ")
        (str-from-n (to-i led-highbeam-on) "%d ")
        (str-from-n led-brightness "%.2f ")
        (str-from-n led-brightness-highbeam "%.2f ")
        (str-from-n led-brightness-idle "%.2f ")
        (str-from-n led-brightness-status "%.2f ")
        (str-from-n 0 "%d ")
    ))

    (send-data config-string)
})

(defun recv-config (in-led-enabled in-reserved-slot-5 in-led-on in-led-highbeam-on in-led-mode in-led-mode-idle in-led-mode-status
    in-led-mall-grab-enabled in-led-brake-light-enabled in-led-brake-light-min-amps
    in-idle-timeout in-idle-timeout-shutoff in-led-brightness in-led-brightness-highbeam in-led-brightness-idle in-led-brightness-status
    in-led-status-pin in-led-status-num in-led-status-type in-led-status-reversed in-led-front-pin in-led-front-num in-led-front-type
    in-led-front-reversed in-led-front-strip-type in-led-rear-pin in-led-rear-num in-led-rear-type in-led-rear-reversed in-led-rear-strip-type
    in-reserved-slot-38 in-reserved-slot-39 in-reserved-slot-40 in-reserved-slot-41 in-reserved-slot-42 in-reserved-slot-43
    in-led-loop-delay in-reserved-slot-53 in-can-loop-delay in-led-max-blend-count
    in-led-dim-on-highbeam-ratio in-reserved-slot-58 in-led-status-strip-type in-reserved-slot-60 in-led-fix in-led-show-battery-charging
    in-led-front-highbeam-pin in-led-rear-highbeam-pin in-reserved-slot-65 in-led-max-brightness in-soc-type in-cell-type in-led-update-not-running
    in-reserved-slot-70 in-series-cells in-reserved-slot-72 in-front-target-id in-rear-target-id in-status-target-id
	in-node-role in-master-can-id in-peers-cache
) {
    (var prev-led-enabled (to-i (get-config 'led-enabled)))
    (set-config 'led-enabled (to-i in-led-enabled))
    
    (var reboot-now nil)
    (if (>= led-context-id 0) {
        (let ((start-time (systime)) (timeout-val 2000000)) ; 2 sec timeout

        (setq led-exit-flag t)

            (loopwhile (and led-exit-flag (< (- (systime) start-time) timeout-val))
                (yield 10000)) ; 10 ms wait

            ; Check if exited due to timeout
            (if led-exit-flag {
                (send-msg "ERROR: LED loop did not exit in time. Rebooting...")
                (setq reboot-now t)
            })
        )
    })


    (var next-series-cells (to-i in-series-cells))
    (if (= next-series-cells 0) (setq next-series-cells -1))
    (if (< next-series-cells -1) (setq next-series-cells -1))
    (if (> next-series-cells 64) (setq next-series-cells 64))

    (if (or (!= (to-i (get-config 'soc-type)) 1)
            (!= (to-i (get-config 'cell-type)) (to-i in-cell-type))
            (!= (to-i (get-config 'series-cells)) next-series-cells)) {
        ; State of charge is voltage-curve only now.
        (apply-battery-config 1 in-cell-type next-series-cells)
    })

    (set-config 'led-on (to-i in-led-on))
    (set-config 'led-highbeam-on (to-i in-led-highbeam-on))
    (set-config 'led-mode (to-i in-led-mode))
    (set-config 'led-mode-idle (to-i in-led-mode-idle))
    (set-config 'led-mode-status (to-i in-led-mode-status))
    (set-config 'led-mall-grab-enabled (to-i in-led-mall-grab-enabled))
    (set-config 'led-brake-light-enabled (to-i in-led-brake-light-enabled))
    (set-config 'led-brake-light-min-amps (to-float in-led-brake-light-min-amps))
    (set-config 'idle-timeout (to-i in-idle-timeout))
    (set-config 'idle-timeout-shutoff (to-i in-idle-timeout-shutoff))
    (set-config 'led-brightness (to-float in-led-brightness))
    (set-config 'led-brightness-highbeam (to-float in-led-brightness-highbeam))
    (set-config 'led-brightness-idle (to-float in-led-brightness-idle))
    (set-config 'led-brightness-status (to-float in-led-brightness-status))

    (set-config 'led-status-num (to-i in-led-status-num))
    (set-config 'led-status-type (to-i in-led-status-type))
    (set-config 'led-status-reversed (to-i in-led-status-reversed))

    (set-config 'led-front-num (to-i in-led-front-num))
    (set-config 'led-front-type (to-i in-led-front-type))
    (set-config 'led-front-reversed (to-i in-led-front-reversed))
    (set-config 'led-front-strip-type (to-i in-led-front-strip-type))

    (set-config 'led-rear-num (to-i in-led-rear-num))
    (set-config 'led-rear-type (to-i in-led-rear-type))
    (set-config 'led-rear-reversed (to-i in-led-rear-reversed))
    (set-config 'led-rear-strip-type (to-i in-led-rear-strip-type))

    (set-config 'reserved-slot-38 -1)
    (set-config 'reserved-slot-39 -1)
    (set-config 'reserved-slot-40 -1)
    (set-config 'reserved-slot-41 -1)
    (set-config 'reserved-slot-42 0)
    (set-config 'reserved-slot-43 0)

    (set-config 'led-loop-delay (to-i in-led-loop-delay))
    (set-config 'reserved-slot-53 (to-i in-reserved-slot-53))
    (set-config 'can-loop-delay (to-i in-can-loop-delay))
    (set-config 'led-max-blend-count (to-i in-led-max-blend-count))
    (set-config 'led-dim-on-highbeam-ratio (to-float in-led-dim-on-highbeam-ratio))

    (set-config 'reserved-slot-58 0)
    (set-config 'led-status-strip-type (to-i in-led-status-strip-type))
    (set-config 'reserved-slot-60 0)
    (set-config 'led-fix (to-i in-led-fix))
    (set-config 'led-show-battery-charging 0)
    (set-config 'reserved-slot-65 128)
    (set-config 'led-max-brightness (to-float in-led-max-brightness))
    (set-config 'soc-type 1)
    (set-config 'cell-type (to-i in-cell-type))
    (set-config 'led-update-not-running  (to-i in-led-update-not-running))

    (set-config 'reserved-slot-70 0)
    (set-config 'series-cells next-series-cells)
    (set-config 'reserved-slot-72 -1)
    (set-config 'front-target-id  (to-i in-front-target-id))
    (set-config 'rear-target-id   (to-i in-rear-target-id))
    (set-config 'status-target-id (to-i in-status-target-id))
    (var requested-node-role (to-i in-node-role))
    (var next-node-role (if (= (to-i (get-config 'node-role)) 0) 0 1))
    (if (= requested-node-role 0) (setq next-node-role 0))
    (if (= requested-node-role 1) (setq next-node-role 1))
    (var next-master-can-id (to-i in-master-can-id))
    (if (and (>= next-master-can-id 0) (= next-master-can-id (can-local-id))) {
        (send-msg "Invalid Master CAN-ID: cannot match local CAN-ID. Reset to -1.")
        (setq next-master-can-id -1)
    })
    (if (= next-node-role 0) {
        (if (!= next-master-can-id -1) {
            (send-msg "Master node forces Master CAN-ID to -1.")
        })
        (setq next-master-can-id -1)
    })
	    (var next-role-marker (if (= next-node-role 0) 3 2))
    (set-config 'node-role       next-node-role)
    (set-config 'reserved-slot-5 next-role-marker)
    (set-config 'master-can-id   next-master-can-id)
    (set-config 'peers-cache     (to-i in-peers-cache))

    ; Do not probe LED/PWM pins during config save. Hardware probing here can
    ; disturb active peripherals (including CAN) on some boards. The LED loop
    ; will apply pins at runtime.
    (set-config 'led-front-pin (to-i in-led-front-pin))
    (set-config 'led-rear-pin (to-i in-led-rear-pin))
    (set-config 'led-status-pin (to-i in-led-status-pin))
    (set-config 'led-front-highbeam-pin (to-i in-led-front-highbeam-pin))
    (set-config 'led-rear-highbeam-pin (to-i in-led-rear-highbeam-pin))

    ; Force-stop any stale loop context before re-spawn to avoid duplicate loops.
    (if (>= led-context-id 0) {
        (trap (kill led-context-id nil))
        (setq led-context-id -1)
    })
    (setq led-exit-flag nil)
    (if (not reboot-now) (setq led-context-id (if (= (get-config 'led-enabled) 1) (spawn led-loop) -1)))

    (save-config)
    (if (not ucl-suppress-send-config) {
        (send-config)
    })
    (if reboot-now {(send-msg "Rebooting") (reboot)})
})

(defun apply-config-from-runtime () {
    (recv-config
        (get-config 'led-enabled)
        (get-config 'reserved-slot-5)
        (get-config 'led-on)
        (get-config 'led-highbeam-on)
        (get-config 'led-mode)
        (get-config 'led-mode-idle)
        (get-config 'led-mode-status)
        (get-config 'led-mall-grab-enabled)
        (get-config 'led-brake-light-enabled)
        (get-config 'led-brake-light-min-amps)
        (get-config 'idle-timeout)
        (get-config 'idle-timeout-shutoff)
        (get-config 'led-brightness)
        (get-config 'led-brightness-highbeam)
        (get-config 'led-brightness-idle)
        (get-config 'led-brightness-status)
        (get-config 'led-status-pin)
        (get-config 'led-status-num)
        (get-config 'led-status-type)
        (get-config 'led-status-reversed)
        (get-config 'led-front-pin)
        (get-config 'led-front-num)
        (get-config 'led-front-type)
        (get-config 'led-front-reversed)
        (get-config 'led-front-strip-type)
        (get-config 'led-rear-pin)
        (get-config 'led-rear-num)
        (get-config 'led-rear-type)
        (get-config 'led-rear-reversed)
        (get-config 'led-rear-strip-type)
        (get-config 'reserved-slot-38)
        (get-config 'reserved-slot-39)
        (get-config 'reserved-slot-40)
        (get-config 'reserved-slot-41)
        (get-config 'reserved-slot-42)
        (get-config 'reserved-slot-43)
        (get-config 'led-loop-delay)
        (get-config 'reserved-slot-53)
        (get-config 'can-loop-delay)
        (get-config 'led-max-blend-count)
        (get-config 'led-dim-on-highbeam-ratio)
        (get-config 'reserved-slot-58)
        (get-config 'led-status-strip-type)
        (get-config 'reserved-slot-60)
        (get-config 'led-fix)
        (get-config 'led-show-battery-charging)
        (get-config 'led-front-highbeam-pin)
        (get-config 'led-rear-highbeam-pin)
        (get-config 'reserved-slot-65)
        (get-config 'led-max-brightness)
        (get-config 'soc-type)
        (get-config 'cell-type)
        (get-config 'led-update-not-running)
        (get-config 'reserved-slot-70)
        (get-config 'series-cells)
        (get-config 'reserved-slot-72)
        (get-config 'front-target-id)
        (get-config 'rear-target-id)
        (get-config 'status-target-id)
        (get-config 'node-role)
        (get-config 'master-can-id)
        (get-config 'peers-cache)
    )
})

(defun send-keys (key-list counter-list) {
    (setq key-list (split-list key-list 4))
    (set-config 'reserved-slot-44 (pack-bytes-to-uint32 (ix key-list 0)))
    (set-config 'reserved-slot-45 (pack-bytes-to-uint32 (ix key-list 1)))
    (set-config 'reserved-slot-46 (pack-bytes-to-uint32 (ix key-list 2)))
    (set-config 'reserved-slot-47 (pack-bytes-to-uint32 (ix key-list 3)))
    (setq counter-list (split-list counter-list 4))
    (set-config 'reserved-slot-48 (pack-bytes-to-uint32 (ix counter-list 0)))
    (set-config 'reserved-slot-49 (pack-bytes-to-uint32 (ix counter-list 1)))
    (set-config 'reserved-slot-50 (pack-bytes-to-uint32 (ix counter-list 2)))
    (set-config 'reserved-slot-51 (pack-bytes-to-uint32 (ix counter-list 3)))
    (save-config)
})

(defun send-config () {

    (var config-string "settings ")

    (loopforeach name ui-config-keys {
        (var type (second (assoc eeprom-addrs name)))
        (var value (read-val-eeprom name))
        (setq config-string
            (str-merge config-string
                (cond
                    ((eq type 'b) (str-from-n value "%d "))
                    ((eq type 'i) (str-from-n value "%d "))
                    ((eq type 'f) (str-from-n value "%.2f "))
                )
            )
        )
    })
    ; Runtime local CAN-ID as trailing token (keeps existing key order stable).
    (setq config-string (str-merge config-string (str-from-n (can-local-id) "%d ")))

        (send-data config-string)
        (send-status "Settings loaded")
})

(defunret get-config (name) {
    (ix runtime-vals (first (assoc eeprom-addrs name)))
})

(defun set-config (name value) {
    (setix runtime-vals (first (assoc eeprom-addrs name)) value)
})

(defun save-config () {
    (var cfg-node-role (to-i (get-config 'node-role)))
    (set-config 'reserved-slot-5 (if (= cfg-node-role 0) 3 2))
    (atomic {
        (loopforeach setting eeprom-addrs {
            (var name (first setting))
            (if (not-eq name 'crc) {
                (write-val-eeprom name (get-config name))
            })
        })

        (write-val-eeprom 'crc (config-crc cfg-len))
    })
	(setq ucl-cfg-dirty t)
    (send-status "Settings saved")
})

(defunret config-crc (len) {
    (var i 0)
	(var crclen (* (- len 1) 4))
	(var crcbuf (bufcreate crclen))
    (var j 0)
	(loopforeach setting eeprom-addrs {
        (if (>= j len) {(break)})
        (var name (first setting))

        (if (not-eq name 'crc) {
            (bufset-i32 crcbuf (* i 4) (get-config name))
            (setq i (+ i 1))
        })
        (setq j (+ j 1))
	})
    (var crc (crc16 crcbuf))
    (free crcbuf)
    (return crc)
})

(defun load-config () {
    (setq read-cfg-len 0)
    (loopforeach setting eeprom-addrs {
        (var name (first setting))
        (var val (read-val-eeprom name))
        (set-config name val)
        ; 0 is a valid stored value. Only stop when EEPROM returns nil.
        (if (not-eq val nil) (setq read-cfg-len (+ read-cfg-len 1)) {(break)})
    })
})

(defun restore-config () {
    (var is-s3-hw (if (= (str-cmp (sysinfo 'hw-name) "Avaspark RGB S3") 0) t nil))
    (var is-tw (= (str-cmp (sysinfo 'hw-name) "Twilight Lord LCM") 0))

    (atomic {
        (loopforeach setting eeprom-addrs {
            (var name (first setting))
            (var default-value (if (eq name 'magic) magic-header (ix setting 3)))
            (match name
                (magic (setq default-value magic-header))
                (led-status-pin (setq default-value (if is-s3-hw 9 10)))
                (led-front-pin (setq default-value (if is-s3-hw 15 5)))
                (led-front-highbeam-pin (setq default-value (if is-s3-hw 14 -1)))
                (led-front-strip-type (setq default-value (if is-s3-hw 7 0)))
                (led-rear-pin (setq default-value (if is-s3-hw 12 6)))
                (led-rear-highbeam-pin (setq default-value (if is-s3-hw 13 -1)))
                (led-rear-strip-type (setq default-value (if is-s3-hw 7 0)))
                (reserved-slot-70 (setq default-value 0))
                (series-cells (setq default-value -1))
                (reserved-slot-72 (setq default-value -1))
                (_ (setq default-value (ix setting 3)))
            )
            (write-val-eeprom name default-value)
        })
        (write-val-eeprom 'crc (config-crc cfg-len))
    })
        (load-config)
        (send-status "Settings restored")
})

(defun print-config ()
    (loopforeach it eeprom-addrs (print (list (first it) (read-val-eeprom (first it)))))
)

(defun read-val-eeprom (name)
    (let
        (
            (addr (first (assoc eeprom-addrs name)))
            (type (second (assoc eeprom-addrs name)))
        )
        (cond
            ((eq type 'i) (eeprom-read-i addr))
            ((eq type 'f) (eeprom-read-f addr))
            ((eq type 'b) (eeprom-read-i addr))
        )
    )
)

(defun write-val-eeprom (name val)
    (let
        (
            (addr (first (assoc eeprom-addrs name)))
            (type (second (assoc eeprom-addrs name)))
        )
        (cond
            ((eq type 'i) (eeprom-store-i addr val))
            ((eq type 'f) (eeprom-store-f addr val))
            ((eq type 'b) (eeprom-store-i addr val))
        )
    )
)

(defun status () {
    (var status-string "float-stats " )
    (setq status-string (str-merge status-string (str-from-n (if (< (secs-since can-last-activity-time) 5) 1 0) "%d ")))
    ; Cutdown build: keep placeholder tokens so the UI parser stays aligned.
    (setq status-string (str-merge status-string (str-from-n 0 "%d ")))
    (setq status-string (str-merge status-string (str-from-n 0 "%d ")))
    (setq status-string (str-merge status-string (str-from-n 0 "%d ")))
    (setq status-string (str-merge status-string (str-from-n 0 "%d ")))
    (setq status-string (str-merge status-string (str-from-n (if wifi-enabled-on-boot (wifi-get-chan) -1) "%d ")))
    (setq status-string (str-merge status-string (str-from-n 0 "%.0f ")))
    (setq status-string (str-merge status-string (str-from-n 0 "%.2f ")))
    (setq status-string (str-merge status-string (str-from-n 0 "%.0f ")))
    (setq status-string (str-merge status-string (str-from-n 0 "%.0f ")))

    ; --- UCL forwarding status (optional trailing tokens) ---
    (setq status-string (str-merge status-string (str-from-n (can-local-id) "%d ")))
    (setq status-string (str-merge status-string (str-from-n ucl-effective-role "%d ")))
    (setq status-string (str-merge status-string (str-from-n (if (ucl-fwd-connected) 1 0) "%d ")))
    (setq status-string (str-merge status-string (str-from-n (ucl-fwd-age) "%.2f ")))

    ; --- Peer list for UI target dropdowns ---
    (var peer-count 0)
    (loopforeach p ucl-peers {
        (setq peer-count (+ peer-count 1))
    })
    (setq status-string (str-merge status-string (str-from-n peer-count "%d ")))
    (loopforeach p ucl-peers {
        (setq status-string (str-merge status-string (str-from-n (ix p 0) "%d ")))
    })

    ; Build marker for UI visibility
    (setq status-string (str-merge status-string (str-from-n magic-header "%d ")))
    ; Runtime target IDs for slave-tab visibility/debug (optional trailing tokens).
    (setq status-string (str-merge status-string (str-from-n (to-i (get-config 'front-target-id)) "%d ")))
    (setq status-string (str-merge status-string (str-from-n (to-i (get-config 'rear-target-id)) "%d ")))
    (setq status-string (str-merge status-string (str-from-n (to-i (get-config 'status-target-id)) "%d ")))

    (send-data status-string)
})

@const-end
