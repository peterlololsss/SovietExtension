#import "../SovietExtension/SovietExtension/QuickClose.mm"
#include <cstdio>
#include <cstdlib>

void YMLog(NSString *format, ...) { (void)format; }

@interface YMCloseTestApplication : NSApplication
@property(nonatomic, strong) NSWindow *testKeyWindow;
@property(nonatomic, strong) NSWindow *testModalWindow;
@property(nonatomic) BOOL testActive;
@end
@implementation YMCloseTestApplication
- (NSWindow *)keyWindow { return self.testKeyWindow; }
- (NSWindow *)modalWindow { return self.testModalWindow; }
- (BOOL)isActive { return self.testActive; }
@end

@interface QNSWindow : NSWindow
@property(nonatomic) BOOL testVisible;
@property(nonatomic, strong) NSWindow *testSheet;
@end
@implementation QNSWindow
- (BOOL)isVisible { return self.testVisible; }
- (NSWindow *)attachedSheet { return self.testSheet; }
@end

@interface WindowObserver : NSObject
@property(nonatomic, weak) QNSWindow *window;
@property(nonatomic) NSUInteger calls;
@property(nonatomic) BOOL veto;
- (void)onCloseButtonClicked;
@end
@implementation WindowObserver
- (void)onCloseButtonClicked {
    self.calls++;
    if (!self.veto) self.window.testVisible = NO;
}
@end

static NSEvent *Key(NSString *characters, NSEventModifierFlags flags, BOOL repeat = NO,
                    NSEventType type = NSEventTypeKeyDown, NSInteger windowNumber = 0) {
    return [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:flags
                           timestamp:0 windowNumber:windowNumber context:nil characters:characters
         charactersIgnoringModifiers:characters isARepeat:repeat keyCode:13];
}

static void Check(BOOL condition, const char *message) {
    if (!condition) { std::fprintf(stderr, "FAIL %s\n", message); std::exit(1); }
}

int main() {
    @autoreleasepool {
        YMCloseTestApplication *app = [YMCloseTestApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyProhibited];
        app.testActive = YES;
        QNSWindow *window = [[QNSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
            backing:NSBackingStoreBuffered defer:YES];
        window.releasedWhenClosed = NO;
        window.testVisible = YES;
        app.testKeyWindow = window;
        WindowObserver *observer = [WindowObserver new];
        observer.window = window;
        NSButton *button = [window standardWindowButton:NSWindowCloseButton];
        button.target = observer;
        button.action = @selector(onCloseButtonClicked);
        NSEvent *cmdW = Key(@"w", NSEventModifierFlagCommand);
        YMSetQuickCloseEnabled(YES);
        Check(YMQuickCloseHandleEvent(cmdW, app) == nil && observer.calls == 1 && !window.testVisible,
              "Cmd+W must invoke the host close button once when Qt does not close the window");

        window.testVisible = YES;
        app.testKeyWindow = nil;
        Check(YMQuickCloseHandleEvent(Key(@"w", NSEventModifierFlagCommand, YES), app) == nil &&
              observer.calls == 1, "held Cmd+W must not close a second window");
        app.testKeyWindow = window;
        YMQuickCloseHandleEvent(Key(@"w", 0, NO, NSEventTypeKeyUp), app);
        observer.veto = YES;
        Check(YMQuickCloseHandleEvent(cmdW, app) == nil && observer.calls == 2 && window.testVisible,
              "the host button may decline closing; do not force-orderOut or close");
        observer.veto = NO;
        YMSetQuickCloseEnabled(NO);
        Check(YMQuickCloseHandleEvent(cmdW, app) == cmdW && observer.calls == 2,
              "disabled repair must preserve original event dispatch");
        YMSetQuickCloseEnabled(YES);

        NSEventModifierFlags otherFlags[] = {0, NSEventModifierFlagOption,
                NSEventModifierFlagCommand | NSEventModifierFlagShift,
                NSEventModifierFlagCommand | NSEventModifierFlagControl,
                NSEventModifierFlagCommand | NSEventModifierFlagOption};
        for (NSEventModifierFlags flags : otherFlags) {
            NSEvent *event = Key(@"w", flags);
            Check(YMQuickCloseHandleEvent(event, app) == event, "other modifier combinations must pass through");
        }
        NSEvent *cmdQ = Key(@"q", NSEventModifierFlagCommand);
        Check(YMQuickCloseHandleEvent(cmdQ, app) == cmdQ, "Cmd+Q must pass through");
        NSEvent *otherWindow = Key(@"w", NSEventModifierFlagCommand, NO,
                                   NSEventTypeKeyDown, MAX(window.windowNumber, 0) + 1);
        Check(YMQuickCloseHandleEvent(otherWindow, app) == otherWindow,
              "an event for a different window must not close the key window");
        app.testActive = NO;
        Check(YMQuickCloseHandleEvent(cmdW, app) == cmdW, "inactive app must not close a window");
        app.testActive = YES;
        app.testModalWindow = window;
        Check(YMQuickCloseHandleEvent(cmdW, app) == cmdW, "modal sessions must keep original dispatch");
        app.testModalWindow = nil;
        window.testSheet = window;
        Check(YMQuickCloseHandleEvent(cmdW, app) == cmdW, "attached sheets must keep original dispatch");
        window.testSheet = nil;
        window.testVisible = NO;
        Check(YMQuickCloseHandleEvent(cmdW, app) == cmdW, "hidden window must not receive a close");
        window.testVisible = YES;
        button.enabled = NO;
        Check(YMQuickCloseHandleEvent(cmdW, app) == cmdW, "disabled host button must not be forced");
        button.enabled = YES;
        button.action = @selector(description);
        Check(YMQuickCloseHandleEvent(cmdW, app) == cmdW, "unrecognized action must pass through");
        button.action = @selector(onCloseButtonClicked);
        app.testKeyWindow = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
            backing:NSBackingStoreBuffered defer:YES];
        Check(YMQuickCloseHandleEvent(cmdW, app) == cmdW, "plugin panels must keep native Cmd+W");
        app.testKeyWindow = nil;
        Check(YMQuickCloseHandleEvent(cmdW, app) == cmdW, "no key window must pass through");
        std::puts("PASS QuickCloseTests host_action_once=true host_veto_preserved=true unsafe_contexts_passthrough=true");
    }
}
