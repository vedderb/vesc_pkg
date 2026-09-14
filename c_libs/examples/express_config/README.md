# Express Custom Config Example

**Custom config** example for the VESC Express. A custom config lets a package describe its settings in XML and have VESC Tool render its standard parameter UI for them - no QML page of your own, no hand-rolled EEPROM layout, no magic numbers or CRCs.

Once the package is installed and its script has run, VESC Tool shows an **Express Config Example** page with the parameters from `conf/settings.xml`, and the package's LispBM code reads the same values through the `ext-cfg-*` extensions.

The config is deliberately not a plausible device configuration - it is a catalogue holding **one parameter of every type VESC Tool can render**, each named after the type it demonstrates, so you can see the editor each one produces and copy the XML for the one you need.

This is the VESC Express counterpart of [`c_libs/examples/config`](../config), which does the same thing for the STM32.

## How it works

The native library registers three callbacks with the firmware:

```c
VESC_IF->conf_custom_add_config(get_cfg, set_cfg, get_cfg_xml);
```

| Callback | Answers | Does |
| --- | --- | --- |
| `get_cfg` | `COMM_GET_CUSTOM_CONFIG` / `..._DEFAULT` | Serializes the live (or default) config for VESC Tool |
| `set_cfg` | `COMM_SET_CUSTOM_CONFIG` | Deserializes what VESC Tool wrote and persists it |
| `get_cfg_xml` | `COMM_GET_CUSTOM_CONFIG_XML` | Hands out the compiled `settings.xml` so VESC Tool knows the parameters |

`conf_custom_clear_configs()` must be called from the lib's stop function, otherwise the firmware keeps calling into unloaded code.

## Files

| File | Role |
| --- | --- |
| `conf/settings.xml` | Parameter description: name, type, range, default, description, grouping |
| `conf/datatypes.h` | The `ExampleConfig` struct - one member per parameter, in `<SerOrder>` order |
| `conf/conf_general.h` | Pulls in the generated `conf_default.h` for the generated parser |
| `conf/buffer.c/h` | Byte packing helpers the generated parser uses |
| `code.c` | The library: the three callbacks, EEPROM persistence and the LispBM extensions |
| `express_config.lisp` | Loads the lib and reads/applies the config |

`vesc_tool --xmlConfToCode conf/settings.xml` generates `confparser.c/h`, `confxml.c/h` and `conf_default.h` from the XML - the Makefile runs it, and the generated files are not in git.

### Adding a parameter

1. Add the tag to `<Params>` in `conf/settings.xml`, and its name to `<SerOrder>` and to a `<subgroupParams>` list.
2. Add the matching member to `ExampleConfig` in `conf/datatypes.h`, in the same position as in `<SerOrder>`.
3. Add an entry to `cfg_names` / `cfg_offsets` / `cfg_types` / `cfg_lengths` in `code.c` and bump `CFG_FIELD_COUNT`, keeping the same order (only needed for the generic LispBM accessors). Widen `CFG_NAME_LEN` if the new name is longer than the current longest.
4. `make clean && make`.

### The types

`<type>` picks the editor and the storage class. For ints and doubles, `<vTx>` then picks the width on the wire — and that is what the C type in `datatypes.h` has to match.

| `<type>` | Editor | `<vTx>` | Wire | C type |
| --- | --- | --- | --- | --- |
| `5` bool | Checkbox | — | 1 byte | `uint8_t` |
| `4` enum | Combo box of `<enumNames>`, stores the index | — | 1 byte | `uint8_t` |
| `6` bitfield | A checkbox per `<enumNames>`, packed into bits | — | 1 byte | `uint8_t` (max 8 flags) |
| `2` int | Spin box | `1` uint8 / `2` int8 | 1 byte | `uint8_t` / `int8_t` |
| | | `3` uint16 / `4` int16 | 2 bytes | `uint16_t` / `int16_t` |
| | | `5` uint32 / `6` int32 | 4 bytes | `uint32_t` / `int32_t` |
| `1` double | Spin box | `7` double16 | 2 bytes | `float` |
| | | `8` double32 | 4 bytes | `float` |
| | | `9` double32 auto | 4 bytes | `float` |
| `3` QString | Text field | — | `maxLen + 1` | `char[maxLen + 1]` |

Notes worth knowing before you pick one:

