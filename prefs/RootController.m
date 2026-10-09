// RootController.m —— 设置面板（1.0.2 诊断增强版）
//
// 背景：1.0.0 白屏（Root.plist 的 cell 名写成了系统设置 App 的写法），
// 1.0.1 改成代码构建 specifier 后**仍然白屏**。两次都是"静默失败"，
// 光靠猜会反复烧编译轮次。
//
// 这一版的设计目标不是"猜对"，而是**让面板自己暴露它卡在哪一层**：
//   · 不依赖 Preferences 的 specifier 机制 —— viewDidLoad 里无条件往 tableView
//     插入一个诊断 section，纯代码建 UITableViewCell，不碰 PSSpecifier。
//   · 每一步的关键状态写进 /var/mobile/Documents/KbdVol-diag.txt，
//     用户可以直接把文件发回来。
// 于是：能看到诊断文字 = bundle 和 controller 都正常，问题在 specifier；
//         连诊断文字都没有 = 入口/bundle 加载就没成功，问题在更外层。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "KbdCommon.h"

static NSString *const kDiagFile = @"/var/mobile/Documents/KbdVol-diag.txt";

static void DiagLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *line = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    static NSMutableString *acc = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ acc = [NSMutableString string]; });
    [acc appendFormat:@"%@ %@\n", [NSDate date], line];
    NSLog(@"[KbdVolPrefs] %@", line);

    // 设置进程对 /var/mobile/Documents 有写权限；失败也不能影响面板
    NSError *err = nil;
    NSString *text = acc;
    if (![text writeToFile:kDiagFile atomically:YES
                  encoding:NSUTF8StringEncoding error:&err]) {
        NSLog(@"[KbdVolPrefs] diag write failed: %@", err);
    }
}

@interface KbdVolPrefsRootController : PSListController
@end

@interface KbdVolPrefsRootController ()
@property (nonatomic, strong) NSMutableArray *diagLines;
@end

@implementation KbdVolPrefsRootController

#pragma mark - 诊断区（不依赖 specifier，纯代码建 cell）

- (void)viewDidLoad {
    DiagLog(@"viewDidLoad 进入 · bundle=%@ · controller=%@",
            [[NSBundle bundleForClass:[self class]] bundleIdentifier],
            NSStringFromClass([self class]));

    [self buildDiagSection];

    // 让诊断文字出现在列表最上面
    [self.tableView reloadData];

    NSUInteger n = [self safeSpecifierCount];
    DiagLog(@"specifier 数量 = %lu", (unsigned long)n);
    if (n == 0) {
        DiagLog(@"!! specifier 为空 —— 开关和滑杆不会出现。原因在 buildSpecifiers。");
    } else {
        DiagLog(@"specifier 正常，将显示 %lu 行", (unsigned long)n);
    }
    [super viewDidLoad];
}

// 用 KVC 绕开 _specifiers ivar 不可见的问题，拿不到就当 0
- (NSUInteger)safeSpecifierCount {
    @try {
        NSArray *s = [self valueForKey:@"specifiers"];
        return s.count;
    } @catch (NSException *e) {
        DiagLog(@"读 specifiers 异常: %@", e.reason);
        return 0;
    }
}

- (void)buildDiagSection {
    NSMutableArray *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"插件版本 1.0.2 · 诊断模式"]];
    [lines addObject:[NSString stringWithFormat:@"控制器：%@",
                      NSStringFromClass([self class])]];
    [lines addObject:[NSString stringWithFormat:@"面板行数：%lu",
                      (unsigned long)[self safeSpecifierCount]]];
    [lines addObject:@"—— 若你看到这一段，说明插件已加载 ——"];

    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:KVDomain];
    [lines addObject:[NSString stringWithFormat:@"开关：%@",
                      [d objectForKey:KVKeyEnabled] ? @"已设置" : @"未设置(默认开)"]];
    id vol = [d objectForKey:KVKeyVolume];
    [lines addObject:[NSString stringWithFormat:@"音量：%@",
                      (vol != nil) ? vol : @"未设置(默认100%)"]];

    NSString *diag = [d stringForKey:KVKeyDiag];
    if (diag.length > 0) {
        for (NSString *l in [diag componentsSeparatedByString:@"\n"]) {
            if (l.length) [lines addObject:l];
        }
    } else {
        [lines addObject:@"（tweak 还没上报状态：打开备忘录打个字再回来看）"];
    }
    self.diagLines = lines;
}

#pragma mark - tableView 数据源：诊断区固定在最前

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return [super numberOfSectionsInTableView:tv] + 1;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return (NSInteger)self.diagLines.count;
    }
    return [super tableView:tv numberOfRowsInSection:section - 1];
}

