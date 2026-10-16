//
//  QuickQuit.mm
//  SovietExtension
//

#import "QuickQuit.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "RevokePatch.h"

// 微信 4.x 的本地事件监视器把按键交给 LongPressHandler；⌘Q 首次按下只显示长按提示，
// 按住触发重复按键后才调用 quitApplication。
@interface NSObject (YMLongPressHandler)
- (nullable NSEvent *)handleLocalEvent:(NSEvent *)event;
- (BOOL)isQuitHandlerRunning;
- (void)setIsQuitHandlerRunning:(BOOL)running;
- (void)quitApplication;
@end

static BOOL YMQuickQuitEnabled = NO;
static NSEvent *(*YMOriginalHandleLocalEvent)(id, SEL, NSEvent *);

// 命中条件与原实现一致（仅按住 ⌘、Q 键、关键窗口不是 FlueMockFramelessWindow），
// 命中后直接执行长按完成时的分支。
static NSEvent *YMQuickQuitHandleLocalEvent(id self, SEL _cmd, NSEvent *event) {
    const NSEventModifierFlags modifiers = NSEventModifierFlagShift | NSEventModifierFlagControl |
                                           NSEventModifierFlagOption | NSEventModifierFlagCommand;
    if (YMQuickQuitEnabled && [self isQuitHandlerRunning] && event.type == NSEventTypeKeyDown &&
        (event.modifierFlags & modifiers) == NSEventModifierFlagCommand && event.keyCode == 12 /* kVK_ANSI_Q */) {
        Class keyWindowClass = [NSApp.keyWindow class];
        if (!keyWindowClass || keyWindowClass != NSClassFromString(@"FlueMockFramelessWindow")) {
            YMLog(@"quick quit: skip long press");
            [self setIsQuitHandlerRunning:NO];
            [self quitApplication];
            return nil;
        }
    }
    return YMOriginalHandleLocalEvent(self, _cmd, event);
}

static BOOL YMInstallQuickQuitHook(void) {
    if (YMOriginalHandleLocalEvent) return YES;

    Class cls = NSClassFromString(@"LongPressHandler");
    Method method = class_getInstanceMethod(cls, @selector(handleLocalEvent:));
    if (!method || strcmp(method_getTypeEncoding(method), "@24@0:8@16") != 0 ||
        ![cls instancesRespondToSelector:@selector(isQuitHandlerRunning)] ||
        ![cls instancesRespondToSelector:@selector(setIsQuitHandlerRunning:)] ||
        ![cls instancesRespondToSelector:@selector(quitApplication)]) {
        YMLog(@"quick quit unavailable: LongPressHandler layout mismatch");
        return NO;
    }

    YMOriginalHandleLocalEvent = (NSEvent *(*)(id, SEL, NSEvent *))
        method_setImplementation(method, (IMP)YMQuickQuitHandleLocalEvent);
    YMLog(@"quick quit hook installed");
    return YES;
}

BOOL YMSetQuickQuitEnabled(BOOL enabled) {
    if (![NSThread isMainThread]) return NO;
    if (enabled && !YMInstallQuickQuitHook()) return NO;
    YMQuickQuitEnabled = enabled;
    return YES;
}
