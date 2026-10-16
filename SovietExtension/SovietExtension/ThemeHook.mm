//  ThemeHook.m
//  SovietExtension
//
//  Created by MustangYM on 2026/6/20.
//

#import "ThemeHook.h"
#import "StartupPermission.h"

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <math.h>
#import "RevokePatch.h"
#import "MistyModeSettingsWindowController.h"
#import "YMColorfulBlurBackgroundView.h"
#import "LiquidGlassNavigation.h"

#pragma mark - 默认值
static const BOOL kYMDefaultMistyModeEnabled = NO;
static const CGFloat kYMDefaultQNSViewAlphaValue = 0.90f;
static const BOOL kYMDefaultWindowBackgroundBlurEnabled = YES;
static const int kYMDefaultWindowBackgroundBlurRadius = 10;

//手动调试出来这个效果
static const CGFloat kYMCarrierAlphaDark = 0.30f;
static const CGFloat kYMCarrierAlphaLight = 0.015f;

static const NSTimeInterval kYMBlurKeepAliveInterval = 2.0;

/// 流光氛围默认参数。
/// ColorfulOpacity 的深色/浅色现在统一使用一个值。
static const CGFloat kYMDefaultColorfulOpacity = 0.42f;
static const CGFloat kYMDefaultColorfulInternalBlurRadius = 70.0f;
static const CGFloat kYMMinColorfulInternalBlurRadius = 40.0f;
static const CGFloat kYMMaxColorfulInternalBlurRadius = 160.0f;
static const NSTimeInterval kYMDefaultColorfulAnimationDuration = 10.0;

#pragma mark - 私有 CGS 接口声明

/// 这里不直接链接私有符号，而是运行时 dlsym，避免链接阶段报错。
typedef int YMCGSConnectionID;
typedef int YMCGSWindowID;
typedef int (*YMCGSMainConnectionIDFunc)(void);
typedef CGError (*YMCGSSetWindowBackgroundBlurRadiusFunc)(YMCGSConnectionID cid,
                                                          YMCGSWindowID wid,
                                                          int radius);

static YMCGSMainConnectionIDFunc gYMCGSMainConnectionID = NULL;
static YMCGSSetWindowBackgroundBlurRadiusFunc gYMCGSSetWindowBackgroundBlurRadius = NULL;
static BOOL gYMCGSBlurResolved = NO;
static BOOL gYMCGSBlurResolveFailedLogged = NO;

#pragma mark - 原始 IMP

typedef BOOL (*YMIsOpaqueIMP)(id self, SEL _cmd);
typedef void (*YMVoidIMP)(id self, SEL _cmd);
typedef void (*YMOneObjectIMP)(id self, SEL _cmd, id arg);

static YMIsOpaqueIMP gOrig_QNSView_isOpaque = NULL;
static YMVoidIMP gOrig_QNSView_viewDidMoveToWindow = NULL;
static YMVoidIMP gOrig_QNSView_viewDidMoveToSuperview = NULL;
static YMOneObjectIMP gOrig_QNSView_setLayer = NULL;

#pragma mark - 状态

static BOOL gYMStarted = NO;
static BOOL gYMQNSViewHookInstalled = NO;
static NSTimer *gYMBlurKeepAliveTimer = nil;
static NSHashTable *gYMModifiedThemeObjects;
static char kYMOriginalThemeStateKey;
static void YMRestoreThemeObject(id object);

/// 防止处理背景过程中触发 setLayer / view move 后递归。
static BOOL gYMApplyingBlurBackground = NO;

/// 用于记录窗口上一次应用的 blur radius，避免重复刷日志。
static char kYMAppliedBlurRadiusAssociatedKey;
static char kYMAppliedBlurWindowNumberAssociatedKey;

#pragma mark - 配置读取

static void YMRegisterMistyThemeDefaults(void) {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kThemeMistyMode: @(kYMDefaultMistyModeEnabled),
        kThemeMistyQNSAlpha: @(kYMDefaultQNSViewAlphaValue),
        kThemeMistyWindowBlurEnabled: @(kYMDefaultWindowBackgroundBlurEnabled),
        kThemeMistyWindowBlurRadius: @(kYMDefaultWindowBackgroundBlurRadius),
        kThemeMistyColorful: @(NO),
        kThemeMistyColorfulOpacity: @(kYMDefaultColorfulOpacity),
        kThemeMistyColorfulBlurRadius: @(kYMDefaultColorfulInternalBlurRadius),
        kThemeMistyColorfulAnimationDuration: @(kYMDefaultColorfulAnimationDuration),
    }];
}

static BOOL YMBoolSetting(NSString *key, BOOL defaultValue) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:key] == nil) {
        return defaultValue;
    }
    return [defaults boolForKey:key];
}

static CGFloat YMFloatSetting(NSString *key, CGFloat defaultValue) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:key] == nil) {
        return defaultValue;
    }
    return (CGFloat)[defaults doubleForKey:key];
}

static NSInteger YMIntegerSetting(NSString *key, NSInteger defaultValue) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:key] == nil) {
        return defaultValue;
    }
    return [defaults integerForKey:key];
}

#pragma mark - 系统辅助功能偏好

