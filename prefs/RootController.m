// RootController.m —— 设置面板。plist 驱动，代码里不构造任何 PSSpecifier。

#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import "KbdCommon.h"

@interface KbdVolPrefsRootController : PSListController
@end

// _specifiers 是 PSListController 的 ivar，SDK 头文件里不暴露，这里声明一个同名 ivar
@interface KbdVolPrefsRootController () {
    NSArray *_specifiers;
}
@end

@implementation KbdVolPrefsRootController

// PSListController 不会自动按类名找 plist，必须显式指定（否则白屏且无报错）
- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
    }
    return _specifiers;
}

- (void)showDiag {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:KVDomain];
        NSString *diag = [d stringForKey:KVKeyDiag];

        NSString *msg = nil;
        if (diag.length == 0) {
            msg = @"还没有记录到任何状态。\n\n"
                  @"· 如果你是刚装完还没打开过任何 App，属正常；\n"
                  @"· 打开一次备忘录或微信，在输入框里打几个字，再回来看这里。\n\n"
                  @"另外请确认：设置 → 声音与触感 → 键盘反馈 → 声音 是打开的。";
        } else {
            msg = [diag stringByAppendingString:
                   @"\n\n（上面为空表示还没在 App 里打过字，回来重看即可）"];
        }

        UIAlertController *a =
            [UIAlertController alertControllerWithTitle:@"键盘音量 · 插件状态"
                                                message:msg
                                         preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    });
}

@end