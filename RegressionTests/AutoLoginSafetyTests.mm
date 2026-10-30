#import "../SovietExtension/SovietExtension/AutoLogin.mm"
#include <cstdio>

void YMLog(NSString *format, ...) {
    (void)format;
}

@interface YMAutoLoginActionRecorder : NSObject
@property(nonatomic) NSUInteger activationCount;
- (void)recordActivation:(id)sender;
@end

@implementation YMAutoLoginActionRecorder
- (void)recordActivation:(id)sender {
    (void)sender;
    self.activationCount++;
}
@end

int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];

        NSUInteger failures = 0;
        NSArray<NSString *> *logoutLabels = @[
            @"退出登录", @"退出登入", @"退出登錄", @"登出",
            @"注销登录", @"註銷登入",
            @"Log out of this login", @"Logout (login again later)",
            @"Sign out of signed-in login", @"Signout / Login",
        ];
        for (NSString *label in logoutLabels) {
            YMAutoLoginActionRecorder *recorder = [YMAutoLoginActionRecorder new];
            NSButton *button = [NSButton buttonWithTitle:label target:recorder
                                                action:@selector(recordActivation:)];
            BOOL activated = YMAutoLoginTryPressView(button, [NSMutableArray array], 0);
            if (activated || recorder.activationCount != 0) {
                std::fprintf(stderr, "FAIL logout label was activated: %s count=%lu\n",
                             label.UTF8String, (unsigned long)recorder.activationCount);
                failures++;
            }
        }

        for (NSString *label in @[@"登录", @"登入", @"登錄", @"进入微信", @"進入微信",
                                   @"Log in", @"Login", @"Sign in", @"로그인", @"サインイン"]) {
            YMAutoLoginActionRecorder *recorder = [YMAutoLoginActionRecorder new];
            NSButton *button = [NSButton buttonWithTitle:label target:recorder
                                                action:@selector(recordActivation:)];
            BOOL activated = YMAutoLoginTryPressView(button, [NSMutableArray array], 0);
            if (!activated || recorder.activationCount != 1) {
                std::fprintf(stderr, "FAIL login label was not activated once: %s count=%lu\n",
                             label.UTF8String, (unsigned long)recorder.activationCount);
                failures++;
            }
        }
        for (NSString *label in @[@"", @"切换账号登录", @"仅传输文件", @"网络代理设置",
                                   @"Switch account login", @"File transfer login"]) {
            if (YMAutoLoginTextLooksLikeLoginButton(label)) {
                std::fprintf(stderr, "FAIL excluded label was accepted: %s\n", label.UTF8String);
                failures++;
            }
        }
        if (failures != 0) return 1;
        std::puts("PASS AutoLoginSafetyTests logout_actions=0 login_labels_preserved=true");
        return 0;
    }
}
