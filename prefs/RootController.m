// KbdVolPrefsRootController.m —— 设置面板（1.1.0，纯原生自绘）
//
// 为什么彻底重写：1.0.0 ~ 1.0.3 连续白屏/崩溃，包本身反复排查全部正确
//   （权限 0755、入口 bundle 字段、Info.plist 类名、Root.plist cell 名与必需项、
//     arm64+arm64e 双切片、崩溃日志证明 bundle 已被加载）。
//   根因在宿主环境：设备装了 SettingsRevamp / SettingsRevamp_CN / SwitchTheme / libprefs，
//   这些设置美化插件**专门 hook PSListController 及其子类**来接管第三方面板渲染。
//   ——只要我的控制器还继承 PSListController，就永远在它们的射程内。
//
// 这一版的做法：**不再继承 PSListController**，直接继承 UIViewController，
//   界面全部用原生 UIKit 手绘（UISwitch / UISlider / UIButton / UILabel）。
//   Preferences 的 specifier、cell、tableView 回调链路一概不碰，
//   美化插件的 hook 目标一个都碰不到，从结构上免疫。
//
// 保留的能力（一个不少）：启用开关、音量滑杆(0~1)、实时生效、查看插件状态。
// 偏好读写仍走 initWithSuiteName:，与 tweak 侧同一个域。

#import <UIKit/UIKit.h>
#import "KbdCommon.h"

@interface KbdVolPrefsRootController : UIViewController
@end

@implementation KbdVolPrefsRootController {
    UISwitch *_enabledSwitch;
    UISlider *_volumeSlider;
    UILabel *_volumeLabel;
    UILabel *_hookLabel;
}

- (NSUserDefaults *)prefs {
    return [[NSUserDefaults alloc] initWithSuiteName:KVDomain];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.title = @"键盘音量";

    [self buildUI];
    [self reloadValues];
}

#pragma mark - 界面

- (UILabel *)mkLabel:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [UIFont systemFontOfSize:size weight:weight];
    l.textColor = [UIColor labelColor];
    l.numberOfLines = 0;
    l.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:l];
    return l;
}

- (void)buildUI {
    UIView *v = self.view;
    UILayoutGuide *safe = v.safeAreaLayoutGuide;

    // ---- 说明区
    UILabel *desc = [self mkLabel:
        @"独立于静音拨片和系统音量。\n音量拉到 0 就是完全不打字声，来电、通知、铃声照常响。"
                               size:13 weight:UIFontWeightRegular];
    desc.textColor = [UIColor secondaryLabelColor];

    // ---- 启用开关
    UILabel *enLabel = [self mkLabel:@"启用独立音量控制" size:17 weight:UIFontWeightRegular];
    _enabledSwitch = [[UISwitch alloc] init];
    _enabledSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [_enabledSwitch addTarget:self action:@selector(onSwitch:)
              forControlEvents:UIControlEventValueChanged];
    [v addSubview:_enabledSwitch];

    // ---- 音量
    UILabel *volTitle = [self mkLabel:@"打字声音量" size:17 weight:UIFontWeightRegular];
    _volumeLabel = [self mkLabel:@"100%" size:15 weight:UIFontWeightSemibold];
    _volumeLabel.textAlignment = NSTextAlignmentRight;

    _volumeSlider = [[UISlider alloc] init];
    _volumeSlider.minimumValue = 0.0f;
    _volumeSlider.maximumValue = 1.0f;
    _volumeSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [_volumeSlider addTarget:self action:@selector(onSlider:)
            forControlEvents:UIControlEventValueChanged];
    [_volumeSlider addTarget:self action:@selector(onSlider:)
            forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:_volumeSlider];

    UILabel *hint = [self mkLabel:
        @"0% = 完全不打字声（不用拨静音拨片）\n100% = 完全走系统原声，零延迟、音色不变"
                              size:12 weight:UIFontWeightRegular];
    hint.textColor = [UIColor secondaryLabelColor];

    // ---- 状态
    UILabel *diagTitle = [self mkLabel:@"插件状态" size:17 weight:UIFontWeightSemibold];
    _hookLabel = [self mkLabel:@"（正在读取…）" size:13 weight:UIFontWeightRegular];
    _hookLabel.textColor = [UIColor secondaryLabelColor];
    _hookLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:@"查看插件状态" forState:UIControlStateNormal];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn addTarget:self action:@selector(showDiag) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:btn];

    // ---- 约束
    CGFloat pad = 20.0;
    [NSLayoutConstraint activateConstraints:@[
        [desc.topAnchor constraintEqualToAnchor:safe.topAnchor constant:18],
        [desc.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:pad],
        [desc.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-pad],

        [enLabel.topAnchor constraintEqualToAnchor:desc.bottomAnchor constant:26],
        [enLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:pad],
        [enLabel.centerYAnchor constraintEqualToAnchor:_enabledSwitch.centerYAnchor],
        [_enabledSwitch.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-pad],

        [volTitle.topAnchor constraintEqualToAnchor:_enabledSwitch.bottomAnchor constant:26],
        [volTitle.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:pad],
        [_volumeLabel.centerYAnchor constraintEqualToAnchor:volTitle.centerYAnchor],
        [_volumeLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-pad],

        [_volumeSlider.topAnchor constraintEqualToAnchor:volTitle.bottomAnchor constant:10],
        [_volumeSlider.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:pad],
        [_volumeSlider.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-pad],

        [hint.topAnchor constraintEqualToAnchor:_volumeSlider.bottomAnchor constant:6],
        [hint.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:pad],
        [hint.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-pad],

        [diagTitle.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:30],
        [diagTitle.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:pad],

        [_hookLabel.topAnchor constraintEqualToAnchor:diagTitle.bottomAnchor constant:8],
        [_hookLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:pad],
        [_hookLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-pad],

        [btn.topAnchor constraintEqualToAnchor:_hookLabel.bottomAnchor constant:12],
        [btn.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:pad],
    ]];
}

