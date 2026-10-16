//
//  LiquidGlassNavigation.mm
//  SovietExtension
//
//  依据 analysis/liquid-glass-wechat-4.1.11/RUNTIME-EVIDENCE.md R3：4.1.11 主窗口的导航栏
//  固定在 QNSView 左侧 60 pt、全高，窗口宽 760–1400 pt 时都不变。
//
//  结构（都在 QNSView 之后，不接收鼠标事件）：
//    [NSGlassEffectView, Regular]  x 0–60      导航栏，Qt 的图标和文字仍画在它上面
//    [不透明背板]                   x 60–宽度   会话列表 / 聊天区，防止透明窗口露出桌面
//

#import "LiquidGlassNavigation.h"
#import "LiquidGlassIdentity.hpp"
#import "ThemeHook.h"

#import <dlfcn.h>
#import <libkern/OSCacheControl.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <mach/mach_vm.h>
#import <sys/mman.h>
#import <unistd.h>

#include <cstdint>
#include <cstring>
#include <string>

NSString *const kThemeLiquidGlassNavigation = @"kThemeLiquidGlassNavigation.SOVIET";
NSString *const kThemeLiquidGlassNavigationIntensity = @"kThemeLiquidGlassNavigationIntensity.SOVIET";

static NSString *const kYMNavigationGlassIdentifier = @"YMLiquidGlassNavigationGlass";
static NSString *const kYMNavigationBackplateIdentifier = @"YMLiquidGlassNavigationBackplate";
static NSString *const kYMNavigationBackdropIdentifier = @"YMLiquidGlassNavigationBackdrop";
static const CGFloat kYMNavigationRailWidth = 60.0;
static const CGFloat kYMEligibleMinWidth = 600.0;
static const CGFloat kYMEligibleMinHeight = 400.0;

#pragma mark - 偏好（玻璃强度）

BOOL YMLiquidGlassNavigationRequested(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kThemeLiquidGlassNavigation];
}

// 读取并钳制到 [0,1]：导航栏玻璃背后「中性灰渐变背衬」的强度（整体透明度）。玻璃在桌面
// 前方几乎没有可折射的内容，会显得很平；垫一层中性（无彩色）渐变给它折射，就有了玻璃
// 质感。0 == 不加背衬（纯透出桌面，整体仍跟随系统「外观 → 液态玻璃」设置）。
double YMLiquidGlassNavigationIntensity(void) {
    double value = [[NSUserDefaults standardUserDefaults] doubleForKey:kThemeLiquidGlassNavigationIntensity];
    if (value < 0.0) return 0.0;
    if (value > 1.0) return 1.0;
    return value;
}

#pragma mark - 视图

@interface YMNavigationGlassView : NSGlassEffectView
@end

@implementation YMNavigationGlassView
- (NSView *)hitTest:(NSPoint)point {
    return nil;
}
@end

// 放在玻璃「之后」的中性灰竖直渐变背衬：给玻璃内容去折射 → 明显的玻璃质感，但不带任何
// 彩色。整体透明度 = 强度偏好；0 时隐藏、纯透出桌面。随浅/深外观重画，不接收鼠标、非 AX。
@interface YMNavigationGlassBackdropView : NSView
@end

@implementation YMNavigationGlassBackdropView
- (BOOL)isOpaque {
    return NO;
}
- (NSView *)hitTest:(NSPoint)point {
    return nil;
}
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;  // 浅/深切换后重画渐变
}
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSString *match = [self.effectiveAppearance bestMatchFromAppearancesWithNames:@[
        NSAppearanceNameAqua, NSAppearanceNameDarkAqua
    ]];
    const BOOL dark = [match isEqualToString:NSAppearanceNameDarkAqua];
    // 纯中性灰（无色相）上亮下暗渐变；深色模式用更暗的一段。
    NSColor *top = dark ? [NSColor colorWithWhite:0.42 alpha:1.0] : [NSColor colorWithWhite:0.97 alpha:1.0];
    NSColor *bottom = dark ? [NSColor colorWithWhite:0.08 alpha:1.0] : [NSColor colorWithWhite:0.55 alpha:1.0];
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:top endingColor:bottom];
    [gradient drawInRect:self.bounds angle:-90.0];
}
@end