/// 降低透明度 / 提高对比度时暂停整窗透明，减少动态效果时停用流光动画。
/// 用户的迷离模式开关保持不变，系统偏好恢复后自动重新应用。
static BOOL gYMAccessibilitySuppressesMisty = NO;
static BOOL gYMAccessibilityReduceMotion = NO;
static id gYMAccessibilityObserver = nil;

static void YMReadAccessibilityDisplayOptions(void) {
    NSWorkspace *workspace = NSWorkspace.sharedWorkspace;
    gYMAccessibilitySuppressesMisty = workspace.accessibilityDisplayShouldReduceTransparency ||
                                      workspace.accessibilityDisplayShouldIncreaseContrast;
    gYMAccessibilityReduceMotion = workspace.accessibilityDisplayShouldReduceMotion;
}

static BOOL YMMistyModeEnabled(void) {
    if (gYMAccessibilitySuppressesMisty) return NO;
    return YMBoolSetting(kThemeMistyMode, kYMDefaultMistyModeEnabled);
}

/// 液态玻璃导航栏（2.0 第一阶段）：迷离模式优先，系统要求不透明时同样暂停。
static BOOL YMNavigationGlassModeEnabled(void) {
    if (gYMAccessibilitySuppressesMisty) return NO;
    if (YMBoolSetting(kThemeMistyMode, kYMDefaultMistyModeEnabled)) return NO;
    if (!YMLiquidGlassNavigationRequested()) return NO;
    return YMLiquidGlassNavigationIdentityVerified();
}

/// 任一模式需要改写窗口 / QNSView 时为 YES。
static BOOL YMThemeEffectEnabled(void) {
    return YMMistyModeEnabled() || YMNavigationGlassModeEnabled();
}

static BOOL YMWindowBackgroundBlurEnabled(void) {
    if (!YMMistyModeEnabled()) return NO;
    return YMBoolSetting(kThemeMistyWindowBlurEnabled, kYMDefaultWindowBackgroundBlurEnabled);
}

static CGFloat YMQNSViewAlphaValue(void) {
    if (!YMMistyModeEnabled()) {
        return 1.0f;
    }

    CGFloat alpha = YMFloatSetting(kThemeMistyQNSAlpha, kYMDefaultQNSViewAlphaValue);
    alpha = MAX(0.20f, MIN(1.0f, alpha));
    return alpha;
}

static int YMWindowBackgroundBlurRadius(void) {
    if (!YMWindowBackgroundBlurEnabled()) {
        return 0;
    }

    NSInteger radius = YMIntegerSetting(kThemeMistyWindowBlurRadius, kYMDefaultWindowBackgroundBlurRadius);
    radius = MAX(0, MIN(100, radius));
    return (int)radius;
}

static BOOL YMIsAppearanceDark(NSAppearance *appearance) {
    if (!appearance) {
        appearance = NSApp.effectiveAppearance ?: NSAppearance.currentAppearance;
    }

    NSString *bestMatch = [appearance bestMatchFromAppearancesWithNames:@[
        NSAppearanceNameAqua,
        NSAppearanceNameDarkAqua
    ]];

    return [bestMatch isEqualToString:NSAppearanceNameDarkAqua];
}

BOOL YMCarrierStyleIsDark(void) {
    // 自动跟随当前微信 / AppKit 的有效外观，不再依赖手动“深色 / 浅色”配置。
    if (![NSThread isMainThread]) {
        __block BOOL dark = YES;
        dispatch_sync(dispatch_get_main_queue(), ^{
            dark = YMCarrierStyleIsDark();
        });
        return dark;
    }

    NSWindow *keyWindow = NSApp.keyWindow;
    if (keyWindow) {
        return YMIsAppearanceDark(keyWindow.effectiveAppearance);
    }

    NSWindow *mainWindow = NSApp.mainWindow;
    if (mainWindow) {
        return YMIsAppearanceDark(mainWindow.effectiveAppearance);
    }

    return YMIsAppearanceDark(NSApp.effectiveAppearance);
}

static CGFloat YMWindowBlurCarrierAlpha(void) {
    if (!YMWindowBackgroundBlurEnabled() || YMWindowBackgroundBlurRadius() <= 0) {
        return 0.0f;
    }

    return YMCarrierStyleIsDark() ? kYMCarrierAlphaDark : kYMCarrierAlphaLight;
}

#pragma mark - Colorful 风格动态渐变背景

BOOL YMColorfulBlurBackgroundEnabled(void) {
    if (!YMMistyModeEnabled()) return NO;
    if (gYMAccessibilityReduceMotion) return NO;
    if (!YMBoolSetting(kThemeMistyColorful, NO)) return NO;
    if (!YMWindowBackgroundBlurEnabled()) return NO;
    if (YMWindowBackgroundBlurRadius() <= 0) return NO;
    return YES;
}

CGFloat YMColorfulBlurBackgroundOpacity(void) {
    CGFloat opacity = YMFloatSetting(kThemeMistyColorfulOpacity, kYMDefaultColorfulOpacity);
    return MAX(0.0f, MIN(1.0f, opacity));
}

