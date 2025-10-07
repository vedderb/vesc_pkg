(def init-complete nil)

@const-start

(import "pkg@://vesc_packages/lib_code_server/code_server.vescpkg" 'code-server)
(read-eval-program code-server)

(import "pkg::disp-text@://vesc_packages/lib_disp_ui/disp_ui.vescpkg" 'disp-text)
(read-eval-program disp-text)

(import "pkg::disp-button@://vesc_packages/lib_disp_ui/disp_ui.vescpkg" 'disp-button)
(read-eval-program disp-button)

(import "pkg::disp-gauges@://vesc_packages/lib_disp_ui/disp_ui.vescpkg" 'disp-gauges)
(read-eval-program disp-gauges)

(import "config.lisp" 'code-config)
(read-eval-program code-config)

(import "fonts/font_12_15_aa.bin" 'font15)
(import "fonts/font_15_18_aa.bin" 'font18)
(import "fonts/font_22_24_aa.bin" 'font24)
(import "fonts/font_21_32_aa_digits.bin" 'font32)
(import "fonts/font_60_88_aa.bin" 'font88)
(import "fonts/font_77_128_aa.bin" 'font128)

(import "assets/logo-16c.bin" 'icon-logo)
(import "assets/stripes-bare-15c.bin" 'icon-stripe)
(import "assets/stripes-top-7c.bin" 'icon-stripe-top)
(import "assets/stripes-arrow-l-15c.bin" 'icon-arrow-l)
(import "assets/stripes-arrow-r-15c.bin" 'icon-arrow-r)
(import "assets/motor-4c.bin" 'icon-motor)
(import "assets/esc-4c.bin" 'icon-esc)
(import "assets/battery-4c.bin" 'icon-battery)
(import "assets/warning-4c.bin" 'icon-warning)
(import "assets/bike-6c.bin" 'icon-bike)
(import "assets/bms-cell-high-4c.bin" 'icon-bms-cell-high)
(import "assets/bms-cell-low-4c.bin" 'icon-bms-cell-low)
(import "assets/bms-temp-high-4c.bin" 'icon-bms-temp-high)
(import "assets/bms-temp-low-4c.bin" 'icon-bms-temp-low)
(import "assets/bms-chip-4c.bin" 'icon-bms-chip)
(import "assets/bms-charge-4c.bin" 'icon-bms-charge)
(import "assets/bms-discharge-4c.bin" 'icon-bms-discharge)

(if config-homologation-enable {
    ; Homologation Elements
    (import "assets/blinker-left-4c.bin" 'icon-blinker-left)
    (import "assets/blinker-right-4c.bin" 'icon-blinker-right)
    (import "assets/cruise-control-4c.bin" 'icon-cruise-control)
    (import "assets/light-4c.bin" 'icon-lights)
    (import "assets/high-beam-4c.bin" 'icon-highbeam)
    (import "assets/kickstand-4c.bin" 'icon-kickstand)
    (import "assets/neutral-4c.bin" 'icon-neutral)
    (import "assets/drive-4c.bin" 'icon-drive)
    (import "assets/reverse-4c.bin" 'icon-reverse)
    (import "assets/charge-bolt-4c.bin" 'icon-charge-bolt)
    (import "assets/hot-battery-16c.bin" 'icon-hot-battery)
    (import "assets/hot-motor-16c.bin" 'icon-hot-motor)
    (import "assets/low-beam-4c.bin" 'icon-lowbeam)
    (import "assets/press-to-start-4c.bin" 'icon-start-msg)
    (import "assets/motor-start-4c.bin" 'icon-start-motor)
})

(import "lib/vehicle-state.lisp" 'code-vehicle-state)
(read-eval-program code-vehicle-state)

(import "lib/colors.lisp" 'code-colors)
(read-eval-program code-colors)

(import "lib/user-settings.lisp" 'code-user-settings)
(read-eval-program code-user-settings)

(import "lib/persistent-settings.lisp" 'code-persistent-settings)
(read-eval-program code-persistent-settings)

(import "lib/statistics.lisp" 'code-statistics)
(read-eval-program code-statistics)

(import "lib/draw-utils.lisp" 'code-draw-utils)
(read-eval-program code-draw-utils)

(import "views/components/view-startup.lisp" 'code-view-startup)
(read-eval-program code-view-startup)

(import "views/components/view-menu.lisp" 'code-view-menu)
(read-eval-program code-view-menu)

(if config-homologation-enable {
    (import "views/view-homologation.lisp" 'code-view-homologation)
    (read-eval-program code-view-homologation)
} {
    (import "views/view-main.lisp" 'code-view-main)
    (read-eval-program code-view-main)
})

(import "views/view-speed-large.lisp" 'code-view-speed-large)
(read-eval-program code-view-speed-large)

(import "views/view-statistics.lisp" 'code-view-statistics)
(read-eval-program code-view-statistics)

(import "views/view-bms.lisp" 'code-view-bms)
(read-eval-program code-view-bms)

(import "views/view-live-chart.lisp" 'code-view-live-chart)
(read-eval-program code-view-live-chart)

(import "views/view-profile-select.lisp" 'code-view-profile-select)
(read-eval-program code-view-profile-select)

(import "views/view-profile-edit.lisp" 'code-view-profile-edit)
(read-eval-program code-view-profile-edit)

(import "views/view-minigame.lisp" 'code-view-minigame)
(read-eval-program code-view-minigame)

(import "lib/input.lisp" 'code-input)
(read-eval-program code-input)

(import "lib/display-utils.lisp" 'code-display-utils)
(read-eval-program code-display-utils)

(import "lib/communication.lisp" 'code-communication)
(read-eval-program code-communication)

@const-end

(if config-metric-speeds
    (def settings-units-speeds '(kmh . "km/h"))
    (def settings-units-speeds '(mph . "MPH"))
)

(if config-metric-temps
    (def settings-units-temps '(celsius . "C"))
    (def settings-units-temps '(fahrenheit . "F"))
)

(if config-code-server (start-code-server)) ; Enable remote code execution

(display-init)

(if config-boot-animation-enable (start-boot-animation))

(def init-complete true)
