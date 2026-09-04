# Dash ESC

CAN-server for the VESC Labs [Dash16](https://www.vesclabs.com/product/vesc-dash-16l/) and [Dash35B](https://www.vesclabs.com/product/vesc-dash-35b/) displays. This package should be installed on the ESC on the CAN-bus that provides data for the Dash. This package also implements the drive modes, cruise control and maps the analog lever to ADC2 on the ADC app.

**Note**  
Version 2.1 goes with the 2.1 Dash packages. It is tested on two bikes, but not every combination of settings has been ridden, so expect some rough edges.

**Note**  
To use cruise control it needs to be enabled in APP ADC.

**Note**  
To use reverse APP ADC needs to use the mode **Current Reverse Button** or **Current Reverse ADC2 Brake Button**. On the Dash16 **Current Reverse ADC2 Brake Button** is recommended as it allows using the lever on the dash as a brake while enabling the reverse mode.

## Changelog

**Version 2.1 (2026-09-04)**
* Fixes the package not loading on firmware below 7.00.5
* Set profile with conf-set instead of native lib
* Trap proc-sid

**Version 1.4 (2026-08-01)**
* Use native lib for setting profile
* Detach button in all modes

**Version 1.3 (2026-07-18)**
* Better multi-ESC support

**Version 1.2 (2026-07-14)**
* New app UI
* Configurable mode settings in UI

**Version 1.1 (2026-07-14)**
* Cruise control support
* Reverse support

**Version 1.0 (2026-07-03)**

* Initial Release