@interface YMNavigationBackplateView : NSView
@end

@implementation YMNavigationBackplateView
- (BOOL)isOpaque {
    return YES;
}
- (BOOL)wantsUpdateLayer {
    return YES;
}
- (void)updateLayer {
    // updateLayer 在当前 effectiveAppearance 下执行，语义色会跟随浅色 / 深色。
    self.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
}
- (NSView *)hitTest:(NSPoint)point {
    return nil;
}
@end

#pragma mark - 导航栏背景填充抑制（迷离模式 2.0 第一阶段，A 之步骤 2）

// 导航栏 widget 自己会画一层不透明背景，挡住放在 QNSView 之后的玻璃。它的背景色
// 走主 vtable 槽 0x1c8（slice VA 0x1ad4010）：读 this+0x16c（int 标志）否则
// this+0x128（QColor 源指针）；两者都为 0 时 getter 返回 0，paintEvent 里的填充
// 分支被跳过。这里按实例把这两个字段清零，并快照原值，关闭时还原。
//
// 只作用于身份校验通过的那一个 WeChat 4.1.11 / 269079 / arm64 进程，且在改写前再
// 校验 owner 的 vtable，命中不了就整体 no-op。owner 由侧边栏主 hook 捕获
// （SidebarManager，RUNTIME-EVIDENCE R6）。
//
// 注意：这一步单独并不能让玻璃可见——导航栏的父 widget（整窗）在 x0–60 仍会填充，
// 需要步骤 3 的 detour 处理（见本文件「外层父 widget 背景填充抑制」一节）。

// 由 LiquidGlassNavigationHook.S 的 detour stub 读取，必须是外部链接的 C 符号。
// gYMNavParentPaintTarget     ：要跳过填充的外层父实例（0 = 全部放行）。
// gYMNavParentPaintTrampoline ：原函数 16 字节 prologue + 跳回 原址+16。
// 安装顺序保证 patch 生效时两者都已就绪，卸载时先还原入口再清空。
extern "C" {
void *gYMNavParentPaintTarget = nullptr;
void *gYMNavParentPaintTrampoline = nullptr;
}

