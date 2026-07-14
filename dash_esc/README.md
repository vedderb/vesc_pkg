# Dash ESC

CAN-server for the VESC Labs [Dash16](https://www.vesclabs.com/product/vesc-dash-16l/) and [Dash35B](https://www.vesclabs.com/product/vesc-dash-35b/) displays. This package should be installed on the ESC on the CAN-bus that provides data for the Dash. This package also implements the drive modes, cruise control and maps the analog lever to ADC2 on the ADC app.

**Note**  
To use cruise control it needs to be enabled in APP ADC.

**Note**  
To use reverse APP ADC needs to use the mode **Current Reverse Button** or **Current Reverse ADC2 Brake Button**. On the Dash16 **Current Reverse ADC2 Brake Button** is recommended as it allows using the lever on the dash as a brake while enabling the reverse mode. 

## Changelog

**Version 1.1 (2026-07-14)**
* Cruise control support
* Reverse support

**Version 1.0 (2026-07-03)**

* Initial Release
