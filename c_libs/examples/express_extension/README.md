# Express Native Lib Example

Example native library (C extensions) for the VESC Express. It builds the same small C library for every supported chip (ESP32-C3, C6, S3 and P4), picks the right binary at runtime with `(sysinfo 'hw-target)` and runs a short self-test that prints to the LispBM console.

The library exercises the parts of the C interface that differ between the targets:

* `(ext-test-hello)` - prints a string (rodata addressing; on the S3 this verifies the DRAM-alias relocation of string pointers).
* `(ext-test-mul a b)` - float multiply (soft float via RVfplib on C3/C6, hardware FPU on S3/P4 - a wrong ABI shows up here).
* `(ext-test-counter)` - value of a counter incremented every 100 ms by a thread the lib spawns (spawn/terminate and the ARG base-address bookkeeping; on the S3 this verifies the IRAM-alias relocation of code pointers).

## Expected output when the package starts

```
Loading native test lib for esp32c3
Native test lib loaded
t
Hello from the native test lib!
2.5 * 3.0 = 7.500000
Counter after 1s (expect ~10): 10
```

Restarting or stopping the lisp script should print `Test lib stopped, counter was ...`, which verifies the stop function and thread termination.

## Building

```sh
make
```

builds the library for all four chips (needs the `riscv32-esp-elf` and `xtensa-esp32s3-elf` toolchains in the path and the `c_libs/express/RVfplib` submodule initialized: `git submodule update --init`).

```sh
make pkg
```

## Requirements

Firmware with native lib support, including `(sysinfo 'hw-target)`. On the ESP32-S3 the firmware must be built with `CONFIG_ESP_SYSTEM_MEMPROT_FEATURE=n`.
