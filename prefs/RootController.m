// RootController.m —— 设置面板（1.3.0，基于 1.0.1 回退修正）
//
// 策略：**完全回到 1.0.1**——那是唯一确认「设置里菜单能正常显示」的版本。
// 1.0.1 白屏的根因只有一个：Root.plist 里 cell 名写成了系统设置 App 的写法
//   （PSSwitchSpecifier / PSSliderSpecifier），第三方 bundle 里认不出来 → cell 建不出来。
// 本版相对 1.0.1 的**唯一改动**就是把它们改成 PSSwitchCell / PSSliderCell，
// 其余文件（入口 plist / Info.plist / 控制器结构）全部保持 1.0.1 原样，
// 不再引入任何新的写法，避免又踩未知的坑。
//
// 关键纪律（都是这几轮踩出来的）：
//   · 不override tableView 的任何数据源/委托方法 —— 父类没实现时 [super xxx]
//     会走 doesNotRecognizeSelector 直接把设置进程打崩。
//   · viewDidLoad 只调 [super viewDidLoad]。
//   · 偏好读写走 initWithSuiteName:，与 tweak 侧同一个域。

#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "KbdCommon.h"

@interface KbdVolPrefsRootController : PSListController
@end

@interface KbdVolPrefsRootController () {
    NSArray *_specifiers;      // PSListController 的 ivar，SDK 头里不暴露
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

- (void)viewDidLoad {
    [super viewDidLoad];
}

#pragma mark - 偏好读写（与 tweak 侧同一个 suite）

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
    NSUserDefaults *d = [self prefs];
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
    [self presentViewController:a animated:YES completion:nil];
}

@end
