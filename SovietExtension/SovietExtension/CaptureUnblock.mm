//
//  CaptureUnblock.mm
//  SovietExtension
//

#import "CaptureUnblock.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "RevokePatch.h"

// 微信 4.1.11 收到 sysmsg pc_forbid_screenshot（screenshot_status/screenshot_expire_ts）后，
// 对主窗口及独立聊天窗口调用 setSharingType:NSWindowSharingNone，系统截图、录屏、共享屏幕都拍不到。
// 开启后把这类请求改为 ReadOnly，并记下微信要求的值，关闭时还原。
// 只处理普通层级、接收鼠标、带标题的窗口；微信截图工具自身的浮层（高层级或忽略鼠标）保持不可捕获。

static BOOL YMAllowWindowCaptureEnabled = NO;
static void (*YMOriginalSetSharingType)(id, SEL, NSWindowSharingType);
static const void *YMRequestedSharingTypeKey = &YMRequestedSharingTypeKey;

static BOOL YMIsCaptureUnblockTarget(NSWindow *window) {
    // 普通层级 + 接收鼠标，排除微信截图工具自身的浮层（高层级或忽略鼠标）。
    if (window.level != NSNormalWindowLevel || window.ignoresMouseEvents) return NO;
    // 原先还要求 title.length>0，会漏掉无标题的内容窗口（大图预览、独立朋友圈子窗、
    // 某些状态下的主窗），它们因此保持 NSWindowSharingNone -> 截图发黑。改为按尺寸判定：
    // 足够大的即视为内容窗口。
    NSRect f = window.frame;
    return f.size.width >= 200.0 && f.size.height >= 200.0;
}

static void YMAllowCaptureSetSharingType(NSWindow *self, SEL _cmd, NSWindowSharingType type) {
    objc_setAssociatedObject(self, YMRequestedSharingTypeKey, @(type), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (YMAllowWindowCaptureEnabled && type == NSWindowSharingNone && YMIsCaptureUnblockTarget(self)) {
        YMLog(@"allow capture: keep window %ld readable", (long)self.windowNumber);
        type = NSWindowSharingReadOnly;
    }
    YMOriginalSetSharingType(self, _cmd, type);
}

// 开关切换或窗口出现时同步已打开的窗口；标题可能在 sharingType 之后才设置，所以出现/成为 key 时再查一次。
static void YMApplyAllowWindowCaptureToOpenWindows(void) {
    for (NSWindow *window in NSApp.windows) {
        if (!YMIsCaptureUnblockTarget(window)) continue;
        NSNumber *requested = objc_getAssociatedObject(window, YMRequestedSharingTypeKey);
        if (YMAllowWindowCaptureEnabled) {
            if (window.sharingType != NSWindowSharingNone) continue;
            if (!requested) {
                objc_setAssociatedObject(window, YMRequestedSharingTypeKey, @(NSWindowSharingNone),
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            YMLog(@"allow capture: unhide window %ld", (long)window.windowNumber);
            YMOriginalSetSharingType(window, @selector(setSharingType:), NSWindowSharingReadOnly);
        } else if (requested && requested.integerValue == NSWindowSharingNone &&
                   window.sharingType != NSWindowSharingNone) {
            YMOriginalSetSharingType(window, @selector(setSharingType:), NSWindowSharingNone);
        }
    }
}

static BOOL YMInstallAllowWindowCaptureHook(void) {
    if (YMOriginalSetSharingType) return YES;

    Method method = class_getInstanceMethod([NSWindow class], @selector(setSharingType:));
    if (!method) {
        YMLog(@"allow capture unavailable: -[NSWindow setSharingType:] missing");
        return NO;
    }
    YMOriginalSetSharingType = (void (*)(id, SEL, NSWindowSharingType))
        method_setImplementation(method, (IMP)YMAllowCaptureSetSharingType);

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    for (NSNotificationName name in @[NSWindowDidBecomeKeyNotification, NSWindowDidChangeOcclusionStateNotification,
                                      NSWindowDidUpdateNotification, NSWindowDidResizeNotification,
                                      NSWindowDidMiniaturizeNotification, NSWindowDidDeminiaturizeNotification]) {
        [center addObserverForName:name object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            if (YMAllowWindowCaptureEnabled) YMApplyAllowWindowCaptureToOpenWindows();
        }];
    }
    // 兜底轮询：微信可能在不触发上述通知的时机对新窗口调用 setSharingType:None（如大图预览
    // 弹出、pc_forbid_screenshot 延迟下发）。每 0.75s 扫一遍，确保所有内容窗口都被放开。
    NSTimer *sweep = [NSTimer timerWithTimeInterval:0.75 repeats:YES block:^(NSTimer *t) {
        if (YMAllowWindowCaptureEnabled) YMApplyAllowWindowCaptureToOpenWindows();
    }];
    [[NSRunLoop mainRunLoop] addTimer:sweep forMode:NSRunLoopCommonModes];
    YMLog(@"allow capture hook installed");
    return YES;
}

BOOL YMSetAllowWindowCaptureEnabled(BOOL enabled) {
    if (![NSThread isMainThread]) return NO;
    if (enabled && !YMInstallAllowWindowCaptureHook()) return NO;
    YMAllowWindowCaptureEnabled = enabled;
    if (YMOriginalSetSharingType) YMApplyAllowWindowCaptureToOpenWindows();
    return YES;
}
