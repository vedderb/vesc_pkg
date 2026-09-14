# X1-Unlocker

Automatically sends a "magic" message, to unlock the CAN-port of INNOTRACE X1 controllers.

INNOTRACE was a brand that sold aftermarket controllers for chinese Bafang Ultra M620/G510 mid-drive motors with integrated torque-sensor. Their X1-Controller and X1-Tool were basically a commercialized copy of the VESC-Project. It was tied to a subscription service and overpriced USB-FTDI-cable, which connected via UART to the motor, like the stock Bafang-Controller does. With this package a magic CAN-message is sent, which makes the X1-Controller show up as VESC-CAN-device and accessible.

<br/><br/>

---
## Disclaimer
This is experimental and mostlikely not intended by Innotrace! Functions are limited and you should be very careful with changing unknown parameters! It works with X1-FW 2.4.x.x and 2.5.x.x. Things you can do with this:
 
* Rotor-Calibration
* Max Current
* Max Wattage

<br/><br/>

---
## Usage
The package is made to be used with VESC-Express, but can run it on any VESC that supports lispBM. The script automatically runs one time at boot, therefore please exactly follow these steps, to prepare your setup correctly:
 
1. Download the latest VESC-Tool beta from https://vesc-project.com/vesc_tool
2. Connect the CAN-H and CAN-L of the VESC-Express with your X1 motor. (see pinout below)
3. Turn on the battery.
4. Turn on the display. (**Important! Do not skip!**)
5. Plug the VESC-Express into your computer.
6. Connect via VESC-Tool beta.
7. Wait until LED changes from RED to BLUE.
8. Now click "Scan CAN" and click on "X1".
9. There you go!

<br/><br/>

---
## Locate Connector
With Bafang this connector is normally for optional battery communication via UART. On X1, this connector is repurposed and has CAN-Bus accessible from the outside, without opening the motor: [plug_location.png](https://github.com/Tomblarom/vesc_pkg/blob/main/x1_unlocker/plug_location.png)\
[image source: [https://www.greenbikekit.com](https://www.greenbikekit.com)]
<br/><br/>

---
## Pinout Connector
Copied from  [@dedo](https://forums.electricbikereview.com/threads/archon-x1-programming-thread-questions-and-experiences.40034/page-16#post-627685). Thanks for providing! [plug_pinout.png](https://github.com/Tomblarom/vesc_pkg/blob/main/x1_unlocker/plug_pinout.png)\
Female: 04R-JWPF-VSLE-S\
Male:     04T-JWPF-VSLE-S

<br/><br/>

---
### Version
- X1-Unlocker v1.0