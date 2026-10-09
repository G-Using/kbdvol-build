// KbdVol - 独立键盘打字声音音量
// 共享声明（tweak 与设置面板共用；只含 ObjC 声明，无 C 符号，无需 extern "C"）

#import <Foundation/Foundation.h>

#define KVDomain @"com.gusing.kbdvol"

// 偏好键
#define KVKeyEnabled  @"enabled"        // BOOL，默认 YES
#define KVKeyVolume   @"volume"         // Double 0.0~1.0，默认 1.0
#define KVKeyForce    @"forceInSilent"  // BOOL，默认 NO
#define KVKeyDiag     @"lastDiag"       // String，tweak 写入、面板显示

// 播放音色
typedef NS_ENUM(NSInteger, KbdTone) {
    KbdToneClick = 0,
    KbdToneDelete = 1,
    KbdToneModifier = 2
};

@interface KbdAudio : NSObject
// 系统键盘音文件是否可用（不可用时 tweak 不装 hook，保持系统原样，绝不"变哑巴"）
+ (BOOL)available;
+ (NSString *)loadedPath;
// 后台预热（加载 caf、prepareToPlay），可在任意线程调
+ (void)prepare;
// 按音量播放一次；vol<=0 时静默不播
+ (void)playVolume:(float)vol tone:(KbdTone)tone;
@end