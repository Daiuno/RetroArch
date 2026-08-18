//
//  LibretroCore.h
//  LibretroCore
//
//  Created by Daiuno on 2025/4/22.
//  Copyright © 2025 Manic EMU. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "CheevosBridge.h"
#import "AzaharKeyboardConfig.h"
#import "LibretroShaders.h"
#import "LibretroKeyboardCode.h"
#import "LibretroCoreOptions.h"
#import "LibretroDisk.h"
#import "LibretroPSPGame.h"
#import "LibretroHost.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, LibretroButton) {
   LibretroButtonUp = 4,
   LibretroButtonDown = 5,
   LibretroButtonLeft = 6,
   LibretroButtonRight = 7,
   LibretroButtonA = 8,
   LibretroButtonB = 0,
   LibretroButtonX = 9,
   LibretroButtonY = 1,
   LibretroButtonSelect = 2,
   LibretroButtonStart = 3,
   LibretroButtonL1 = 10,
   LibretroButtonR1 = 11,
   LibretroButtonL2 = 12,
   LibretroButtonR2 = 13,
   LibretroButtonL3 = 14,
   LibretroButtonR3 = 15,
};

extern NSString * const RetroAchievementsNotification;
/// 联机事件通知, userInfo: @{@"event": @(LibretroNetplayEvent), @"info": NSString(相关昵称, 可能为空串)}
extern NSString * const LibretroNetplayEventNotification;

/// 联机事件(与 netplay.h 中 enum netplay_frontend_event 一一对应)
typedef NS_ENUM(NSInteger, LibretroNetplayEvent) {
    /// 本机作为主机启动完成
    LibretroNetplayEventHostStarted = 0,
    /// 本机主机停止
    LibretroNetplayEventHostStopped,
    /// 作为客户端连接到主机(info=主机昵称)
    LibretroNetplayEventConnected,
    /// 作为客户端与主机断开
    LibretroNetplayEventDisconnected,
    /// 主机侧:有客户端接入(info=对方昵称)
    LibretroNetplayEventPeerConnected,
    /// 主机侧:客户端断开(info=对方昵称)
    LibretroNetplayEventPeerDisconnected,
    /// 有玩家加入游玩(info=昵称, 空串表示本机)
    LibretroNetplayEventPeerJoined,
    /// 有玩家退出游玩转为观战(info=昵称, 空串表示本机)
    LibretroNetplayEventPeerLeft,
};

@interface LibretroCore : NSObject

@property(nonatomic, strong) id retroArch_iOS;
@property (nonatomic, copy, nullable) NSString *workspace;
@property (assign) BOOL forbitJIT;

+ (instancetype)sharedInstance;

- (UIViewController *)startWithCustomSaveDir:(NSString *_Nullable)customSaveDir;
- (void)pause;
- (BOOL)isPaused;
- (void)resume;
- (void)stop;
- (void)mute:(BOOL)mute;
- (void)snapshot:(void(^ _Nullable)(UIImage *_Nullable image))completion;
- (BOOL)saveState:(void(^ _Nullable)(NSString *_Nullable path))completion;
- (BOOL)loadState:(NSString *_Nonnull)path;
- (void)fastForward:(float)rate;
/// 开启或关闭回朔功能(开启后开始在后台记录快照,有内存与CPU开销)
/// @param granularity 回朔帧数(每隔多少帧记录一个快照,回朔时每步跨越的帧数),默认 10
/// @param bufferSizeMB 回朔缓冲区大小(MB),默认 20
/// @param bufferSizeStepMB 回朔缓冲区大小调整步长(MB),默认 10
/// @param mute 回朔时是否静音,默认 NO
- (void)setRewindEnable:(BOOL)enable
            granularity:(unsigned)granularity
           bufferSizeMB:(unsigned)bufferSizeMB
       bufferSizeStepMB:(unsigned)bufferSizeStepMB
                   mute:(BOOL)mute;
