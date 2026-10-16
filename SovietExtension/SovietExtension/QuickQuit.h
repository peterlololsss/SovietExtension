//
//  QuickQuit.h
//  SovietExtension
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 跳过微信“长按 ⌘Q 退出微信”：开启后按下 ⌘Q 直接走微信自身的退出流程。
// 主线程调用；首次开启时安装 Hook，找不到 LongPressHandler 时返回 NO 且不改变状态。
FOUNDATION_EXPORT BOOL YMSetQuickQuitEnabled(BOOL enabled);

NS_ASSUME_NONNULL_END
