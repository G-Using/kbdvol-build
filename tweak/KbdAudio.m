// KbdAudio.m —— 用 AVAudioPlayer 重播系统键盘音，音量完全由我们决定。
// 不改宿主 App 的 AVAudioSession category，避免打断它正在播的媒体音。

#import "KbdCommon.h"
#import <AVFoundation/AVFoundation.h>

// 候选音色文件：优先 iOS 10+ 的 key_press_*，回落到老的 Tock.caf
static NSString *KbdTonePath(KbdTone tone) {
    static NSArray *paths = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        paths = @[
            @"/System/Library/Audio/UISounds/key_press_click.caf",     // 0 普通键
            @"/System/Library/Audio/UISounds/key_press_delete.caf",   // 1 删除键
            @"/System/Library/Audio/UISounds/key_press_modifier.caf", // 2 修饰键
        ];
    });
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *want = (tone >= 0 && tone <= 2) ? paths[(NSUInteger)tone] : paths[0];
    if ([fm fileExistsAtPath:want]) return want;
    // 指定音色缺失：回落 Tock.caf，再不行返回 nil（调用方放弃播放、保留静音结果）
    NSString *fallback = @"/System/Library/Audio/UISounds/Tock.caf";
    if ([fm fileExistsAtPath:fallback]) return fallback;
    return nil;
}

@implementation KbdAudio

// 4 个播放器轮转，快速连按不互相打断
#define KVD_POOL 4
static AVAudioPlayer *gPool[KVD_POOL];
static NSInteger gNext = 0;
static BOOL gPrepared = NO;
static NSString *gLoadedPath = nil;

// 已用音量缓存：只有音量/音色变化时才写回播放器
static float gCurVol = -1.0f;

+ (BOOL)available {
    return KbdTonePath(KbdToneClick) != nil;
}

+ (NSString *)loadedPath {
    @synchronized (self) { return gLoadedPath; }
}

+ (void)prepare {
    @synchronized (self) {
        if (gPrepared) return;
        NSString *p = KbdTonePath(KbdToneClick);
        if (p == nil) {
            // 一个音色文件都没有：标记成"已准备"，播放时直接返回，不崩
            gPrepared = YES;
            gLoadedPath = nil;
            return;
        }
        NSError *err = nil;
        for (int i = 0; i < KVD_POOL; i++) {
            gPool[i] = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:p]
                                                             error:&err];
            if (gPool[i] != nil) {
                [gPool[i] prepareToPlay];
                gPool[i].volume = 0.0f;
            }
        }
        gLoadedPath = p;
        gPrepared = YES;
    }
}

+ (void)playVolume:(float)vol tone:(KbdTone)tone {
    if (vol <= 0.001f) return;              // 0 = 完全不打字声（核心诉求）
    [self prepare];

    @synchronized (self) {
        if (gLoadedPath == nil) return;     // 无可用音色：静默（音量已由我们接管，原声不会再响）

        // 音色不同 → 重新加载
        NSString *want = KbdTonePath(tone);
        if (want != nil && ![want isEqualToString:gLoadedPath]) {
            NSError *err = nil;
            for (int i = 0; i < KVD_POOL; i++) {
                gPool[i] = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:want]
                                                                 error:&err];
                if (gPool[i] != nil) [gPool[i] prepareToPlay];
            }
            gLoadedPath = want;
            gCurVol = -1.0f;
        }

        if (vol != gCurVol) {
            for (int i = 0; i < KVD_POOL; i++) gPool[i].volume = vol;
            gCurVol = vol;
        }

        AVAudioPlayer *p = gPool[gNext];
        gNext = (gNext + 1) % KVD_POOL;
        if (p == nil) return;
        p.currentTime = 0.0;
        [p play];
    }
}

@end