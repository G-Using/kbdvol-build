// RootController.m —— 设置面板（1.0.3）
//
// 崩溃根因（由用户提供的 Preferences.ips 精确定位）：
//   lastExceptionBacktrace 里唯一属于本bundle 的帧紧挨着
//   `-[UIResponder doesNotRecognizeSelector:]` + `_CF_forwarding_prep_0`，
//   调用链是 `-[UIViewController _sendViewDidLoadWithAppearanceProxyObject...]`
//   → 本 bundle 帧。**即 viewDidLoad 里向 self 发送了 PSListController 未实现的消息，
//   ObjC 转发失败直接 abort**（不是specifier 排版问题，是根本没走到排版）。
//
// 这一版的做法：**viewDidLoad 里一行业务代码都不写**，只调 [super viewDidLoad]。
//   · 不 override tableView 数据源系列（super 可能未实现，转发即崩）
//   · 不用 objc_getAssociatedObject（const char* key 在 ObjC 上下文里语义不明）
//   · 不在 specifiers getter 里做 KVC / 反射
//   面板内容完全交给 specifier 机制；诊断靠一个按钮 +官方 API。
//
// 判据：能进面板 = 之前崩在 viewDidLoad 的问题已除；
//       内容是否正常 = 看 specifier 机制，这两层现在互不干扰。

#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "KbdCommon.h"

@interface KbdVolPrefsRootController : PSListController
// _specifiers 是 PSListController 的 ivar，SDK 头文件里不暴露，这里声明一个同名 ivar
@end

@interface KbdVolPrefsRootController () {
    NSArray *_specifiers;
}
@end

@implementation KbdVolPrefsRootController

// PSListController 默认按控制器类名找 plist，必须显式指定（否则白屏且无报错）
- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
    }
    return _specifiers;
}

// 刻意保持空实现：任何在这里向 self 发消息的代码都可能导致 doesNotRecognizeSelector
- (void)viewDidLoad {
    [super viewDidLoad];
}

#pragma mark - 偏好读写（tweak 侧同一个 suite）

- (NSUserDefaults *)prefs {
    return [[NSUserDefaults alloc] initWithSuiteName:KVDomain];
}

- (id)readEnabledValue {
    NSUserDefaults *d = [self prefs];
    if ([d objectForKey:KVKeyEnabled] == nil) return @YES;
    return @([d boolForKey:KVKeyEnabled]);
}

- (void)setEnabledValue:(id)value specifier:(PSSpecifier *)spec {
    [[self prefs] setBool:[value boolValue] forKey:KVKeyEnabled];
}

- (id)readVolumeValue {
    NSUserDefaults *d = [self prefs];
    id v = [d objectForKey:KVKeyVolume];
    if (![v isKindOfClass:[NSNumber class]]) return @1.0f;
    return @([(NSNumber *)v floatValue]);
}

- (void)setVolumeValue:(id)value specifier:(PSSpecifier *)spec {
    float f = [value floatValue];
    if (f < 0.0f) f = 0.0f;
    if (f > 1.0f) f = 1.0f;
    [[self prefs] setFloat:f forKey:KVKeyVolume];
}

- (void)showDiag {
    NSString *diag = [[self prefs] stringForKey:KVKeyDiag];
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
    [self presentViewController:a animated:YES completion:nil];
}

@end