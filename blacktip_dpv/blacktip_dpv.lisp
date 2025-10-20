; =============================================================================
; Constants
; =============================================================================

; Sleep intervals (seconds) - controls loop frequencies
(define SLEEP_STATE_MACHINE 0.02)     ; 50Hz - button state polling
(define SLEEP_MOTOR_CONTROL 0.04)     ; 25Hz - motor/GPIO polling
(define SLEEP_MOTOR_SPEED_CHANGE 0.25) ; 4Hz - motor speed transitions
(define SLEEP_UI_UPDATE 0.25)         ; 4Hz - display/beeper updates
(define SLEEP_BACKGROUND_CHECK 0.5)   ; 2Hz - Smart Cruise checking
(define SLEEP_BATTERY_STABILIZE 1.0)  ; 1Hz - one-time battery reading delay

; Timer durations (seconds)
(define TIMER_DISABLED 86400)         ; 24 hours - effectively infinite for scooter operation
(define TIMER_CLICK_WINDOW 0.3)       ; Click detection window
(define TIMER_RELEASE_WINDOW 0.5)     ; Release detection window
(define TIMER_SMART_CRUISE_TIMEOUT 5) ; Smart Cruise half-enable timeout
(define TIMER_SMART_CRUISE_HOLD 1.0)  ; Hold duration before Smart Cruise adjustments
(define TIMER_DISPLAY_DURATION 5)     ; Display duration (used in calculations)
(define TIMER_LONG_PRESS 10)          ; Long press duration for special functions

; Thread stack sizes (in 4-byte words) for loopwhile-thd and spawn
; Reduced to minimum safe values to conserve memory
(define THREAD_STACK_GPIO 80)         ; GPIO reading - minimal needs
(define THREAD_STACK_SMART_CRUISE 100) ; Smart Cruise - reduced
(define THREAD_STACK_STATE_MACHINE 80) ; State 2 (pressed) - reduced
(define THREAD_STACK_STATE_TRANSITIONS 80) ; States 0, 3 - reduced
(define THREAD_STACK_STATE_COUNTING 80) ; State 1 (counting clicks) - reduced
(define THREAD_STACK_MOTOR 150)       ; Motor control - reduced but still largest
(define THREAD_STACK_DISPLAY 100)     ; Display updates - reduced
(define THREAD_STACK_BATTERY 100)     ; Battery display - reduced
(define THREAD_STACK_CLICK_BEEP 80)   ; Click beep playback - reduced

; State values
(define STATE_UNINITIALIZED -1)
(define STATE_OFF 0)
(define STATE_COUNTING_CLICKS 1)
(define STATE_PRESSED 2)
(define STATE_GOING_OFF 3)

; Special speed values
(define SPEED_REVERSE_2 0)            ; Reverse speed level 2 (strong reverse)
(define SPEED_UNTANGLE 1)             ; Reverse speed level 1 / untangle assist
(define SPEED_OFF 99)                 ; Motor off indicator
(define SPEED_REVERSE_THRESHOLD 2)    ; Speeds below this are reverse
(define SPEED_SOFT_START_SENTINEL 0.5) ; Sentinel value for soft start tracking

; Click counts
(define CLICKS_SINGLE 1)
(define CLICKS_DOUBLE 2)
(define CLICKS_TRIPLE 3)
(define CLICKS_QUADRUPLE 4)
(define CLICKS_SMART_CRUISE_CHANGE 5)

; Smart Cruise states
(define SMART_CRUISE_OFF 0)
(define SMART_CRUISE_HALF_ENABLED 1)
(define SMART_CRUISE_FULLY_ENABLED 2)
(define SMART_CRUISE_AUTO_ENGAGED 3)

; Hardware configuration thresholds
(define HARDWARE_BLACKTIP_MAX 2)      ; Hardware configs 0-2 are Blacktip

; Scooter types (indices into hardware lists)
(define SCOOTER_BLACKTIP 0)
(define SCOOTER_CUDAX 1)

; Motor control constants
(define MAX_ERPM_BLACKTIP 4100)
(define MAX_ERPM_CUDAX 7100)
(define MAX_CURRENT_BLACKTIP 22.8)
(define MAX_CURRENT_CUDAX 46)
(define MIN_CURRENT_BLACKTIP 1.7)
(define MIN_CURRENT_CUDAX 0.35)

; RPM scaling
(define RPM_PERCENT_DENOMINATOR 100)

; Safe start parameters
(define SAFE_START_DUTY 0.06)         ; Initial duty cycle for soft start
(define SAFE_START_TIMEOUT 0.5)       ; Timeout for safe start checks
(define SAFE_START_TIMEOUT_GRACE 0.1) ; Additional grace period before aborting (seconds)
(define SAFE_START_MIN_RPM 350)       ; Minimum RPM for safe start success
(define SAFE_START_MIN_DUTY 0.05)     ; Minimum duty for safe start check
(define SAFE_START_MAX_CURRENT 5)     ; Maximum current during safe start spin-up
(define SAFE_START_FAIL_CURRENT 8)    ; Current threshold for safe start failure
(define SAFE_START_MAX_RETRIES 3)     ; Max safe start retries before shutting down
(define SAFE_START_RETRY_BACKOFF 0.2) ; Delay before retrying safe start (seconds)

; Soft-start duration (how long to hold reduced current before restoring)
(define SOFT_START_DURATION SAFE_START_TIMEOUT)

; Smart Cruise speed adjustment (slowdown to 80%)
(define SMART_CRUISE_SLOWDOWN_DIVISOR 125) ; Divide by 125 instead of 100 for 80%

; Display offset (speed value to display number mapping)
(define DISPLAY_SPEED_OFFSET 4)

; Display numbers for special screens
(define DISPLAY_OFF 14)
(define DISPLAY_SMART_CRUISE_HALF 16)
(define DISPLAY_SMART_CRUISE_FULL 17)
(define DISPLAY_SENTINEL 99)          ; Sentinel for "no previous display"

; Warbler beep parameters
(define WARBLER_FREQUENCY 450)
(define WARBLER_DURATION 0.2)

; Display timing calculations (from State 2 repeat display)
(define DISPLAY_REPEAT_FIRST 6)       ; display duration + 1
(define DISPLAY_REPEAT_SECOND 12)     ; 2 * display duration + 2

; Lookup table for brightness values
(define BRIGHTNESS_LUT (list 224 227 230 233 236 239))

; Masks for 0..8 LEDs lit (ordered per hardware bit mapping)
(define TIMER_BAR_MASKS (list 0x00 0x40 0x60 0x70 0x78 0x7C 0x7E 0x7F 0xFF))

; EEPROM settings buffer size
(define EEPROM_SETTINGS_COUNT 30)

; Battery polynomial coefficients (for voltage-based calculation)
(define BATTERY_COEFF_4 4.3867)
(define BATTERY_COEFF_3 -6.7072)
(define BATTERY_COEFF_2 2.4021)
(define BATTERY_COEFF_1 1.3619)

; Data receive handshake code
(define HANDSHAKE_CODE 255)

; Display timer stop value
(define DISPLAY_TIMER_STOP 2)


