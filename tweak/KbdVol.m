// KbdVol.m —— 独立键盘打字声音音量（不受静音拨片 / 系统音量影响）
//
// 原理：
//   系统键盘的"哒哒"声由 UIKit 私有类（UIKeyboardSound / UIKeyboardLayout 一族）在
//   每次按键时播放。我们把这些播放入口接管，改为用 AVAudioPlayer 以自定音量重播。
//   音量 = 100% 时直接放行原实现（零延迟、零音色差异）；音量 < 100% 时才接管。
//   音量 = 0% 就是"不打字声"，而且不需要拨静音拨片、不影响来电/通知。
//
// 稳健性：
//   · 不硬编码类名 —— 运行时扫描类名含 "Keyboard" 的类，按已知 selector 名单挂钩，
//     iOS 小版本改名/增减时最多是"没钩到"（退化到原样），不会崩、不会误伤别的类。
//   · 找不到系统键盘音文件时**根本不装 hook**，宁可不做也不把用户搞成"永久哑巴"。

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#include <substrate.h>
#include <pthread.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include "KbdCommon.h"

// ---------------------------------------------------------------- 偏好读取

static float   gCachedVol   = 1.0f;
static BOOL    gCachedOn    = YES;
static NSTimeInterval gCachedAt = 0;

// 偏好读写：走 NSUserDefaults 的 suite，和设置面板写的是同一个域。
// （不用 CFPreferencesSetValue —— 16.5 SDK 上它是 5 参数版本，写错会直接编译失败。）
static NSUserDefaults *KvbDefaults(void) {
    static NSUserDefaults *d = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = [[NSUserDefaults alloc] initWithSuiteName:KVDomain];
    });
    return d;
}

static BOOL KvbEnabled(void) {
    NSUserDefaults *d = KvbDefaults();
    if ([d objectForKey:KVKeyEnabled] == nil) return YES;   // 没写过 = 默认开
    return [d boolForKey:KVKeyEnabled];
}

static float KvbVolume(void) {
    NSUserDefaults *d = KvbDefaults();
    id v = [d objectForKey:KVKeyVolume];
    if (![v isKindOfClass:[NSNumber class]]) return 1.0f;   // 没写过 = 默认 100%
    float f = (float)[(NSNumber *)v doubleValue];
    if (f < 0.0f) f = 0.0f;
    if (f > 1.0f) f = 1.0f;
    return f;
}

static void KvbSetDiag(NSString *s) {
    NSUserDefaults *d = KvbDefaults();
    [d setObject:s forKey:KVKeyDiag];
    [d synchronize];

    // 同时落盘：App 一关偏好还在，但"哪个进程挂了几个"的信息会覆盖，
    // 落盘文件能保留最后一次真实结果，用户可以直接把文件发回来。
    NSString *path = @"/var/mobile/Documents/KbdVol-hooks.txt";
    NSError *err = nil;
    NSString *text = [NSString stringWithFormat:@"%@\n\n=== %@ ===\n%@\n",
                      [NSDate date], [[NSProcessInfo processInfo] processName], s];
    if (![text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
        NSLog(@"[KbdVol] diag write failed: %@", err);
    }
    NSLog(@"[KbdVol] %@", s);
}

// 每秒最多刷新一次，避免每次按键都走 cfprefsd
static void KvbRefreshIfStale(void) {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - gCachedAt < 1.0) return;
    gCachedAt = now;
    gCachedOn  = KvbEnabled();
    gCachedVol = KvbVolume();
}

// ---------------------------------------------------------------- 音色判定

static KbdTone KvbToneForSelector(const char *name) {
    if (name == NULL) return KbdToneClick;
    if (strstr(name, "Delete") != NULL) return KbdToneDelete;
    if (strstr(name, "Modifier") != NULL || strstr(name, "Shift") != NULL
        || strstr(name, "Caps") != NULL || strstr(name, "Space") != NULL) return KbdToneModifier;
    return KbdToneClick;
}

// 已知的键盘音播放入口。宁可少列也不要列错 —— 列错会钩到不相关的类。
static BOOL KvbIsTargetSelector(const char *n) {
    if (n == NULL) return NO;
    static const char *names[] = {
        "playInputClick",
        "playInputClickWithSound:",
        "playInputClickWithType:",
        "playDeleteClick",
        "playDeleteClickWithSound:",
        "playModifierClick",
        "playKeyClickSound",
        "playClickSound",
        "playKeyboardClick",
    };
    int cnt = (int)(sizeof(names) / sizeof(names[0]));
    for (int i = 0; i < cnt; i++) {
        if (strcmp(n, names[i]) == 0) return YES;
    }
    return NO;
}

// ---------------------------------------------------------------- 接管逻辑

static void KvbFire(id self, SEL cmd, IMP orig, id arg) {
    KvbRefreshIfStale();

    // 音量满 且 开关开 —— 放行系统原声，不做任何事
    if (!gCachedOn || gCachedVol >= 0.999f) {
        if (orig != NULL) ((void (*)(id, SEL, id))orig)(self, cmd, arg);
        return;
    }

    // 接管：0% 时 playVolume 直接返回（= 静音打字声）；>0% 按设定音量重播
    [KbdAudio playVolume:gCachedVol tone:KvbToneForSelector(sel_getName(cmd))];
}

// ---------------------------------------------------------------- 挂钩安装

static NSMutableArray *gBlockKeepalive = nil;
static NSUInteger gHookCount = 0;
static NSUInteger gKeyboardClassCount = 0;   // 名字含 Keyboard 的类有几个
static NSUInteger gSelectorSeen = 0;         // 匹配上 selector 名单的有几个

