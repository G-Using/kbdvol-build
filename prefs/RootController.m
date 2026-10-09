// RootController.m —— 设置面板。
//
// 为什么用代码构建 specifier 而不是 Root.plist：
//   plist 里的 cell 名是**字符串**（"PSSliderSpecifier" / "PSSwitchSpecifier" 这类
//   系统设置 App 的写法），第三方 PreferenceBundle 里认不出来 → cell 建不出来 →
//   **面板白屏且无任何报错**，编译器也不会提醒（2026-10-09 实测踩过）。
//   改成代码构建后，cell 常量名写错**编译器立刻报错**，把静默故障变成硬失败。

#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSSwitchCell.h>
#import <Preferences/PSSliderCell.h>
#import <Preferences/PSButtonCell.h>
#import <Preferences/PSGroupCell.h>
#import "KbdCommon.h"

@interface KbdVolPrefsRootController : PSListController
@end

// _specifiers 是 PSListController 的 ivar，SDK 头文件里不暴露，这里声明一个同名 ivar
@interface KbdVolPrefsRootController () {
    NSArray *_specifiers;
}
@end

@implementation KbdVolPrefsRootController

- (NSArray *)specifiers {
    if (!_specifiers) {
        [self buildSpecifiers];
    }
    return _specifiers;
}

- (void)buildSpecifiers {
    NSMutableArray *specs = [NSMutableArray array];

    // 分组
    PSSpecifier *g1 = [PSSpecifier groupSpecifierWithName:@"键盘打字声"];
    [g1 setProperty:@"独立于静音拨片和系统音量。拉到 0 就是完全不打字声，"
                      @"来电、通知、铃声照常响。\n\n"
                      @"需要外部键盘或第三方输入法（百度/搜狗/微信输入法等）的按键声，"
                      @"请到那些 App 自己的设置里关。" forKey:@"footerText"];
    [specs addObject:g1];

    // 启用开关
    PSSpecifier *sw = [PSSpecifier preferenceSpecifierNamed:@"启用独立音量控制"
                                                      target:self
                                                         set:@selector(setEnabledValue:specifier:)
                                                         get:@selector(readEnabledValue)
                                                      detail:nil
                                                        cell:PSSwitchCell
                                                        edit:nil];
    [sw setProperty:@"enabled" forKey:@"key"];
    [sw setProperty:KVDomain forKey:@"defaults"];
    [sw setProperty:@YES forKey:@"default"];
    [specs addObject:sw];

    // 音量滑杆
    PSSpecifier *sl = [PSSpecifier preferenceSpecifierNamed:@"打字声音量"
                                                      target:self
                                                         set:@selector(setVolumeValue:specifier:)
                                                         get:@selector(readVolumeValue)
                                                      detail:nil
                                                        cell:PSSliderCell
                                                        edit:nil];
    [sl setProperty:@"volume" forKey:@"key"];
    [sl setProperty:KVDomain forKey:@"defaults"];
    [sl setProperty:@YES forKey:@"showValue"];
    [sl setProperty:@0.0f forKey:@"min"];
    [sl setProperty:@1.0f forKey:@"max"];
    [sl setProperty:@1.0f forKey:@"default"];
    [specs addObject:sl];

    // 诊断分组
    PSSpecifier *g2 = [PSSpecifier groupSpecifierWithName:@"诊断"];
    [g2 setProperty:@"装完插件后，先去备忘录或微信的输入框打几个字，再点下面的按钮，"
                     @"它会如实告诉你有没有挂上键盘音的播放入口。" forKey:@"footerText"];
    [specs addObject:g2];

    PSSpecifier *btn = [PSSpecifier preferenceSpecifierNamed:@"查看插件状态"
                                                       target:self
                                                          set:nil
                                                          get:nil
                                                       detail:nil
                                                         cell:PSButtonCell
                                                         edit:nil];
    [btn setProperty:NSStringFromSelector(@selector(showDiag)) forKey:@"action"];
    [specs addObject:btn];

    _specifiers = specs;
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

#pragma mark - 诊断

- (void)showDiag {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *diag = [[self prefs] stringForKey:KVKeyDiag];

        NSString *msg = nil;
        if (diag.length == 0) {
            msg = @"还没有记录到任何状态。\n\n"
                  @"· 刚装完还没打开过任何 App，属正常；\n"
                  @"· 打开一次备忘录或微信，在输入框里打几个字，再回来看这里。\n\n"
                  @"另外请确认：设置 → 声音与触感 → 键盘反馈 → 声音 是打开的。";
        } else {
            msg = [diag stringByAppendingString:@"\n\n（回到有文字的地方重看一次即可刷新）"];
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