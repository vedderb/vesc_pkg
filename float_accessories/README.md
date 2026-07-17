# FLOAT ACESSORIES PACKAGE

A VESC Express package for controlling LEDs, BMS and Pubmote.

<H2>THIS PORT</H2>

This version of the package differs from the original in two ways:

<ul>
  <li><b>LEDs are rendered by the ESPLED Strip native library</b> (lib_espled_strip). The library owns the framebuffers, a background render thread and the LED driver; the package only drives high-level segment state (effect, color, brightness). Strips that share one pin are chained automatically, and each strip can pick a wire timing preset (Universal / WS2812B / WS2815 / SK6812 / SK6815). Highbeams are fully supported: the Stock GT preset drives a separate PWM highbeam pin, and the embedded-highbeam presets (Avaspark Laserbeams, Light-shutka Flashfires, JetFleet H4/GT, Fungineers GTFO) drive the in-strip highbeam LEDs as overlay pixels.</li>
  <li><b>Master/slave over CAN</b> (Node Role setting). A <b>Master</b> (the default) behaves exactly like a single node did before: it polls the VESC/Refloat and now also broadcasts that telemetry, plus the shared lighting settings, to the rest of the bus. A <b>Slave</b> does not poll the VESC at all - it renders its own strips from the master's broadcast and stores the settings the master pushes, so a build can spread its LEDs across several ESP32 boards while configuring them in one place. Physical wiring (pins, LED counts, strip timing, highbeam hardware) stays local to each node; only appearance/behaviour is synced. Set the role on the package's settings page or in VESC Tool's Float Accessories, then reboot the node.</li>
  <li><b>All settings live in a VESC custom config</b> ("Float Accessories" in VESC Tool's parameter UI), provided by the fa_cfg native lib and described by conf/settings.xml. The firmware persists the config; the old in-package eeprom layout, magic numbers and CRC handling are gone. The package's own settings page keeps working like before (it reads and writes the same config), so you can use either it or VESC Tool's parameter pages - edits from both apply live.</li>
</ul>

Requires VESC Express firmware with native lib support (load-native-lib, custom configs and (sysinfo 'hw-target)). Works on ESP32-C3, C6, S3 and P4; on the S3 the firmware must be built with CONFIG_ESP_SYSTEM_MEMPROT_FEATURE=n.

<H2>Support Future Work</H2>

Support me on Patreon: <a href='https://patreon.com/SylerTheCreator'>https://patreon.com/SylerTheCreator</a>

Buy me a coffee: <a href='https://venmo.com/sylerclayton'>https://venmo.com/sylerclayton</a>

<H2>CREDITS</H2>

Special Thanks: Benjamin Vedder, surfdado, NuRxG, Siwoz, lolwheel (OWIE), ThankTheMaker (rESCue), 4_fools (avaspark), auden_builds (pubmote)
gr33tz: outlandnish, exphat, datboig42069
Beta Testers: Pickles

My Blog: <a href='https://sylerclayton.com'>https://sylerclayton.com</a>

<H2>RELEASE NOTES</H2>

<ul>
  <li>Master/slave (multi-node) LED support over CAN</li>
  <li>Memory optimization</li>
  <li>Setting save fix</li>
  <li>Motor Config fix</li>
  <li>SD card logging support</li>
  <li>Mall Grab short press LED on/off. Long press highbeams</li>
  <li>Different default pins for Avaspark RGB S3 than C3</li>
  <li>Option to disable updates for front/rear LED bars (white/red hardcoded) while motor is running to prevent flicker on PCBs prone to EMF</li>
  <li>Pulse pattern while charging</li>
  <li>Overhaul of LED patterns to use time instead of indexes (fixes Knight Rider and makes animation smoother)</li>
  <li>Dynamic way of adding new settings to EEPROM. No more resetting config while upgrading to new version with new params</li>
  <li>Support for battery cell type-specific discharge curves for battery meter pattern (stock BMS will also use now)</li>
  <li>Add handtest and connecting LED patterns</li>
  <li>Fix for GTFO strips</li>
  <li>Humidity Sensor Support</li>
  <li>Support for future refloat humidity pushback and alert</li>
  <li>GNSS receiver support (u-blox or NMEA over UART) - feeds the SD log position and the CAN GNSS broadcast</li>
</ul>

<H3>BUILD INFO</H3>

Version 4.0.0

Source code can be found here:  <a href='https://github.com/relys/vesc%5Fpkg'>https://github.com/relys/vesc_pkg</a>