ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 96K
    /* Data-port alias: address bits above bit16 are not decoded by local RAM.
       BSS can reuse the DATA copy of instruction bytes without touching the
       independently stored instruction ROM. Constants remain above it. */
    /* Sparse UI DATA profile: low 16K + high 32K, with no physical RAM
       for DATA addresses 0x10004000..0x1000ffff. Instruction ROM is separate. */
    BSS (rw) : ORIGIN = 0x10020000, LENGTH = 16K
}

SECTIONS
{
    .text :
    {
        KEEP(*(.text.start))
        *(.text*)
        . = ALIGN(4);
    } > RAM

    .rodata :
    {
        _rodata_start = .;
        *(.rodata*)
    } > RAM

    .data :
    {
        . = ALIGN(4);
        *(.data*)
        *(.sdata*)
    } > RAM

    _image_end = .;

    .bss (NOLOAD) :
    {
        . = ALIGN(4);
        _sbss = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > BSS

    _end = .;
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
    /* The UI fetch port has a 64 KiB base and a 16 KiB extension.  The build
       script emits both ROM images and enforces this same 80 KiB boundary.
       .bss resides in the low 16 KiB DATA bank; constants and stack occupy
       the high 32 KiB DATA bank within the original 96 KiB address window. */
    ASSERT(SIZEOF(.text) + SIZEOF(.rodata) + SIZEOF(.data) <= 81920,
           "Firmware image exceeds the 80 KiB instruction ROM")
    ASSERT(_image_end + 12288 <= _stack_top, "UI needs at least 12 KiB stack headroom")
    ASSERT(SIZEOF(.bss) <= _rodata_start - ORIGIN(RAM),
           "BSS data alias overlaps read-only constants")
    ASSERT(_rodata_start >= 0x10010000, "UI constants fall in sparse DATA hole")
}