namespace {

using YMNavRailOwnerGetter = void *(*)(void);

// 运行时解析侧边栏导出的 owner 访问器（与 ThemeHook 解析 CGS 符号同一思路），
// 避免链接期依赖——独立单测里没链接 SidebarManager，解析不到就整体 no-op。
YMNavRailOwnerGetter YMNavRailResolveOwnerGetter(void) {
    static YMNavRailOwnerGetter getter =
        reinterpret_cast<YMNavRailOwnerGetter>(
            dlsym(RTLD_DEFAULT, "YMNavigationSidebarCapturedOwnerForLiquidGlass"));
    return getter;
}

constexpr std::uintptr_t kYMNavRailVtableSliceVA = 0x8b26bd0;
constexpr std::uintptr_t kYMNavRailFillFlagOffset = 0x16c;   // int
constexpr std::uintptr_t kYMNavRailFillColorOffset = 0x128;  // pointer

// 身份校验通过后，Contents/Resources/wechat.dylib 的加载基址与期望 vtable 运行时地址。
const void *gYMLiquidGlassImageHeader = nullptr;
std::uintptr_t gYMNavRailExpectedVtable = 0;

// 当前被抑制的 owner 及其原始字段值。
void *gYMNavRailSuppressedOwner = nullptr;
std::uint32_t gYMNavRailSavedFlag = 0;
std::uintptr_t gYMNavRailSavedColor = 0;

bool YMNavRailReadMemory(std::uintptr_t address, void *out, std::size_t length) {
    mach_vm_size_t got = 0;
    return mach_vm_read_overwrite(mach_task_self(),
                                  static_cast<mach_vm_address_t>(address),
                                  length,
                                  reinterpret_cast<mach_vm_address_t>(out),
                                  &got) == KERN_SUCCESS &&
           got == length;
}

bool YMNavRailWriteMemory(std::uintptr_t address, const void *in, std::size_t length) {
    const vm_size_t pageSize = static_cast<vm_size_t>(getpagesize());
    const vm_address_t pageStart =
        static_cast<vm_address_t>(address & ~(static_cast<std::uintptr_t>(pageSize) - 1));
    const std::uintptr_t end =
        (address + length + pageSize - 1) & ~(static_cast<std::uintptr_t>(pageSize) - 1);
    const vm_size_t span = static_cast<vm_size_t>(end - pageStart);
    if (vm_protect(mach_task_self(), pageStart, span, false,
                   VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) != KERN_SUCCESS) {
        return false;
    }
    std::memcpy(reinterpret_cast<void *>(address), in, length);
    return true;
}

// 读 owner 的 vtable 指针，确认它确实是导航栏 widget，再改写。
bool YMNavRailOwnerMatches(void *owner) {
    if (owner == nullptr || gYMNavRailExpectedVtable == 0) return false;
    std::uintptr_t vtable = 0;
    return YMNavRailReadMemory(reinterpret_cast<std::uintptr_t>(owner), &vtable,
                               sizeof(vtable)) &&
           vtable == gYMNavRailExpectedVtable;
}

void YMNavRailSuppressFill(void) {
    if (gYMNavRailExpectedVtable == 0) return;  // 身份未通过
    YMNavRailOwnerGetter getter = YMNavRailResolveOwnerGetter();
    if (getter == nullptr) return;  // 侧边栏访问器不可用
    void *owner = getter();
    if (owner == nullptr || owner == gYMNavRailSuppressedOwner) return;
    if (!YMNavRailOwnerMatches(owner)) return;

    const std::uintptr_t flagAddress =
        reinterpret_cast<std::uintptr_t>(owner) + kYMNavRailFillFlagOffset;
    const std::uintptr_t colorAddress =
        reinterpret_cast<std::uintptr_t>(owner) + kYMNavRailFillColorOffset;

    std::uint32_t flag = 0;
    std::uintptr_t color = 0;
    if (!YMNavRailReadMemory(flagAddress, &flag, sizeof(flag)) ||
        !YMNavRailReadMemory(colorAddress, &color, sizeof(color))) {
        return;
    }
    const std::uint32_t zeroFlag = 0;
    const std::uintptr_t zeroColor = 0;
    if (!YMNavRailWriteMemory(flagAddress, &zeroFlag, sizeof(zeroFlag)) ||
        !YMNavRailWriteMemory(colorAddress, &zeroColor, sizeof(zeroColor))) {
        // 尽量回滚已写入的字段。
        YMNavRailWriteMemory(flagAddress, &flag, sizeof(flag));
        return;
    }
    gYMNavRailSuppressedOwner = owner;
    gYMNavRailSavedFlag = flag;
    gYMNavRailSavedColor = color;
    NSLog(@"[YMLiquidGlass] nav rail fill suppressed");
}

void YMNavRailRestoreFill(void) {
    void *owner = gYMNavRailSuppressedOwner;
    if (owner == nullptr) return;
    if (YMNavRailOwnerMatches(owner)) {
        YMNavRailWriteMemory(
            reinterpret_cast<std::uintptr_t>(owner) + kYMNavRailFillFlagOffset,
            &gYMNavRailSavedFlag, sizeof(gYMNavRailSavedFlag));
        YMNavRailWriteMemory(
            reinterpret_cast<std::uintptr_t>(owner) + kYMNavRailFillColorOffset,
            &gYMNavRailSavedColor, sizeof(gYMNavRailSavedColor));
        NSLog(@"[YMLiquidGlass] nav rail fill restored");
    }
    gYMNavRailSuppressedOwner = nullptr;
    gYMNavRailSavedFlag = 0;
    gYMNavRailSavedColor = 0;
}

#pragma mark - 外层父 widget 背景填充抑制（A 之步骤 3，detour）

// 导航栏的直接父 widget（铺满整窗，vtable slice VA 0x8b272a8）会在 x0–60 填一层不透明
// 背景，挡住放在 QNSView 之后的玻璃。它的背景 paint 是该类虚表槽 56（偏移 0x1c0，
// slice VA 0xe658f4，返回 void，x0 = this QWidget），两条分支都用全局样式
// (_DAT_076cd358) 填充，没有按实例字段开关，所以步骤 2 的字段清零对它无效，必须用
// 函数入口 detour 按实例跳过。
//
// 外层父 = 导航栏 owner 的 Qt 父对象：QObject d_ptr(+0x8) → QObjectData parent(+0x10)
// （偏移见 analysis/.../runtime-probe/lg_probe.py，进程内已验证 OWNER_PARENT ==
// NAV_PARENT[2] == 整窗 0x8b272a8 实例；右侧面板里的同类 1016×688 实例从 x60 起，填充
// 本就在聊天区背后，不受影响）。
//
// detour stub 在 LiquidGlassNavigationHook.S，用 dlsym 解析以保持和独立单测解耦；身份
// 未通过、owner 不可得、父 vtable 不符、入口字节签名不符或 stub 不可用时整体 no-op
// （fail closed）。只在主线程（AppKit view hook 驱动的 attach / detach）安装与卸载，
// 与导航栏自身的 paint 同线程，无需挂起其他线程。

constexpr std::uintptr_t kYMNavParentVtableSliceVA = 0x8b272a8;  // 外层父 widget 类 vtable
constexpr std::uintptr_t kYMNavParentPaintSliceVA = 0xe658f4;    // 其背景 paint（虚表槽 56）
constexpr std::uintptr_t kYMQObjectDPtrOffset = 0x8;             // QObject::d_ptr
constexpr std::uintptr_t kYMQObjectDataParentOffset = 0x10;      // QObjectData::parent

// 入口 16 字节原始 prologue 签名（全是 sub sp / stp，位置无关，可整段搬进 trampoline）。
constexpr std::uint8_t kYMNavParentPaintPrologue[16] = {
    0xff, 0xc3, 0x07, 0xd1,  // sub  sp, sp, #0x1f0
    0xe9, 0x23, 0x1a, 0x6d,  // stp  d9, d8, [sp, #0x1a0]
    0xfc, 0x6f, 0x1b, 0xa9,  // stp  x28, x27, [sp, #0x1b0]
    0xf6, 0x57, 0x1c, 0xa9,  // stp  x22, x21, [sp, #0x1c0]
};

// 身份通过后填入（slice VA 以 0 为 image base，运行时地址 = 加载基址 + slice VA）。
std::uintptr_t gYMNavParentExpectedVtable = 0;
std::uintptr_t gYMNavParentPaintRuntime = 0;

// detour 安装状态。
bool gYMNavParentPatchInstalled = false;
std::uint8_t gYMNavParentSavedPrologue[16] = {0};
void *gYMNavParentTrampolineAlloc = nullptr;
std::size_t gYMNavParentTrampolineSize = 0;

using YMNavParentDetourFn = void (*)(void);

// 运行时解析汇编 detour stub（与 owner 访问器同一思路）；独立单测里没编 .S，解析不到
// 就不安装。
YMNavParentDetourFn YMNavParentResolveDetour(void) {
    static YMNavParentDetourFn fn = reinterpret_cast<YMNavParentDetourFn>(
        dlsym(RTLD_DEFAULT, "YMNavigationParentPaintDetour"));
    return fn;
}

// owner 的 Qt 父对象指针：*(*(owner+0x8)+0x10)。任何一步读失败或为空都返回 nullptr。
void *YMNavParentResolveOuterParent(void *owner) {
    if (owner == nullptr) return nullptr;
    std::uintptr_t dptr = 0;
    if (!YMNavRailReadMemory(reinterpret_cast<std::uintptr_t>(owner) + kYMQObjectDPtrOffset,
                             &dptr, sizeof(dptr)) ||
        dptr == 0) {
        return nullptr;
    }
    std::uintptr_t parent = 0;
    if (!YMNavRailReadMemory(dptr + kYMQObjectDataParentOffset, &parent, sizeof(parent)) ||
        parent == 0) {
        return nullptr;
    }
    return reinterpret_cast<void *>(parent);
}

// 确认对象首字（vptr）是期望的外层父 vtable。
bool YMNavParentVtableMatches(void *obj) {
    if (obj == nullptr || gYMNavParentExpectedVtable == 0) return false;
    std::uintptr_t vtable = 0;
    return YMNavRailReadMemory(reinterpret_cast<std::uintptr_t>(obj), &vtable, sizeof(vtable)) &&
           vtable == gYMNavParentExpectedVtable;
}

// 构造 16 字节绝对跳转：ldr x16,#8 / br x16 / .quad dest。
void YMNavParentEmitAbsoluteJump(std::uintptr_t dest, std::uint8_t out[16]) {
    const std::uint32_t insnLdrX16 = 0x58000050;  // ldr x16, #8
    const std::uint32_t insnBrX16 = 0xD61F0200;   // br  x16
    std::memcpy(out + 0, &insnLdrX16, sizeof(insnLdrX16));
    std::memcpy(out + 4, &insnBrX16, sizeof(insnBrX16));
    std::memcpy(out + 8, &dest, sizeof(dest));
}

// 向代码页写 16 字节：RW|COPY（复用 YMNavRailWriteMemory）→ 刷 icache → 还原 RX →
// 校验。对等于 RevokePatch 的 YMPatchARM64AbsoluteJump 的那段写入序列。
bool YMNavParentWriteCode(std::uintptr_t address, const std::uint8_t bytes[16]) {
    if (!YMNavRailWriteMemory(address, bytes, 16)) return false;
    sys_icache_invalidate(reinterpret_cast<void *>(address), 16);
    const vm_size_t pageSize = static_cast<vm_size_t>(getpagesize());
    const vm_address_t pageStart =
        static_cast<vm_address_t>(address & ~(static_cast<std::uintptr_t>(pageSize) - 1));
    const std::uintptr_t end =
        (address + 16 + pageSize - 1) & ~(static_cast<std::uintptr_t>(pageSize) - 1);
    vm_protect(mach_task_self(), pageStart, static_cast<vm_size_t>(end - pageStart), false,
               VM_PROT_READ | VM_PROT_EXECUTE);
    return std::memcmp(reinterpret_cast<const void *>(address), bytes, 16) == 0;
}

// 分配并写入 32 字节 trampoline（原 prologue + 跳回 原址+16），置为 RX。幂等。
bool YMNavParentBuildTrampoline(void) {
    if (gYMNavParentPaintTrampoline != nullptr) return true;
    std::uint8_t bytes[32];
    std::memcpy(bytes, gYMNavParentSavedPrologue, 16);
    YMNavParentEmitAbsoluteJump(gYMNavParentPaintRuntime + 16, bytes + 16);
    const std::size_t size = sizeof(bytes);
    void *alloc = mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (alloc == MAP_FAILED) return false;
    std::memcpy(alloc, bytes, size);
    if (mprotect(alloc, size, PROT_READ | PROT_EXEC) != 0 ||
        std::memcmp(alloc, bytes, size) != 0) {
        munmap(alloc, size);
        return false;
    }
    sys_icache_invalidate(alloc, size);
    gYMNavParentTrampolineAlloc = alloc;
    gYMNavParentTrampolineSize = size;
    gYMNavParentPaintTrampoline = alloc;
    return true;
}

void YMNavParentReleaseTrampoline(void) {
    if (gYMNavParentTrampolineAlloc != nullptr) {
        munmap(gYMNavParentTrampolineAlloc, gYMNavParentTrampolineSize);
        gYMNavParentTrampolineAlloc = nullptr;
        gYMNavParentTrampolineSize = 0;
    }
    gYMNavParentPaintTrampoline = nullptr;
}

void YMNavParentSuppressInstall(void) {
    if (gYMNavParentExpectedVtable == 0 || gYMNavParentPaintRuntime == 0) return;  // 身份未通过
    YMNavRailOwnerGetter getter = YMNavRailResolveOwnerGetter();
    if (getter == nullptr) return;
    void *owner = getter();
    if (!YMNavRailOwnerMatches(owner)) return;          // owner 必须是导航栏 widget
    void *parent = YMNavParentResolveOuterParent(owner);
    if (!YMNavParentVtableMatches(parent)) return;      // 父必须是期望的外层父类

    // 已安装：owner / 窗口可能已更换，只刷新目标实例指针即可。
    if (gYMNavParentPatchInstalled) {
        gYMNavParentPaintTarget = parent;
        return;
    }

    YMNavParentDetourFn detour = YMNavParentResolveDetour();
    if (detour == nullptr) return;                      // stub 不可用（独立单测）

    // 入口 16 字节必须与已知 prologue 签名一致（防版本漂移 / 已被二次 hook）。
    std::uint8_t live[16];
    if (!YMNavRailReadMemory(gYMNavParentPaintRuntime, live, sizeof(live)) ||
        std::memcmp(live, kYMNavParentPaintPrologue, sizeof(live)) != 0) {
        return;
    }
    std::memcpy(gYMNavParentSavedPrologue, live, sizeof(live));

    if (!YMNavParentBuildTrampoline()) return;

    // 先把 target 设好（trampoline 已就绪），再写入口跳转；patch 一旦生效，stub 读到
    // 的两个指针都有效。
    gYMNavParentPaintTarget = parent;

    std::uint8_t jump[16];
    YMNavParentEmitAbsoluteJump(reinterpret_cast<std::uintptr_t>(detour), jump);
    if (!YMNavParentWriteCode(gYMNavParentPaintRuntime, jump)) {
        gYMNavParentPaintTarget = nullptr;
        YMNavParentReleaseTrampoline();
        return;
    }
    gYMNavParentPatchInstalled = true;
    NSLog(@"[YMLiquidGlass] nav parent fill detour installed");
}

void YMNavParentSuppressRemove(void) {
    // 先还原入口字节（停用 detour），再释放 trampoline；与 paint 同在主线程，无在途调用。
    if (gYMNavParentPatchInstalled && gYMNavParentPaintRuntime != 0) {
        YMNavParentWriteCode(gYMNavParentPaintRuntime, gYMNavParentSavedPrologue);
        NSLog(@"[YMLiquidGlass] nav parent fill detour removed");
    }
    gYMNavParentPatchInstalled = false;
    gYMNavParentPaintTarget = nullptr;
    YMNavParentReleaseTrampoline();
}

}  // namespace

