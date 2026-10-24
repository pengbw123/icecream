ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 128K
}

SECTIONS
{
    .text :
    {
        KEEP(*(.text.start))
        *(.text*)
        *(.rodata*)
    } > RAM

    .data :
    {
        . = ALIGN(4);
        *(.data*)
        *(.sdata*)
    } > RAM

    .bss (NOLOAD) :
    {
        . = ALIGN(4);
        _sbss = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > RAM

    _end = .;
    /* The UI fetch port has a 64 KiB base and a 16 KiB extension.  The build
       script emits both ROM images and enforces this same 80 KiB boundary.
       .bss resides only in the separate 128 KiB writable data memory. */
    ASSERT(SIZEOF(.text) + SIZEOF(.data) <= 81920,
           "Firmware image exceeds the 80 KiB instruction ROM")
    ASSERT(_end <= ORIGIN(RAM) + LENGTH(RAM), "Firmware exceeds 128 KiB data memory")
}
