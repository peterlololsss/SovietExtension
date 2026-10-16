//
//  LiquidGlassNavigationHook.S
//  SovietExtension
//
//  迷离模式 2.0 第一阶段 · A 步骤 3：导航栏「外层父 widget」背景填充 detour。
//
//  目标是 WeChat 4.1.11 (arm64) 里外层父 widget 类（vtable slice VA 0x8b272a8）的背景
//  paint 虚方法：虚表槽 56 / 偏移 0x1c0，slice VA 0xe658f4，返回 void，x0 = this
//  (QWidget)。LiquidGlassNavigation.mm 在身份校验通过后对该函数入口装 16 字节绝对
//  跳转，使每次调用先进本 stub。
//
//  本 stub 只做「放行 / 拦截」，不碰业务，也不读聊天数据：
//    - this == gYMNavParentPaintTarget（导航栏 owner 的 Qt 父对象，也就是铺满整窗的
//      那一个实例）→ 直接返回，跳过填充，让放在 QNSView 之后的 NSGlassEffectView 在
//      x0–60 透出；
//    - 其余实例（包括右侧面板里 x≥60 的同类 1016×688 实例）→ 跳到
//      gYMNavParentPaintTrampoline（原函数 16 字节 prologue + 跳回 原址+16），照常填充。
//
//  经被 patch 的入口 `ldr x16,#8; br x16` 进入，x0..x7 / q0..q7 和 lr 都保持原调用者
//  设定，本 stub 只用 x16（IP0，按 AAPCS 调用者可破坏）。target 为 0 时（尚未捕获
//  owner）因为 this 非空而不会命中，等价于全部放行。两个全局指针定义在
//  LiquidGlassNavigation.mm，安装时先就绪再写入口跳转，卸载时先还原入口再释放。

#if defined(__arm64__)

.text
.p2align 2
.globl _YMNavigationParentPaintDetour
_YMNavigationParentPaintDetour:
    .cfi_startproc
    .long 0xd503245f                                     // bti c：br x16 / blr x16 的落点（非 BTI 硬件为 NOP）
    adrp x16, _gYMNavParentPaintTarget@PAGE
    ldr  x16, [x16, _gYMNavParentPaintTarget@PAGEOFF]
    cmp  x0, x16
    b.eq Lym_nav_parent_skip
    adrp x16, _gYMNavParentPaintTrampoline@PAGE
    ldr  x16, [x16, _gYMNavParentPaintTrampoline@PAGEOFF]
    br   x16
Lym_nav_parent_skip:
    ret                                                  // 原方法返回 void；x0..x7 原样留给调用者
    .cfi_endproc

#endif  // __arm64__
