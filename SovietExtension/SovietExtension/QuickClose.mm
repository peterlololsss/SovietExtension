#import "QuickClose.h"
#import <AppKit/AppKit.h>
#import "RevokePatch.h"
#include <cstring>

static BOOL YMQuickCloseEnabled;
static BOOL YMQuickCloseConsumedKeyDown;
static unsigned short YMQuickCloseKeyCode;
static id YMQuickCloseMonitor;

static BOOL YMIsQuickCloseShortcut(NSEvent *event) {
    const NSEventModifierFlags modifiers = NSEventModifierFlagCommand | NSEventModifierFlagShift |
                                           NSEventModifierFlagControl | NSEventModifierFlagOption;
    return (event.modifierFlags & modifiers) == NSEventModifierFlagCommand &&
           [event.charactersIgnoringModifiers.lowercaseString isEqualToString:@"w"];
}

static NSButton *YMQuickCloseButtonForEvent(NSEvent *event, NSApplication *app) {
    if (!app.isActive || app.modalWindow) return nil;
    NSWindow *window = app.keyWindow;
    Class hostWindowClass = NSClassFromString(@"QNSWindow");
    if (!hostWindowClass || ![window isKindOfClass:hostWindowClass] || !window.isVisible ||
        window.attachedSheet || !(window.styleMask & NSWindowStyleMaskClosable) ||
        (event.windowNumber > 0 && event.windowNumber != window.windowNumber)) return nil;

    NSButton *button = [window standardWindowButton:NSWindowCloseButton];
    Class observerClass = NSClassFromString(@"WindowObserver");
    if (!button.isEnabled || !observerClass || ![button.target isKindOfClass:observerClass] ||
        button.action != NSSelectorFromString(@"onCloseButtonClicked")) return nil;

    NSMethodSignature *signature = [button.target methodSignatureForSelector:button.action];
    return signature.numberOfArguments == 2 &&
           std::strcmp(signature.methodReturnType, @encode(void)) == 0 ? button : nil;
}

static NSEvent *YMQuickCloseHandleEvent(NSEvent *event, NSApplication *app) {
    if (!YMQuickCloseEnabled) return event;
    if (event.type == NSEventTypeKeyUp && event.keyCode == YMQuickCloseKeyCode)
        YMQuickCloseConsumedKeyDown = NO;
    if (event.type != NSEventTypeKeyDown) return event;
    if (!event.isARepeat) YMQuickCloseConsumedKeyDown = NO;
    // 关闭后焦点可能转移；同一次长按的重复事件不能再关闭其他窗口。
    if (YMQuickCloseConsumedKeyDown && event.isARepeat && event.keyCode == YMQuickCloseKeyCode)
        return nil;
    if (!YMIsQuickCloseShortcut(event)) return event;

    NSButton *button = YMQuickCloseButtonForEvent(event, app);
    YMLog(@"[QuickClose] route=%@ active=%d window=%ld class=%@",
          button ? @"native-button" : @"original", app.isActive,
          (long)app.keyWindow.windowNumber, NSStringFromClass(app.keyWindow.class));
    if (!button) return event;
    YMQuickCloseConsumedKeyDown = YES;
    YMQuickCloseKeyCode = event.keyCode;
    // 微信给关闭按钮绑定了 subscriber 事件 7；performClose: 会绕过这条宿主流程。
    [button performClick:nil];
    return nil;
}

BOOL YMSetQuickCloseEnabled(BOOL enabled) {
    if (![NSThread isMainThread]) return NO;
    if (enabled && !YMQuickCloseMonitor) {
        YMQuickCloseMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskKeyUp
            handler:^NSEvent *(NSEvent *event) { return YMQuickCloseHandleEvent(event, NSApp); }];
        if (!YMQuickCloseMonitor) return NO;
    } else if (!enabled && YMQuickCloseMonitor) {
        [NSEvent removeMonitor:YMQuickCloseMonitor];
        YMQuickCloseMonitor = nil;
    }
    YMQuickCloseEnabled = enabled;
    YMQuickCloseConsumedKeyDown = NO;
    YMLog(@"[QuickClose] enabled=%d", enabled);
    return YES;
}