CGFloat YMColorfulBlurInternalBlurRadius(void) {
    CGFloat radius = YMFloatSetting(kThemeMistyColorfulBlurRadius, kYMDefaultColorfulInternalBlurRadius);
    return MAX(kYMMinColorfulInternalBlurRadius, MIN(kYMMaxColorfulInternalBlurRadius, radius));
}

NSTimeInterval YMColorfulAnimationDuration(void) {
    CGFloat duration = YMFloatSetting(kThemeMistyColorfulAnimationDuration, kYMDefaultColorfulAnimationDuration);
    return MAX(2.0f, MIN(60.0f, duration));
}

static YMColorfulBlurBackgroundView *YMFindColorfulBlurBackgroundViewInContainer(NSView *container) {
    if (!container) return nil;

    for (NSView *subview in container.subviews) {
        if ([subview.identifier isEqualToString:kYMColorfulBlurBackgroundViewIdentifier] &&
            [subview isKindOfClass:[YMColorfulBlurBackgroundView class]]) {
            return (YMColorfulBlurBackgroundView *)subview;
        }
    }

    return nil;
}

static void YMEnsureColorfulBlurBackgroundInContainer(NSView *container, NSView *qnsView) {
    if (!container || !qnsView) return;

    //过滤掉鼠标放到输入框右上角会开启狂暴模式彩蛋,哈哈哈
    if ([container.description containsString:@"FramelessMainWindowClassWindow"]) {
        return;
    }
    
    YMColorfulBlurBackgroundView *colorfulView = YMFindColorfulBlurBackgroundViewInContainer(container);

    if (!YMColorfulBlurBackgroundEnabled()) {
        if (colorfulView) {
            [colorfulView removeFromSuperview];
        }
        return;
    }

    if (!colorfulView) {
        colorfulView = [[YMColorfulBlurBackgroundView alloc] initWithFrame:container.bounds];
        [container addSubview:colorfulView positioned:NSWindowBelow relativeTo:qnsView];
        YMLog(@"已插入 Colorful 动态渐变背景 view：%@", colorfulView);
    } else {
        colorfulView.frame = container.bounds;
        if (colorfulView.superview != container) {
            [colorfulView removeFromSuperview];
            [container addSubview:colorfulView positioned:NSWindowBelow relativeTo:qnsView];
        } else {
            [container addSubview:colorfulView positioned:NSWindowBelow relativeTo:qnsView];
        }
    }

    [colorfulView ym_updateColorfulBackgroundIfNeeded];
}

#pragma mark - 工具：判断 QNSView

static BOOL YMIsQNSView(NSView *view) {
    if (!view) return NO;

    Class qnsClass = NSClassFromString(@"QNSView");
    if (!qnsClass) return NO;

    return [view isKindOfClass:qnsClass];
}

static void YMRestoreQNSViewForSkippedWindow(NSView *view) {
    YMRestoreThemeObject(view.layer);
    YMRestoreThemeObject(view);
}

static void YMRemoveColorfulBlurBackgroundViewsInTree(NSView *view) {
    if (!view) return;

    NSArray<NSView *> *subviews = [view.subviews copy];
    for (NSView *subview in subviews) {
        if ([subview.identifier isEqualToString:kYMColorfulBlurBackgroundViewIdentifier]) {
            [subview removeFromSuperview];
            continue;
        }

        YMRemoveColorfulBlurBackgroundViewsInTree(subview);
    }
}

static void YMRestoreQNSViewsForSkippedWindowInTree(NSView *view) {
    if (!view) return;

    YMRestoreQNSViewForSkippedWindow(view);

    NSArray<NSView *> *subviews = [view.subviews copy];
    for (NSView *subview in subviews) {
        YMRestoreQNSViewsForSkippedWindowInTree(subview);
    }
}

static void YMCleanupMistyArtifactsForSkippedWindow(NSWindow *window) {
    if (!window) return;

    YMRemoveColorfulBlurBackgroundViewsInTree(window.contentView);
    // 被跳过窗口清理：只移除它自己的 view，不得拆主窗的全局玻璃。
    YMLiquidGlassNavigationRemoveViews(window);
    YMRestoreQNSViewsForSkippedWindowInTree(window.contentView);
    YMRestoreThemeObject(window);
}


#pragma mark - 工具：窗口过滤

