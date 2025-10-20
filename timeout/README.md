# Remote Timeout

A simple safety script for VESC-based ESCs that do not properly handle remote disconnect timeouts. If the remote input stops updating for 1.00 s, motor current is set to zero.

## What it does

- Monitors the age of the last received remote input using `get-remote-state`.
- If the age exceeds 1.00 s, commands zero current to stop the motor.
- Runs at a low cadence to minimize load.

## Usage

1. Install the package from the VESC Tool package store.
2. Start the package once from the Packages page to save it.
3. After that it runs at boot automatically. The timeout is fixed to 1.00 s.

## Compatibility

- Works on VESC-based ESCs that support packages and expose `get-remote-state`.
- Not compatible with the classic VESC BMS.

 