/// 便捷方法,使用默认参数:granularity=10, bufferSizeMB=20, bufferSizeStepMB=10, mute=NO
- (void)setRewindEnable:(BOOL)enable;
/// 开始(YES,按住语义)或结束(NO)回朔,需先开启回朔功能
- (void)setRewind:(BOOL)rewinding;
- (void)reload;
- (void)reloadByKeepState:(BOOL)keepState;
- (BOOL)loadGame:(NSString *_Nonnull)gamePath corePath:(NSString *_Nonnull)corePath completion:(void(^ _Nullable)(NSDictionary *_Nullable))completion;
- (void)loadCoreWithoutContent:(NSString *_Nonnull)corePath;
- (void)loadCoreWithoutRunning:(NSString *_Nonnull)corePath;
- (NSArray<CoreOptionCategory *> *_Nullable)getCoreOptions:(NSString *_Nonnull)corePath;
- (void)sendEvent:(UIEvent * _Nonnull)event;
- (void)pressButton:(LibretroButton)button playerIndex:(unsigned)playerIndex;
- (void)releaseButton:(LibretroButton)button playerIndex:(unsigned)playerIndex;
- (void)pressKeyboard:(LibretroKeyboardCode *_Nonnull)keyboardCode;
- (void)releaseKeyboard:(LibretroKeyboardCode *_Nonnull)keyboardCode;
- (void)handleUIPress:(UIPress *)press withEvent:(UIPressesEvent *)event down:(BOOL)down;
- (void)keyboardEvent:(UIEvent *_Nonnull)event;
///x,y取值范围 -1~1
- (void)moveStick:(BOOL)isLeft x:(CGFloat)x y:(CGFloat)y playerIndex:(unsigned)playerIndex;
- (void)updatePSPCheat:(NSString *_Nonnull)cheatCode cheatFilePath:(NSString *_Nonnull)cheatFilePath reloadGame:(BOOL)reloadGame;
- (void)updateCoreConfig:(NSString *_Nonnull)coreName key:(NSString *_Nonnull)key value:(NSString *_Nonnull)value reload:(BOOL)reload;
- (void)updateCoreConfig:(NSString *_Nonnull)coreName configs:(NSDictionary<NSString*, NSString*> *_Nullable)configs reload:(BOOL)reload;
- (void)updateCoreConfig:(NSString *_Nonnull)coreName content:(NSString *_Nullable)content reload:(BOOL)reload;
- (void)updateRunningCoreConfigs:(NSDictionary<NSString*, NSString*> *_Nullable)configs flush:(BOOL)flush;
- (void)updateLibretroConfig:(NSString *_Nonnull)key value:(NSString *_Nonnull)value;
- (void)updateLibretroConfigs:(NSDictionary<NSString*, NSString*> *_Nullable)configs;
/// 写入当前进程内的 RetroArch 运行时 settings, 立刻生效, 不写 retroarch.cfg
- (void)updateRuningLibretroConfigs:(NSDictionary<NSString*, NSString*> *_Nullable)configs;
- (BOOL)setShader:(NSString *_Nullable)path;
- (NSArray<ShaderParameter *> *_Nullable)loadParameters;
- (void)updateParameterWith:(NSString *_Nonnull)identifier
                      value:(float)value
               changingPath:(NSString *_Nonnull)changingPath;
