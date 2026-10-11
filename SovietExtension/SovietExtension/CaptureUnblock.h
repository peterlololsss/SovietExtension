//
//  CaptureUnblock.h
//  SovietExtension
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 允许系统截图/录屏捕获微信主窗口：服务器下发 pc_forbid_screenshot 后微信会把主窗口设为不可捕获。
// 主线程调用；首次开启时安装 Hook，关闭时把窗口还原为微信要求的状态。
FOUNDATION_EXPORT BOOL YMSetAllowWindowCaptureEnabled(BOOL enabled);

NS_ASSUME_NONNULL_END
