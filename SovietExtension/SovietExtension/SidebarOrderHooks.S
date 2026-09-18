.text
.p2align 2

.macro YM_ORDER_GETTER_VENEER hook, trampoline, group
.globl _\hook
.private_extern _\hook
_\hook:
    .cfi_startproc
    .long 0xd503245f
    stp x20, x19, [sp, #-32]!
    .cfi_def_cfa_offset 32
    .cfi_offset w20, -32
    .cfi_offset w19, -24
    stp x29, x30, [sp, #16]
    .cfi_offset w29, -16
    .cfi_offset w30, -8
    add x29, sp, #16
    .cfi_def_cfa w29, 16
    mov x19, x0
    mov x20, x8
    adrp x16, _\trampoline@PAGE
    ldr x16, [x16, _\trampoline@PAGEOFF]
    blr x16
    mov x1, x19
    mov x19, x0
    mov x0, x20
    mov w2, #\group
    bl _YMNavigationSidebarReorderOrderResult
    mov x0, x19
    mov x8, x20
    ldp x29, x30, [sp, #16]
    ldp x20, x19, [sp], #32
    .cfi_def_cfa wsp, 0
    ret
    .cfi_endproc
.endmacro

YM_ORDER_GETTER_VENEER \
    YMNavigationSidebarPrimaryOrderHook, \
    YMNavigationSidebarPrimaryOrderTrampoline, \
    0

YM_ORDER_GETTER_VENEER \
    YMNavigationSidebarSecondaryOrderHook, \
    YMNavigationSidebarSecondaryOrderTrampoline, \
    1

.p2align 2
.globl _YMNavigationSidebarFormatNativeTitle
.private_extern _YMNavigationSidebarFormatNativeTitle
_YMNavigationSidebarFormatNativeTitle:
    .cfi_startproc
    .long 0xd503245f
    sub sp, sp, #32
    .cfi_def_cfa_offset 32
    stp x29, x30, [sp, #16]
    .cfi_offset w29, -16
    .cfi_offset w30, -8
    add x29, sp, #16
    .cfi_def_cfa w29, 16
    str x2, [sp]
    mov x8, x0
    mov x0, x1
    blr x3
    .cfi_def_cfa wsp, 32
    ldp x29, x30, [sp, #16]
    .cfi_restore w29
    .cfi_restore w30
    add sp, sp, #32
    .cfi_def_cfa wsp, 0
    ret
    .cfi_endproc