- (void)appendShader:(NSString *_Nonnull)path prepend:(BOOL)prepend;
- (void)addCheatCode:(NSString *_Nonnull)code index:(unsigned)index enable:(BOOL)enable;
- (void)resetCheatCode;
+ (BOOL)JITAvailable;
- (NSString * _Nullable)coreConfigValue:(NSString * _Nonnull)coreName key:(NSString * _Nonnull)key;
- (NSString * _Nullable)libretroConfigValue:(NSString * _Nonnull)key;
- (void)setRespectSilentMode:(BOOL)respect;
- (void)setDiskIndex:(unsigned)index delay:(BOOL)delay;
- (void)setDiskIndex2:(unsigned)index;
- (LibretroDisk *_Nullable)getDiskInfo;
- (BOOL)insertDisk:(NSString *_Nonnull)path;
- (void)setPSXAnalog:(BOOL)isAnalog;
- (void)setReloadDelay:(double)delay;
- (void)turnOffHardcode;
- (void)resetRetroAchievements;
- (void)setCustomSaveExtension:(NSString *_Nullable)customSaveExtension;
- (void)setEnableRumble:(BOOL)enable;
- (BOOL)getSensorEnable:(int)playerIndex;
- (void)startWFCStatusMonitor;
- (void)setNDSCustomLayout:(NSString *_Nullable)layout;
- (void)setNDSWFCDNS:(NSString *_Nullable)nds;
- (void)setPSPCustomServerAddress:(NSString *_Nullable)address;
- (void)setPSPCustomServerPort:(NSString *_Nullable)port;
- (void)setCoreOptionNeedsUpdate;
- (void)sendTouchEventX:(CGFloat)x y:(CGFloat)y;
- (void)releaseTouchEvent;
- (void)sendMultiTouchEvent:(NSArray<NSDictionary *> *)points;
- (NSString *_Nullable)getCoreConfigs:(NSString *_Nonnull)coreName;
- (void)updateFBNeoCheatCode:(NSArray<NSString *> *_Nonnull)keys enable:(BOOL)enable;
- (void)setFastforwardFrameSkip:(BOOL)frameSkip;
- (void)set3DSCustomLayout:(NSString *_Nullable)layout;
- (void)setLibretroLogMonitor:(BOOL)enable;
- (void)loadAmiibo:(NSString *_Nonnull)path;
- (BOOL)isSearchingAmiibo;
- (void)registerAzaharKeyboard:(void(^ _Nullable)(AzaharKeyboardConfig *_Nonnull config))callback;
- (void)inputAzaharKeyboard:(NSString *_Nullable)text buttonType:(AzaharButtonType)buttonType;
- (void)installAzaharCIA:(NSString *_Nonnull)path;
+ (NSString *_Nullable)getPSPGameIDWithRomPath:(NSString *_Nonnull)romPath;
+ (LibretroPSPGame *_Nullable)installPSPGameWithZipPath:(NSString *_Nonnull)zipPath destDir:(NSString *_Nonnull)destDir;
- (void)setFullScreen:(BOOL)isFullScreen;
+ (UIImage *_Nullable)previewImageWithImage:(UIImage *_Nonnull)image shaderPath:(NSString *_Nonnull)shaderPath;
+ (void)clearPreviewCache;

#pragma mark - 联机(Netplay)
/// 作为游戏主机开启联机(需已加载游戏, 会重载游戏内容)
/// @param nickname 联机昵称, 局域网/大厅发现时展示; 空则沿用当前配置(未设置时为 Anonymous)
/// 结果通过 LibretroNetplayEventNotification 的 HostStarted 事件回调
- (BOOL)startNetplayHost:(NSString * _Nullable)nickname;
/// 停止联机主机
- (void)stopNetplayHost;
/// 刷新互联网联机主机列表(异步, 主线程回调; 失败时 hosts 为 nil)
- (void)refreshNetplayHostList:(void(^ _Nullable)(NSArray<LibretroHost *> * _Nullable hosts))completion;
/// 刷新局域网联机主机列表(异步, 主线程回调, 约 2.5s 扫描超时; 失败时 hosts 为 nil)
- (void)refreshNetplayLANHostList:(void(^ _Nullable)(NSArray<LibretroHost *> * _Nullable hosts))completion;
/// 作为客户端连接到指定主机(需已加载与主机相同的游戏和核心)
/// @param nickname 本机联机昵称, 主机侧会看到; 空则沿用当前配置(未设置时为 Anonymous)
/// 结果通过 LibretroNetplayEventNotification 的 Connected/Disconnected 事件回调
- (BOOL)connectToNetplayHost:(LibretroHost *_Nonnull)host nickname:(NSString * _Nullable)nickname;
/// 断开当前联机(客户端断开连接/主机停止, 等价于 stopNetplayHost)
- (void)disconnectNetplay;
/// 当前已加载的核心是否支持联机(需在加载游戏后调用)
- (BOOL)currentCoreSupportsNetplay;

@end

NS_ASSUME_NONNULL_END