#pragma mark - 身份校验

typedef NS_ENUM(NSInteger, YMLiquidGlassIdentityState) {
    YMLiquidGlassIdentityUnknown,
    YMLiquidGlassIdentityPending,
    YMLiquidGlassIdentityVerified,
    YMLiquidGlassIdentityRejected,
};

static YMLiquidGlassIdentityState gYMLiquidGlassIdentityState = YMLiquidGlassIdentityUnknown;

static void YMLiquidGlassFinishIdentity(BOOL verified, NSString *reason) {
    gYMLiquidGlassIdentityState =
        verified ? YMLiquidGlassIdentityVerified : YMLiquidGlassIdentityRejected;
    NSLog(@"[YMLiquidGlass] identity %@%@", verified ? @"verified" : @"rejected: ",
          verified ? @"" : reason);
    if (verified && gYMLiquidGlassImageHeader != nullptr) {
        // 保存项目 image base 为 0，运行时地址 = 加载基址 + slice VA。
        const std::uintptr_t base = reinterpret_cast<std::uintptr_t>(gYMLiquidGlassImageHeader);
        gYMNavRailExpectedVtable = base + kYMNavRailVtableSliceVA;
        gYMNavParentExpectedVtable = base + kYMNavParentVtableSliceVA;
        gYMNavParentPaintRuntime = base + kYMNavParentPaintSliceVA;
    }
    if (verified) {
        [ThemeHook refreshAllQNSViews];
    }
}

