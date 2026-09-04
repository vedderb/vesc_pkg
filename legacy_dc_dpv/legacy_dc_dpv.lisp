; =============================================================================
; CONST BLOCK 1 - constants and the debug-logging macros (flashed, immutable)
; =============================================================================
@const-start

; Sleep intervals (seconds) - controls loop frequencies
(define SLEEP_STATE_MACHINE 0.02)     ; 50Hz - button state polling
(define SLEEP_MOTOR_CONTROL 0.04)     ; 25Hz - motor/GPIO polling
(define SLEEP_MOTOR_SPEED_CHANGE 0.05) ; 20Hz - motor speed transitions
(define SLEEP_BACKGROUND_CHECK 0.5)   ; 2Hz - Smart Cruise checking

; Timer durations (seconds)
(define TIMER_DISABLED 86400)         ; 24 hours - effectively infinite for scooter operation
(define TIMER_CLICK_WINDOW 0.3)       ; Click detection window
(define TIMER_RELEASE_WINDOW 0.3)     ; Release detection window
(define TIMER_SMART_CRUISE_TIMEOUT 5) ; Smart Cruise half-enable timeout
(define TIMER_SMART_CRUISE_HOLD 0.5)  ; Hold duration before Smart Cruise adjustments

; Thread stack sizes (in 4-byte words) for loopwhile-thd and spawn
; Reduced to minimum safe values to conserve memory
(define THREAD_STACK_ADC 80)         ; ADC reading - minimal needs
(define THREAD_STACK_SMART_CRUISE 100) ; Smart Cruise - reduced
(define THREAD_STACK_STATE_MACHINE 80) ; State 2 (pressed) - reduced
(define THREAD_STACK_STATE_TRANSITIONS 80) ; States 0, 3 - reduced
(define THREAD_STACK_STATE_COUNTING 80) ; State 1 (counting clicks) - reduced
(define THREAD_STACK_MOTOR 150)       ; Motor control - reduced but still largest

; State values
(define STATE_UNINITIALIZED -1)
(define STATE_OFF 0)
(define STATE_COUNTING_CLICKS 1)
(define STATE_PRESSED 2)
(define STATE_GOING_OFF 3)

; Special speed values
(define SPEED_REVERSE 0)            ; Reverse speed level 2 (strong reverse)
(define SPEED_UNTANGLE 1)             ; Reverse speed level 1 / untangle assist
(define SPEED_OFF 99)                 ; Motor off indicator
(define SPEED_REVERSE_THRESHOLD 2)    ; Speeds below this are reverse
(define SPEED_SOFT_START_SENTINEL 0.5) ; Sentinel value for soft start tracking

; Click counts
(define CLICKS_SINGLE 1)
(define CLICKS_DOUBLE 2)
(define CLICKS_TRIPLE 3)
(define CLICKS_QUADRUPLE 4)

; Smart Cruise states
(define SMART_CRUISE_OFF 0)
(define SMART_CRUISE_HALF_ENABLED 1)
(define SMART_CRUISE_FULLY_ENABLED 2)
(define SMART_CRUISE_AUTO_ENGAGED 3)

