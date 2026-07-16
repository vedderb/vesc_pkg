;@const-symbol-strings
@const-start

; MQTT client support. Publishes board telemetry to <prefix>/telemetry and
; accepts commands on <prefix>/cmd, using the firmware's mqtt-* extensions
; (mqtt-connect / -publish / -subscribe) and the event system
; (event-mqtt-connected, event-mqtt-rx - dispatched from the shared
; event-handler in utils.lisp).
;
; Wi-Fi is assumed to be configured and managed by the firmware (VESC
; Express Wi-Fi settings); this loop just (re)connects to the broker and
; retries while the link is down.

; Build the telemetry payload as a compact JSON object. Fields mirror the
; can.lisp globals kept up to date by the CAN loop.
(defun mqtt-telemetry-json () {
    (str-merge
        "{\"vin\":"        (str-from-n vin "%.2f")
        ",\"soc\":"        (str-from-n (* battery-percent-remaining 100.0) "%.1f")
        ",\"speed\":"      (str-from-n speed "%.2f")
        ",\"rpm\":"        (str-from-n rpm "%.0f")
        ",\"duty\":"       (str-from-n duty-cycle-now "%.3f")
        ",\"current\":"    (str-from-n tot-current "%.2f")
        ",\"fet_temp\":"   (str-from-n fet-temp-filtered "%.1f")
        ",\"motor_temp\":" (str-from-n motor-temp-filtered "%.1f")
        ",\"state\":"      (str-from-n (to-i state) "%d")
        ",\"fault\":"      (str-from-n (to-i fault-code) "%d")
        "}"
    )
})

; Connect using the stored broker settings. Empty broker URI = do nothing.
; Empty client-id/user/password are passed through; the broker/esp-mqtt
; treat an empty client-id as "auto-generate" and empty credentials as no
; authentication.
(defun mqtt-try-connect () {
    (var uri (get-config 'mqtt-broker-uri))
    (if (> (str-len uri) 0)
        (mqtt-connect uri
            (get-config 'mqtt-client-id)
            (get-config 'mqtt-user)
            (get-config 'mqtt-password)
            (get-config 'mqtt-keepalive))
    )
})

; Fired from event-mqtt-connected: (re)subscribe to the command topic.
(defun mqtt-on-connect () {
    (mqtt-subscribe (str-merge (get-config 'mqtt-topic-prefix) "/cmd")
        (get-config 'mqtt-qos))
    (send-msg "MQTT connected")
})

; Fired from event-mqtt-rx: a command arrived on <prefix>/cmd. The payload is
; evaluated as a lisp expression, the same command surface used by the app
; channel (e.g. "(set-config 'led-on 0)" or "(recv-control ...)"). Trapped so
; a malformed payload cannot kill the shared event thread.
; NOTE: this evaluates arbitrary lisp from anyone who can publish to the
; broker - only point it at a trusted broker/topic.
(defun mqtt-rx (topic data) {
    (if (> (buflen data) 0) {
        (var res (trap (eval (read data))))
        (if (eq (ix res 0) 'exit-error)
            (print (list "mqtt-rx eval error" (ix res 1) topic)))
    })
})

(defun mqtt-loop () {
    (event-enable 'event-mqtt-connected)
    (event-enable 'event-mqtt-disconnected)
    (event-enable 'event-mqtt-rx)

    (var period (/ 1.0 (to-float (max (get-config 'mqtt-publish-rate) 1))))
    (var qos (get-config 'mqtt-qos))
    (var pub-topic (str-merge (get-config 'mqtt-topic-prefix) "/telemetry"))
    (var next-pub (secs-since 0))

    (loopwhile (not mqtt-exit-flag) {
        (if (mqtt-connected) {
            (if (>= (secs-since 0) next-pub) {
                (setq next-pub (+ (secs-since 0) period))
                (mqtt-publish pub-topic (mqtt-telemetry-json) qos 0)
            })
            (sleep 0.1)
        } {
            ; Not connected: broker down or Wi-Fi not up yet. Retry slowly;
            ; mqtt-connect tears down any half-open client first.
            (mqtt-try-connect)
            (sleep 2.0)
        })
    })

    (mqtt-disconnect)
    (setq mqtt-exit-flag nil)
})

@const-end