static BOOL YMTextContainsAnyKeyword(NSString *text, NSArray<NSString *> *keywords) {
    if (text.length == 0 || keywords.count == 0) {
        return NO;
    }

    for (NSString *keyword in keywords) {
        if (keyword.length == 0) {
            continue;
        }

        if ([text rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }

    return NO;
}

static NSString *YMWindowInspectionText(NSWindow *window) {
    if (!window) {
        return @"";
    }

    NSMutableString *text = [NSMutableString string];

    NSString *className = NSStringFromClass(window.class);
    if (className.length > 0) {
        [text appendFormat:@"%@ ", className];
    }

    if (window.title.length > 0) {
        [text appendFormat:@"%@ ", window.title];
    }

    // QNSWindow 的 description 里会带出 Qt 的 QWidgetWindow name，
    // 例如：name="PreviewWindow_xxxWindow"。这是过滤图片预览窗口最稳定的特征。
    NSString *windowDescription = window.description;
    if (windowDescription.length > 0) {
        [text appendFormat:@"%@ ", windowDescription];
    }

    NSString *contentViewDescription = window.contentView.description;
    if (contentViewDescription.length > 0) {
        [text appendFormat:@"%@ ", contentViewDescription];
    }

    return text;
}

static BOOL YMShouldSkipMistyEffectForWindow(NSWindow *window) {
    if (!window) {
        return YES;
    }

    NSString *className = NSStringFromClass(window.class);
    NSArray<NSString *> *blockedKeywords = @[
        @"Status",
        @"Menu",
        @"Popover",
        @"Tooltip",
        @"TouchBar",
        @"QNSPanel"
    ];
    
    for (NSString *keyword in blockedKeywords) {
        if ([className rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }

    NSString *inspectionText = YMWindowInspectionText(window);
    NSArray<NSString *> *blockedQtWindowNameKeywords = @[
        // 聊天图片预览窗口
        @"PreviewWindow",
        //个人资料
        @"ProfileUniquePopClassWindow",
        //表情包
        @"EmoticonPopoverWindow",
    ];

    if (YMTextContainsAnyKeyword(inspectionText, blockedQtWindowNameKeywords)) {
        return YES;
    }

    // AppKit 的菜单 / 状态栏相关窗口常见窗口层级。
    // 不用“非 NSNormalWindowLevel 一律跳过”，因为微信登录窗口在某些状态下可能不是普通 level。
    NSInteger level = window.level;
    if (level == NSMainMenuWindowLevel ||
        level == NSStatusWindowLevel ||
        level == NSPopUpMenuWindowLevel) {
        return YES;
    }

    NSRect frame = window.frame;

    // 顶部状态栏图标、菜单承载窗口一般非常小。
    // 这里阈值故意放低，避免把微信登录窗口误判掉。
    if (frame.size.width < 220.0 || frame.size.height < 120.0) {
        return YES;
    }

    // 导航栏玻璃只用于主窗口大小的窗口，而且只用于承载导航栏 owner 的那一个主窗。
    if (!YMMistyModeEnabled()) {
        if (!YMLiquidGlassNavigationWindowEligible(window)) {
            return YES;
        }
        // 朋友圈 / 大图预览等其它顶层窗口一旦被透明化就会透穿成空白（回归：点开朋友圈
        // 图片后主窗全白），所以这里把它们全部跳过、保持不透明。主窗在外层父 detour 首次
        // 安装时锁定；未锁定前（启动早期）放行，让主窗能被处理并完成锁定。
        NSView *mainQNS = YMLiquidGlassNavigationMainQNSView();
        if (mainQNS && mainQNS.window && mainQNS.window != window) {
            return YES;
        }
    }

    return NO;
}

static BOOL YMShouldApplyMistyEffectForWindow(NSWindow *window) {
    return !YMShouldSkipMistyEffectForWindow(window);
}

#pragma mark - 工具：CGS 背景模糊

static BOOL YMResolveCGSBlurSymbolsIfNeeded(void) {
    if (gYMCGSBlurResolved) {
        return gYMCGSMainConnectionID && gYMCGSSetWindowBackgroundBlurRadius;
    }

    gYMCGSBlurResolved = YES;

    // 通常这两个符号可以从当前进程已经加载的 CoreGraphics / ApplicationServices 里找到。
    gYMCGSMainConnectionID = (YMCGSMainConnectionIDFunc)dlsym(RTLD_DEFAULT, "CGSMainConnectionID");
    gYMCGSSetWindowBackgroundBlurRadius = (YMCGSSetWindowBackgroundBlurRadiusFunc)dlsym(RTLD_DEFAULT, "CGSSetWindowBackgroundBlurRadius");

    if (!gYMCGSMainConnectionID || !gYMCGSSetWindowBackgroundBlurRadius) {
        void *handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY);
        if (handle) {
            if (!gYMCGSMainConnectionID) {
                gYMCGSMainConnectionID = (YMCGSMainConnectionIDFunc)dlsym(handle, "CGSMainConnectionID");
            }
            if (!gYMCGSSetWindowBackgroundBlurRadius) {
                gYMCGSSetWindowBackgroundBlurRadius = (YMCGSSetWindowBackgroundBlurRadiusFunc)dlsym(handle, "CGSSetWindowBackgroundBlurRadius");
            }
        }
    }

    if (!gYMCGSMainConnectionID || !gYMCGSSetWindowBackgroundBlurRadius) {
        void *handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY);
        if (handle) {
            if (!gYMCGSMainConnectionID) {
                gYMCGSMainConnectionID = (YMCGSMainConnectionIDFunc)dlsym(handle, "CGSMainConnectionID");
            }
            if (!gYMCGSSetWindowBackgroundBlurRadius) {
                gYMCGSSetWindowBackgroundBlurRadius = (YMCGSSetWindowBackgroundBlurRadiusFunc)dlsym(handle, "CGSSetWindowBackgroundBlurRadius");
            }
        }
    }

    BOOL ok = gYMCGSMainConnectionID && gYMCGSSetWindowBackgroundBlurRadius;
    if (!ok && !gYMCGSBlurResolveFailedLogged) {
        gYMCGSBlurResolveFailedLogged = YES;
        YMLog(@"CGS 背景模糊接口解析失败，当前系统可能不可用：CGSMainConnectionID=%p CGSSetWindowBackgroundBlurRadius=%p",
              gYMCGSMainConnectionID,
              gYMCGSSetWindowBackgroundBlurRadius);
    }

    return ok;
}

static void YMApplyWindowBackgroundBlur(NSWindow *window, int radius) {
    if (!window) return;

    NSInteger windowNumber = window.windowNumber;
    if (windowNumber <= 0) {
        // windowNumber 为 0 通常说明窗口还没真正进入 WindowServer，稍后 refresh 会再应用。
        return;
    }

    // 如果 radius 为 0，也要调用一次 CGS，把旧 blur 关掉。
    if (!YMResolveCGSBlurSymbolsIfNeeded()) {
        return;
    }

    NSNumber *oldRadius = objc_getAssociatedObject(window, &kYMAppliedBlurRadiusAssociatedKey);
    NSNumber *oldWindowNumber = objc_getAssociatedObject(window, &kYMAppliedBlurWindowNumberAssociatedKey);
    if (oldRadius && oldWindowNumber &&
        oldRadius.intValue == radius &&
        oldWindowNumber.integerValue == windowNumber) {
        return;
    }

    YMCGSConnectionID cid = gYMCGSMainConnectionID();
    CGError err = gYMCGSSetWindowBackgroundBlurRadius(cid, (YMCGSWindowID)windowNumber, radius);
    if (err != kCGErrorSuccess) {
        YMLog(@"窗口背景模糊应用失败：radius=%d err=%d", radius, err);
        return;
    }

    objc_setAssociatedObject(window,
                             &kYMAppliedBlurRadiusAssociatedKey,
                             @(radius),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(window,
                             &kYMAppliedBlurWindowNumberAssociatedKey,
                             @(windowNumber),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    YMLog(@"已应用窗口背景模糊：window=%@ windowNumber=%ld radius=%d err=%d",
          window,
          (long)windowNumber,
          radius,
          err);
}

// 快照只记录插件首次改写前的值；layer 独立记录，兼容 Qt 运行中替换 layer。
static void YMSaveThemeObject(id object) {
    if (!object || objc_getAssociatedObject(object, &kYMOriginalThemeStateKey)) return;
    NSDictionary *state;
    if ([object isKindOfClass:NSWindow.class]) {
        NSWindow *window = object;
        state = @{ @"opaque": @(window.opaque), @"color": window.backgroundColor ?: NSNull.null };
    } else if ([object isKindOfClass:NSView.class]) {
        NSView *view = object;
        state = @{ @"alpha": @(view.alphaValue), @"wantsLayer": @(view.wantsLayer) };
    } else {
        CALayer *layer = object;
        state = @{ @"opaque": @(layer.opaque), @"color": (__bridge id)layer.backgroundColor ?: NSNull.null };
    }
    objc_setAssociatedObject(object, &kYMOriginalThemeStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!gYMModifiedThemeObjects) gYMModifiedThemeObjects = [NSHashTable weakObjectsHashTable];
    [gYMModifiedThemeObjects addObject:object];
}

static void YMRestoreThemeObject(id object) {
    NSDictionary *state = objc_getAssociatedObject(object, &kYMOriginalThemeStateKey);
    if (!state) return;
    // 先消费快照，避免 AppKit 属性 setter 触发回调时重复还原。
    objc_setAssociatedObject(object, &kYMOriginalThemeStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gYMModifiedThemeObjects removeObject:object];
    id color = state[@"color"] == NSNull.null ? nil : state[@"color"];
    if ([object isKindOfClass:NSWindow.class]) {
        NSWindow *window = object;
        YMApplyWindowBackgroundBlur(window, 0);
        window.opaque = [state[@"opaque"] boolValue];
        window.backgroundColor = color;
    } else if ([object isKindOfClass:NSView.class]) {
        NSView *view = object;
        YMRemoveColorfulBlurBackgroundViewsInTree(view);
        // 还原单个 view 是个偶发事件（任何窗口的 QNSView churn 都会触发），所以只能移除
        // 该窗口的 view，绝不能拆全局 detour / 填充（否则朋友圈点图会把主窗弄白）。
        YMLiquidGlassNavigationRemoveViews(view.window);
        view.alphaValue = [state[@"alpha"] doubleValue];
        view.wantsLayer = [state[@"wantsLayer"] boolValue];
        view.needsDisplay = YES;
    } else {
        CALayer *layer = object;
        layer.opaque = [state[@"opaque"] boolValue];
        layer.backgroundColor = (__bridge CGColorRef)color;
    }
}

#pragma mark - Cocoa 层：窗口与 View 透明 / blur carrier

static NSColor *YMWindowBlurCarrierColor(void) {
    if (!YMWindowBackgroundBlurEnabled() || YMWindowBackgroundBlurRadius() <= 0) {
        return [NSColor clearColor];
    }

    CGFloat alpha = MAX(0.0, MIN(1.0, YMWindowBlurCarrierAlpha()));
    CGFloat white = YMCarrierStyleIsDark() ? 0.0 : 1.0;

    return [NSColor colorWithCalibratedWhite:white alpha:alpha];
}

static void YMMakeWindowTransparent(NSWindow *window) {
    if (!window) return;

    // 防御纵深：导航栏玻璃模式下绝不透明化非主窗（该分支正常不应触发，触发即说明
    // 有路径绕过了 YMShouldSkipMistyEffectForWindow）。
    if (!YMMistyModeEnabled()) {
        NSView *mainQNS = YMLiquidGlassNavigationMainQNSView();
        if (mainQNS && mainQNS.window && mainQNS.window != window) {
            NSLog(@"[YMLiquidGlass] WARN refusing to transparentize non-main window %@ %@",
                  NSStringFromClass(window.class), NSStringFromRect(window.frame));
            return;
        }
    }

    YMSaveThemeObject(window);
    window.opaque = NO;

    // 不再插入额外 overlay view。
    // 这里用 window 自己的背景色作为 blur carrier。
    // 深色模式内部 alpha = 0.3；浅色模式内部 alpha = 0.015。
    window.backgroundColor = YMWindowBlurCarrierColor();

    // 保留阴影，整体观感更像系统窗口。
    // window.hasShadow = YES;

    YMApplyWindowBackgroundBlur(window, YMWindowBackgroundBlurRadius());
}

static void YMMakeViewTransparent(NSView *view) {
    if (!view) return;

    YMSaveThemeObject(view);
    view.wantsLayer = YES;
    YMSaveThemeObject(view.layer);
    view.layer.opaque = NO;
    view.layer.backgroundColor = NSColor.clearColor.CGColor;

    if ([view respondsToSelector:@selector(setAlphaValue:)]) {
        // 这里不要设成 0，否则整个 Qt 内容都会不可见。
        view.alphaValue = YMQNSViewAlphaValue();
    }
}

static void YMMakeContainerBlurCarrier(NSView *container) {
    if (!container) return;

    YMSaveThemeObject(container);
    container.wantsLayer = YES;
    YMSaveThemeObject(container.layer);
    container.layer.opaque = NO;

    // 不用额外 view，而是让 contentView / QNSView 父容器自己提供 blur carrier。
    // 这样 QNSView 内部完全透明的区域，例如最左侧工具栏，也能看到 WindowServer blur。
    container.layer.backgroundColor = YMWindowBlurCarrierColor().CGColor;
}

// 朋友圈等「停靠面板」出现时，微信会把主面板画成空白的 Metal 层；整窗透明会把它
// 透穿成空白。检测主窗容器里是否有「外来的、够大的、靠右停靠」的兄弟 view（朋友圈 feed 就是
// 这样一块 ~440pt 宽、贴右边的面板）。普通聊天态没有这种 view，所以玻璃照常；一旦检测到
// 就暂歇玻璃、保持窗口不透明（绝不空白），面板关闭后下次刷新自动恢复玻璃。
static BOOL YMMainWindowHasDockedPane(NSView *container, NSView *qnsView) {
    if (!container) return NO;
    CGFloat cw = container.bounds.size.width;
    if (cw <= 0) return NO;
    for (NSView *v in container.subviews) {
        if (v == qnsView) continue;
        if ([v.identifier hasPrefix:@"YMLiquidGlassNavigation"]) continue;  // 本模块自己的 view
        if (v.isHidden || v.alphaValue <= 0.01) continue;
        NSRect f = v.frame;
        if (f.size.width >= 200.0 && f.size.height >= 400.0 && NSMinX(f) > cw * 0.4) {
            return YES;
        }
    }
    return NO;
}

static void YMInstallBlurBackgroundBehindQNSView(NSView *qnsView) {
    if (!YMIsQNSView(qnsView)) return;
    if (gYMApplyingBlurBackground || !YMThemeEffectEnabled()) return;

    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            YMInstallBlurBackgroundBehindQNSView(qnsView);
        });
        return;
    }

    gYMApplyingBlurBackground = YES;

    @try {
        NSWindow *window = qnsView.window;
        if (!window) return;

        // 只跳过 macOS 顶部状态栏图标、菜单、popover 等附属窗口。
        // 不跳过登录窗口，避免登录界面的迷离效果失效。
        if (!YMShouldApplyMistyEffectForWindow(window)) {
            YMCleanupMistyArtifactsForSkippedWindow(window);
            YMRestoreQNSViewForSkippedWindow(qnsView);
            return;
        }

        NSView *container = qnsView.superview ?: window.contentView;
        if (!container) return;

        // QNSView 必须已经是 container 的直接子 view，否则不要强行处理。
        if (qnsView.superview != container) {
            return;
        }

        // 停靠面板（朋友圈等）在时暂歇玻璃，避免主面板空白透穿；面板消失后自动恢复。
        if (!YMMistyModeEnabled() && YMMainWindowHasDockedPane(container, qnsView)) {
            YMCleanupMistyArtifactsForSkippedWindow(window);
            YMRestoreQNSViewForSkippedWindow(qnsView);
            return;
        }

        YMMakeWindowTransparent(window);
        YMMakeContainerBlurCarrier(container);
        YMEnsureColorfulBlurBackgroundInContainer(container, qnsView);
        if (YMNavigationGlassModeEnabled()) {
            YMLiquidGlassNavigationAttach(container, qnsView);
        } else {
            YMLiquidGlassNavigationDetach(window);
        }
        YMMakeViewTransparent(qnsView);
    }
    @finally {
        gYMApplyingBlurBackground = NO;
    }
}

static void YMInstallBlurBackgroundBehindQNSViewAsync(NSView *qnsView) {
    if (!qnsView) return;

    __weak NSView *weakView = qnsView;

    dispatch_async(dispatch_get_main_queue(), ^{
        NSView *strongView = weakView;
        if (!strongView) return;

        YMInstallBlurBackgroundBehindQNSView(strongView);
    });
}

static void YMRefreshViewTree(NSView *view) {
    if (!view) return;

    if (YMIsQNSView(view)) {
        YMInstallBlurBackgroundBehindQNSView(view);
        return;
    }

    NSArray<NSView *> *subviews = [view.subviews copy];
    for (NSView *subview in subviews) {
        YMRefreshViewTree(subview);
    }
}

static void YMRefreshAllWindows(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            YMRefreshAllWindows();
        });
        return;
    }

    YMRegisterMistyThemeDefaults();
    if (!YMThemeEffectEnabled()) {
        // 保活定时器在任一模式下都要跑；只有两种模式都关掉时才停。
        [gYMBlurKeepAliveTimer invalidate];
        gYMBlurKeepAliveTimer = nil;
    }
    if (!YMThemeEffectEnabled()) {
        BOOL wasApplying = gYMApplyingBlurBackground;
        gYMApplyingBlurBackground = YES;
        for (id object in gYMModifiedThemeObjects.allObjects) {
            YMRestoreThemeObject(object);
        }
        for (NSWindow *window in NSApp.windows) {
            YMLiquidGlassNavigationDetach(window);
        }
        gYMApplyingBlurBackground = wasApplying;
        return;
    }

    for (NSWindow *window in NSApp.windows) {
        if (!YMShouldApplyMistyEffectForWindow(window)) {
            YMCleanupMistyArtifactsForSkippedWindow(window);
            continue;
        }

        YMMakeWindowTransparent(window);

        // window.contentView 本身也设成 blur carrier，保证还没找到 QNSView 时也能先有承载面。
        YMMakeContainerBlurCarrier(window.contentView);

        YMRefreshViewTree(window.contentView);
    }
}

