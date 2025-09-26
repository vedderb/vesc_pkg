SECTIONS
{
    . = 0;
    .program_ptr : ALIGN(4) { *(.program_ptr) } /* offset 0 */
    .init_fun : ALIGN(4) { *(.init_fun) }

    .text : ALIGN(4) { *(.text*) *(.rodata*) }
    .data : ALIGN(4) { *(.data*) }
    .bss : ALIGN(4) { *(.bss*) }
    .got : ALIGN(4) { *(.got*) }
}