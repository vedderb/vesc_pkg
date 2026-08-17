; UCLights.lisp
; Smart LED control for remote CANBUS lighting nodes on hardware running VESC(R) software
; Version 2026.042
; Initially a cut down version of Float Accessories 3.2.2

@const-start
(import "lib/utils.lisp" 'utils)
(read-eval-program utils)
(import "lib/settings.lisp" 'settings)
(read-eval-program settings)
(import "lib/ucl_config_push.lisp" 'ucl-config-push)
(read-eval-program ucl-config-push)
(import "lib/can.lisp" 'can)
(read-eval-program can)
(import "lib/led.lisp" 'led)
(read-eval-program led)
(import "lib/led_patterns.lisp" 'led-patterns)
(read-eval-program led-patterns)

(defun main () {
    (setup)
    (init)
})
(defun setup () {
    (var fw-num (+ (first (sysinfo 'fw-ver)) (* (second (sysinfo 'fw-ver)) 0.01)))
    (event-register-handler (spawn event-handler))
    (event-enable 'event-data-rx)
    (if (!= (str-cmp (to-str (sysinfo 'hw-type)) "hw-express") 0) {
        (exit-error "Not running on hw-express")
    })

    (if (< fw-num 6.05) (exit-error "hw-express needs to be running 6.05"))

    ; Stage3 behavior: if magic-header changed, treat EEPROM as incompatible
    ; and restore defaults before doing the normal CRC / new-field handling.
    (if (not-eq (read-val-eeprom 'magic) magic-header) {
        (restore-config)
    } {
        (load-config)
    })
    (var crc (config-crc read-cfg-len))
    (if (!= crc (to-i (read-val-eeprom 'crc))) {
        (send-msg  (str-merge "Error: crc corrupt. Got " (str-from-n (read-val-eeprom 'crc)) ". Expected " (str-from-n crc)))
        (restore-config)
    } {
        (if (> cfg-len read-cfg-len) {
            ;check if crcs match and update default params only for new ones. Make sure they get updated in eeprom, and active variables and then save the crc
            ; Initialize only the new parameters (those beyond read-cfg-len)
            (var count 0)
            (loopforeach setting eeprom-addrs {
                (if (and (>= count read-cfg-len) (< count cfg-len)) {
                    (var name (first setting))
                    (var default-value (ix setting 3))
                    ;(write-val-eeprom name default-value)
                    (set-config name default-value)
                })
                (setq count (+ count 1))
            })
            (save-config)
        })
    })

    (var feature-needs-save nil)
    (if (not-eq (get-config 'soc-type) 1) {
        (set-config 'soc-type 1)
        (if (= (get-config 'cell-type) 0) {
            (set-config 'cell-type 4)
        })
        (setq feature-needs-save t)
    })
    (if (!= (to-i (get-config 'led-enabled)) 1) {
        (set-config 'led-enabled 1)
        (setq feature-needs-save t)
    })
    ; Role marker in reserved-slot-5: 3=master, 2=slave.
    ; Marker is authoritative when present to preserve role across upgrades/images.
    (var cfg-node-role (to-i (get-config 'node-role)))
    (var role-marker (to-i (get-config 'reserved-slot-5)))
    (if (or (= role-marker 2) (= role-marker 3)) {
        (var marker-role (if (= role-marker 3) 0 1))
        (if (!= cfg-node-role marker-role) {
            (setq cfg-node-role marker-role)
            (set-config 'node-role cfg-node-role)
            (setq feature-needs-save t)
        })
    } {
        (if (and (!= cfg-node-role 0) (!= cfg-node-role 1)) {
            (setq cfg-node-role 1)
            (set-config 'node-role cfg-node-role)
            (setq feature-needs-save t)
        })
        (set-config 'reserved-slot-5 (if (= cfg-node-role 0) 3 2))
        (setq feature-needs-save t)
    })

    ; Cutdown build: keep legacy config slots for compatibility, but clear the
    ; removed deprecated features so they stay dormant across reboots.
    
    (if (not-eq (get-config 'led-show-battery-charging) 0) { (set-config 'led-show-battery-charging 0) (setq feature-needs-save t) })
    (if (not-eq (get-config 'reserved-slot-70) 0) { (set-config 'reserved-slot-70 0) (setq feature-needs-save t) })
    (var cfg-series-cells (to-i (get-config 'series-cells)))
    (if (= cfg-series-cells 0) { (set-config 'series-cells -1) (setq feature-needs-save t) })
    (if (< cfg-series-cells -1) { (set-config 'series-cells -1) (setq feature-needs-save t) })
    (if (> cfg-series-cells 64) { (set-config 'series-cells 64) (setq feature-needs-save t) })
    (if (not-eq (get-config 'reserved-slot-72) -1) { (set-config 'reserved-slot-72 -1) (setq feature-needs-save t) })

    (if feature-needs-save {
        (save-config)
    })
    (apply-battery-config 1 (get-config 'cell-type) (get-config 'series-cells))
})

(defun init () {
    ; Reset runtime loop markers each boot path to avoid stale image state.
    (setq led-exit-flag nil)
    (setq led-heartbeat-time 0.0)
    (setq led-context-id -1)
    (setq can-context-id -1)
    ; Start CAN first so role election is settled before LED target gating/buffer init.
    (setq can-context-id (spawn can-loop))

    (var role-wait-start (secs-since 0))
    (loopwhile (and (not ucl-role-ready)
                    (< (- (secs-since 0) role-wait-start) 2.0)) {
        (yield 10000)
    })
    (if (not ucl-role-ready) { nil })

    (setq led-context-id (spawn led-loop))
    (if (> (conf-get 'wifi-mode) 0) (setq wifi-enabled-on-boot t))
})

@const-end

(main)