static void YMLiquidGlassBeginIdentityCheck(void) {
#if !defined(__arm64__)
    YMLiquidGlassFinishIdentity(NO, @"not arm64");
    return;
#else
    namespace lg = ym::liquid_glass;
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@(lg::kBundleIdentifier)] ||
        ![info[@"CFBundleShortVersionString"] isEqualToString:@(lg::kShortVersion)] ||
        ![info[@"CFBundleVersion"] isEqualToString:@(lg::kBuildVersion)]) {
        YMLiquidGlassFinishIdentity(NO, @"bundle / version / build mismatch");
        return;
    }

    NSString *expectedPath =
        [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/Resources/wechat.dylib"];
    const mach_header_64 *header = nullptr;
    NSUInteger matches = 0;
    for (uint32_t index = 0; index < _dyld_image_count(); ++index) {
        const char *name = _dyld_get_image_name(index);
        if (name != nullptr && [@(name) isEqualToString:expectedPath]) {
            header = reinterpret_cast<const mach_header_64 *>(_dyld_get_image_header(index));
            ++matches;
        }
    }
    lg::UUID uuid{};
    if (matches != 1 || !lg::LoadedImageUUID(header, uuid) || uuid != lg::kArm64SliceUUID) {
        YMLiquidGlassFinishIdentity(NO, @"loaded image / UUID mismatch");
        return;
    }
    gYMLiquidGlassImageHeader = header;

    std::string path = expectedPath.fileSystemRepresentation;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        lg::Digest digest{};
        const BOOL ok = lg::Arm64SliceDigest(path.c_str(), digest) &&
                        digest == lg::kArm64SliceSHA256;
        dispatch_async(dispatch_get_main_queue(), ^{
            YMLiquidGlassFinishIdentity(ok, @"arm64 slice SHA-256 mismatch");
        });
    });
