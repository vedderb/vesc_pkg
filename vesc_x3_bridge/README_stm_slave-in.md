# VESC X3 Bridge STM Slave

VESC-side companion for **additional motors** in a multi-motor setup.
Install this on every VESC other than the one that owns throttle input --
that VESC runs the **VESC X3 Bridge STM** package instead, not this one.

## What it does

This package only keeps this VESC's speed limit (`l-max-erpm`) in sync
with the dashboard's active profile (Eco/Drive/Sport). It registers
itself with the Express-side **VESC X3 Bridge ESP** package (CAN id
only -- Express doesn't need this VESC's motor config or battery) and
applies whatever speed limit Express relays back.

Everything else -- throttle, brake, cruise control -- reaches this VESC
on its own, via a VESC Tool setting on the master, not a script:

## Required VESC Tool setting on the MASTER VESC

**App Settings -> General -> Multi ESC over CAN: Enabled**

Set this on the master (the VESC running **VESC X3 Bridge STM**), not on
this slave VESC. Once enabled, the master forwards the throttle current,
brake current, and cruise-hold current it computes to every VESC it's
recently seen a CAN status message from -- which includes this one, as
long as it has a distinct controller id from the master and is sending
CAN status messages (VESC's default behavior).

## This is only a third of the bridge

This package needs both the throttle-owning **VESC X3 Bridge STM**
package (a different physical VESC) and the **VESC X3 Bridge ESP**
package (on VESC Express) installed and working -- none of the three is
useful installed alone.

If VESC Express's controller id isn't the default (2), edit
`express-can-id` at the top of `code_stm_slave.lisp` to match.

## Change Log
1.0 Initial release