static void YMBlurKeepAliveTick(void) {
    if (YMMistyModeEnabled()) {
        // 迷离模式：整窗刷新，兼做 CGS 私有模糊保活。
        YMRefreshAllWindows();
        return;
    }
    // 导航栏玻璃模式：只重新评估被锁定的主窗 QNSView。朋友圈等停靠面板关闭后，主窗
    // QNSView 未必再产生 churn 事件（viewDidMoveTo* / setLayer），玻璃就卡在暂歇态
    // 回不来；靠这个轮询把它重新挂回去。面板还在时仍会命中 YMMainWindowHasDockedPane
    // 保持暂歇、保持窗口不透明，不会整窗透明化（所以不走 YMRefreshAllWindows，避免闪白）。
    if (!YMNavigationGlassModeEnabled()) return;
    NSView *mainQNS = YMLiquidGlassNavigationMainQNSView();
    if (mainQNS) YMInstallBlurBackgroundBehindQNSView(mainQNS);
}

static void YMStartBlurKeepAliveIfNeeded(void) {
    if (!YMThemeEffectEnabled() || gYMBlurKeepAliveTimer) return;
    gYMBlurKeepAliveTimer = [NSTimer timerWithTimeInterval:kYMBlurKeepAliveInterval repeats:YES block:^(NSTimer *timer) {
        YMBlurKeepAliveTick();
    }];
    [[NSRunLoop mainRunLoop] addTimer:gYMBlurKeepAliveTimer forMode:NSRunLoopCommonModes];
}