; Display LUT binary format helpers (init-only, not moved to flash)
(defun validate_lut_header (data magic expected_version)
{
    (var file_magic (bufget-u32 data 0 'little-endian))
    (var file_version (bufget-u16 data 4 'little-endian))
    (var num_items (bufget-u16 data 6 'little-endian))
    (if (!= file_magic magic)
        nil
        (if (!= file_version expected_version)
            nil
            num_items
        )
    )
})

(defun load_lookup_tables ()
{
    ; Import display and brightness lookup tables from binary files
    ; These files are generated at build time from CSV sources
    (import "generated/display_lut.bin" 'display_lut_bin)

    ; Initialize display LUT (returns number of frames or nil on error)
    (var display_num_frames (validate_lut_header display_lut_bin 0x4C555444u32 1))

    ; Verify LUTs loaded successfully - halt if validation fails
    (if (not display_num_frames)
        (exit-error "LUT validation failed: display"))
})

; EEPROM initialization (init-only, not moved to flash)
(defun eeprom_set_defaults ()
{
    (if (not-eq (eeprom-read-i 127) (to-i32 1)) {
        (puts "EEPROM: Initializing defaults for 1.0.0")
        ; Check for current version marker (blacktip_dpv release 1.0.0)
        ; New settings added in version 1.0.0
        (eeprom_store_i_if_changed 25 0) ; Enable Auto-Engage Smart Cruise. 1=On 0=Off
        (eeprom_store_i_if_changed 26 10) ; Auto-Engage Time in seconds (5-30 seconds)
        (eeprom_store_i_if_changed 27 0) ; Enable Thirds warning on from power-up. 1=On 0=Off
        (eeprom_store_i_if_changed 28 0) ; Battery calculation method: 0=Voltage-based, 1=Ampere-hour based
        (eeprom_store_i_if_changed 29 0) ; Enable Debug Logging. 1=On 0=Off

        (if (not-eq (eeprom-read-i 127) (to-i32 150)) {
            (puts "EEPROM: No previous version detected, setting all defaults")
            ; Check for previous version marker (Dive Xtras V1.50 'Poseidon')
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
            (eeprom_store_i_if_changed 17 0) ; rotation of Display, 0-3 . Each number rotates display 90 deg.
            (eeprom_store_i_if_changed 18 5) ; Display Brighness 0-5
            (eeprom_store_i_if_changed 19 0) ; Hardware configuration, 0 = Blacktip HW60 + Ble, 1 = Blacktip HW60 - Ble, 2 = Blacktip HW410 - Ble, 3 = Cuda-X HW60 + Ble, 4 = Cuda-X HW60 - Ble
            (eeprom_store_i_if_changed 20 0) ; Battery Beeps
            (eeprom_store_i_if_changed 21 3) ; Beep Volume
            (eeprom_store_i_if_changed 22 0) ; CudaX Flip Screens
            (eeprom_store_i_if_changed 23 0) ; 2nd Screen rotation of Display, 0-3 . Each number rotates display 90 deg.
            (eeprom_store_i_if_changed 24 0) ; Trigger Click Beeps
        })
        ; Mark as initialised for 1.0.0
        (eeprom_store_i_if_changed 127 1) ; indicate that the defaults have been applied
        (puts "EEPROM: Defaults initialized successfully")
    })
})


; Helper function to reduce EEPROM wear by only writing when value changes
(defun eeprom_store_i_if_changed (addr new_val)
{
    (var current_val (eeprom-read-i addr))
    (if (or (eq current_val nil) (!= current_val new_val))
        (eeprom-store-i addr new_val)
    )
})

(move-to-flash eeprom_store_i_if_changed)


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
        (debug_log_format (str-merge "SafeStart: " (to-str old_status) " -> " (to-str new_status)))
    })
})

(move-to-flash safe_start_set_status)

; Helper to set soft_start_active (silent - no logging to reduce noise)
(defun soft_start_set_active (val)
{
    (setvar 'soft_start_active val)
})

(move-to-flash soft_start_set_active)

(defun safe_start_reset_state ()
{
    (setvar 'safe_start_timer 0)
    (setvar 'safe_start_attempt_speed SPEED_OFF)
    (setvar 'safe_start_failures 0)
    (safe_start_set_status 'idle)
    (soft_start_set_active 0)
})

(move-to-flash safe_start_reset_state)

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

(move-to-flash safe_start_begin)

(defun safe_start_success ()
{
    (setvar 'safe_start_timer 0)
    (setvar 'safe_start_attempt_speed SPEED_OFF)
    (setvar 'safe_start_failures 0)
    (safe_start_set_status 'success)
})

(move-to-flash safe_start_success)

(defun safe_start_increment_failure (reason)
{
    (setvar 'safe_start_failures (+ safe_start_failures 1))
    (safe_start_set_status 'failed)
    (if (and (not-eq debug_enabled nil) (= debug_enabled 1)) {
        (debug_log (str-merge "Motor: Safe start attempt " (to-str safe_start_failures) "/" (to-str SAFE_START_MAX_RETRIES) " failed (" reason ")"))
    })
})

(move-to-flash safe_start_increment_failure)

(defun safe_start_should_retry ()
{
    (< safe_start_failures SAFE_START_MAX_RETRIES)
})

(move-to-flash safe_start_should_retry)

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
        (foc-beep 250 0.15 5)
        (safe_start_reset_state)
    })
})

(move-to-flash safe_start_abort_with_reason)

(defun safe_start_value_valid (value max_abs)
{
    (and (= value value) (< (abs value) max_abs))
})

(move-to-flash safe_start_value_valid)

(defun safe_start_telemetry_valid (rpm duty current)
{
    (and (safe_start_value_valid rpm 20000)
         (safe_start_value_valid duty 1.0)
         (safe_start_value_valid current 200))
})

(move-to-flash safe_start_telemetry_valid)

(defun safe_start_met_success_criteria (rpm duty current)
{
    (and (> (abs rpm) SAFE_START_MIN_RPM)
         (> (abs duty) SAFE_START_MIN_DUTY)
         (< (abs current) SAFE_START_MAX_CURRENT))
})

(move-to-flash safe_start_met_success_criteria)

; Settings initialization (init-only, not moved to flash)
(defun update_settings_from_eeprom ()
{
    (setvar 'max_speed_no (eeprom-read-i 10))
    (setvar 'start_speed (eeprom-read-i 11))
    (setvar 'jump_speed (eeprom-read-i 12))
    (setvar 'use_safe_start (eeprom-read-i 13))
    (setvar 'enable_reverse (eeprom-read-i 14))
    (setvar 'enable_smart_cruise (eeprom-read-i 15))
    (setvar 'smart_cruise_timeout (eeprom-read-i 16))
    (setvar 'rotation (eeprom-read-i 17))
    (setvar 'disp_brightness (eeprom-read-i 18))
    (setvar 'hardware_configuration (eeprom-read-i 19))
    (setvar 'enable_battery_beeps (eeprom-read-i 20))
    (setvar 'beeps_vol (eeprom-read-i 21))
    (setvar 'cudax_flip (eeprom-read-i 22))
    (setvar 'rotation2 (eeprom-read-i 23))
    (setvar 'enable_trigger_beeps (eeprom-read-i 24))
    (setvar 'enable_smart_cruise_auto_engage (eeprom-read-i 25))
    (setvar 'smart_cruise_auto_engage_time (eeprom-read-i 26))
    (setvar 'enable_thirds_warning_startup (eeprom-read-i 27))
    (setvar 'battery_calculation_method (eeprom-read-i 28))
    (setvar 'debug_enabled (eeprom-read-i 29))

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

    ; Sets scooter type, 0 = Blacktip, 1 = Cuda X
    (if (<= hardware_configuration HARDWARE_BLACKTIP_MAX)
        (setvar 'scooter_type SCOOTER_BLACKTIP)
        (setvar 'scooter_type SCOOTER_CUDAX)
    )
})


(defun log_startup ()
{
    ; Log configuration on startup
    (if (and (not-eq debug_enabled nil) (= debug_enabled 1)) {
        (debug_log_format (str-merge "Startup, configuration:"
            "\n- hardware_configuration: " (to-str (to-i hardware_configuration))
            "\n- scooter_type: " (if (= scooter_type SCOOTER_BLACKTIP)
                "Blacktip"
                "Cuda X"
            )
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


(defun log_settings_1 ()
{
    (debug_log_format (str-merge "- max_speed_no: " (to-str (to-i max_speed_no))
        "\n- start_speed: " (to-str (to-i start_speed))
        "\n- jump_speed: " (to-str (to-i jump_speed))
        "\n- use_safe_start: " (to-str (to-i use_safe_start))
        "\n- enable_reverse: " (to-str (to-i enable_reverse))
        "\n- enable_smart_cruise: " (to-str (to-i enable_smart_cruise))
        "\n- smart_cruise_timeout: " (to-str (to-i smart_cruise_timeout))
        "\n- rotation: " (to-str (to-i rotation))
        "\n- disp_brightness: " (to-str (to-i disp_brightness))
        "\n- enable_battery_beeps: " (to-str (to-i enable_battery_beeps))
        "\n- beeps_vol: " (to-str (to-i beeps_vol))
        "\n- cudax_flip: " (to-str (to-i cudax_flip))
        "\n- rotation2: " (to-str (to-i rotation2))
        "\n- enable_trigger_beeps: " (to-str (to-i enable_trigger_beeps))
    ))
})


(defun log_settings_2 ()
{
    (debug_log_format (str-merge "- enable_smart_cruise_auto_engage: " (to-str (to-i enable_smart_cruise_auto_engage))
        "\n- smart_cruise_auto_engage_time: " (to-str (to-i smart_cruise_auto_engage_time))
        "\n- enable_thirds_warning_startup: " (to-str (to-i enable_thirds_warning_startup))
        "\n- battery_calculation_method: " (to-str (to-i battery_calculation_method))
    ))
})


(defun log_speeds ()
{
    (debug_log_format (str-merge "- speed (reverse): " (to-str (to-i (ix speed_set 0)))
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


; Debug logging helper function
(defun debug_log (msg)
{
    (if (and (not-eq debug_enabled nil) (= debug_enabled 1))
        (puts msg)
    )
})

(move-to-flash debug_log)

; Lightweight macro to conditionally evaluate debug logging expressions
; Only evaluates the logging expression when debug_enabled is 1
; This prevents expensive str-merge and to-str calls on memory-constrained targets
(define debug_log_format (macro (expr)
    `(if (and (not-eq debug_enabled nil) (= debug_enabled 1))
        (puts ,expr)
    )
))


(defun calculate_corrected_battery ()
{
    ; Calculate corrected battery percentage from raw battery reading
    (var raw_batt (get-batt))
    (+ (* BATTERY_COEFF_4 raw_batt raw_batt raw_batt raw_batt)
        (* BATTERY_COEFF_3 raw_batt raw_batt raw_batt)
        (* BATTERY_COEFF_2 raw_batt raw_batt)
        (* BATTERY_COEFF_1 raw_batt)
    )
})

(move-to-flash calculate_corrected_battery)

(defun calculate_ah_based_battery ()
{
    ; Calculate battery percentage based on ampere-hours used vs total capacity
    (var total-capacity (conf-get 'si-battery-ah))
    (var used-ah (get-ah))
    (var remaining_capacity (- 1.0 (/ used-ah total-capacity)))
    (if (and (> total-capacity 0) (> remaining_capacity 0))
        remaining_capacity
        0.0
    )
})

(move-to-flash calculate_ah_based_battery)

(defun get_battery_level ()
    ; Get battery level using the configured calculation method
    (if (= battery_calculation_method 1)
        (calculate_ah_based_battery)
        (calculate_corrected_battery)
    )
)

(move-to-flash get_battery_level)

(defun receive_data (data)
{
    (if (= (bufget-u8 data 0) HANDSHAKE_CODE) { ; Handshake to trigger data send if not yet received.
        (var setbuf (array-create EEPROM_SETTINGS_COUNT)) ; create a temp array to store setting
        (looprange i 0 EEPROM_SETTINGS_COUNT
            (bufset-i8 setbuf i (or (eeprom-read-i i) 0)))
        (send-data setbuf)
    } {
        ; For non-handshake messages, validate buffer size
        (if (< (buflen data) EEPROM_SETTINGS_COUNT) {
            (debug_log_format (str-merge "Error: Received data buffer too small: " (to-str (buflen data)) " < " (to-str EEPROM_SETTINGS_COUNT)))
            nil ; Return early on invalid data
        } {
            (looprange i 0 EEPROM_SETTINGS_COUNT
                (eeprom_store_i_if_changed i (bufget-u8 data i))) ; writes settings to eeprom
            (update_settings_from_eeprom) ; updates actual settings in lisp
            (debug_log "Settings updated")
        })
    })
})

(move-to-flash receive_data)

; Setup functions (init-only, not moved to flash)
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
    (gpio-configure 'pin-ppm 'pin-mode-in-pd)

    (loopwhile-thd THREAD_STACK_GPIO t {
        (sleep SLEEP_MOTOR_CONTROL)
        (if (= 1 (gpio-read 'pin-ppm))
            (setvar 'sw_pressed 1)
            (setvar 'sw_pressed 0)
        )
    })
})

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
                    (setvar 'disp_num DISPLAY_SMART_CRUISE_FULL)
                    (setvar 'click_beep CLICKS_SMART_CRUISE_CHANGE)
                    ; re command actual speed as reverification sets it to 0.8x
                    (set-rpm (calculate_rpm speed RPM_PERCENT_DENOMINATOR))
                })
            })
        } {
            ; Not in the right state for auto-engage, reset timer
            (setvar 'speed_setting_timer (systime))
        })
    })
})


(defun state_metrics_reset ()
{
    ; State machine tracking (minimal for memory conservation)
    (define state_last_state STATE_UNINITIALIZED)
    (define state_last_change_time 0)
    (define state_last_reason "")

    (setvar 'state_last_state STATE_UNINITIALIZED)
    (setvar 'state_last_change_time (systime))
    (setvar 'state_last_reason "startup")
})

(defun state_record_transition (from_state to_state reason)
{
    (setvar 'state_last_state to_state)
    (setvar 'state_last_change_time (systime))
    (setvar 'state_last_reason reason)
    (debug_log_format (str-merge "State: " (to-str from_state) "->" (to-str to_state) " " reason))
})

(defun state_transition_to (new_state reason thread_stack handler)
{
    (state_record_transition
        (if (= state_last_state STATE_UNINITIALIZED) STATE_UNINITIALIZED sw_state)
        new_state
        reason)
    (setvar 'sw_state new_state)
    (spawn thread_stack handler)
})

(move-to-flash state_metrics_reset)
(move-to-flash state_record_transition)
(move-to-flash state_transition_to)

; =============================================================================
; RPM Calculation Helper
; =============================================================================

(defun clamp (value min_val max_val)
{
    (cond
        ((< value min_val) min_val)
        ((> value max_val) max_val)
        (t value)
    )
})

(move-to-flash clamp)

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
            (var clamped (clamp speed_index SPEED_REVERSE_2 max_index))
            (if (!= speed_index clamped)
                (debug_log_format (str-merge "Speed: Index " (to-str speed_index) " clamped to " (to-str clamped) " for speed_set"))
            )
            (ix speed_set clamped)
        })
    })
})

(move-to-flash speed_percentage_at)

(defun calculate_rpm (speed_index divisor)
{
    (var speed_percent (speed_percentage_at speed_index))
    (var max_rpm (cond
        ((= scooter_type SCOOTER_BLACKTIP) MAX_ERPM_BLACKTIP)
        ((= scooter_type SCOOTER_CUDAX) MAX_ERPM_CUDAX)
        (t (debug_log "Invalid scooter_type, defaulting to Blacktip") MAX_ERPM_BLACKTIP)
    ))
    (var base_rpm (* (/ max_rpm divisor) speed_percent))
    (if (< speed_index SPEED_REVERSE_THRESHOLD)
        (- 0 base_rpm)
        base_rpm
    )
})

(move-to-flash calculate_rpm)

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
; Valid speeds: SPEED_REVERSE_2, SPEED_UNTANGLE, 2-max_speed_no (forward), SPEED_OFF
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
        (if (< new_speed SPEED_REVERSE_2) {
            (setvar 'clamped_speed SPEED_REVERSE_2)
            (debug_log_format (str-merge "Speed: Clamped " (to-str (to-i new_speed)) " to " (to-str SPEED_REVERSE_2) " (underflow)"))
        })

        (if (> clamped_speed max_speed_no) {
            (setvar 'clamped_speed max_speed_no)
            (debug_log_format (str-merge "Speed: Clamped " (to-str new_speed) " to " (to-str (to-i max_speed_no)) " (overflow)"))
        })

        ; Check reverse enable
        (if (and (< clamped_speed SPEED_REVERSE_THRESHOLD) (= enable_reverse 0)) {
            (setvar 'clamped_speed SPEED_REVERSE_THRESHOLD)
            (debug_log_format (str-merge "Speed: Reverse disabled, clamped " (to-str (to-i new_speed)) " to " (to-str SPEED_REVERSE_THRESHOLD)))
        })

        (setvar 'speed clamped_speed)
        (debug_log_format (str-merge "Speed: Set to " (to-str (to-i clamped_speed))))
    })
    clamped_speed
})

(move-to-flash set_speed_safe)

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
            (setvar 'disp_num DISPLAY_SMART_CRUISE_HALF)
            (setvar 'click_beep CLICKS_SMART_CRUISE_CHANGE)
            ; slow scooter to 80% to help people realize cruise is expiring
            (set-rpm (calculate_rpm speed SMART_CRUISE_SLOWDOWN_DIVISOR))
        })
    )
})

(move-to-flash check_smart_cruise_timeout)


(defun smart_cruise_leds_count ()
{
    ; Calculate Smart Cruise timer bar LED count (0-8)
    ; Returns: -1 if Smart Cruise not active, otherwise 0-8 LEDs to light
    (if (or (= smart_cruise SMART_CRUISE_FULLY_ENABLED) (= smart_cruise SMART_CRUISE_AUTO_ENGAGED)) {
        (var leds_lit 8) ; Default to full bar

        ; If trigger is NOT held, calculate countdown based on elapsed time
        (if (!= sw_state STATE_PRESSED) {
            (var elapsed (secs-since timer_start))
            (if (> smart_cruise_timeout 0) {
                (var progress (/ elapsed smart_cruise_timeout))
                (if (< progress 1.0) {
                    (setvar 'leds_lit (clamp (to-i (+ 0.5 (* 8 (- 1.0 progress)))) 1 8))
                } {
                    ; At/after expiry, keep a single LED
                    (setvar 'leds_lit 1)
                })
            } {
                ; Timeout <= 0: treat as immediately expired
                (setvar 'leds_lit 1)
            })
        })

        leds_lit ; Return the LED count
    } {
        -1 ; Smart Cruise not active, return -1
    })
})

(move-to-flash smart_cruise_leds_count)


(defun state_handler_off ()
{
    ; xxxx State "0" Off
    (debug_log "State 0: Off")
    (loopwhile (= sw_state STATE_OFF) {
        (sleep SLEEP_STATE_MACHINE)
        ; Calculate corrected batt %, only needed when scooter is off in state 0
        (setvar 'actual_batt (get_battery_level))

        ; Pressed
        (if (= sw_pressed 1) {
            (debug_log "State 0->1: Button pressed")
            (setvar 'batt_disp_timer_start 0) ; Stop Battery Display in case its running
            (setvar 'disp_timer_start 0) ; Stop Display in case its running
            (setvar 'timer_start (systime))
            (setvar 'timer_duration TIMER_CLICK_WINDOW)
            (setvar 'clicks CLICKS_SINGLE)
            (state_transition_to STATE_COUNTING_CLICKS "button_press" THREAD_STACK_STATE_COUNTING state_handler_counting_clicks)
            (break)
        })
    })
})

(move-to-flash state_handler_off)


(defun smart_cruise_upgrade_if_needed ()
{
    (if (= smart_cruise SMART_CRUISE_HALF_ENABLED) {
        (debug_log "Smart Cruise: Re-enabled from warning mode")
        (setvar 'smart_cruise SMART_CRUISE_FULLY_ENABLED)
        (setvar 'disp_num DISPLAY_SMART_CRUISE_FULL)
        (set-rpm (calculate_rpm speed RPM_PERCENT_DENOMINATOR))
    })
})

(move-to-flash smart_cruise_upgrade_if_needed)


; Encapsulated click action handler
(defun apply_click_action (click_count)
{
    (cond
        ((= click_count CLICKS_SINGLE) {
            (if (!= speed SPEED_OFF) {
                (if (> smart_cruise SMART_CRUISE_OFF) {
                    ; Smart Cruise is active
                    (if (> initial_press_time TIMER_SMART_CRUISE_HOLD) {
                        ; Long hold before click - change speed down
                        (debug_log "Click action: Single click after hold (Smart Cruise: speed down + timer reset)")
                        (setvar 'click_beep CLICKS_SINGLE)
                        (setvar 'timer_start (systime))
                        ; If in warning mode, upgrade back to fully enabled
                        (smart_cruise_upgrade_if_needed)
                        ; Change speed down
                        (if (> speed SPEED_REVERSE_THRESHOLD) {
                            (set_speed_safe (- speed 1))
                        })
                    } {
                        ; Quick tap - just reset timer
                        (debug_log "Click action: Single click (Smart Cruise timer reset)")
                        (setvar 'timer_start (systime))
                        ; If in warning mode, upgrade back to fully enabled
                        (smart_cruise_upgrade_if_needed)
                    })
                } {
                    ; Smart Cruise not active - normal speed down
                    (debug_log "Click action: Single click (speed down)")
                    (setvar 'click_beep CLICKS_SINGLE)
                    (cond
                        ((> speed SPEED_REVERSE_THRESHOLD)
                            (set_speed_safe (- speed 1)))
                        ((= speed SPEED_REVERSE_2)
                            (set_speed_safe SPEED_UNTANGLE)))
                })
            })
        })
        ((= click_count CLICKS_DOUBLE) {
            (if (= speed SPEED_OFF) {
                (debug_log_format (str-merge "Click action: Double click (start at speed " (to-str (to-i new_start_speed)) ")"))
                (setvar 'click_beep CLICKS_DOUBLE)
                (set_speed_safe new_start_speed)
            } {
                (if (> smart_cruise SMART_CRUISE_OFF) {
                    ; Smart Cruise is active - only allow speed change after long hold
                    (if (> initial_press_time TIMER_SMART_CRUISE_HOLD) {
                        ; Long hold before double tap - change speed up
                        (debug_log "Click action: Double click after hold (Smart Cruise: speed up + timer reset)")
                        (setvar 'click_beep CLICKS_DOUBLE)
                        (setvar 'timer_start (systime))
                        ; If in warning mode, upgrade back to fully enabled
                        (smart_cruise_upgrade_if_needed)
                        ; Change speed up
                        (if (and (< speed max_speed_no) (> speed SPEED_UNTANGLE)) {
                            (set_speed_safe (+ speed 1))
                        })
                    } {
                        ; Quick double tap without hold - just reset timer
                        (debug_log "Click action: Double click (Smart Cruise timer reset)")
                        (setvar 'timer_start (systime))
                        ; If in warning mode, upgrade back to fully enabled
                        (smart_cruise_upgrade_if_needed)
                    })
                } {
                    ; Smart Cruise not active - normal speed up
                    (debug_log "Click action: Double click (speed up)")
                    (setvar 'click_beep CLICKS_DOUBLE)
                    (if (< speed max_speed_no) {
                        (if (> speed SPEED_UNTANGLE)
                            (set_speed_safe (+ speed 1))
                            (set_speed_safe SPEED_REVERSE_2))
                    })
                })
            })
        })
        ((= click_count CLICKS_TRIPLE) {
            (if (= speed SPEED_OFF) {
                ; Stopped - jump to preset speed
                (debug_log_format (str-merge "Click action: Triple click (jump to speed " (to-str (to-i jump_speed)) ")"))
                (setvar 'click_beep CLICKS_TRIPLE)
                (set_speed_safe jump_speed)
            } {
                ; Running - only allow Smart Cruise toggle in forward speeds
                (if (>= speed SPEED_REVERSE_THRESHOLD) {
                    ; Running forward - toggle Smart Cruise
                    (if (> smart_cruise SMART_CRUISE_OFF) {
                        ; Smart Cruise is active - disable it
                        (debug_log "Click action: Triple click (Smart Cruise disabled)")
                        (setvar 'click_beep CLICKS_TRIPLE)
                        (setvar 'smart_cruise SMART_CRUISE_OFF)
                    } {
                        ; Smart Cruise not active - enable it if feature is enabled
                        (if (> enable_smart_cruise 0) {
                            (debug_log "Click action: Triple click (Smart Cruise enabled)")
                            (setvar 'click_beep CLICKS_TRIPLE)
                            (setvar 'smart_cruise SMART_CRUISE_FULLY_ENABLED)
                            (setvar 'timer_start (systime))
                            (setvar 'disp_num DISPLAY_SMART_CRUISE_FULL)
                            (set-rpm (calculate_rpm speed RPM_PERCENT_DENOMINATOR))
                        } {
                            (debug_log "Click action: Triple click ignored (Smart Cruise disabled in settings)")
                        })
                    })
                } {
                    ; Running backward - ignore
                    (debug_log "Click action: Triple click ignored (running backward)")
                })
            })
        })
        ((= click_count CLICKS_QUADRUPLE) {
            ; Quadruple click only works when stopped
            (if (= speed SPEED_OFF) {
                (if (= enable_reverse 1) {
                    (debug_log "Click action: Quadruple click (untangle)")
                    (setvar 'click_beep CLICKS_QUADRUPLE)
                    (set_speed_safe SPEED_UNTANGLE)
                } {
                    (debug_log "Click action: Quadruple click ignored (reverse disabled in settings)")
                })
            } {
                ; Running - ignore quadruple click
                (debug_log "Click action: Quadruple click ignored (scooter running)")
            })
        })
        (t
            (debug_log_format (str-merge "Click action: Unsupported count " (to-str click_count))))
    )
})

(move-to-flash apply_click_action)

; xxxx STATE 1 Counting clicks
(defun state_handler_counting_clicks ()
{
    (debug_log_format (str-merge "State 1: Counting clicks=" (to-str clicks)))
    (loopwhile (= sw_state STATE_COUNTING_CLICKS) {
        (sleep SLEEP_STATE_MACHINE)

        ; Released
        (if (= sw_pressed 0) {
            (setvar 'disp_timer_start 0) ; Stop Display in case its running
            (setvar 'timer_start (systime))
            (setvar 'timer_duration TIMER_RELEASE_WINDOW)
            (state_transition_to STATE_GOING_OFF "released" THREAD_STACK_STATE_TRANSITIONS state_handler_going_off)
            (break)
        })

        ; Timer Expiry
        (if (> (secs-since timer_start) timer_duration) {
            (debug_log_format (str-merge "State 1: Timer expired, clicks=" (to-str clicks)))

            ; Process click actions
            (apply_click_action clicks)

            ; End of Click Actions
            (setvar 'clicks 0)
            (setvar 'timer_duration TIMER_DISABLED)

            ; Transition based on actual button state
            (if (= sw_pressed 1) {
                (debug_log_format (str-merge "State 1->2: Speed=" (to-str (to-i speed))))
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

(move-to-flash state_handler_counting_clicks)

; xxxx State 2 "Pressed"
(defun state_handler_pressed ()
{
    (debug_log "State 2: Pressed")
    (loopwhile (= sw_state STATE_PRESSED) {
     (sleep SLEEP_STATE_MACHINE)
        (timeout-reset) ; keeps motor running

        ; xxx repeat display section whilst scooter is running xxx
        (if (and (> (secs-since timer_start) DISPLAY_REPEAT_FIRST) (= smart_cruise SMART_CRUISE_OFF)) ; 6 = display duration +1
            (setvar 'disp_num last_batt_disp_num)
        )

        (if (and (> (secs-since timer_start) DISPLAY_REPEAT_SECOND) (= smart_cruise SMART_CRUISE_OFF)) { ; 12= (2xdisplay duration + 2)
            (setvar 'disp_num (+ speed DISPLAY_SPEED_OFFSET))
            (setvar 'timer_start (systime))
        })

        ; xxx end repeat display section
        (if (and (= smart_cruise SMART_CRUISE_HALF_ENABLED) (> (secs-since timer_start) TIMER_SMART_CRUISE_TIMEOUT)) ; time out Smart Cruise if second activation isn't received within display duration
            (setvar 'smart_cruise SMART_CRUISE_OFF)
        )

        ; Extra Long Press Commands when off (10 seconds)
        (if (and (> (secs-since timer_start) TIMER_LONG_PRESS) (= speed SPEED_OFF) (= thirds_warning_latched 0)) {
            (debug_log "Battery: Thirds warning enabled")
            (setvar 'thirds_total actual_batt)
            (spawn warbler WARBLER_FREQUENCY WARBLER_DURATION 0)
            (setvar 'warning_counter 0)
            (setvar 'thirds_warning_latched 1)
        })

        ; Released
        (if (= sw_pressed 0) {
            (debug_log "State 2->3: Released")
            (setvar 'thirds_warning_latched 0)
            ; Record how long the button was held before first release
            (setvar 'initial_press_time (secs-since timer_start))
            (setvar 'timer_start (systime))
            (setvar 'timer_duration TIMER_RELEASE_WINDOW)
            (state_transition_to STATE_GOING_OFF "released" THREAD_STACK_STATE_TRANSITIONS state_handler_going_off)
            (break)
        })
    })
})

(move-to-flash state_handler_pressed)

; xxxx State 3 "Going Off"
(defun state_handler_going_off ()
{
    (debug_log "State 3: Going Off")
    (loopwhile (= sw_state STATE_GOING_OFF) {
        (sleep SLEEP_STATE_MACHINE)
        (if (> smart_cruise SMART_CRUISE_OFF) ; If Smart Cruise is enabled, dont shut down
            (timeout-reset)
        )

        ; Pressed
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

            (state_transition_to STATE_COUNTING_CLICKS "button_pressed" THREAD_STACK_STATE_COUNTING state_handler_counting_clicks)
            (break)
        })

        ; Timer Expiry
        (if (> (secs-since timer_start) timer_duration) {
            ; Check if we have pending clicks to process first
            (if (> clicks 0) {
                (debug_log_format (str-merge "State 3: Processing pending clicks=" (to-str clicks)))
                (apply_click_action clicks)
                (setvar 'clicks 0)
                ; Reset timer to stay in GOING_OFF state
                (setvar 'timer_start (systime))
                (setvar 'timer_duration TIMER_RELEASE_WINDOW)
            } {
                ; No pending clicks - check if we should shut down
                (if (and (!= smart_cruise SMART_CRUISE_FULLY_ENABLED) (!= smart_cruise SMART_CRUISE_AUTO_ENGAGED)) { ; If Smart Cruise is enabled, don't shut down
                    (debug_log "State 3->0: Timeout, shutting down")
                    (setvar 'timer_duration TIMER_DISABLED)
                    (cond
                        ((and (< speed start_speed) (> speed SPEED_UNTANGLE)) ; start at old speed if less than start speed
                            (setvar 'new_start_speed speed))
                        ((>= speed start_speed)
                            (setvar 'new_start_speed start_speed))
                    )
                    (set_speed_safe SPEED_OFF)
                    (setvar 'smart_cruise SMART_CRUISE_OFF) ; turn off Smart Cruise
                    (state_transition_to STATE_OFF "timeout_shutdown" THREAD_STACK_STATE_TRANSITIONS state_handler_off)
                    (break) ; SWST_OFF
                })

                ; Check if Smart Cruise needs to timeout
                (check_smart_cruise_timeout)
            })
        }) ; end Timer expiry
    }) ; end state
})

(move-to-flash state_handler_going_off)

(defun start_motor_speed_loop ()
{
    (debug_log "Motor: Starting motor speed loop")

    (safe_start_reset_state)

    (var last_speed SPEED_OFF)

    (loopwhile-thd THREAD_STACK_MOTOR t {
        (sleep SLEEP_MOTOR_CONTROL)

        (loopwhile (!= speed last_speed) {
            ; Only log speed changes that aren't part of soft-start monitoring
            (if (!= last_speed SPEED_SOFT_START_SENTINEL)
                (debug_log_format (str-merge "Motor: Speed change " (to-str (to-i last_speed)) "->" (to-str (to-i speed))))
            )
            (sleep SLEEP_MOTOR_SPEED_CHANGE)

            ; turn off motor if speed is 99
            (if (= speed SPEED_OFF) {
                (debug_log "Motor: Stopping motor")
                (set-current 0)
                (setvar 'batt_disp_timer_start (systime)) ; Start trigger for Battery Display
                (setvar 'disp_num DISPLAY_OFF) ; Turn on Off display. (off display is needed to ensure restart triggers a new display number)
                (safe_start_reset_state) ; unlock speed changes and disable safe start timer
                (setvar 'last_speed speed)
            })

            (if (!= speed SPEED_OFF) {
                ; Soft Start initiation section (only when starting from off)
                (if (= last_speed SPEED_OFF) {
                    (debug_log "Motor: Soft start initiated")
                    (conf-set 'l-in-current-max (if (= scooter_type SCOOTER_BLACKTIP) MIN_CURRENT_BLACKTIP MIN_CURRENT_CUDAX))
                    ; Start the soft-start timer regardless of safe-start being enabled so we can restore currents after a short period
                    (setvar 'soft_start_timer (systime))
                    (soft_start_set_active 1)
                    (setvar 'safe_start_attempt_speed speed)
                    (if (= use_safe_start 1)
                        (safe_start_begin speed)
                        (safe_start_set_status 'idle)) ; keep safe_start_status idle when disabled
                    (setvar 'last_speed SPEED_SOFT_START_SENTINEL)
                    (if (< speed SPEED_REVERSE_THRESHOLD)
                        (set-duty (- 0 SAFE_START_DUTY))
                        (set-duty SAFE_START_DUTY)
                    )
                } {
                    ; Speed change while already running (not from off, not during soft-start)
                    (if (!= last_speed SPEED_SOFT_START_SENTINEL) {
                        (set-rpm (calculate_rpm speed RPM_PERCENT_DENOMINATOR))
                        (setvar 'disp_num (+ speed DISPLAY_SPEED_OFFSET))
                        (setvar 'last_speed speed)
                    })
                })

                ; Soft-start/Safe-start monitoring section (runs while sentinel is active)
                (if (= last_speed SPEED_SOFT_START_SENTINEL) {
                    (var soft_elapsed (secs-since soft_start_timer))
                    (var rpm (get-rpm))
                    (var duty (get-duty))
                    (var current (get-current))

                    ; For safe-start enabled: check telemetry and criteria
                    (if (= use_safe_start 1) {
                        (var elapsed (secs-since safe_start_timer))

                        ; Check for invalid telemetry
                        (if (not (safe_start_telemetry_valid rpm duty current))
                            (safe_start_abort_with_reason "invalid telemetry")
                        )

                        ; Check safe-start completion
                        (if (safe_start_met_success_criteria rpm duty current)
                            {
                                (debug_log "Motor: Soft start completed (telemetry)")
                                (conf-set 'l-in-current-max (if (= scooter_type SCOOTER_BLACKTIP) MAX_CURRENT_BLACKTIP MAX_CURRENT_CUDAX))
                                (set-rpm (calculate_rpm speed RPM_PERCENT_DENOMINATOR))
                                (setvar 'disp_num (+ speed DISPLAY_SPEED_OFFSET))
                                (safe_start_success)
                                (soft_start_set_active 0)
                                (setvar 'last_speed speed)
                            } {
                                ; Check timeout
                                (if (> elapsed (+ SAFE_START_TIMEOUT SAFE_START_TIMEOUT_GRACE))
                                    (safe_start_abort_with_reason "timeout")
                                )

                                ; Detect high-current stall
                                (if (and (> elapsed SAFE_START_TIMEOUT) (> (abs current) SAFE_START_FAIL_CURRENT) (< (abs rpm) SAFE_START_MIN_RPM))
                                    (safe_start_abort_with_reason "high current stall")
                                )

                                ; If aborted, exit sentinel
                                (if (not (eq safe_start_status 'running))
                                    (setvar 'last_speed speed)
                                )
                            })
                    } {
                        ; For safe-start disabled: just wait for timer
                        (if (> soft_elapsed SOFT_START_DURATION)
                            {
                                (debug_log "Motor: Soft start completed (timer)")
                                (conf-set 'l-in-current-max (if (= scooter_type SCOOTER_BLACKTIP) MAX_CURRENT_BLACKTIP MAX_CURRENT_CUDAX))
                                (set-rpm (calculate_rpm speed RPM_PERCENT_DENOMINATOR))
                                (setvar 'disp_num (+ speed DISPLAY_SPEED_OFFSET))
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

(move-to-flash start_motor_speed_loop)

; Init-only function (not moved to flash)
(defun thirds_warning_startup ()
{
    (if (> enable_thirds_warning_startup 0) {
        (debug_log "Battery: Thirds warning enabled at startup")
        ; Wait a bit for battery reading to stabilize
        (sleep SLEEP_BATTERY_STABILIZE)
        ; Calculate battery % using the configured method
        ; Set thirds_total to current battery level
        (setvar 'thirds_total (get_battery_level))
        (debug_log (str-merge "Battery: Initial level=" (to-str thirds_total)))
        (setvar 'warning_counter 0)
    })
})


(defun apply_smart_cruise_timer_bar (pixbuf)
{
    ; Apply Smart Cruise timer bar to the bottom row when active
    ; The display buffer is organized as 8 rows of 2 bytes each (16 bytes total)
    ; b0,b1 = row 0 (top), b2,b3 = row 1, ..., b14,b15 = row 7 (bottom)
    ; Within each row: b15 (odd byte) contains the 8 LED bits with the following mapping:
    ; LED positions (left→right): LED1=bit7, LED2=bit0, LED3=bit1, LED4=bit2, LED5=bit3, LED6=bit4, LED7=bit5, LED8=bit6
    ; Show timer bar whenever Smart Cruise is active
    ; If trigger is held, show full bar (all 8 LEDs). If released, show countdown.
    ; Returns the number of LEDs that should be lit (0-8), or -1 if Smart Cruise is not active
    (var leds_lit (smart_cruise_leds_count))

    (if (!= leds_lit -1) {
        ; Build the bottom row byte value - LEDs turn off left to right (LED 1→2→3→4→5→6→7→8)
        ; Physical LED positions mapped to byte bits: LED1=bit7, LED2=bit0, LED3=bit1, LED4=bit2, LED5=bit3, LED6=bit4, LED7=bit5, LED8=bit6
        ; Lookup table approach for clarity
        (var bottom_row_value (ix TIMER_BAR_MASKS (clamp leds_lit 0 8)))

        ; Set the bottom row (byte 15) to show the timer bar
        (var current_byte (bufget-u8 pixbuf 15))
        (bufset-u8 pixbuf 15 (bitwise-or current_byte bottom_row_value))
    })

    leds_lit ; Return the LED count or -1
})

(move-to-flash apply_smart_cruise_timer_bar)


(defun start_display_output_loop ()
{
    (var start_pos 0) ; variable used to define start position in the array of diferent display screens
    (var pixbuf (array-create 16)) ; create a temp array to store display bytes in
    (var display_mpu_addr 0x70) ; I2C Address for the screen
    (var last_timer_bar_leds -1) ; Cache for Smart Cruise timer bar LED count to minimize I2C updates
    (loopwhile-thd THREAD_STACK_DISPLAY t {
        (sleep SLEEP_UI_UPDATE)
        ; Normal display timeout logic - clear display content but keep timer bar visible
        (if (and
                (> disp_timer_start 1)
                (> (secs-since disp_timer_start) TIMER_DISPLAY_DURATION)) {
            ; Clear the display number so 'C' or speed won't re-render with timer bar updates
            ; Only do this if Smart Cruise is active to avoid blank flash
            (if (or (= smart_cruise SMART_CRUISE_FULLY_ENABLED) (= smart_cruise SMART_CRUISE_AUTO_ENGAGED)) {
                (setvar 'disp_num DISPLAY_SENTINEL)
            } {
                ; Smart Cruise not active - turn off display normally
                (setvar 'disp_num DISPLAY_SENTINEL)
                ; For Blacktip, turn off the display
                (if (= scooter_type SCOOTER_BLACKTIP)
                    (i2c-tx-rx 0x70 (list 0x80))
                )
                ; Prevent the off→on flip in the same loop iteration
                (setvar 'last_disp_num DISPLAY_SENTINEL)
            })
            ; For Cuda X make sure it doesn't get stuck on displaying B1 or B2 error, so switch back to last battery.
            (if (and (= scooter_type SCOOTER_CUDAX) (> last_disp_num 20))
                (setvar 'disp_num last_batt_disp_num)
            )

            (setvar 'disp_timer_start 0)
        })

        ; Check if we need to update display (either disp_num changed OR Smart Cruise timer bar needs updating)
        (var should_update_display (!= disp_num last_disp_num))

        ; Check if Smart Cruise timer bar LED count has changed
        (var current_leds (smart_cruise_leds_count))
        (if (!= current_leds -1) {
            ; Smart Cruise active - check if LED count changed
            (if (!= current_leds last_timer_bar_leds) {
                (setvar 'should_update_display 1)
                (setvar 'last_timer_bar_leds current_leds)
            })
        } {
            ; Smart Cruise not active - reset cache if it was previously set
            (if (!= last_timer_bar_leds -1) {
                (setvar 'last_timer_bar_leds -1)
                (setvar 'should_update_display 1) ; Force update to clear timer bar
            })
        })

        (if should_update_display {
            (setvar 'display_mpu_addr 0x70)
            (if (= scooter_type 1) { ; For cuda X second screen
                (if (or (= disp_num 0) (= disp_num 1) (= disp_num 2) (= disp_num 3) (> disp_num 17))
                    (if (= cudax_flip 1)
                        (setvar 'display_mpu_addr 0x71)
                    )
                    (if (!= cudax_flip 1)
                        (setvar 'display_mpu_addr 0x71)
                    )
                )
            })
            ; Only update disp_timer_start if disp_num actually changed
            (if (!= disp_num last_disp_num) {
                (setvar 'disp_timer_start (systime))
            })
            (if (= display_mpu_addr 0x70)
                (setvar 'start_pos (+(* 64 disp_num) (* 16 rotation))) ; define the correct start position in the array for the display
                (setvar 'start_pos (+(* 64 disp_num) (* 16 rotation2)))
            )
            (bufclear pixbuf)
            ; Copy display data from binary LUT only if not sentinel (allows timer bar only display)
            (if (!= disp_num DISPLAY_SENTINEL)
                (bufcpy pixbuf 0 display_lut_bin (+ 8 start_pos) 16) ; copy the required display from binary LUT to "pixbuf"
            )
            ; Apply Smart Cruise timer bar overlay to bottom row if active
            (apply_smart_cruise_timer_bar pixbuf)
            (i2c-tx-rx display_mpu_addr pixbuf) ; send display characters
            (i2c-tx-rx display_mpu_addr (list 0x81)) ; Turn on display
            (setvar 'last_disp_num disp_num)
        })
    })
})

(move-to-flash start_display_output_loop)

; **** Program that triggers the display to show battery status ****
(defun start_display_battery_loop ()
{
    (var batt_disp_state 0)
    (loopwhile-thd THREAD_STACK_BATTERY t {
       (sleep SLEEP_UI_UPDATE)

        (if (or (= batt_disp_timer_start 0) (= batt_disp_state 0)) {
        (setvar 'batt_disp_state 0)})


        (if (and (> batt_disp_timer_start 1) (> (secs-since batt_disp_timer_start) 6) (= batt_disp_state 0)) { ; waits Display Duration + 1 second after scooter is turned off to stabilize battery readings

            ; xxxx Section for normal 4 bar battery capacity display

            (if (= thirds_total 0)
                (cond
                    ((> actual_batt 0.75) {
                        (setvar 'disp_num 3)
                        (spawn beeper 4)
                    })
                    ((> actual_batt 0.5) {
                        (setvar 'disp_num 2)
                        (spawn beeper 3)
                    })
                    ((> actual_batt 0.25) {
                        (setvar 'disp_num 1)
                        (spawn beeper 2)
                    })
                    (t {
                        (setvar 'disp_num 0)
                        (spawn beeper 1)
                    })
                )

                ; Section for 1/3rds display
                (cond
                    ((and (> actual_batt (* thirds_total 0.66)) (= warning_counter 0)) {
                        (debug_log "Battery: 2/3rds warning triggered")
                        (setvar 'disp_num 20)
                    })
                    ((and (> actual_batt (* thirds_total 0.33)) (< warning_counter 3)) {
                        (debug_log "Battery: 1/3rd warning triggered")
                        (setvar 'disp_num 19)
                        (if (< warning_counter 2) {
                            (spawn warbler 350 0.5 0.5)
                            (setvar 'warning_counter (+ warning_counter 1))
                        })
                    })
                    (t {
                        (debug_log "Battery: Critical warning triggered")
                        (setvar 'disp_num 18)
                        (if (< warning_counter 4) {
                            (spawn warbler 350 0.5 0.5)
                            (setvar 'warning_counter (+ warning_counter 1))
                        })
                    })
                )
            )

            (setvar 'batt_disp_state 1)
            (setvar 'last_batt_disp_num disp_num)
        })

        (if (and (> batt_disp_timer_start 1) (> (secs-since batt_disp_timer_start) 12) (= batt_disp_state 1) (> thirds_total 0)) {

            (cond
                ((> actual_batt 0.95)
                    (setvar 'disp_num 30))
                ((> actual_batt 0.90)
                    (setvar 'disp_num 29)) ; 90%
                ((> actual_batt 0.80)
                    (setvar 'disp_num 28)) ; 80%
                ((> actual_batt 0.70)
                    (setvar 'disp_num 27)) ; 70%
                ((> actual_batt 0.60)
                    (setvar 'disp_num 26)) ; 60%
                ((> actual_batt 0.50)
                    (setvar 'disp_num 25)) ; 50%
                ((> actual_batt 0.40)
                    (setvar 'disp_num 24)) ; 40%
                ((> actual_batt 0.30)
                    (setvar 'disp_num 23)) ; 30%
                ((> actual_batt 0.20)
                    (setvar 'disp_num 22)) ; 20%
                (t
                    (setvar 'disp_num 21))
            )
            (setvar 'batt_disp_state 0)
            (setvar 'batt_disp_timer_start 0)
        })
    })
})

(move-to-flash start_display_battery_loop)

(defun beeper (beeps)
(loopwhile (and (= enable_battery_beeps 1) (> batt_disp_timer_start 0) (> beeps 0)) {
       (sleep SLEEP_UI_UPDATE)
       (foc-beep 350 0.5 beeps_vol)
      (setvar 'beeps (- beeps 1))
    }))

(move-to-flash beeper)

; xxxx warbler Program xxxx"
(defun warbler (Tone Time Delay)
{
    (sleep Delay)
    (foc-beep Tone Time beeps_vol)
    (foc-beep (- Tone 200) Time beeps_vol)
    (foc-beep Tone Time beeps_vol)
    (foc-beep (- Tone 200) Time beeps_vol)
})

(move-to-flash warbler)

; ***** Program that beeps trigger clicks
(defun start_beeper_loop ()
{
    (var click_beep_timer 0)
    (loopwhile-thd THREAD_STACK_CLICK_BEEP t {
        (sleep SLEEP_UI_UPDATE)

        (if (and (> (secs-since click_beep_timer) SLEEP_UI_UPDATE) (!= click_beep_timer 0)) {
            (foc-play-stop)
            (setvar 'click_beep_timer 0)
        })

        (if (> click_beep 0) {
            (cond
                ((= click_beep CLICKS_SMART_CRUISE_CHANGE)
                    (foc-play-tone 1 1500 beeps_vol))
                ((= enable_trigger_beeps 1) {
                    (cond
                        ((= click_beep CLICKS_SINGLE) (foc-play-tone 1 2500 beeps_vol))
                        ((= click_beep CLICKS_DOUBLE) (foc-play-tone 1 3000 beeps_vol))
                        ((= click_beep CLICKS_TRIPLE) (foc-play-tone 1 3500 beeps_vol))
                        ((= click_beep CLICKS_QUADRUPLE) (foc-play-tone 1 4000 beeps_vol))
                    )
                })
            )

            (setvar 'click_beep_timer (systime))
            (setvar 'click_beep 0)
        })
    })
})

(move-to-flash start_beeper_loop)

; Init-only function (not moved to flash)
(defun peripherals_setup ()
{
    (if (or (= 0 hardware_configuration) (= 3 hardware_configuration)) ; turn on i2c for the screen based on wiring. 0 = Blacktip with Bluetooth, 3 = CudaX with Bluetooth
            (i2c-start 'rate-400k 'pin-swdio 'pin-swclk) ; Works HW 60 with screen on SWD Connector. Screen SDA pin to Vesc SWDIO (2), Screen SCL pin to Vesc SWCLK (4)
            (if (or (= 1 hardware_configuration) ( = 4 hardware_configuration)) ; 1 = Blacktip without Bluetooth, 4 = CudaX without Bluetooth
                (i2c-start 'rate-400k 'pin-rx 'pin-tx) ; Works HW 60 with screen on Comm Connector. Screen SDA pin to Vesc RX/SDA (5), Screen SCL pin to Vesc TX/SCL (6)
                (if ( = 2 hardware_configuration)
                    (i2c-start 'rate-400k 'pin-tx 'pin-rx) ; tested on HW 410 Tested: SN 189, SN 1691
                    (nil))))

    (i2c-tx-rx 0x70 (list 0x21)) ; start the oscillator
    ; Set brightness using BRIGHTNESS_LUT (six discrete levels, indices 0..5)
    (i2c-tx-rx 0x70 (list (ix BRIGHTNESS_LUT (clamp disp_brightness 0 (- (length BRIGHTNESS_LUT) 1))))) ; set brightness safely

    (if (= scooter_type 1) { ; For cuda X setup second screen
            (i2c-tx-rx 0x71 (list 0x21)) ; start the oscillator
            (i2c-tx-rx 0x71 (list (ix BRIGHTNESS_LUT (clamp disp_brightness 0 (- (length BRIGHTNESS_LUT) 1))))) ; set brightness safely
    })
})

(defun init ()
{
    (load_lookup_tables)

    (eeprom_set_defaults)

    (gc) ; Initialisation is done, clean up

    (debug_log "Initialisation done")
})

(defun main ()
{
    (update_settings_from_eeprom)

    (log_startup)

    (define thirds_total 0)
    (define warning_counter 0) ; Count how many times the 3rds warnings have been triggered.
    (define thirds_warning_latched 0) ; Prevents repeated long-press activation

    (thirds_warning_startup)

    (setup_event_handler)

    (define sw_state 0)
    (define timer_start 0)
    (define timer_duration 0)
    (define initial_press_time 0)
    (define clicks 0)
    (define actual_batt 0)
    (define new_start_speed start_speed)
    (define state_last_state STATE_UNINITIALIZED)
    (define state_last_change_time 0)
    (define state_last_reason "")

    (state_metrics_reset)

    (define speed SPEED_OFF)
    (define safe_start_timer 0)
    (define soft_start_timer 0)
    (define soft_start_active 0)
    (define safe_start_attempt_speed SPEED_OFF)
    (define safe_start_failures 0)
    (define safe_start_status 'idle)

    (start_motor_speed_loop)

    (define click_beep 0)

    (start_beeper_loop)

    (define disp_timer_start 0) ; Timer for display duration

    (peripherals_setup)

    (define disp_num 1) ; variable used to define the display screen you are accesing 0-X
    (define last_disp_num 1) ; variable used to track last display screen show

    (start_display_output_loop)

    (define batt_disp_timer_start 0) ; Timer to see if Battery display has been triggered
    (define last_batt_disp_num 3) ; variable used to track last display screen show

    (start_display_battery_loop)

    (define smart_cruise SMART_CRUISE_OFF)

    (start_smart_cruise_loop)

    (define sw_pressed 0)

    (start_trigger_loop)

    (state_transition_to STATE_OFF "startup" THREAD_STACK_STATE_TRANSITIONS state_handler_off) ; ***Start state machine running for first time

    (setvar 'disp_num 15) ; display startup screen, change bytes if you want a different one
    (setvar 'batt_disp_timer_start (systime)) ; turns battery display on for power on.

    (puts "Startup complete")
})

; Configuration settings
(define max_speed_no 0)
(define start_speed 0)
(define jump_speed 0)
(define use_safe_start 0)
(define enable_reverse 0)
(define enable_smart_cruise 0)
(define smart_cruise_timeout 0)
(define rotation 0)
(define disp_brightness 0)
(define hardware_configuration 0)
(define enable_battery_beeps 0)
(define beeps_vol 0)
(define cudax_flip 0)
(define rotation2 0)
(define enable_trigger_beeps 0)
(define enable_smart_cruise_auto_engage 0)
(define smart_cruise_auto_engage_time 0)
(define enable_thirds_warning_startup 0)
(define battery_calculation_method 0)
(define debug_enabled 0)
(define speed_set 0)
(define scooter_type 0)

(init)

(image-save)

(main)
