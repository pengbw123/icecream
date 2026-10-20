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
    /* The RV32I fetches instructions with a 14-bit word address, so the load
       image must stay inside the low 64 KiB (16 384 words).  The build script
       enforces the same limit on firmware.bin; this assertion catches a link
       that would otherwise wrap silently.  .bss is not part of the image and
       may use the rest of the 128 KiB data memory. */
    ASSERT(SIZEOF(.text) + SIZEOF(.data) <= 65536,
           "Firmware image exceeds the 64 KiB instruction ROM")
    ASSERT(_end <= ORIGIN(RAM) + LENGTH(RAM), "Firmware exceeds 128 KiB data memory")
}
