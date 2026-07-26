;@const-symbol-strings
@const-start

; Pubmote runtime state and host callback slots.
; Depends on pubmote-consts.lisp.

; State
(def pubmote-loop-delay)  ; Loop rate in Hz, read from the config
(def pairing-state PAIR_STATE_IDLE)
(def pubmote-exit-flag nil)
(def pubmote-send-pair-complete-retries 0)
(def pubmote-pair-complete-status 0)
(def pubmote-last-pairing-broadcast 0)
(def pubmote-last-activity-time (systime))
(def wifi-enabled-on-boot nil)
(def pubmote-remote-mac '())
(def pubmote-ble-paired nil)
(def pubmote-pairing-timer 31)
(def pubmote-pairing-timer-timeout 60) ; How many seconds to wait before aborting pairing
(def uni-mac '(255 255 255 255 255 255)) ; Universal mac (all devices)
(def channel-locked 0)
(def channel-locked-timeout 10) ; How many seconds of no activity to wait before unlocking locked wifi channel
(def pubmote-version '(0 0 0))
(def pubmote-api-version 1)
(def pubmote-vehicle-type VEHICLE_TYPE_UNSPECIFIED)

; Host callbacks, injected by pubmote-setup
(def pubmote-on-control nil)
(def pubmote-get-telemetry nil)
(def pubmote-send-msg-cb nil)
(def pubmote-get-config nil)
(def pubmote-set-config nil)
(def pubmote-save-config nil)
(def pubmote-on-pairing-state nil)

(def last-log-time-telemetry-tx 0)
(def last-log-time-telemetry-rx 0)

@const-end