#endif
}

BOOL YMLiquidGlassNavigationIdentityVerified(void) {
    if (gYMLiquidGlassIdentityState == YMLiquidGlassIdentityUnknown && NSThread.isMainThread) {
        gYMLiquidGlassIdentityState = YMLiquidGlassIdentityPending;
        YMLiquidGlassBeginIdentityCheck();
    }
    return gYMLiquidGlassIdentityState == YMLiquidGlassIdentityVerified;
}

#pragma mark - 视图管理

BOOL YMLiquidGlassNavigationWindowEligible(NSWindow *window) {
    if (!window || window.parentWindow || window.isSheet) return NO;
    NSRect frame = window.frame;
    return NSWidth(frame) >= kYMEligibleMinWidth && NSHeight(frame) >= kYMEligibleMinHeight;
}

static NSView *YMLiquidGlassFindDirectSubview(NSView *container, NSString *identifier) {
    for (NSView *subview in container.subviews) {
        if ([subview.identifier isEqualToString:identifier]) return subview;
    }
    return nil;
}

// 外层父 detour 首次安装成功的那一次，锁定承载导航栏 owner 的主窗 QNSView。导航栏玻璃
// 只对这个窗口透明化，其它窗口（朋友圈、大图预览…）不碰。弱引用，窗口销毁即自动置空。
static __weak NSView *gYMNavGlassMainQNSView = nil;