#pragma mark - 读值

- (void)reloadValues {
    NSUserDefaults *d = [self prefs];

    id en = [d objectForKey:KVKeyEnabled];
    [_enabledSwitch setOn:(en != nil) ? [en boolValue] : YES animated:NO];

    id vol = [d objectForKey:KVKeyVolume];
    float f = [vol isKindOfClass:[NSNumber class]] ? [vol floatValue] : 1.0f;
    [_volumeSlider setValue:f animated:NO];
    [self updateVolumeLabel:f];

    [self reloadHookLabel];
}

- (void)updateVolumeLabel:(float)f {
    _volumeLabel.text = [NSString stringWithFormat:@"%d%%", (int)lroundf(f * 100.0f)];
}

- (void)reloadHookLabel {
    NSString *diag = [[self prefs] stringForKey:KVKeyDiag];
    if (diag.length == 0) {
        _hookLabel.text = @"还没上报状态。\n请先打开备忘录或微信，在输入框里打几个字，再回到这里。";
        return;
    }
    // 诊断串可能很长，截取结论行即可
    NSMutableArray *keep = [NSMutableArray array];
    for (NSString *line in [diag componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"结论："] || [line hasPrefix:@"已挂钩"]
            || [line hasPrefix:@"键盘类："] || [line length] == 0) {
            [keep addObject:line];
        }
    }
    _hookLabel.text = [keep componentsJoinedByString:@"\n"];
}

#pragma mark - 写值

- (void)onSwitch:(UISwitch *)sw {
    [[self prefs] setBool:sw.isOn forKey:KVKeyEnabled];
    [[self prefs] synchronize];
}

- (void)onSlider:(UISlider *)slider {
    float f = slider.value;
    if (f < 0.0f) f = 0.0f;
    if (f > 1.0f) f = 1.0f;
    [self updateVolumeLabel:f];

    NSUserDefaults *d = [self prefs];
    [d setFloat:f forKey:KVKeyVolume];
    // 不急着 synchronize：每次拖动都刷盘会拖慢UI，
    // tweak 侧每秒才读一次，松手时同步一次足够。
    [d synchronize];
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