; Safe start parameters
(define SAFE_START_DUTY 0.10)         ; Initial duty cycle for safe start
(define SAFE_START_TIMEOUT 0.5)       ; Timeout for safe start checks
(define SAFE_START_TIMEOUT_GRACE 0.1) ; Additional grace period before aborting (seconds)
(define SAFE_START_MIN_DUTY 0.05)     ; Minimum duty for safe start check
(define SAFE_START_MAX_CURRENT 5)     ; Maximum current during safe start spin-up
(define SAFE_START_FAIL_CURRENT 8)    ; Current threshold for safe start failure
(define SAFE_START_MAX_RETRIES 3)     ; Max safe start retries before shutting down
(define SAFE_START_RETRY_BACKOFF 0.2) ; Delay before retrying safe start (seconds)
(define MAX_CURRENT (conf-get 'l-current-max)) ; Save configured max current

; Soft-start duration (how long to hold reduced current before restoring)
(define SOFT_START_DURATION SAFE_START_TIMEOUT)

; Smart Cruise speed adjustment (slowdown to 80%)
(define SMART_CRUISE_SLOWDOWN_FACTOR 0.8) ; Slowdown Smart Cruise as timeout nears

; EEPROM settings buffer size.
(define EEPROM_SETTINGS_COUNT 22)

; Data receive handshake code
(define HANDSHAKE_CODE 255)

@const-end

; =============================================================================
; MUTABLE GLOBAL STATE - heap-resident (NOT flashed), so setvar/set works.
; Defined here (after the constants block) so initialisers may reference the
; constants above. main re-initialises these at runtime.
; =============================================================================

; --- EEPROM-backed configuration ---
(define max_speed_no 0)
(define start_speed 0)
(define jump_speed 0)
(define use_safe_start 0)
(define enable_reverse 0)
(define enable_smart_cruise 0)
(define smart_cruise_timeout 0)
(define enable_smart_cruise_auto_engage 0)
(define smart_cruise_auto_engage_time 0)
(define debug_enabled 1)
(define speed_set 0)
(define min_current 0)

; --- Runtime state machine / motor / display vars ---
(define sw_state 0)
(define sw_pressed 0)
(define timer_start 0)
(define timer_duration 0)
(define initial_press_time 0)
(define clicks 0)
(define speed SPEED_OFF)
(define new_start_speed 0)
(define new_start_speed_timer 0)
(define new_start_speed_timeout 0)
(define speed_set_via_jump nil)       ; Track if current speed was set via jump (triple-click) and not manually changed
(define smart_cruise SMART_CRUISE_OFF)

(define state_last_state STATE_UNINITIALIZED)

(define safe_start_timer 0)
(define soft_start_timer 0)
(define soft_start_active 0)
(define safe_start_attempt_speed SPEED_OFF)
(define safe_start_failures 0)
(define safe_start_status 'idle)

; =============================================================================
; CONST BLOCK 2 - all functions (flashed, immutable). Function order is not
; significant for flashing because LispBM resolves symbols at call time.
; =============================================================================
@const-start

; Helper function to reduce EEPROM wear by only writing when value changes
(defun eeprom_store_i_if_changed (addr new_val)
{
    (var current_val (eeprom-read-i addr))
    (if (or (eq current_val nil) (!= current_val new_val))
        (eeprom-store-i addr new_val)
    )
})

; Debug logging helper function
(defun debug_log (msg)
{
    (if (and (not-eq debug_enabled nil) (= debug_enabled 1))
        (puts (str-merge (str-from-n (/ (systime) 10000.0) "%.4f") " | " msg))
    )
})


; =============================================================================
; Safe Start Helpers
; =============================================================================
; Canonical values for `safe_start_status` used throughout the codebase:
;  - 'idle    : not running / feature disabled
;  - 'running : safe-start attempt in progress
;  - 'success : safe-start completed successfully
;  - 'failed  : safe-start attempt failed (may retry)
; Keep checks limited to these symbols and use `soft_start_active` boolean for
; soft-start vs safe-start distinctions when needed.
; =============================================================================

; Helper to set safe_start_status and emit a concise debug log when it changes
(defun safe_start_set_status (new_status)
{
    (var old_status safe_start_status)
    (setvar 'safe_start_status new_status)
    (if (and (not-eq debug_enabled nil) (= debug_enabled 1) (not-eq old_status new_status)) {
        (debug_log (str-merge "SafeStart: " (to-str old_status) " -> " (to-str new_status)))
    })
})

; Helper to set soft_start_active (silent - no logging to reduce noise)
(defun soft_start_set_active (val)
{
    (setvar 'soft_start_active val)
})

(defun safe_start_reset_state ()
{
    (setvar 'safe_start_timer 0)
    (setvar 'safe_start_attempt_speed SPEED_OFF)
    (setvar 'safe_start_failures 0)
    (safe_start_set_status 'idle)
    (soft_start_set_active 0)
})

(defun safe_start_begin (target_speed)
{
    ; Only perform safe-start initialization when the feature is enabled.
    (if (= use_safe_start 1) {
        (setvar 'safe_start_timer (systime))
        (setvar 'safe_start_attempt_speed target_speed)
        (safe_start_set_status 'running)
        (debug_log (str-merge "Motor: Safe start attempt " (to-str (+ safe_start_failures 1)) " targeting speed " (to-str (to-i target_speed))))
    } {
        ; Feature disabled: set status to 'idle so callers treat it as not running
        (safe_start_set_status 'idle)
        (setvar 'safe_start_timer 0)
        (setvar 'safe_start_attempt_speed SPEED_OFF)
    })
})

(defun safe_start_success ()
{
    (setvar 'safe_start_timer 0)
    (setvar 'safe_start_attempt_speed SPEED_OFF)
    (setvar 'safe_start_failures 0)
    (safe_start_set_status 'success)
})

(defun safe_start_increment_failure (reason)
{
    (setvar 'safe_start_failures (+ safe_start_failures 1))
    (safe_start_set_status 'failed)
    (if (and (not-eq debug_enabled nil) (= debug_enabled 1)) {
        (debug_log (str-merge "Motor: Safe start attempt " (to-str safe_start_failures) "/" (to-str SAFE_START_MAX_RETRIES) " failed (" reason ")"))
    })
})

(defun safe_start_should_retry ()
{
    (< safe_start_failures SAFE_START_MAX_RETRIES)
})

(defun safe_start_abort_with_reason (reason)
{
    (safe_start_increment_failure reason)
    (if (safe_start_should_retry) {
        (sleep SAFE_START_RETRY_BACKOFF)
        (safe_start_begin safe_start_attempt_speed)
    } {
        (if (and (not-eq debug_enabled nil) (= debug_enabled 1)) {
            (debug_log (str-merge "Motor: Safe start retries exhausted, stopping motor (reason=" reason ")"))
        })
        (set_speed_safe SPEED_OFF)
        (state_transition_to STATE_COUNTING_CLICKS "safe_start_abort" THREAD_STACK_STATE_COUNTING state_handler_counting_clicks)
        (safe_start_reset_state)
    })
})

(defun safe_start_value_valid (value max_abs)
{
    (and (= value value) (< (abs value) max_abs))
})

(defun safe_start_telemetry_valid (duty current)
{
    (and (safe_start_value_valid duty 1.0)
         (safe_start_value_valid current 200))
})

(defun safe_start_met_success_criteria (duty current)
{
    (var min_current_amps (/ min_current 10.0)) ; EEPROM stores current * 10
    (debug_log (str-merge "safe_start_met_success: duty " (to-str duty) " current " (to-str current)))
    (and (> (abs duty) SAFE_START_MIN_DUTY)
         (>= (abs current) min_current_amps)
         (< (abs current) SAFE_START_MAX_CURRENT))
})


; Settings initialization (init-only, but harmless to flash - it only reads
; eeprom and writes mutable heap globals via setvar)
(defun update_settings_from_eeprom ()
{
    ; Speed duty cycles
    (setvar 'speed_set (list
        (eeprom-read-i 0) ; Reverse Speed 2 %
        (eeprom-read-i 1) ; Untangle Speed 1 %
        (eeprom-read-i 2) ; Speed 1 %
        (eeprom-read-i 3) ; Speed 2 %
        (eeprom-read-i 4) ; Speed 3 %
        (eeprom-read-i 5) ; Speed 4 %
        (eeprom-read-i 6) ; Speed 5 %
        (eeprom-read-i 7) ; Speed 6 %
        (eeprom-read-i 8) ; Speed 7 %
        (eeprom-read-i 9) ; Speed 8 %
    ))

    (setvar 'max_speed_no (eeprom-read-i 10))
    (setvar 'start_speed (eeprom-read-i 11))
    (setvar 'jump_speed (eeprom-read-i 12))
    (setvar 'use_safe_start (eeprom-read-i 13))
    (setvar 'enable_reverse (eeprom-read-i 14))
    (setvar 'enable_smart_cruise (eeprom-read-i 15))
    (setvar 'smart_cruise_timeout (eeprom-read-i 16))
    (setvar 'min_current (eeprom-read-i 17)) ; New current * 10 so it's an INT
    (setvar 'enable_smart_cruise_auto_engage (eeprom-read-i 18))
    (setvar 'smart_cruise_auto_engage_time (eeprom-read-i 19))
    (setvar 'debug_enabled (eeprom-read-i 20))
    (setvar 'new_start_speed_timeout (eeprom-read-i 21))

})

(defun log_settings_1 ()
{
    (debug_log (str-merge "- max_speed_no: " (to-str (to-i max_speed_no))
        "\n- start_speed: " (to-str (to-i start_speed))
        "\n- jump_speed: " (to-str (to-i jump_speed))
        "\n- use_safe_start: " (to-str (to-i use_safe_start))
        "\n- enable_reverse: " (to-str (to-i enable_reverse))
        "\n- enable_smart_cruise: " (to-str (to-i enable_smart_cruise))
        "\n- smart_cruise_timeout: " (to-str (to-i smart_cruise_timeout))
    ))
})

(defun log_settings_2 ()
{
    (debug_log (str-merge "- enable_smart_cruise_auto_engage: " (to-str (to-i enable_smart_cruise_auto_engage))
        "\n- smart_cruise_auto_engage_time: " (to-str (to-i smart_cruise_auto_engage_time))
    ))
})

(defun log_speeds ()
{
    (debug_log (str-merge "- speed (reverse): " (to-str (to-i (ix speed_set 0)))
        "\n- speed (untangle): " (to-str (to-i (ix speed_set 1)))
        "\n- speed (1): " (to-str (to-i (ix speed_set 2)))
        "\n- speed (2): " (to-str (to-i (ix speed_set 3)))
        "\n- speed (3): " (to-str (to-i (ix speed_set 4)))
        "\n- speed (4): " (to-str (to-i (ix speed_set 5)))
        "\n- speed (5): " (to-str (to-i (ix speed_set 6)))
        "\n- speed (6): " (to-str (to-i (ix speed_set 7)))
        "\n- speed (7): " (to-str (to-i (ix speed_set 8)))
        "\n- speed (8): " (to-str (to-i (ix speed_set 9)))
    ))
})

(defun log_startup ()
{
    ; Log configuration on startup
    (if (and (not-eq debug_enabled nil) (= debug_enabled 1)) {
        (debug_log (str-merge "Startup, configuration:"
            "\n- debug_enabled: " (to-str (to-i debug_enabled))
            "\n"
        ))
        (log_settings_1)
        (log_settings_2)
        (log_speeds)
        (gc)
    } {
        (puts "Startup")
    })
})

(defun send_current_settings ()
{
    (var setbuf (array-create EEPROM_SETTINGS_COUNT))
    (looprange i 0 EEPROM_SETTINGS_COUNT
        (bufset-i8 setbuf i (or (eeprom-read-i i) 0)))
    (send-data setbuf)
})

(defun receive_data (data)
{
    (if (> (buflen data) 0) {
        (if (= (bufget-u8 data 0) HANDSHAKE_CODE) {
            ; Handshake to trigger data send if not yet received.
            (send_current_settings)
        } {
            ; For non-handshake messages, validate buffer size
            (if (< (buflen data) EEPROM_SETTINGS_COUNT) {
                (debug_log (str-merge "Error: Received data buffer too small: " (to-str (buflen data)) " < " (to-str EEPROM_SETTINGS_COUNT)))
                nil ; Return early on invalid data
            } {
                (looprange i 0 EEPROM_SETTINGS_COUNT
                    (eeprom_store_i_if_changed i (bufget-u8 data i))) ; writes settings to eeprom
                (update_settings_from_eeprom) ; updates actual settings in lisp
                (debug_log "Settings updated")
            })
        })
    })
})

; Setup functions
(defun setup_event_handler ()
{
    (defun event_handler ()
    {
        (loopwhile t
            (recv
                ((event-data-rx . (? data)) (receive_data data))
                (_ nil))
        )
    })

    (event-register-handler (spawn event_handler))
    (event-enable 'event-data-rx)
})

(defun start_trigger_loop ()
{
    (loopwhile-thd THREAD_STACK_ADC t {
        (sleep SLEEP_MOTOR_CONTROL)
        (if (> 0.2 (get-adc 0))
            (setvar 'sw_pressed 1)
            (setvar 'sw_pressed 0)
        )
    })
})


; start_smart_cruise_loop()
;
; Watch for conditions to start Smart Cruise Auto Start
;
;   Watches "speed" variable, when it changes set a timer.
;   When timer expires, start Smart Cruise

(defun start_smart_cruise_loop ()
{
    (debug_log "Smart Cruise: Starting loop")

    (var speed_setting_timer 0) ; Timer for auto-engage functionality
    (var last_speed_setting SPEED_OFF) ; Track last speed setting for auto-engage

    (loopwhile-thd THREAD_STACK_SMART_CRUISE t {
        (sleep SLEEP_BACKGROUND_CHECK)
        (if (and (> enable_smart_cruise 0) (> enable_smart_cruise_auto_engage 0) (= sw_state STATE_PRESSED) (= smart_cruise SMART_CRUISE_OFF) (!= speed SPEED_OFF) (>= speed SPEED_REVERSE_THRESHOLD)) {
            ; Check if speed setting has changed
            (if (!= speed last_speed_setting) {
                (setvar 'last_speed_setting speed)
                (setvar 'speed_setting_timer (systime))
            } {
                ; Speed setting hasn't changed, check if timer expired
                (if (> (secs-since speed_setting_timer) smart_cruise_auto_engage_time) {
                    (debug_log "Smart Cruise: Auto-engaged")
                    (setvar 'smart_cruise SMART_CRUISE_AUTO_ENGAGED)
                    (setvar 'timer_start (systime))
                    ; re-command actual speed as reverification sets it to 0.8x
                    (set_duty_cycle (calculate_duty_cycle speed))
                })
            })
        } {
            ; Not in the right state for auto-engage, reset timer
            (setvar 'speed_setting_timer (systime))
        })
    })
})


; state_transition_to ( new_state reason thread_stack handler )
;
; Change to a new state. This runs the new state "handler" function
; with the "thread_stack" stack size, logs the "reason"

(defun state_transition_to (new_state reason thread_stack handler)
{
    (var from_state (if (= state_last_state STATE_UNINITIALIZED) STATE_UNINITIALIZED sw_state))

    (debug_log (str-merge "State: " (to-str from_state) "->" (to-str new_state) " " reason))
    (setvar 'sw_state new_state)
    (setvar 'state_last_state new_state)
    (spawn thread_stack handler)
})

;
; Duty Cycle Calculation Helper
;

(defun clamp (value min_val max_val)
{
    (cond
        ((< value min_val) min_val)
        ((> value max_val) max_val)
        (t value)
    )
})


; speed_percentage_at ( speed_index )
;
; Looks up the duty cycle from "speed_index" which can
; also be 99 (SPEED_OFF) from the "speed_set" array.

(defun speed_percentage_at (speed_index)
{
    (if (= speed_index SPEED_OFF) {
        0
    } {
        (var count (length speed_set))
        (if (= count 0) {
            (debug_log "Speed: speed_set empty, defaulting to 0%")
            0
        } {
            (var max_index (- count 1))
            (var clamped (clamp speed_index SPEED_REVERSE max_index))
            (if (!= speed_index clamped)
                (debug_log (str-merge "Speed: Index " (to-str speed_index) " clamped to " (to-str clamped) " for speed_set"))
            )
            (ix speed_set clamped)
        })
    })
})

; calculate_duty_cycle ( speed_index )
;
; Gets duty cycle from speed_percentage_at(), and converts it
; to a positive or negative duty cycle.

(defun calculate_duty_cycle (speed_index)
{
    (var speed_percent (/ (speed_percentage_at speed_index) 100.00))
    (if (< speed_index SPEED_REVERSE_THRESHOLD)
        (- 0 speed_percent)
        speed_percent
    )
})

; set_duty_cycle ( duty_cycle_pct )
;
; Sets duty cycle.

(defun set_duty_cycle (duty_cycle_pct)
{
    (debug_log (str-merge "Setting duty cycle: " (str-from-n duty_cycle_pct)))
    (set-duty duty_cycle_pct)
})


; =============================================================================
; State Machine Design Notes:
; - Each state handler runs in a loop checking (= sw_state N)
; - When transitioning, sw_state is updated, new handler spawned, and (break) called
; - The loop condition prevents race conditions by ensuring old handler exits
; - Old thread terminates naturally when loop condition becomes false
; =============================================================================

; =============================================================================
; Speed Bounds Checking
; =============================================================================

; Helper function to safely set speed with bounds checking
; Valid speeds: SPEED_REVERSE, SPEED_UNTANGLE, 2-max_speed_no (forward), SPEED_OFF
; Returns the actual speed that was set after bounds checking

(defun set_speed_safe (new_speed)
{
    (var clamped_speed new_speed)
    (if (= new_speed SPEED_OFF) {
        ; Speed 99 (OFF) is always valid
        (setvar 'speed SPEED_OFF)
        (debug_log "Speed: Set to OFF")
    } {
        ; Clamp to valid range
        (if (< new_speed SPEED_REVERSE) {
            (setvar 'clamped_speed SPEED_REVERSE)
            (debug_log (str-merge "Speed: Clamped " (to-str (to-i new_speed)) " to " (to-str SPEED_REVERSE) " (underflow)"))
        })

        (if (> clamped_speed max_speed_no) {
            (setvar 'clamped_speed max_speed_no)
            (debug_log (str-merge "Speed: Clamped " (to-str new_speed) " to " (to-str (to-i max_speed_no)) " (overflow)"))
        })

        ; Check reverse enable
        (if (and (< clamped_speed SPEED_REVERSE_THRESHOLD) (= enable_reverse 0)) {
            (setvar 'clamped_speed SPEED_REVERSE_THRESHOLD)
            (debug_log (str-merge "Speed: Reverse disabled, clamped " (to-str (to-i new_speed)) " to " (to-str SPEED_REVERSE_THRESHOLD)))
        })

        (setvar 'speed clamped_speed)
        (debug_log (str-merge "Speed: Set to " (to-str (to-i clamped_speed))))
    })
    clamped_speed
})

; =============================================================================
; Smart Cruise Timeout Helper
; =============================================================================

; Checks if Smart Cruise should transition to warning mode (HALF_ENABLED)
; and performs the transition if needed
; Called from state_handler_going_off timer expiry

(defun check_smart_cruise_timeout ()
{
    (if (or (= smart_cruise SMART_CRUISE_FULLY_ENABLED) (= smart_cruise SMART_CRUISE_AUTO_ENGAGED))
        (if (> (secs-since timer_start) smart_cruise_timeout) {
            (debug_log "Smart Cruise: Timeout - entering warning slowdown")
            (setvar 'smart_cruise SMART_CRUISE_HALF_ENABLED)
            (setvar 'timer_start (systime))
            (setvar 'timer_duration TIMER_SMART_CRUISE_TIMEOUT)
            ; slow scooter to 80% to help people realize cruise is expiring
            (set_duty_cycle (* (calculate_duty_cycle speed) SMART_CRUISE_SLOWDOWN_FACTOR))
        })
    )
})


; State 0: Off
;
;    Wait for trigger pull, then got to State 1
;

(defun state_handler_off ()
{
    ; State "0" Off
    (debug_log "State 0: Off")
    (loopwhile (= sw_state STATE_OFF) {
        (sleep SLEEP_STATE_MACHINE)

        ; Pressed
        (if (= sw_pressed 1) {
            (debug_log "State 0->1: Button pressed")
            (setvar 'timer_start (systime))
            (setvar 'timer_duration TIMER_CLICK_WINDOW)
            (setvar 'clicks CLICKS_SINGLE)
            (state_transition_to STATE_COUNTING_CLICKS "button_press" THREAD_STACK_STATE_COUNTING state_handler_counting_clicks)
            (break)
        })
    })
})

(defun smart_cruise_upgrade_if_needed ()
{
    (if (= smart_cruise SMART_CRUISE_HALF_ENABLED) {
        (debug_log "Smart Cruise: Re-enabled from warning mode")
        (setvar 'smart_cruise SMART_CRUISE_FULLY_ENABLED)
        (set_duty_cycle (calculate_duty_cycle speed))
    })
})

; Encapsulated click action handler
(defun apply_click_action (click_count)
{
    (cond
        ((= click_count CLICKS_SINGLE) {
            (if (!= speed SPEED_OFF) {
                (if (> smart_cruise SMART_CRUISE_OFF) {
                    ; Smart Cruise is active
                    ; Only allow speed change with long hold when NOT in warning mode (timing out)
                    (if (and (> initial_press_time TIMER_SMART_CRUISE_HOLD) (!= smart_cruise SMART_CRUISE_HALF_ENABLED)) {
                        ; Long hold before click - change speed down (not allowed during timeout warning)
                        (debug_log "Click action: Single click after hold (Smart Cruise: speed down + timer reset)")
                        (setvar 'timer_start (systime))
                        (setvar 'speed_set_via_jump nil) ; User manually changed speed, allow remembering
                        ; If in warning mode, upgrade back to fully enabled
                        (smart_cruise_upgrade_if_needed)
                        ; Change speed down
                        (if (> speed SPEED_REVERSE_THRESHOLD) {
                            (set_speed_safe (- speed 1))
                        })
                    } {
                        ; Quick tap OR in warning mode - just reset timer (no speed change)
                        (debug_log "Click action: Single click (Smart Cruise timer reset)")
                        (setvar 'timer_start (systime))
                        ; If in warning mode, upgrade back to fully enabled
                        (smart_cruise_upgrade_if_needed)
                    })
                } {
                    ; Smart Cruise not active - normal speed down
                    (debug_log "Click action: Single click (speed down)")
                    (setvar 'speed_set_via_jump nil) ; User manually changed speed, allow remembering
                    (cond
                        ((> speed SPEED_REVERSE_THRESHOLD)
                            (set_speed_safe (- speed 1)))
                        ((= speed SPEED_REVERSE)
                            (set_speed_safe SPEED_UNTANGLE)))
                })
            })
        })
        ((= click_count CLICKS_DOUBLE) {
            (if (= speed SPEED_OFF) {
                (if (and (!= new_start_speed_timer 0) (> (secs-since new_start_speed_timer) new_start_speed_timeout)) {
                    (debug_log "Timeout on new_start_speed_timer, reverting start speed to default")
                    (setvar 'new_start_speed_timer 0)
                    (setvar 'new_start_speed start_speed)
                })
                (debug_log (str-merge "Click action: Double click (start at speed " (to-str (to-i new_start_speed)) ")"))
                (setvar 'speed_set_via_jump nil) ; Normal start, allow speed to be remembered
                (set_speed_safe new_start_speed)
            } {
                (if (> smart_cruise SMART_CRUISE_OFF) {
                    ; Smart Cruise is active - only allow speed change after long hold, and not during timeout warning
                    (if (and (> initial_press_time TIMER_SMART_CRUISE_HOLD) (!= smart_cruise SMART_CRUISE_HALF_ENABLED)) {
                        ; Long hold before double tap - change speed up (not allowed during timeout warning)
                        (debug_log "Click action: Double click after hold (Smart Cruise: speed up + timer reset)")
                        (setvar 'timer_start (systime))
                        (setvar 'speed_set_via_jump nil) ; User manually changed speed, allow remembering
                        ; If in warning mode, upgrade back to fully enabled
                        (smart_cruise_upgrade_if_needed)
                        ; Change speed up
                        (if (and (< speed max_speed_no) (>= speed SPEED_REVERSE_THRESHOLD)) {
                            (set_speed_safe (+ speed 1))
                        })
                    } {
                        ; Quick double tap without hold OR in warning mode - just reset timer (no speed change)
                        (debug_log "Click action: Double click (Smart Cruise timer reset)")
                        (setvar 'timer_start (systime))
                        ; If in warning mode, upgrade back to fully enabled
                        (smart_cruise_upgrade_if_needed)
                    })
                } {
                    ; Smart Cruise not active - normal speed up
                    (debug_log "Click action: Double click (speed up)")
                    (setvar 'speed_set_via_jump nil) ; User manually changed speed, allow remembering
                    (if (< speed max_speed_no) {
                        (if (>= speed SPEED_REVERSE_THRESHOLD)
                            (set_speed_safe (+ speed 1))
                            (set_speed_safe SPEED_REVERSE))
                    })
                })
            })
        })
        ((= click_count CLICKS_TRIPLE) {
            (if (= speed SPEED_OFF) {
                ; Stopped - jump to preset speed
                (debug_log (str-merge "Click action: Triple click (jump to speed " (to-str (to-i jump_speed)) ")"))
                (setvar 'speed_set_via_jump t) ; Speed set via jump, don't remember unless changed
                (set_speed_safe jump_speed)
            } {
                ; Running - only allow Smart Cruise toggle in forward speeds
                (if (>= speed SPEED_REVERSE_THRESHOLD) {
                    ; Running forward - toggle Smart Cruise
                    (if (> smart_cruise SMART_CRUISE_OFF) {
                        ; Smart Cruise is active - disable it
                        (debug_log "Click action: Triple click (Smart Cruise going off)")
                        (setvar 'smart_cruise SMART_CRUISE_OFF)
                    } {
                        ; Smart Cruise not active - enable it if feature is enabled
                        (if (> enable_smart_cruise 0) {
                            (debug_log "Click action: Triple click (Smart Cruise going on)")
                            (setvar 'smart_cruise SMART_CRUISE_FULLY_ENABLED)
                            (setvar 'initial_press_time 0)
                            (setvar 'timer_start (systime))
                            (set_duty_cycle (calculate_duty_cycle speed))
                        } {
                            (debug_log "Click action: Triple click ignored (Smart Cruise disabled in settings)")
                        })
                    })
                } {
                    ; Running backward - ignore
                    (debug_log "Click action: Triple click ignored (running in reverse)")
                })
            })
        })
        ((= click_count CLICKS_QUADRUPLE) {
            ; Quadruple click only works when stopped
            (if (= speed SPEED_OFF) {
                (if (= enable_reverse 1) {
                    (debug_log "Click action: Quadruple click (untangle)")
                    (set_speed_safe SPEED_UNTANGLE)
                } {
                    (debug_log "Click action: Quadruple click ignored (reverse disabled in settings)")
                })
            } {
                ; Running - ignore quadruple click
                (debug_log "Click action: Quadruple click ignored (scooter running)")
            })
        })
    )
})


; STATE 1: Wait for trigger release during TIMEOUT_CLICK_WINDOW
;
;           Waiting for:
;
;              Trigger release: count clicks, and got to State 3
;              Timeout, with trigger pull: go to State 2
;              Timeout, with trigger released: go to State 0: Off
;

(defun state_handler_counting_clicks ()
{
    (debug_log (str-merge "State 1: Counting clicks=" (to-str clicks)))

    (loopwhile (= sw_state STATE_COUNTING_CLICKS) {
        (sleep SLEEP_STATE_MACHINE)

        ; Keep motor running while in Smart Cruise mode
        (if (> smart_cruise SMART_CRUISE_OFF)
            (timeout-reset)
        )

        ; Released
        (if (= sw_pressed 0) {
            (setvar 'timer_start (systime))
            (setvar 'timer_duration TIMER_RELEASE_WINDOW)
            ;; State 1 -> 3: Running with trigger off
            (state_transition_to STATE_GOING_OFF "Running, Trigger released" THREAD_STACK_STATE_TRANSITIONS state_handler_going_off)
            (break)
        })

        ; Timer Expiry
        (if (> (secs-since timer_start) timer_duration) {
            (debug_log (str-merge "State 1: Timer expired, clicks=" (to-str clicks)))

            ; Process click actions
            (apply_click_action clicks)

            ; End of Click Actions
            (setvar 'clicks 0)
            (setvar 'timer_duration TIMER_DISABLED)

            ; Transition based on actual button state
            (if (= sw_pressed 1) {
                (debug_log (str-merge "State 1->2: Speed=" (to-str (to-i speed))))
                (state_transition_to STATE_PRESSED "click_window_expired" THREAD_STACK_STATE_MACHINE state_handler_pressed)
            } {
                (debug_log "State 1->3: Button released during click window")
                (setvar 'timer_start (systime))
                (setvar 'timer_duration TIMER_RELEASE_WINDOW)
                (state_transition_to STATE_GOING_OFF "click_window_expired" THREAD_STACK_STATE_TRANSITIONS state_handler_going_off)
            })
            (break)
        })
    })
})

;
; State 2: Running, Trigger on, waiting for trigger release
;
;          Waiting for:
;              Trigger release (no timeout): then go to State 3
;

(defun state_handler_pressed ()
{
    (debug_log "State 2: Pressed")

    (loopwhile (= sw_state STATE_PRESSED) {
        (sleep SLEEP_STATE_MACHINE)
        (timeout-reset) ; keeps motor running

        (if (and (= smart_cruise SMART_CRUISE_HALF_ENABLED) (> (secs-since timer_start) TIMER_SMART_CRUISE_TIMEOUT)) ; time out Smart Cruise if second activation isn't received within display duration
            (setvar 'smart_cruise SMART_CRUISE_OFF)
        )

        ; Trigger Released
        (if (= sw_pressed 0) {
            ; Record how long the button was held before first release
            (if (= initial_press_time 0) (setvar 'initial_press_time (secs-since timer_start)))
            (setvar 'timer_start (systime))
            (setvar 'timer_duration TIMER_RELEASE_WINDOW)
            ;; State 2 -> 3: Running with trigger off
            (state_transition_to STATE_GOING_OFF "released" THREAD_STACK_STATE_TRANSITIONS state_handler_going_off)
            (break)
        })
    })
})

; State 3: Running, Trigger off, wait for timeout to stop, or Trigger press to accumulate clicks
;
;          Wait for:
;
;              Trigger press: Accumulate clicks, then go to State 1
;              Timeout, with clicks: Handle clicks,
;              Timeout, without clicks: Go to State 0: Off
;
(defun state_handler_going_off ()
{
    (debug_log "State 3: Going Off")

    (loopwhile (= sw_state STATE_GOING_OFF) {
        (sleep SLEEP_STATE_MACHINE)
        (if (> smart_cruise SMART_CRUISE_OFF) ; If Smart Cruise is enabled, don't shut down
            (timeout-reset)
        )

        ; Trigger press, count click
        (if (= sw_pressed 1) {
            (timeout-reset) ; keeps motor running, vesc automatically stops if it doesn't receive this command every second

            ; Check if this is a new click sequence (timer expired) or continuation
            (if (> (secs-since timer_start) timer_duration) {
                ; New click sequence - reset counter and initial press time
                (setvar 'clicks 1)
                (setvar 'initial_press_time 0)
            } {
                ; Continuation of existing click sequence - increment
                (if (not (eq safe_start_status 'running)) { ; block only while safe-start is in progress
                    (setvar 'clicks (+ clicks 1))
                })
            })

            (setvar 'timer_start (systime))
            (setvar 'timer_duration TIMER_CLICK_WINDOW)

            ; Go to State 1: Wait for trigger release
            (state_transition_to STATE_COUNTING_CLICKS "button_pressed" THREAD_STACK_STATE_COUNTING state_handler_counting_clicks)
            (break)
        })

        ; Timer Expiry
        (if (> (secs-since timer_start) timer_duration) {
            ; Check if we have pending clicks to process first
            (if (> clicks 0) {
                (debug_log (str-merge "State 3: Processing pending clicks=" (to-str clicks)))
                (apply_click_action clicks)
                (setvar 'clicks 0)
                (setvar 'initial_press_time 0)
                ; Reset timer to stay in GOING_OFF state
                (setvar 'timer_start (systime))
                (setvar 'timer_duration TIMER_RELEASE_WINDOW)
            } {
                ; No pending clicks - check if we should shut down
                (setvar 'initial_press_time 0)
                (if (and (!= smart_cruise SMART_CRUISE_FULLY_ENABLED) (!= smart_cruise SMART_CRUISE_AUTO_ENGAGED)) { ; If Smart Cruise is enabled, don't shut down
                    (debug_log "State 3->0: Timeout, shutting down")
                    (setvar 'timer_duration TIMER_DISABLED)
                    ; Only remember speed if user manually changed it (not just started via jump speed)
                    (if (and (not speed_set_via_jump) (>= speed SPEED_REVERSE_THRESHOLD) (< speed SPEED_OFF)) {
                        ; start at old speed
                        (setvar 'new_start_speed_timer (systime))
                        (setvar 'new_start_speed speed)
                    } {
                        ; Speed set via jump and not changed - reset to normal start speed
                        (setvar 'new_start_speed_timer 0)
                        (setvar 'new_start_speed start_speed)
                    })
                    (set_speed_safe SPEED_OFF)
                    (setvar 'smart_cruise SMART_CRUISE_OFF) ; turn off Smart Cruise
                    (state_transition_to STATE_OFF "timeout_shutdown" THREAD_STACK_STATE_TRANSITIONS state_handler_off)
                    (break)
                })

                ; Check if Smart Cruise needs to timeout
                (check_smart_cruise_timeout)
            })
        }) ; end Timer expiry
    }) ; end state
})


; start_motor_speed_loop()
;
; This runs continuously.
; It waits for other code to change the "speed" variable.

(defun start_motor_speed_loop ()
{
    (debug_log "Motor: Starting motor speed loop")

    (safe_start_reset_state)

    (var last_speed SPEED_OFF)
    (var ramp_step 0.0)
    (var ramp_speed 0.0)

    ; Run continuously
    (loopwhile-thd THREAD_STACK_MOTOR t {
        (sleep SLEEP_MOTOR_CONTROL)

        ;; Speed needs changing
        (loopwhile (!= speed last_speed) {
            ; Only log speed changes that aren't part of soft-start monitoring
            (if (!= last_speed SPEED_SOFT_START_SENTINEL)
                (debug_log (str-merge "Motor: Speed change " (to-str (to-i last_speed)) "->" (to-str (to-i speed))))
            )
            (sleep SLEEP_MOTOR_SPEED_CHANGE)

            ; turn off motor if speed is 99
            (if (= speed SPEED_OFF) {
                (debug_log "Motor: Stopping motor")
                (set-current 0) ;; Soft off, spins. set-duty 0 does a hard stop
                (safe_start_reset_state) ; unlock speed changes and disable safe start timer
                (setvar 'last_speed speed)
            })

            (if (!= speed SPEED_OFF) {
                ; Soft Start initiation section (only when starting from off)
                (if (= last_speed SPEED_OFF) {
                    (debug_log "Motor: Soft start initiated")
                    (setvar 'ramp_step (/ (calculate_duty_cycle speed) (/ SOFT_START_DURATION SLEEP_MOTOR_SPEED_CHANGE)))
                    (setvar 'ramp_speed 0)

                    ;;DEL(conf-set 'l-in-current-max min_current)
                    ; Start the soft-start timer regardless of safe-start being enabled so we can restore currents after a short period
                    (setvar 'soft_start_timer (systime))
                    (soft_start_set_active 1)
                    (setvar 'safe_start_attempt_speed speed)
                    (if (= use_safe_start 1)
                        (safe_start_begin speed)
                        (safe_start_set_status 'idle)) ; keep safe_start_status idle when disabled
                    (setvar 'last_speed SPEED_SOFT_START_SENTINEL)
                    (set_duty_cycle SAFE_START_DUTY)
                } {
                    ; Speed change while already running (not from off, not during soft-start)
                    (if (!= last_speed SPEED_SOFT_START_SENTINEL) {
                        (set_duty_cycle (calculate_duty_cycle speed))
                        (setvar 'last_speed speed) ;; End speed change loop
                    })
                })

                ; Soft-start/Safe-start monitoring section (runs while sentinel is active)
                (if (= last_speed SPEED_SOFT_START_SENTINEL) {
                    (var soft_elapsed (secs-since soft_start_timer))
                    (var duty (get-duty))
                    (var current (get-current))

                    ; For safe-start enabled: check telemetry and criteria
                    (if (= use_safe_start 1) {
                        (var elapsed (secs-since safe_start_timer))

                        ; Check for invalid telemetry
                        (if (not (safe_start_telemetry_valid duty current))
                            (safe_start_abort_with_reason "invalid telemetry")
                        )

                        ; Check safe-start completion
                        (if (safe_start_met_success_criteria duty current)
                            {
                                (debug_log "Motor: Soft start completed (telemetry)")
                                (conf-set 'l-in-current-max MAX_CURRENT)
                                (set_duty_cycle (calculate_duty_cycle speed))
                                (safe_start_success)
                                (soft_start_set_active 0)
                                (setvar 'last_speed speed)
                            } {
                                ; Check timeout
                                (if (> elapsed (+ SAFE_START_TIMEOUT SAFE_START_TIMEOUT_GRACE))
                                    (safe_start_abort_with_reason "timeout")
                                )

                                ; Detect high-current stall
                                (if (and (> elapsed SAFE_START_TIMEOUT) (> (abs current) SAFE_START_FAIL_CURRENT) )
                                    (safe_start_abort_with_reason "high current stall")
                                )

                                ; If aborted, exit sentinel
                                (if (not (eq safe_start_status 'running))
                                    (setvar 'last_speed speed)
                                )
                            })
                    } {
                        ; For safe-start disabled: just wait for timer
                        (if (< soft_elapsed SOFT_START_DURATION)
                            {
                              ; Increase ramp speed
                              (setvar 'ramp_speed (+ ramp_speed ramp_step))
                              (if (> (abs ramp_speed) (abs (calculate_duty_cycle speed)))
                                   (setvar 'ramp_speed (calculate_duty_cycle speed))
                              )
                              (set_duty_cycle ramp_speed)
                            } {
                                (debug_log "Motor: Soft start completed (timer)")
                                ;; DEL (conf-set 'l-in-current-max MAX_CURRENT)
                                (set_duty_cycle (calculate_duty_cycle speed))
                                ; Clear timers without changing safe-start status (feature disabled)
                                (setvar 'soft_start_timer 0)
                                (setvar 'safe_start_timer 0)
                                (soft_start_set_active 0)
                                (setvar 'last_speed speed)
                        })
                    })
                })
            })
        })
    })
})


; EEPROM initialization (init-only)
; Migration uses a monotonically increasing version marker in slot 127. Each
; migration block runs only when the stored version is BELOW the block's target,
; so once we have migrated to v3 older blocks will not re-run on subsequent boots.
; The previous code used (not-eq stored target) which caused the v1 block to fire
; again after the v2 block had run, silently resetting any user changes to slots
; 25-29 on every boot (and also resetting hardware_configuration in slot 19
; whenever there was no prior 150-era install, which could kill the display).
(defun eeprom_set_defaults ()
{
    (var stored_version (eeprom-read-i 127))
    (if (eq stored_version nil) (setq stored_version 0))

    ; Migration for 1.0.0: baseline settings added in this release.
    (if (< stored_version 1) {
        (puts "EEPROM: Initializing defaults for 1.0.0")

        ; User speeds, ie 1 thru 8 are only used in the GUI, this lisp code uses speeds 0-9 with 0 & 1 being the 2 reverse speeds.
        ; 99 is used as the "off" speed
        (eeprom_store_i_if_changed 0 45) ; Reverse Speed 2 %
        (eeprom_store_i_if_changed 1 20) ; Untangle Speed 1 %
        (eeprom_store_i_if_changed 2 30) ; Speed 1 %
        (eeprom_store_i_if_changed 3 38) ; Speed 2 %
        (eeprom_store_i_if_changed 4 46) ; Speed 3 %
        (eeprom_store_i_if_changed 5 54) ; Speed 4 %
        (eeprom_store_i_if_changed 6 62) ; Speed 5 %
        (eeprom_store_i_if_changed 7 70) ; Speed 6 %
        (eeprom_store_i_if_changed 8 78) ; Speed 7 %
        (eeprom_store_i_if_changed 9 100) ; Speed 8 %
        (eeprom_store_i_if_changed 10 9) ; Maximum number of Speeds to use, must be greater or equal to start_speed (actual speed #, not user speed)
        (eeprom_store_i_if_changed 11 4) ; Speed the scooter starts in. Range 2-9, must be less or equal to the max_speed_no (actual speed #, not user speed)
        (eeprom_store_i_if_changed 12 7) ; Speed to jump to on triple click, (actual speed #, not user speed)
        (eeprom_store_i_if_changed 13 1) ; Turn safe start on or off 1=On 0=Off
        (eeprom_store_i_if_changed 14 0) ; Enable Reverse speed. 1=On 0=Off
        (eeprom_store_i_if_changed 15 0) ; Enable Smart Cruise (3 clicks while running). 1=On 0=Off
        (eeprom_store_i_if_changed 16 60) ; How long before Smart Cruise times out and requires reactivation in sec.
        (eeprom_store_i_if_changed 17 1); Min current used for safe start
        (eeprom_store_i_if_changed 18 0) ; Enable Auto-Engage Smart Cruise. 1=On 0=Off
        (eeprom_store_i_if_changed 19 10) ; Auto-Engage Time in seconds (5-30 seconds)
        (eeprom_store_i_if_changed 20 0) ; Enable Debug Logging. 1=On 0=Off
        (eeprom_store_i_if_changed 21 15) ; Re-start timeout for same speed
        (puts "EEPROM: Defaults initialized successfully")
    })

    ; newer firmware, so downgrade/upgrade cycles remain monotonic.
    (if (< stored_version 1)
         (eeprom_store_i_if_changed 127 1))
})

(defun init ()
{
    (eeprom_set_defaults)

    (gc) ; Initialisation is done, clean up

    (debug_log "Initialisation done")
})

(defun main ()
{
    (update_settings_from_eeprom)

    (log_startup)

    (setup_event_handler)

    (setvar 'sw_state STATE_OFF)
    (setvar 'timer_start 0)
    (setvar 'timer_duration 0)
    (setvar 'initial_press_time 0)
    (setvar 'clicks 0)
    (setvar 'new_start_speed start_speed)
    (setvar 'speed_set_via_jump nil) ; Track if current speed was set via jump (triple-click) and not manually changed
    (setvar 'state_last_state STATE_UNINITIALIZED)

    (setvar 'speed SPEED_OFF)
    (setvar 'safe_start_timer 0)
    (setvar 'soft_start_timer 0)
    (setvar 'soft_start_active 0)
    (setvar 'safe_start_attempt_speed SPEED_OFF)
    (setvar 'safe_start_failures 0)
    (setvar 'safe_start_status 'idle)

    (start_motor_speed_loop)

    (setvar 'smart_cruise SMART_CRUISE_OFF)

    (start_smart_cruise_loop)

    (setvar 'sw_pressed 0)

    (start_trigger_loop)

    (state_transition_to STATE_OFF "startup" THREAD_STACK_STATE_TRANSITIONS state_handler_off) ; ***Start state machine running for first time

    (puts "Startup complete")

    ; Keep main resident as a persistent supervisory context instead of
    ; returning. The worker threads (motor/state-machine/balance/etc.)
    ; were all spawned above and run independently; this loop simply keeps the
    ; main context alive (matching the common image-save 'looping main' idiom)
    ; and gives a single place for periodic health checks. Low frequency to keep
    ; CPU/wakeups negligible.
    (loopwhile t {
        (sleep 1.0)
        ; (optional) supervisory hooks could go here later, e.g. re-assert the
        ; display controller or restart a thread that has died.
    })
})

@const-end

; See DEVELOPMENT.md for boot sequence details.
(init)

(progn
    (image-save)
    (main))