static void KvbHookOneClass(Class cls, BOOL classMethod, NSMutableString *log) {
    Class target = classMethod ? object_getClass(cls) : cls;
    const char *cn = class_getName(cls);

    unsigned int mcount = 0;
    Method *methods = class_copyMethodList(target, &mcount);
    if (methods == NULL) return;

    for (unsigned int i = 0; i < mcount; i++) {
        SEL sel = method_getName(methods[i]);
        const char *sn = sel_getName(sel);
        if (!KvbIsTargetSelector(sn)) continue;
        gSelectorSeen++;

        __block IMP orig = NULL;
        SEL keepSel = sel;
        id blk = ^(__unsafe_unretained id s, SEL c, id a) {
            (void)s;
            KvbFire(s, c, orig, a);
        };
        IMP newIMP = imp_implementationWithBlock(blk);
        // imp_implementationWithBlock 内部会 copy 一份，但保险起见我们自己再持有原始 block
        [gBlockKeepalive addObject:blk];

        // 注意：MSHookMessageEx 返回 void，成功与否看 orig 有没有被填上
        MSHookMessageEx(target, keepSel, newIMP, &orig);
        if (orig != NULL) {
            NSString *kind = classMethod ? @" (class)" : @"";
            [log appendFormat:@"%@ %@%@\n", [NSString stringWithUTF8String:cn],
                                          [NSString stringWithUTF8String:sn], kind];
            gHookCount++;
        }
    }
    free(methods);
}

static void KvbInstallHooks(void) {
    @autoreleasepool {
        // 设置进程绝对不碰：向 com.apple.Preferences 注入会触发看门狗 0x8BADF00D
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
        if ([bid isEqualToString:@"com.apple.Preferences"]) return;

        [KbdAudio prepare];

        NSString *path = [KbdAudio loadedPath];

        // 找不到音色文件 —— 不装任何 hook，一切保持系统原样
        if (path == nil) {
            KvbSetDiag(@"KbdVol: 未找到系统键盘音文件，本进程未挂钩（保持系统原样）");
            return;
        }

        gBlockKeepalive = [NSMutableArray array];
        gHookCount = 0;
        gKeyboardClassCount = 0;
        gSelectorSeen = 0;
        NSMutableString *log = [NSMutableString string];

        // iOS 上objc_copyClassList 是单参数版本：只传 outCount，返回的数组以 NULL 结尾
        unsigned int count = 0;
        Class *classes = objc_copyClassList(&count);
        if (classes == NULL) {
            KvbSetDiag(@"KvbInstallHooks: objc_copyClassList 返回空，无法扫描");
            return;
        }

        for (unsigned int i = 0; i < count; i++) {
            if (classes[i] == NULL) continue;
            const char *cn = class_getName(classes[i]);
            if (cn == NULL) continue;
            // 只碰键盘相关类，避免误伤
            if (strstr(cn, "Keyboard") == NULL) continue;
            gKeyboardClassCount++;
            KvbHookOneClass(classes[i], NO, log);
            KvbHookOneClass(classes[i], YES, log);
        }
        free(classes);

        NSUInteger hooked = gHookCount;
        NSString *detail = (hooked > 0)
            ? [NSString stringWithFormat:@"%lu 个入口：\n%@", (unsigned long)hooked, log]
            : @"(未挂上播放入口)";

        // 三种失败要能区分开，否则用户只看到"没生效"，无从下手：
        //   A. 没找到任何 Keyboard 类   → 过滤条件太严
        //   B. 找到类但没匹配到 selector → selector 名单太窄（iOS 改名了）
        //   C. 匹配到但MSHookMessageEx 没填 orig → hook 失败
        NSString *verdict = nil;
        if (hooked > 0) {
            verdict = @"正常";
        } else if (gKeyboardClassCount == 0) {
            verdict = @"失败A：没扫描到任何名字含 Keyboard 的类";
        } else if (gSelectorSeen == 0) {
            verdict = [NSString stringWithFormat:
                       @"失败B：扫到 %lu 个键盘类，但没有方法名匹配 selector 名单"
                       @"（iOS 可能改了私有 API 名，需要更新名单）",
                       (unsigned long)gKeyboardClassCount];
        } else {
            verdict = [NSString stringWithFormat:
                       @"失败C：%lu 个方法名匹配了，但 MSHookMessageEx 都没挂上",
                       (unsigned long)gSelectorSeen];
        }

        NSString *diag = [NSString stringWithFormat:
            @"音色：%@\n已挂钩 %lu 个入口\n键盘类：%lu 个 · 匹配方法：%lu 个\n结论：%@\n%@",
            [path lastPathComponent], (unsigned long)hooked,
            (unsigned long)gKeyboardClassCount, (unsigned long)gSelectorSeen,
            verdict, detail];

        KvbSetDiag(diag);
    }
}

// ---------------------------------------------------------------- 启动

// ⚠️ %ctor 里只起线程，绝不做重活（会拖死宿主 App 的启动看门狗 0x8BADF00D）
static void *KvbWorker(void *arg) {
    (void)arg;
    sleep(1);
    @autoreleasepool { KvbInstallHooks(); }
    return NULL;
}

__attribute__((constructor))
static void KvbInit(void) {
    pthread_attr_t attr;
    if (pthread_attr_init(&attr) != 0) return;
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_t th;
    (void)pthread_create(&th, &attr, KvbWorker, NULL);
    pthread_attr_destroy(&attr);
}