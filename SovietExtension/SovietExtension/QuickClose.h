#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 让 ⌘W 使用微信当前原生窗口的关闭按钮；主线程调用，可即时关闭修复。
FOUNDATION_EXPORT BOOL YMSetQuickCloseEnabled(BOOL enabled);

NS_ASSUME_NONNULL_END