#pragma mark - Runtime Hook：QNSView

static BOOL YM_QNSView_isOpaque(id self, SEL _cmd) {
    if (!YMThemeEffectEnabled()) {
        return gOrig_QNSView_isOpaque ? gOrig_QNSView_isOpaque(self, _cmd) : YES;
    }
    if ([self isKindOfClass:[NSView class]]) {
        NSWindow *window = ((NSView *)self).window;
        if (window && !YMShouldApplyMistyEffectForWindow(window)) {
            if (gOrig_QNSView_isOpaque) {
                return gOrig_QNSView_isOpaque(self, _cmd);
            }
            return YES;
        }
    }

    return NO;
}

static void YM_QNSView_viewDidMoveToWindow(id self, SEL _cmd) {
    if (gOrig_QNSView_viewDidMoveToWindow) {
        gOrig_QNSView_viewDidMoveToWindow(self, _cmd);
    }

    if ([self isKindOfClass:[NSView class]]) {
        YMInstallBlurBackgroundBehindQNSViewAsync((NSView *)self);
    }
}

static void YM_QNSView_viewDidMoveToSuperview(id self, SEL _cmd) {
    if (gOrig_QNSView_viewDidMoveToSuperview) {
        gOrig_QNSView_viewDidMoveToSuperview(self, _cmd);
    }

    if ([self isKindOfClass:[NSView class]]) {
        YMInstallBlurBackgroundBehindQNSViewAsync((NSView *)self);
    }
}