NSView *YMLiquidGlassNavigationMainQNSView(void) {
    return gYMNavGlassMainQNSView;
}

void YMLiquidGlassNavigationAttach(NSView *container, NSView *qnsView) {
    if (!container || !qnsView || qnsView.superview != container) return;

    NSRect q = qnsView.frame;
    CGFloat railWidth = MIN(kYMNavigationRailWidth, NSWidth(q));
    NSRect railRect = NSMakeRect(NSMinX(q), NSMinY(q), railWidth, NSHeight(q));
    NSRect restRect = NSMakeRect(NSMinX(q) + railWidth, NSMinY(q), NSWidth(q) - railWidth, NSHeight(q));

    NSView *backplate = YMLiquidGlassFindDirectSubview(container, kYMNavigationBackplateIdentifier);
    if (!backplate) {
        backplate = [[YMNavigationBackplateView alloc] initWithFrame:restRect];
        backplate.wantsLayer = YES;
        backplate.identifier = kYMNavigationBackplateIdentifier;
        backplate.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        backplate.accessibilityElement = NO;
        [container addSubview:backplate positioned:NSWindowBelow relativeTo:qnsView];
    }
    backplate.frame = restRect;

    NSView *glass = YMLiquidGlassFindDirectSubview(container, kYMNavigationGlassIdentifier);
    if (!glass) {
        YMNavigationGlassView *view = [[YMNavigationGlassView alloc] initWithFrame:railRect];
        view.style = NSGlassEffectViewStyleRegular;
        view.cornerRadius = 0;
        view.identifier = kYMNavigationGlassIdentifier;
        view.autoresizingMask = NSViewHeightSizable | NSViewMaxXMargin;
        view.accessibilityElement = NO;
        [container addSubview:view positioned:NSWindowBelow relativeTo:qnsView];
        glass = view;
        NSLog(@"[YMLiquidGlass] navigation glass attached");
    }
    glass.frame = railRect;

    // 在玻璃「之后」垫一层中性灰渐变背衬，给玻璃内容去折射（强度 = 偏好；0 则隐藏，纯透出
    // 桌面）。拖动设置里的「玻璃强度」滑块 → refreshAllQNSViews → 这里，实现实时预览。
    NSView *backdrop = YMLiquidGlassFindDirectSubview(container, kYMNavigationBackdropIdentifier);
    if (!backdrop) {
        backdrop = [[YMNavigationGlassBackdropView alloc] initWithFrame:railRect];
        backdrop.identifier = kYMNavigationBackdropIdentifier;
        backdrop.autoresizingMask = NSViewHeightSizable | NSViewMaxXMargin;
        backdrop.accessibilityElement = NO;
        [container addSubview:backdrop positioned:NSWindowBelow relativeTo:glass];
    }
    backdrop.frame = railRect;
    const double intensity = YMLiquidGlassNavigationIntensity();  // 0..1
    backdrop.alphaValue = intensity;
    backdrop.hidden = intensity <= 0.0;

    // 去掉导航栏自身的不透明背景填充（按实例、可逆、身份 + vtable 门控）。
    YMNavRailSuppressFill();
    // 再让外层父 widget 在 x0–60 跳过填充（入口 detour，身份 + 父 vtable + 字节签名门控）。
    const bool parentWasInstalled = gYMNavParentPatchInstalled;
    YMNavParentSuppressInstall();
    // detour 由「未安装」变「已安装」的唯一那次，正是启动时带导航栏 owner 的主窗（此
    // 刻朋友圈等窗口还不存在）。锁定它的 QNSView，之后只有这个窗口会被透明化。
    if (!parentWasInstalled && gYMNavParentPatchInstalled) {
        gYMNavGlassMainQNSView = qnsView;
        NSLog(@"[YMLiquidGlass] main window pinned (qnsView=%@ window=%@)",
              qnsView, qnsView.window);
    }
}

