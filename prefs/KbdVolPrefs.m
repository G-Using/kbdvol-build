// KbdVolPrefs.m —— 面板按钮 action 的宿主。
//
// 面板本体由**系统的 PSListItemsController** 承载：入口 plist（PreferenceLoader 那份）
// 里 items 已经写全，开关/滑杆/按钮都是系统 cell，显示与读写全走系统机制。
// 这个类只负责实现 showDiag 按钮的 action。
//
// 为什么不自己画面板（1.1.0 的做法）：
//   用户提供的 .ips 崩溃栈显示，崩溃发生在
//   `-[PSListController tableView:didSelectRowAtIndexPath:]`
//   → `-[PSListController controllerForSpecifier:]` → doesNotRecognizeSelector，
//   **我的 bundle 一帧都没有**。说明点进去的根本不是我的控制器，
//   而是系统用 PSListController 承载、却找不到对应的 detail 控制器。
//   —— 最省事也最稳的做法就是**老老实实用系统控制器**，别跟它抢。

#import <UIKit/UIKit.h>
#import "KbdCommon.h"

@interface KbdVolPrefsRootController : UIViewController
@end

@implementation KbdVolPrefsRootController

- (void)showDiag {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:KVDomain];
    NSString *diag = [d stringForKey:KVKeyDiag];

    NSString *msg = diag.length
        ? diag
        : @"还没有状态。\n\n请先打开备忘录或微信，在输入框里打几个字，再回来看。\n"
          @"同时确认：设置 → 声音与触感 → 键盘反馈 → 声音 是打开的。";

    UIAlertController *a =
        [UIAlertController alertControllerWithTitle:@"插件状态"
                                            message:msg
                                     preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好"
                                          style:UIAlertActionStyleDefault
                                        handler:nil]];

    [[self activePresenter] presentViewController:a animated:YES completion:nil];
}

// 找一个真的能 present 的控制器：从 keyWindow 一路往下取最顶层的 presented
- (UIViewController *)activePresenter {
    UIApplication *app = [UIApplication sharedApplication];
    UIWindow *win = nil;
    for (UIWindow *w in app.windows) {
        if (w.isKeyWindow) { win = w; break; }
    }
    if (win == nil) win = app.windows.lastObject;

    UIViewController *vc = win.rootViewController;
    while (vc != nil && vc.presentedViewController != nil) {
        vc = vc.presentedViewController;
    }
    return vc;
}

@end