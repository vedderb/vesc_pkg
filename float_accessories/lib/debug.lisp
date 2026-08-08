;@const-symbol-strings

; Verbose diagnostics logger.
;
; The enable flag (dbg-mask) lives in RAM only - deliberately NOT in the
; fa_cfg config. Turning verbose logging on is a debugging action: it must
; not survive a power cycle, must not wear NVS, and must never ship enabled
; on a user's board. It resets to 0 (silent) on every boot.
;
; Every message is gated by a category bit so one noisy subsystem can be
; watched without the others drowning it out:
;
;   (dbg DBG-LED "led: message")             ; logged when DBG-LED is on
;   (if (dbg-active DBG-LED)                 ; hot path: keep the str-merge
;       (dbg DBG-LED (str-merge ...)))       ; out of the loop when off
;   (if (dbg-tick DBG-CAN 'can-tel 2.0)      ; at most one line per 2 s
;       (dbg DBG-CAN (str-merge ...)))
;
; str-merge is the expensive part (it allocates), which is why call sites in
; loops guard it rather than passing a built string into a function that
; then throws it away.
;
; dbg-err / dbg-warn are NOT gated - a real failure always prints.
;
; Message text is deliberately terse. Every literal here lives in the
; LispBM constant heap (flash), which this package very nearly fills, so
; log lines are telegraphic and carry their own short subsystem prefix
; rather than being formatted by a tag table. See README.md for what the
; categories mean.
;
; Control it from the Diagnostics card on the QML Config tab, or from the
; VESC Tool lisp REPL:
;
;   (dbg-on)            everything on
;   (dbg-off)           everything off
;   (dbg-add DBG-LED)   turn one category on
;   (dbg-del DBG-LED)   turn one category off
;   (dbg-set 12)        set the raw mask (DBG-CAN + DBG-LED)
;   (dbg-status)        show the current mask
;   (diag)              one-shot system report, works with logging off
;
; Note the naming: LispBM folds symbol case, so a function may not share a
; name with a DBG-* constant. (dbg-all) would BE the constant DBG-ALL.

; Throttle table for rate-limited log lines. Deliberately built with
; (list (cons ...)) above @const-start: dbg-due rewrites these cells in
; place with setcdr, and cells that live in the constant heap cannot be
; written. Pre-seeding every key also means the steady state allocates
; nothing at all.
(def dbg-throttle (list
    (cons 'cfg-ctl 0)
    (cons 'can-tel 0)
    (cons 'can-loop 0)
    (cons 'can-overrun 0)
    (cons 'can-frame 0)
    (cons 'can-ctl 0)
    (cons 'led-state 0)
    (cons 'led-loop 0)
    (cons 'bms-rx 0)
    (cons 'bms-val 0)
    (cons 'rem-tx 0)
    (cons 'rem-txerr 0)
    (cons 'rem-rx 0)
    (cons 'rem-in 0)
    (cons 'rem-drop 0)
    (cons 'gnss-pos 0)
    (cons 'gnss-nmea 0)
    (cons 'gnss-err 0)
    (cons 'hum-read 0)
    (cons 'sdlog 0)
    (cons 'cmd-rx 0)
))

@const-start

; ---- Categories ----------------------------------------------------------

(def DBG-CORE   1)    ; boot, threads, heartbeat, memory
(def DBG-CFG    2)    ; config reads/writes, apply-config, QML control
(def DBG-CAN    4)    ; CAN discovery, telemetry, settings sync
(def DBG-LED    8)    ; segment setup, mode/direction/highbeam decisions
(def DBG-BMS    16)   ; RS485 packets and decoded values
(def DBG-REM    32)   ; pubmote ESP-NOW / BLE link and pairing
(def DBG-GNSS   64)   ; GNSS init, fix state, position
(def DBG-HUM    128)  ; humidity sensor
(def DBG-SDLOG  256)  ; SD card logger
(def DBG-CMD    512)  ; inbound QML / CAN commands
(def DBG-ALL    1023)

; ---- State ---------------------------------------------------------------

; RAM only. 0 = silent (default on every boot).
(def dbg-mask 0)

; Per-loop iteration counters, reset by the heartbeat every second so they
; report a rate and can never overflow a fixnum. Only incremented while
; some category is enabled, so the cost with logging off is one integer
; compare per loop.
(def dbg-ticks-led 0)
(def dbg-ticks-can 0)
(def dbg-ticks-bms 0)
(def dbg-ticks-rem 0)
(def dbg-ticks-evt 0)

; Last-seen values for edge-triggered logging (only log on change, so a
; state machine sitting still doesn't produce a line per iteration).
(def dbg-prev-state -99)
(def dbg-prev-fault -99)
(def dbg-prev-switch -99)
(def dbg-prev-can-conn -1)
(def dbg-prev-bms-conn -1)
(def dbg-prev-led-mode -99)
(def dbg-prev-led-on -99)
(def dbg-prev-direction 0)
(def dbg-prev-hb -1)
(def dbg-prev-rem-conn -1)
(def dbg-prev-gnss-fix -1)

; LED loop phase timestamps, filled in by led-loop and read by its overrun
; report. Globals because the report sits outside the block that marks them.
(def dbg-led-t1 0.0)
(def dbg-led-t2 0.0)
(def dbg-led-t3 0.0)

; ---- Core helpers --------------------------------------------------------

(defun dbg-active (cat) (!= (bitwise-and dbg-mask cat) 0))

; The (key . systime) pair itself, so dbg-due can write the timestamp back
; with setcdr instead of rebuilding the list.
(defunret dbg-cell (key) {
    (loopforeach c dbg-throttle
        (if (eq (car c) key) (return c)))
    (return nil)
})

; True at most once per `secs` for `key`. The table is only touched once the
; category check has already passed (see dbg-tick), so a disabled category
; costs nothing.
(defunret dbg-due (key secs) {
    (var cell (dbg-cell key))
    (if (eq cell nil) (return t)) ; unknown key: never throttle
    (if (> (secs-since (cdr cell)) secs) {
        (setcdr cell (systime))
        (return t)
    })
    (return nil)
})

; Guard for log lines inside loops: category on AND the throttle is due.
; `and` short-circuits, so with the category off the throttle table is
; never read or written.
(defun dbg-tick (cat key secs) (and (dbg-active cat) (dbg-due key secs)))

(defun dbg (cat msg) (if (dbg-active cat) (print msg)))

; Always printed - a failure the user needs to see is not "verbose".
; One str-merge, not two print args: VESC print puts each argument on
; its own line, which split every warning across two lines.
(defun dbg-err (msg) (print (str-merge "ERR " msg)))
(defun dbg-warn (msg) (print (str-merge "WARN " msg)))

; ---- Control -------------------------------------------------------------

(defun dbg-status () (print (str-merge "dbg mask " (str-from-n dbg-mask "%d"))))

; Push the current mask to the QML page (which has no other way to know it,
; since the flag is not part of the config it reads on connect).
(defun send-debug () (send-data (str-merge "debug " (str-from-n dbg-mask "%d"))))

(defun dbg-set (m) {
    (setq dbg-mask (bitwise-and (to-i m) DBG-ALL))
    (dbg-status)
    (send-debug)
})

(defun dbg-add (cat) (dbg-set (bitwise-or dbg-mask cat)))
; bitwise-or first so the bit is definitely set, then subtract it - clears
; the bit whether or not it was already on, without needing bitwise-not.
(defun dbg-del (cat) (dbg-set (- (bitwise-or dbg-mask cat) cat)))
; dbg-on / dbg-off, NOT dbg-all / dbg-none: LispBM folds symbol case, so a
; function named dbg-all is the same binding as the constant DBG-ALL and
; would silently overwrite it with a closure.
(defun dbg-on () (dbg-set DBG-ALL))
(defun dbg-off () (dbg-set 0))

; ---- Heartbeat -----------------------------------------------------------

; No memory reporting: VESC Express exposes no heap introspection at all.
; mem-num-free / mem-longest-free / mem-size / lbm-heap-state all live in
; lbm_runtime_extensions_init(), which the Express firmware never calls (see
; lispBM/src/extensions/runtime_extensions.c - they are gated on
; FULL_RTS_LIB and only wired up in the desktop REPL). Calling them here
; produced a trapped variable_not_bound every 10 s.

; Per-second loop-rate heartbeat. This is the cheapest way to see that a
; thread has died or stalled: a loop that stops ticking shows 0 here long
; before its symptom (frozen LEDs, stale telemetry) is obvious.
(defun dbg-loop () {
    (loopwhile t {
        (sleep 1.0)
        (if (dbg-active DBG-CORE)
            (print (str-merge "hz led " (str-from-n dbg-ticks-led "%d")
                " can " (str-from-n dbg-ticks-can "%d")
                " bms " (str-from-n dbg-ticks-bms "%d")
                " rem " (str-from-n dbg-ticks-rem "%d")
                " evt " (str-from-n dbg-ticks-evt "%d"))))
        ; Reset unconditionally so the counters stay bounded even if the
        ; category is toggled off mid-second.
        (setq dbg-ticks-led 0)
        (setq dbg-ticks-can 0)
        (setq dbg-ticks-bms 0)
        (setq dbg-ticks-rem 0)
        (setq dbg-ticks-evt 0)
    })
})

; ---- One-shot report -----------------------------------------------------

; Everything worth knowing when someone reports "it doesn't work", printed
; whether or not verbose logging is on. Each block is trapped so a missing
; extension or an unbound var can't truncate the rest of the report.
(defun diag () {
    (print "--- fa diag ---")
    (trap (print (str-merge "ver " (to-str (get-version))
        " fw " (str-from-n fw-num "%.2f")
        " " (sysinfo 'hw-target)
        " cpu " (str-from-n (sysinfo 'cpu-freq) "%d")
        " up " (str-from-n (secs-since 0) "%.0f"))))
    (trap (print (str-merge "canid " (str-from-n (get-config 'can-id) "%d")
        " self " (str-from-n (can-local-id) "%d")
        " canage " (str-from-n (secs-since can-last-activity-time) "%.1f"))))
    (trap (print (str-merge "cid led " (str-from-n led-context-id "%d")
        " can " (str-from-n can-context-id "%d")
        " bms " (str-from-n bms-context-id "%d")
        " rem " (str-from-n pubmote-context-id "%d")
        " gnss " (str-from-n gnss-context-id "%d")
        " hum " (str-from-n humidity-context-id "%d")
        " log " (str-from-n log-context-id "%d"))))
    (trap (print (str-merge "state " (str-from-n state "%d")
        " fault " (str-from-n fault-code "%d")
        " sw " (str-from-n switch-state "%d")
        " vin " (str-from-n (to-float vin) "%.1f")
        " soc " (str-from-n (* 100.0 battery-percent-remaining) "%.0f")
        " cells " (str-from-n series-cells "%d")
        " rpm " (str-from-n (to-float rpm) "%.0f")
        " duty " (str-from-n (to-float duty-cycle-now) "%.2f"))))
    (trap (print (str-merge "seg st " (str-from-n seg-status "%d")
        " fr " (str-from-n seg-front "%d")
        " re " (str-from-n seg-rear "%d")
        " fp " (str-from-n seg-footpad "%d")
        " bt " (str-from-n seg-button "%d")
        " on " (str-from-n (to-i led-on) "%d")
        " hb " (str-from-n (to-i led-highbeam-on) "%d")
        " mode " (str-from-n led-mode "%d")
        " dir " (str-from-n direction "%d"))))
    (trap (print (str-merge "bms age " (str-from-n (secs-since bms-last-activity-time) "%.1f")
        " type " (str-from-n bms-type "%d")
        " status " (str-from-n bms-status "%d")
        " v " (str-from-n (get-bms-val 'bms-v-tot) "%.2f"))))
    (trap (print (str-merge "rem conn " (str-from-n (is-pubmote-connected) "%d")
        " pair " (str-from-n pairing-state "%d")
        " ble " (if pubmote-ble-paired "1" "0")
        " ch " (str-from-n (if (> (conf-get 'wifi-mode) 0) (wifi-get-chan) -1) "%d"))))
    (trap (print (str-merge "gnss age " (str-from-n (gnss-age) "%.1f")
        " hdop " (str-from-n (gnss-hdop) "%.1f")
        " " (to-str (gnss-lat-lon))
        " hum " (str-from-n (to-float hum) "%.0f")
        " sdlog " (if log-running "1" "0"))))
    (dbg-status)
})

@const-end
