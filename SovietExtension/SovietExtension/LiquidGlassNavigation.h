//
//  LiquidGlassNavigation.h
//  SovietExtension
//
//  迷离模式 2.0 第一阶段：只给左侧主导航栏加一块系统 Liquid Glass。
//  其余区域保持不透明，不读取、不 Hook 任何 Qt 对象。
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// 实现在 LiquidGlassNavigation.mm（Objective-C++）。用 C 链接导出，供 C（MenuManager.m）
// 与 C++（ThemeHook.mm）两边调用，避免 C++ name mangling 造成的链接不一致。
#ifdef __cplusplus
extern "C" {
#endif

/// 偏好键，默认关闭。迷离模式打开时它不生效（迷离模式优先）。
extern NSString *const kThemeLiquidGlassNavigation;

/// 导航栏玻璃“强度”偏好键（double，0.0–1.0，默认 0）。公开 API 只有 tint / style，不能
/// 增强玻璃本身的折射；这里把强度映射到 NSGlassEffectView 的私有材质折射旋钮
/// (_contentLensing)，无着色。0 == 系统默认外观（跟随系统“外观 → 液态玻璃”）。
/// 私有接口带 respondsToSelector 守卫，macOS 升级后不可用则自动退化为 no-op。
extern NSString *const kThemeLiquidGlassNavigationIntensity;

/// 用户是否打开了“液态玻璃导航栏”。
BOOL YMLiquidGlassNavigationRequested(void);

/// 读取并钳制到 [0,1] 的玻璃强度。0 == 系统默认。
double YMLiquidGlassNavigationIntensity(void);

/// 目标身份是否已确认：WeChat 4.1.11 / 269079 / arm64、镜像 UUID、arm64 切片 SHA-256。
/// 第一次调用会在后台开始校验并返回 NO；校验完成后通过 ThemeHook 重新应用。
/// 只在主线程调用。
BOOL YMLiquidGlassNavigationIdentityVerified(void);

/// 窗口是否像主窗口（足够大，能容纳导航栏 + 会话列表 + 聊天区）。
BOOL YMLiquidGlassNavigationWindowEligible(NSWindow *window);

/// 按导航栏 owner 重新定位承载导航栏的主窗 QNSView（owner → 顶层 QWidget → winid），
/// 并更新缓存。导航栏玻璃只对这一个窗口做透明化；朋友圈 / 大图预览等其它窗口一律保持
/// 不透明。找不到（身份未通过、owner 尚未捕获、主窗重建中）时返回 nil。只在主线程调用。
NSView *_Nullable YMLiquidGlassNavigationResolveHostQNSView(void);

/// 最近一次定位的结果（缓存，弱引用），给 isOpaque 这类高频路径用。
NSView *_Nullable YMLiquidGlassNavigationHostQNSView(void);

/// 自上次调用以来主窗（QNSView 或其所在 NSWindow）是否换过；调用即清除标记。
BOOL YMLiquidGlassNavigationConsumeHostChange(void);

/// 找不到主窗时调用：外层父 widget 恢复自己的背景填充，导航栏回到微信原本的不透明外观，
/// 不会露出一条背后没有玻璃的透明导航栏。下次挂上玻璃时自动重新跳过。
void YMLiquidGlassNavigationSuspendFillSuppression(void);

/// 在 qnsView 之后放置或更新导航栏玻璃，以及覆盖其余区域的不透明背板；
/// 其它容器里残留的本模块 view 会一并移除。
void YMLiquidGlassNavigationAttach(NSView *container, NSView *qnsView);

/// 仅移除本窗口里由本模块插入的 view（玻璃 / 背板 / 背衬），**不**触碰全局
/// detour / 填充抑制状态。供「清理被跳过 / 其它窗口」这类按窗口的还原路径调用，
/// 避免一个无关窗口（朋友圈 / 大图预览）的 view churn 把主窗的全局玻璃拆掉。
void YMLiquidGlassNavigationRemoveViews(NSWindow *_Nullable window);

/// 移除所有窗口里本模块插入、但不在 keepContainer 里的 view（keepContainer 为 nil 时全部移除）。
void YMLiquidGlassNavigationRemoveStaleViews(NSView *_Nullable keepContainer);

/// 移除窗口里由本模块插入的所有 view。
void YMLiquidGlassNavigationDetach(NSWindow *_Nullable window);

#ifdef __cplusplus
}  // extern "C"
#endif

NS_ASSUME_NONNULL_END