- **`double16` and `double32` are scaled integers.** The value goes over the wire as `value * vTxDoubleScale`, so scale sets both range and precision — at scale 100 a `double16` covers roughly ±327 in steps of 0.01. **`double32 auto`** is a real self-scaling float with no scale to choose, and is the right default unless wire size matters.
- **A bitfield is just an integer** on both the C and LispBM sides. Only VESC Tool knows it's flags.
- **Strings are the one variable-length type**, so `SERIALIZED_CONFIG_LENGTH` is an upper bound rather than the exact size.
- **`maxInt` is parsed as a signed int**, so a `uint32` parameter cannot have an editable maximum above 2147483647 even though the field holds more.
- **Presentation-only knobs** don't change storage: `suffix` appends a unit, `editAsPercentage` edits a 0.0-1.0 value as 0-100 %, `editorDecimalsDouble` sets displayed decimals, and `showDisplay` adds a readout.
- **`::sep::Some Text`** as a `<param>` entry in a `<subgroupParams>` list draws a labelled separator instead of a field. The Integers subgroup uses these.

### Grouping

**The top-level `<groupName>` must be `General`.** Both custom config pages — `pages/pagecustomconfig.cpp` on the desktop and `mobile/ConfigPageCustom.qml` — call `getParamSubgroups("General")` with the name hardcoded. Any other group name yields no subgroups and the page renders **empty, with no error**, so this is easy to lose time on.

Within that group, each `<subgroup>` becomes a tab (desktop) or a combo box entry (mobile), and its `<subgroupParams>` are the fields on it, in order. A parameter that is in `<Params>` and `<SerOrder>` but in no subgroup is stored and transmitted normally but never shown — which is how a package keeps internal state in the config without exposing it. Putting such parameters in a second top-level group works too, and for the same reason: only `General` is rendered.

Changing the parameters changes the signature VESC Tool derives from the XML, so a config stored by an older layout is rejected on load and the defaults are used. That check replaces the magic number and CRC scheme a package would otherwise need.

## Storage

The serialized config is written to the firmware's eeprom vars (32-bit slots backed by NVS) with `store_eeprom_var` / `read_eeprom_var`, which move `count` words from a base address in one NVS transaction. Storing the config as a single call rather than a word at a time (`count` 1) is both faster and atomic - a config is one thing, and a partial write is a corrupt config.

`EEPROM_BASE_IDX + CONFIG_WORDS` must stay within the firmware's `EEPROM_VARS` count; this example starts at index 0, while a package that also uses eeprom vars for other things should leave the low indices free.

## LispBM interface

| Extension | Description |
| --- | --- |
| `(ext-cfg-get "name")` | Read a parameter |
| `(ext-cfg-set "name" value)` | Write a parameter (RAM only) |
| `(ext-cfg-store)` | Persist the current config |
| `(ext-cfg-restore)` | Reset to the XML defaults and persist |
| `(ext-cfg-changed)` | `t` once after VESC Tool wrote the config, then `nil` |

Names use the XML names, with `-` and `_` treated as equal, so `'demo-float16` reaches `demo_float16`. Polling `(ext-cfg-changed)` is what lets settings take effect without a reboot.

The lookup table in `code.c` maps each field to its C storage type, so `ext-cfg-get` hands back a float for the double parameters, an integer for the ints, and a byte array for the string. A bitfield arrives as a plain integer — `express_config.lisp` has a `bit-set?` helper showing how to test a flag.

## Position-independence caveat

On the RISC-V targets the lib executes in place from flash with no load-time relocation, so a statically initialized array of *pointers* (`const char *names[] = {"a", ...}`) holds meaningless link-time addresses at runtime. The name table in `code.c` is therefore a fixed-size `char[N][LEN]` array, whose element addresses are computed at runtime. Note also that `get_cfg_xml` does **not** add `PROG_ADDR` to the XML data pointer the way the STM32 example does - on the Express the address is already correct.

## Building

```sh
make
```

builds the library for all four chips. Needs `vesc_tool` in the path for the conf generation, the `riscv32-esp-elf` and `xtensa-esp32s3-elf` toolchains, and the `c_libs/express/RVfplib` submodule initialized (`git submodule update --init`).

```sh
make pkg
```

also builds `express_config.vescpkg`.

## Requirements

Firmware with native lib support, including `(sysinfo 'hw-target)`. On the ESP32-S3 the firmware must be built with `CONFIG_ESP_SYSTEM_MEMPROT_FEATURE=n`.