static void YMLiquidGlassRemoveInTree(NSView *view) {
    for (NSView *subview in [view.subviews copy]) {
        if ([subview.identifier isEqualToString:kYMNavigationGlassIdentifier] ||
            [subview.identifier isEqualToString:kYMNavigationBackplateIdentifier] ||
            [subview.identifier isEqualToString:kYMNavigationBackdropIdentifier]) {
            [subview removeFromSuperview];
            continue;
        }
        YMLiquidGlassRemoveInTree(subview);
    }
}

void YMLiquidGlassNavigationRemoveViews(NSWindow *window) {
    // 只移除本窗口里本模块插入的 view，不动任何全局状态。
    NSView *root = window.contentView.superview ?: window.contentView;
    if (root) YMLiquidGlassRemoveInTree(root);
}

void YMLiquidGlassNavigationDetach(NSWindow *window) {
    // 全局拆除：卸载外层父 detour（恢复入口字节）+ 还原导航栏自身背景字段 +
    // 解除主窗锁定，再移除本模块插入的 view。**只应在功能真正关闭时调用**（迷离 /
    // 导航栏玻璃都不再改写）。「清理其它 / 被跳过窗口」只调用 YMLiquidGlassNavigationRemoveViews，
    // 绝不走这里——否则一个无关窗口的 view churn 会把主窗的全局玻璃拆掉（朋友圈点图变
    // 空白的根因）。即使没有 window 也要全部还原。
    YMNavParentSuppressRemove();
    YMNavRailRestoreFill();
    gYMNavGlassMainQNSView = nil;
    YMLiquidGlassNavigationRemoveViews(window);
}