static void YM_QNSView_setLayer(id self, SEL _cmd, id layer) {
    if (gOrig_QNSView_setLayer) {
        gOrig_QNSView_setLayer(self, _cmd, layer);
    }

    if (YMThemeEffectEnabled() && !gYMApplyingBlurBackground && [self isKindOfClass:[NSView class]]) {
        NSView *view = (NSView *)self;
        NSWindow *window = view.window;

        // window 还没绑定时不要提前改透明度。
        // 图片预览窗口的 QNSView 可能先 setLayer、后绑定到 PreviewWindow；
        // 如果这里在 window == nil 时先改 alpha，后面即使过滤 PreviewWindow，也会造成图片预览发虚。
        if (window && YMShouldApplyMistyEffectForWindow(window)) {
            YMMakeViewTransparent(view);
            YMInstallBlurBackgroundBehindQNSViewAsync(view);
        } else if (window) {
            YMRestoreQNSViewForSkippedWindow(view);
        }
    }
}

/// 只替换一次，避免 oldImp 被覆盖成自己的 hook，导致无限递归。
static void YMReplaceInstanceMethodOnce(Class cls, SEL sel, IMP newImp, IMP *oldImpStorage) {
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) {
        YMLog(@"找不到方法：%@ %@", NSStringFromClass(cls), NSStringFromSelector(sel));
        return;
    }

    IMP currentImp = method_getImplementation(method);

    if (currentImp == newImp) {
        YMLog(@"方法已经 hook，跳过：%@ %@", NSStringFromClass(cls), NSStringFromSelector(sel));
        return;
    }

    // 继承的方法应添加到 QNSView，不能改写 NSView 的实现。
    IMP oldImp = currentImp;
    if (!class_addMethod(cls, sel, newImp, method_getTypeEncoding(method))) {
        oldImp = method_setImplementation(method, newImp);
    }

    // 只在第一次保存原始 IMP。
    if (oldImpStorage && *oldImpStorage == NULL) {
        *oldImpStorage = oldImp;
    }

    YMLog(@"已 hook 方法：%@ %@", NSStringFromClass(cls), NSStringFromSelector(sel));
}