- (UITableViewCell *)tableView:(UITableView *)tv
         cellForRowAtIndexPath:(NSIndexPath *)idx {
    if (idx.section == 0) {
        static NSString *kID = @"KbdVolDiagCell";
        UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:kID];
        if (c == nil) {
            c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:kID];
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            c.textLabel.numberOfLines = 0;
            c.detailTextLabel.numberOfLines = 0;
            c.backgroundColor = [UIColor colorWithWhite:0.97 alpha:1.0];
        }
        if (idx.row < (NSInteger)self.diagLines.count) {
            c.textLabel.text = self.diagLines[(NSUInteger)idx.row];
            // 第一行是标题，其余是详情样式，读起来像一份状态单
            c.textLabel.font = (idx.row == 0)
                ? [UIFont boldSystemFontOfSize:15]
                : [UIFont systemFontOfSize:13];
            c.detailTextLabel.text = nil;
        }
        return c;
    }
    return [super tableView:tv cellForRowAtIndexPath:
            [NSIndexPath indexPathForRow:idx.row inSection:idx.section - 1]];
}

#pragma mark - specifier 构建

- (NSArray *)specifiers {
    // 不用 ivar（PSListController 的 _specifiers 在 SDK 头里不暴露，
    // 自己声明同名 ivar 会和父类的 slot 打架），改用 associated object 缓存
    static const char *kKey = "KbdVolSpecs";
    NSArray *cached = objc_getAssociatedObject(self, kKey);
    if (cached == nil) {
        cached = [self buildSpecifiers];
        objc_setAssociatedObject(self, kKey, cached, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DiagLog(@"buildSpecifiers 生成 %lu 行", (unsigned long)cached.count);
        for (PSSpecifier *s in cached) {
            // cell / name 都不是公开属性，只能从 properties 字典里读
            id cellName = s.properties[@"cell"];
            id label = s.properties[@"label"];
            DiagLog(@"  spec: cell=%@ label=%@ key=%@",
                    cellName, label, s.properties[@"key"]);
        }
    }
    return cached;
}

- (NSArray *)buildSpecifiers {
    NSMutableArray *specs = [NSMutableArray array];

    PSSpecifier *g1 = [PSSpecifier groupSpecifierWithName:@"键盘打字声"];
    [g1 setProperty:@"独立于静音拨片和系统音量。拉到 0 就是完全不打字声，来电通知照常响。"
             forKey:@"footerText"];
    [specs addObject:g1];

    PSSpecifier *sw = [PSSpecifier preferenceSpecifierNamed:@"启用独立音量控制"
                                                      target:self
                                                         set:@selector(setEnabledValue:specifier:)
                                                         get:@selector(readEnabledValue)
                                                      detail:nil
                                                        cell:PSSwitchCell
                                                        edit:nil];
    [sw setProperty:KVKeyEnabled forKey:@"key"];
    [sw setProperty:KVDomain forKey:@"defaults"];
    [specs addObject:sw];

    PSSpecifier *sl = [PSSpecifier preferenceSpecifierNamed:@"打字声音量"
                                                      target:self
                                                         set:@selector(setVolumeValue:specifier:)
                                                         get:@selector(readVolumeValue)
                                                      detail:nil
                                                        cell:PSSliderCell
                                                        edit:nil];
    [sl setProperty:KVKeyVolume forKey:@"key"];
    [sl setProperty:KVDomain forKey:@"defaults"];
    [sl setProperty:@YES forKey:@"showValue"];
    [sl setProperty:@0.0f forKey:@"min"];
    [sl setProperty:@1.0f forKey:@"max"];
    [specs addObject:sl];

    PSSpecifier *g2 = [PSSpecifier groupSpecifierWithName:@"诊断"];
    [g2 setProperty:@"先在上面看状态。真实按键声是否挂上，以「已挂钩 N 个入口」为准。"
            forKey:@"footerText"];
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

    return specs;
}

#pragma mark - 偏好读写

- (id)readEnabledValue {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:KVDomain];
    if ([d objectForKey:KVKeyEnabled] == nil) return @YES;
    return @([d boolForKey:KVKeyEnabled]);
}

- (void)setEnabledValue:(id)value specifier:(PSSpecifier *)spec {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:KVDomain];
    [d setBool:[value boolValue] forKey:KVKeyEnabled];
    DiagLog(@"开关 -> %@", value);
}

- (id)readVolumeValue {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:KVDomain];
    id v = [d objectForKey:KVKeyVolume];
    if (![v isKindOfClass:[NSNumber class]]) return @1.0f;
    return @([(NSNumber *)v floatValue]);
}

- (void)setVolumeValue:(id)value specifier:(PSSpecifier *)spec {
    float f = [value floatValue];
    if (f < 0.0f) f = 0.0f;
    if (f > 1.0f) f = 1.0f;
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:KVDomain];
    [d setFloat:f forKey:KVKeyVolume];
    DiagLog(@"音量 -> %.2f", f);
}

- (void)showDiag {
    DiagLog(@"点击了查看插件状态");
    dispatch_async(dispatch_get_main_queue(), ^{
        NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:KVDomain];
        NSString *diag = [d stringForKey:KVKeyDiag];
        NSString *msg = diag.length
            ? diag
            : @"还没有状态。请先去备忘录或微信的输入框打几个字，再回来看。";
        UIAlertController *a =
            [UIAlertController alertControllerWithTitle:@"插件状态"
                                                message:msg
                                         preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    });
}

@end