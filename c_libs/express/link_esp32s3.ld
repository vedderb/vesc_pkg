/* Linker script for ESP32-S3 (Xtensa) native libraries.
 *
 * Unlike the RISC-V targets, Xtensa cannot generate position-independent
 * code, so S3 libraries are linked at 0 with relocations kept (ld -q) and
 * the firmware copies them into RAM, patching every absolute word at load
 * time (see mkreloc.py). Code and data must live in separate output
 * sections: words that point at executable sections are patched with the
 * IRAM alias of the load address and everything else with the byte-
 * accessible DRAM alias.
 */

/* The image is loaded in two parts: the code region (executable RAM,
   word-access only is fine) and the data region (byte-accessible RAM).
   Code sections come first, then the data sections with .program_ptr
   leading the data region (the loader expects it at data base + 4). */

SECTIONS
{
    . = 0;
    /* code region */
    .init_fun : ALIGN(4) { *(.init_fun.literal) *(.init_fun) }
    .text : ALIGN(4) { *(.literal) *(.text) *(.literal.*) *(.text.*) }

    /* data region */
    .program_ptr : ALIGN(4) { *(.program_ptr) }
    .rodata : ALIGN(4) { *(.rodata*) *(.srodata*) }
    .data : ALIGN(4) { *(.data*) *(.sdata*) }
    .bss : ALIGN(4) { *(.bss*) *(.sbss*) *(COMMON) }
}