static void YMInstallQNSViewHooks(void) {
    if (gYMQNSViewHookInstalled) {
        return;
    }

    Class qnsClass = NSClassFromString(@"QNSView");
    if (!qnsClass) {
        YMLog(@"QNSView 类不存在，稍后重试");
        return;
    }

    gYMQNSViewHookInstalled = YES;

    YMReplaceInstanceMethodOnce(qnsClass,
                                @selector(isOpaque),
                                (IMP)YM_QNSView_isOpaque,
                                (IMP *)&gOrig_QNSView_isOpaque);

    YMReplaceInstanceMethodOnce(qnsClass,
                                @selector(viewDidMoveToWindow),
                                (IMP)YM_QNSView_viewDidMoveToWindow,
                                (IMP *)&gOrig_QNSView_viewDidMoveToWindow);

    YMReplaceInstanceMethodOnce(qnsClass,
                                @selector(viewDidMoveToSuperview),
                                (IMP)YM_QNSView_viewDidMoveToSuperview,
                                (IMP *)&gOrig_QNSView_viewDidMoveToSuperview);

    YMReplaceInstanceMethodOnce(qnsClass,
                                @selector(setLayer:),
                                (IMP)YM_QNSView_setLayer,
                                (IMP *)&gOrig_QNSView_setLayer);
}

#pragma mark - 启动入口

@implementation ThemeHook

+ (void)ym_observeAccessibilityDisplayOptions {
    if (gYMAccessibilityObserver) return;
    YMReadAccessibilityDisplayOptions();
    gYMAccessibilityObserver = [NSWorkspace.sharedWorkspace.notificationCenter
        addObserverForName:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification
                    object:nil
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(__unused NSNotification *note) {
        YMReadAccessibilityDisplayOptions();
        [ThemeHook start];
    }];
}

+ (void)start {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self start]; });
        return;
    }
    [self ym_observeAccessibilityDisplayOptions];
    YMRegisterMistyThemeDefaults();
    if (!YMThemeEffectEnabled()) {
        YMRefreshAllWindows();
        return;
    }

    YMInstallQNSViewHooks();
    YMRefreshAllWindows();
    YMStartBlurKeepAliveIfNeeded();
    if (gYMStarted) return;
    gYMStarted = YES;

    // Qt 可能延迟注册 QNSView；重试只安装一次，关闭后不重新应用主题。
    for (NSNumber *delay in @[@1, @3]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!YMThemeEffectEnabled()) return;
            YMInstallQNSViewHooks();
            YMRefreshAllWindows();
        });
    }
}

+ (void)setBackgroundImagePath:(NSString *)path {
    // 当前版本已经从背景图 / NSVisualEffectView 切换为 WindowServer 可调背景模糊。
    // 保留这个接口只是为了兼容旧调用，避免外部代码调用时报错。
    (void)path;
    [self refreshAllQNSViews];
}

+ (void)refreshAllQNSViews {
    [self start];
}

@end

__attribute__((constructor))
static void YMWeChatAntiRevokePatchEntry(void) {
    SOVEXTCheckStartupPermission();
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            [ThemeHook start];
        });
    }
}

//
