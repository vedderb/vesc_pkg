# Float Accessories

<H3>About</H3>

A VESC Express package for BMS, Pubmote, GNSS and LED control on VESC Express modules for one-wheeled balance vehicles running Refloat.

<H3>Credits</H3>

Special Thanks: Benjamin Vedder, surfdado, NuRxG, Siwoz, lolwheel (OWIE), ThankTheMaker (rESCue), 4_fools (avaspark), auden_builds (pubmote)
gr33tz: outlandnish, exphat, datboig42069
Beta Testers: Pickles

<H3>Support Future Work</H3>

Support me on Patreon: <a href='https://patreon.com/SylerTheCreator'>https://patreon.com/SylerTheCreator</a>

Buy me a coffee: <a href='https://venmo.com/sylerclayton'>https://venmo.com/sylerclayton</a>

My Blog: <a href='https://sylerclayton.com'>https://sylerclayton.com</a>

<H3>Release Notes</H3>

<ul>
  <li>New LED backend</li>
  <li>GNSS receiver support (u-blox or NMEA over UART) - feeds the SD log position and the CAN GNSS broadcast</li>
  <li>Diagnostics card on the Config tab: per-area verbose logging plus a one-shot system report. The flag is held in RAM only, so it never persists and resets on reboot.</li>
</ul>

<H3>Diagnostics</H3>

When something misbehaves, open <b>Config &rarr; Diagnostics</b>, tick the areas you are chasing and watch
VESC Tool's Lisp console (<i>Dev Tools &rarr; Lisp &rarr; Console</i>). <b>Print Report</b> dumps a one-shot
snapshot - versions, thread ids, CAN/BMS/GNSS state and the LED segment map - and works with logging
switched off.

<b>DBG-CORE</b> also prints a once-per-second heartbeat of each loop's iteration rate
(<code>hz led 50 can 20 bms 20 rem 20 evt 3</code>). A loop that has died or stalled shows 0 here long
before the symptom is visible. There is no free-memory readout: VESC Express exposes no heap
introspection to lisp at all.

The same controls are available from the Lisp REPL:

<pre>
(dbg-on)            every category on
(dbg-off)           off
(dbg-add DBG-LED)   one category on
(dbg-del DBG-LED)   one category off
(dbg-set 12)        set the raw mask
(dbg-status)        show the current mask
(diag)              one-shot system report

categories: DBG-CORE 1     threads, heartbeat (per-loop rates), free memory
            DBG-CFG 2      config reads/writes, feature loops starting/stopping
            DBG-CAN 4      discovery, telemetry, state/fault/footpad changes
            DBG-LED 8      segment setup, mode/direction/highbeam decisions
            DBG-BMS 16     RS485 packets and decoded pack values
            DBG-REM 32     pubmote link, pairing, dropped packets
            DBG-GNSS 64    init, fix changes, position
            DBG-HUM 128    humidity sensor
            DBG-SDLOG 256  SD card logger
            DBG-CMD 512    inbound QML / CAN commands
            DBG-ALL 1023
</pre>

Errors and warnings always print, whatever the mask. Verbose logging is deliberately <i>not</i> stored in
the configuration: it is a debugging aid, it must not survive a power cycle and it must not wear the flash.

Log lines are terse on purpose. Every string literal in the package lives in the LispBM constant heap
(flash), which this package very nearly fills, so messages are telegraphic rather than sentences.

