//
//  LibretroCore.m
//  LibretroCore
//
//  Created by Daiuno on 2025/4/22.
//  Copyright © 2025 Manic EMU. All rights reserved.
//

#import "LibretroCore.h"
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

#include <boolean.h>

#include <file/file_path.h>
#include <queues/task_queue.h>
#include <string/stdstring.h>
#include <retro_timers.h>

#include "cocoa/cocoa_common.h"
#include "cocoa/apple_platform.h"
#include "../ui_companion_driver.h"
#include "../../audio/audio_driver.h"
#include "../../configuration.h"
#include "../../frontend/frontend.h"
#include "../../input/drivers/cocoa_input.h"
#include "../../input/drivers_keyboard/keyboard_event_apple.h"
#include "../../retroarch.h"
#include "../../tasks/task_content.h"
#include "../../verbosity.h"

#ifdef HAVE_MENU
#include "../../menu/menu_setting.h"
#endif

#import <AVFoundation/AVFoundation.h>
#import <CoreFoundation/CoreFoundation.h>

#import <MetricKit/MetricKit.h>
#import <MetricKit/MXMetricManager.h>

#ifdef HAVE_MFI
#import <GameController/GCMouse.h>
#endif

#ifdef HAVE_SDL2
#define SDL_MAIN_HANDLED
#include "SDL.h"
#endif

#import "JITSupport.h"
#include "../../cheevos/cheevos.h"
#include "../../deps/rcheevos/include/rc_client.h"

NSString * const RetroAchievementsNotification = @"RetroAchievementsNotification";
NSString * const LibretroDidShutdownNotification = @"LibretroDidShutdownNotification";
NSString * const DidConnectToWFCNotification = @"DidConnectToWFCNotification";
NSString * const DidDisconnectFromWFCNotification = @"DidDisconnectFromWFCNotification";
NSString * const MAMEGameFileMissingNotification = @"MAMEGameFileMissingNotification";

@interface LibretroCore()

@property (assign) BOOL isRunning;
@property (assign) unsigned keyboardMods;

@end

@implementation LibretroCore

+ (instancetype)sharedInstance {
    static LibretroCore *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
        instance.retroArch_iOS = [RetroArch_iOS new];
    });
    return instance;
}

// 可选：重写 allocWithZone，防止外部 alloc init 创建新实例
+ (id)allocWithZone:(struct _NSZone *)zone {
    static LibretroCore *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [super allocWithZone:zone];
    });
    return instance;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    return self;
}

- (UIViewController *)startWithCustomSaveDir:(NSString *_Nullable)customSaveDir {
    self.isRunning = YES;
    [[self getRetroArch] startWithCustomSaveDir:customSaveDir];
    cheevos_event_register_callback(cheevosDidTrigger);
    shutdown_register_callback(shutdownCallback);
    log_register_callback(libretroLogCallback);
    return [CocoaView get];
}

- (void)pause {
    [[self getRetroArch] pause];
}

- (void)resume {
    [[self getRetroArch] resume];
}

- (void)stop {
    self.isRunning = NO;
    cheevos_event_register_callback(NULL);
    shutdown_register_callback(NULL);
    wfc_status_register_callback(NULL);
    log_register_callback(NULL);
    g_enableMonitorLibretroLog = NO;
    [self registerAzaharKeyboard:nil];
    [[self getRetroArch] stop];
}

- (void)mute:(BOOL)mute {
    [[self getRetroArch] mute:mute];
}

- (void)snapshot:(void(^ _Nullable)(UIImage *_Nullable image))completion {
#if !TARGET_IPHONE_SIMULATOR
    [[self getRetroArch] snapshot:completion];
#else
    if (completion) {
        completion(nil);
    }
#endif
    
}

- (BOOL)saveState:(void(^ _Nullable)(NSString *_Nullable path))completion {
    return [[self getRetroArch] saveState:completion];
}

- (BOOL)loadState:(NSString *_Nonnull)path {
    return [[self getRetroArch] loadState:path];
}

- (void)fastForward:(float)rate {
    [[self getRetroArch] fastForward:rate];
}

- (void)reload {
    [[self getRetroArch] reload];
}

- (void)reloadByKeepState:(BOOL)keepState {
    [[self getRetroArch] reloadByKeepState:keepState];
}

- (BOOL)loadGame:(NSString *_Nonnull)gamePath corePath:(NSString *_Nonnull)corePath completion:(void(^ _Nullable)(NSDictionary *_Nullable))completion {
    return [[self getRetroArch] loadGame:gamePath corePath:corePath completion:completion];
}

- (void)loadCoreWithoutContent:(NSString *_Nonnull)corePath {
    [[self getRetroArch] loadCoreWithoutContent:corePath];
}

- (void)loadCoreWithoutRunning:(NSString *_Nonnull)corePath {
    [[self getRetroArch] loadCoreWithoutRunning:corePath];
}

- (NSArray<CoreOptionCategory *> *_Nullable)getCoreOptions:(NSString *_Nonnull)corePath {
    return [[self getRetroArch] getCoreOptions:corePath];
}

- (void)pressButton:(LibretroButton)button playerIndex:(unsigned)playerIndex {
    [[self getRetroArch] pressButton:(unsigned)button playerIndex:playerIndex];
}

- (void)releaseButton:(LibretroButton)button playerIndex:(unsigned)playerIndex {
    [[self getRetroArch] releaseButton:(unsigned)button playerIndex:playerIndex];
}

- (void)pressKeyboard:(LibretroKeyboardCode *_Nonnull)keyboardCode {
    // 先更新修饰键状态
    if (keyboardCode.code == RETROK_LSHIFT || keyboardCode.code == RETROK_RSHIFT) {
        _keyboardMods |= RETROKMOD_SHIFT;
    } else if (keyboardCode.code == RETROK_LCTRL || keyboardCode.code == RETROK_RCTRL) {
        _keyboardMods |= RETROKMOD_CTRL;
    } else if (keyboardCode.code == RETROK_LALT || keyboardCode.code == RETROK_RALT) {
        _keyboardMods |= RETROKMOD_ALT;
    }
    
    // 再发送键盘事件（包含更新后的修饰键状态）
    apple_direct_input_keyboard_event(true, keyboardCode.code, 0, _keyboardMods, RETRO_DEVICE_KEYBOARD);
}

- (void)releaseKeyboard:(LibretroKeyboardCode *_Nonnull)keyboardCode {
    // 先清除修饰键状态（使用按位取反）
    if (keyboardCode.code == RETROK_LSHIFT || keyboardCode.code == RETROK_RSHIFT) {
        _keyboardMods &= ~RETROKMOD_SHIFT;
    } else if (keyboardCode.code == RETROK_LCTRL || keyboardCode.code == RETROK_RCTRL) {
        _keyboardMods &= ~RETROKMOD_CTRL;
    } else if (keyboardCode.code == RETROK_LALT || keyboardCode.code == RETROK_RALT) {
        _keyboardMods &= ~RETROKMOD_ALT;
    }
    
    // 再发送键盘事件（包含更新后的修饰键状态）
    apple_direct_input_keyboard_event(false, keyboardCode.code, 0, _keyboardMods, RETRO_DEVICE_KEYBOARD);
}

- (void)handleUIPress:(UIPress *)press withEvent:(UIPressesEvent *)event down:(BOOL)down {
   NSString       *ch;
   uint32_t character = 0;
   uint32_t mod       = 0;
   NSUInteger mods    = 0;
   if (@available(iOS 13.4, tvOS 13.4, *))
   {
      ch = (NSString*)press.key.characters;
      mods = event.modifierFlags;
   }

   if (mods & UIKeyModifierAlphaShift)
      mod |= RETROKMOD_CAPSLOCK;
   if (mods & UIKeyModifierShift)
      mod |= RETROKMOD_SHIFT;
   if (mods & UIKeyModifierControl)
      mod |= RETROKMOD_CTRL;
   if (mods & UIKeyModifierAlternate)
      mod |= RETROKMOD_ALT;
   if (mods & UIKeyModifierCommand)
      mod |= RETROKMOD_META;
   if (mods & UIKeyModifierNumericPad)
      mod |= RETROKMOD_NUMLOCK;

   if (ch && ch.length != 0)
   {
      unsigned i;
      character = [ch characterAtIndex:0];

      apple_input_keyboard_event(down,
                                 (uint32_t)press.key.keyCode, 0, mod,
                                 RETRO_DEVICE_KEYBOARD);

      for (i = 1; i < ch.length; i++)
         apple_input_keyboard_event(down,
                                    0, [ch characterAtIndex:i], mod,
                                    RETRO_DEVICE_KEYBOARD);
   }

   if (@available(iOS 13.4, tvOS 13.4, *))
      apple_input_keyboard_event(down,
                                 (uint32_t)press.key.keyCode, character, mod,
                                 RETRO_DEVICE_KEYBOARD);
}

- (void)keyboardEvent:(UIEvent *_Nonnull)event {
    // 严格参考 DeltaCore KeyboardResponder.swift 实现
    // 通过 KVC 从私有字段直接读取
    NSNumber *keyCodeNum       = [event valueForKey:@"_keyCode"];
    NSNumber *isKeyDownNum     = [event valueForKey:@"_isKeyDown"];
    NSNumber *modifierFlagsNum = [event valueForKey:@"_modifierFlags"];
    NSString *unmodifiedInput  = [event valueForKey:@"_unmodifiedInput"];

    if (!keyCodeNum || !isKeyDownNum || !modifierFlagsNum) {
        return;
    }

    NSInteger hidKeyCode   = keyCodeNum.integerValue;
    BOOL isKeyDown         = isKeyDownNum.boolValue;
    NSInteger rawModifiers = modifierFlagsNum.integerValue;

    // ── 1. 计算 RETROKMOD 位掩码 ─────────────────────────────────────────
    static const NSInteger kShift   = 1 << 17; // UIKeyModifierShift
    static const NSInteger kCtrl    = 1 << 18; // UIKeyModifierControl
    static const NSInteger kAlt     = 1 << 19; // UIKeyModifierAlternate
    static const NSInteger kMeta    = 1 << 20; // UIKeyModifierCommand
    static const NSInteger kCapsLk  = 1 << 16; // UIKeyModifierAlphaShift

    uint32_t newMods = RETROKMOD_NONE;
    if (rawModifiers & kShift)  newMods |= RETROKMOD_SHIFT;
    if (rawModifiers & kCtrl)   newMods |= RETROKMOD_CTRL;
    if (rawModifiers & kAlt)    newMods |= RETROKMOD_ALT;
    if (rawModifiers & kMeta)   newMods |= RETROKMOD_META;
    if (rawModifiers & kCapsLk) newMods |= RETROKMOD_CAPSLOCK;

    // ── 2. HID Usage → RETROK 映射表（初始化一次）────────────────────────
    static unsigned hidToRetrok[0x200];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        memset(hidToRetrok, 0, sizeof(hidToRetrok));
        // 字母 a-z (HID 0x04–0x1D)
        hidToRetrok[0x04] = RETROK_a; hidToRetrok[0x05] = RETROK_b;
        hidToRetrok[0x06] = RETROK_c; hidToRetrok[0x07] = RETROK_d;
        hidToRetrok[0x08] = RETROK_e; hidToRetrok[0x09] = RETROK_f;
        hidToRetrok[0x0A] = RETROK_g; hidToRetrok[0x0B] = RETROK_h;
        hidToRetrok[0x0C] = RETROK_i; hidToRetrok[0x0D] = RETROK_j;
        hidToRetrok[0x0E] = RETROK_k; hidToRetrok[0x0F] = RETROK_l;
        hidToRetrok[0x10] = RETROK_m; hidToRetrok[0x11] = RETROK_n;
        hidToRetrok[0x12] = RETROK_o; hidToRetrok[0x13] = RETROK_p;
        hidToRetrok[0x14] = RETROK_q; hidToRetrok[0x15] = RETROK_r;
        hidToRetrok[0x16] = RETROK_s; hidToRetrok[0x17] = RETROK_t;
        hidToRetrok[0x18] = RETROK_u; hidToRetrok[0x19] = RETROK_v;
        hidToRetrok[0x1A] = RETROK_w; hidToRetrok[0x1B] = RETROK_x;
        hidToRetrok[0x1C] = RETROK_y; hidToRetrok[0x1D] = RETROK_z;
        // 数字 1-9, 0 (HID 0x1E–0x27)
        hidToRetrok[0x1E] = RETROK_1; hidToRetrok[0x1F] = RETROK_2;
        hidToRetrok[0x20] = RETROK_3; hidToRetrok[0x21] = RETROK_4;
        hidToRetrok[0x22] = RETROK_5; hidToRetrok[0x23] = RETROK_6;
        hidToRetrok[0x24] = RETROK_7; hidToRetrok[0x25] = RETROK_8;
        hidToRetrok[0x26] = RETROK_9; hidToRetrok[0x27] = RETROK_0;
        // 控制键
        hidToRetrok[0x28] = RETROK_RETURN;    // Return
        hidToRetrok[0x29] = RETROK_ESCAPE;    // Escape
        hidToRetrok[0x2A] = RETROK_BACKSPACE; // Backspace
        hidToRetrok[0x2B] = RETROK_TAB;       // Tab
        hidToRetrok[0x2C] = RETROK_SPACE;     // Space
        // 符号
        hidToRetrok[0x2D] = RETROK_MINUS;        // -
        hidToRetrok[0x2E] = RETROK_EQUALS;       // =
        hidToRetrok[0x2F] = RETROK_LEFTBRACKET;  // [
        hidToRetrok[0x30] = RETROK_RIGHTBRACKET; // ]
        hidToRetrok[0x31] = RETROK_BACKSLASH;    // backslash
        hidToRetrok[0x33] = RETROK_SEMICOLON;    // ;
        hidToRetrok[0x34] = RETROK_QUOTE;        // '
        hidToRetrok[0x35] = RETROK_BACKQUOTE;    // `
        hidToRetrok[0x36] = RETROK_COMMA;        // ,
        hidToRetrok[0x37] = RETROK_PERIOD;       // .
        hidToRetrok[0x38] = RETROK_SLASH;        // /
        // CapsLock
        hidToRetrok[0x39] = RETROK_CAPSLOCK;
        // F1–F12 (HID 0x3A–0x45)
        hidToRetrok[0x3A] = RETROK_F1;  hidToRetrok[0x3B] = RETROK_F2;
        hidToRetrok[0x3C] = RETROK_F3;  hidToRetrok[0x3D] = RETROK_F4;
        hidToRetrok[0x3E] = RETROK_F5;  hidToRetrok[0x3F] = RETROK_F6;
        hidToRetrok[0x40] = RETROK_F7;  hidToRetrok[0x41] = RETROK_F8;
        hidToRetrok[0x42] = RETROK_F9;  hidToRetrok[0x43] = RETROK_F10;
        hidToRetrok[0x44] = RETROK_F11; hidToRetrok[0x45] = RETROK_F12;
        // 导航区
        hidToRetrok[0x49] = RETROK_INSERT;   hidToRetrok[0x4A] = RETROK_HOME;
        hidToRetrok[0x4B] = RETROK_PAGEUP;   hidToRetrok[0x4C] = RETROK_DELETE;
        hidToRetrok[0x4D] = RETROK_END;      hidToRetrok[0x4E] = RETROK_PAGEDOWN;
        hidToRetrok[0x4F] = RETROK_RIGHT;    hidToRetrok[0x50] = RETROK_LEFT;
        hidToRetrok[0x51] = RETROK_DOWN;     hidToRetrok[0x52] = RETROK_UP;
        // 小键盘
        hidToRetrok[0x53] = RETROK_NUMLOCK;
        hidToRetrok[0x54] = RETROK_KP_DIVIDE;   hidToRetrok[0x55] = RETROK_KP_MULTIPLY;
        hidToRetrok[0x56] = RETROK_KP_MINUS;    hidToRetrok[0x57] = RETROK_KP_PLUS;
        hidToRetrok[0x58] = RETROK_KP_ENTER;
        hidToRetrok[0x59] = RETROK_KP1; hidToRetrok[0x5A] = RETROK_KP2;
        hidToRetrok[0x5B] = RETROK_KP3; hidToRetrok[0x5C] = RETROK_KP4;
        hidToRetrok[0x5D] = RETROK_KP5; hidToRetrok[0x5E] = RETROK_KP6;
        hidToRetrok[0x5F] = RETROK_KP7; hidToRetrok[0x60] = RETROK_KP8;
        hidToRetrok[0x61] = RETROK_KP9; hidToRetrok[0x62] = RETROK_KP0;
        hidToRetrok[0x63] = RETROK_KP_PERIOD;
        // PrintScreen/SysReq, ScrollLock, Pause (HID 0x46–0x48)
        hidToRetrok[0x46] = RETROK_PRINT;
        hidToRetrok[0x47] = RETROK_SCROLLOCK;
        hidToRetrok[0x48] = RETROK_PAUSE;
        // F13–F15 (HID 0x68–0x6A)
        hidToRetrok[0x68] = RETROK_F13;
        hidToRetrok[0x69] = RETROK_F14;
        hidToRetrok[0x6A] = RETROK_F15;
        // 小键盘等号 (HID 0x67)
        hidToRetrok[0x67] = RETROK_KP_EQUALS;
        // 非 US 键盘第102键反斜杠 (HID 0x64)
        hidToRetrok[0x64] = RETROK_OEM_102;
        // Application/Menu 键 → Compose (HID 0x65)
        hidToRetrok[0x65] = RETROK_COMPOSE;
        // Power 键 (HID 0x66)
        hidToRetrok[0x66] = RETROK_POWER;
        // Help 键 (HID 0x75)
        hidToRetrok[0x75] = RETROK_HELP;
        // 键盘音量键（HID 键盘页 0x07：0x7F–0x81）
        hidToRetrok[0x7F] = RETROK_VOLUME_MUTE;
        hidToRetrok[0x80] = RETROK_VOLUME_UP;
        hidToRetrok[0x81] = RETROK_VOLUME_DOWN;
        // 修饰键（左/右）(HID 0xE0–0xE7)
        hidToRetrok[0xE0] = RETROK_LCTRL;  hidToRetrok[0xE1] = RETROK_LSHIFT;
        hidToRetrok[0xE2] = RETROK_LALT;   hidToRetrok[0xE3] = RETROK_LMETA;
        hidToRetrok[0xE4] = RETROK_RCTRL;  hidToRetrok[0xE5] = RETROK_RSHIFT;
        hidToRetrok[0xE6] = RETROK_RALT;   hidToRetrok[0xE7] = RETROK_RMETA;
    });

    // ── 3. 统一的 activeKeys 跟踪（参考 KeyboardResponder.activeKeyPresses）──
    // 字典存储每个 HID keyCode 的 {retrok, isActive}，用于：
    //   a) 去重（过滤 key-repeat）
    //   b) keyUp 时使用按下时记录的 retrok（因为 keyUp 时 _unmodifiedInput 可能无效）
    //   c) 修饰键也统一走此路径，不再单独 early return

    // activeKeys: key=HID keyCode, value=@[@(retrok), @(isActive)]
    static NSMutableDictionary<NSNumber *, NSArray<NSNumber *> *> *activeKeys = nil;
    static dispatch_once_t keysOnce;
    dispatch_once(&keysOnce, ^{ activeKeys = [NSMutableDictionary dictionary]; });

    NSNumber *keyNum = @(hidKeyCode);
    NSArray<NSNumber *> *previousEntry = activeKeys[keyNum];
    BOOL previousIsActive = previousEntry ? previousEntry[1].boolValue : NO;

    // 参考 KeyboardResponder: guard previousKeyPress?.isActive != isActive
    // 过滤重复的 down/up 事件（包括 key-repeat 和重复 up）
    if (previousEntry && previousIsActive == isKeyDown) {
        return;
    }

    // ── 4. 确定 RETROK 值 ────────────────────────────────────────────────
    unsigned retrok = RETROK_UNKNOWN;

    if (!isKeyDown && previousEntry) {
        // keyUp 时优先使用按下时记录的 retrok（参考 KeyboardResponder: previousKeyPress?.key）
        // 因为 _unmodifiedInput 在 keyUp 时可能无效或不同
        retrok = previousEntry[0].unsignedIntValue;
    } else {
        // keyDown：根据 unmodifiedInput 和 HID keyCode 确定 retrok
        if (unmodifiedInput.length == 0) {
            // 纯修饰键事件（参考 KeyboardResponder 对空 key 的处理）
            // 通过比较前后 modifier flags 确定是哪个修饰键
            if (isKeyDown) {
                // 新按下的修饰键 = 当前 flags 中新增的部分
                uint32_t activated = newMods & ~((uint32_t)_keyboardMods);
                retrok = [self retrokForModifierFlags:activated];
            } else {
                // 新释放的修饰键 = 之前 flags 中消失的部分
                uint32_t deactivated = ((uint32_t)_keyboardMods) & ~newMods;
                retrok = [self retrokForModifierFlags:deactivated];
            }
        } else {
            // 有 unmodifiedInput：使用 HID keyCode 映射
            if (hidKeyCode > 0 && hidKeyCode < 0x200) {
                retrok = hidToRetrok[hidKeyCode];
            }
        }
    }

    // 更新修饰键状态（参考 KeyboardResponder 的 defer 语义：无论是否发送事件都要更新）
    _keyboardMods = newMods;

    if (retrok == RETROK_UNKNOWN) {
        return;
    }

    // ── 5. 更新 activeKeys 并发送事件 ────────────────────────────────────
    if (isKeyDown) {
        activeKeys[keyNum] = @[@(retrok), @YES];
        apple_direct_input_keyboard_event(true, retrok, 0, newMods, RETRO_DEVICE_KEYBOARD);
    } else {
        apple_direct_input_keyboard_event(false, retrok, 0, newMods, RETRO_DEVICE_KEYBOARD);
        [activeKeys removeObjectForKey:keyNum];
    }
}

// 辅助方法：根据 modifier flags 差异确定对应的 RETROK（参考 KeyboardResponder.key(for:)）
- (unsigned)retrokForModifierFlags:(uint32_t)flags {
    if (flags & RETROKMOD_SHIFT)    return RETROK_LSHIFT;
    if (flags & RETROKMOD_CTRL)     return RETROK_LCTRL;
    if (flags & RETROKMOD_ALT)      return RETROK_LALT;
    if (flags & RETROKMOD_META)     return RETROK_LMETA;
    if (flags & RETROKMOD_CAPSLOCK) return RETROK_CAPSLOCK;
    return RETROK_UNKNOWN;
}

- (void)moveStick:(BOOL)isLeft x:(CGFloat)x y:(CGFloat)y playerIndex:(unsigned)playerIndex {
    [[self getRetroArch] moveStick:isLeft x:x y:y playerIndex:playerIndex];
}

- (void)updatePSPCheat:(NSString *_Nonnull)cheatCode cheatFilePath:(NSString *_Nonnull)cheatFilePath reloadGame:(BOOL)reloadGame {
    [[self getRetroArch] updatePSPCheat:cheatCode cheatFilePath:cheatFilePath reloadGame:reloadGame];
}

- (void)updateCoreConfig:(NSString *_Nonnull)coreName key:(NSString *_Nonnull)key value:(NSString *_Nonnull)value reload:(BOOL)reload {
    [[self getRetroArch] updateCoreConfig:coreName key:key value:value reload:reload];
}

- (void)updateCoreConfig:(NSString *_Nonnull)coreName configs:(NSDictionary<NSString*, NSString*> *_Nullable)configs reload:(BOOL)reload {
    [[self getRetroArch] updateCoreConfig:coreName configs:configs reload:reload];
}

- (void)updateCoreConfig:(NSString *_Nonnull)coreName content:(NSString *_Nullable)content reload:(BOOL)reload {
    [[self getRetroArch] updateCoreConfig:coreName content:content reload:reload];
}

- (void)updateRunningCoreConfigs:(NSDictionary<NSString*, NSString*> *_Nullable)configs flush:(BOOL)flush {
    [[self getRetroArch] updateRunningCoreConfigs:configs flush:flush];
}

- (void)updateLibretroConfig:(NSString *_Nonnull)key value:(NSString *_Nonnull)value {
    [[self getRetroArch] updateLibretroConfig:key value:value];
}

- (void)updateLibretroConfigs:(NSDictionary<NSString*, NSString*> *_Nullable)configs {
    [[self getRetroArch] updateLibretroConfigs:configs];
}

- (BOOL)setShader:(NSString *_Nullable)path {
    return [[self getRetroArch] setShaderWith:path];
}

- (NSArray<ShaderParameter *> *_Nullable)loadParameters {
    return [[self getRetroArch] loadParameters];
}

- (void)updateParameterWith:(NSString *_Nonnull)identifier
                      value:(float)value
               changingPath:(NSString *_Nonnull)changingPath {
    [[self getRetroArch] updateParameterWith:identifier value:value changingPath:changingPath];
}

- (void)appendShader:(NSString *_Nonnull)path prepend:(BOOL)prepend {
    [[self getRetroArch] appendShader:path prepend:prepend];
}

- (void)addCheatCode:(NSString *_Nonnull)code index:(unsigned)index enable:(BOOL)enable {
    [[self getRetroArch] addCheatCode:code index:index enable:enable];
}

- (void)resetCheatCode {
    [[self getRetroArch] resetCheatCode];
}

- (RetroArch_iOS *)getRetroArch {
#if !TARGET_IPHONE_SIMULATOR
    return (RetroArch_iOS *)self.retroArch_iOS;
#else
    return nil;
#endif
}

- (void)sendEvent:(UIEvent * _Nonnull)event {
    if (self.isRunning) {
        [[self getRetroArch] sendEvent:event];
    }
}

- (void)setWorkspace:(NSString *)workspace {
    [self getRetroArch].workspace = workspace;
}

- (NSString *)workspace {
    return [self getRetroArch].workspace;
}

+ (BOOL)JITAvailable {
    if (LibretroCore.sharedInstance.forbitJIT) {
        return false;
    }
    return jit_available();
}

- (NSString * _Nullable)libretroConfigValue:(NSString * _Nonnull)key {
    return [[self getRetroArch] libretroConfigValue:key];
}

- (NSString * _Nullable)coreConfigValue:(NSString * _Nonnull)coreName key:(NSString * _Nonnull)key {
    return [[self getRetroArch] coreConfigValue:coreName key:key];
}

- (void)setRespectSilentMode:(BOOL)respect {
    [[self getRetroArch] setRespectSilentMode:respect];
}

- (void)setDiskIndex:(unsigned)index delay:(BOOL)delay {
    [[self getRetroArch] setDiskIndex:index delay:delay];
}

- (void)setDiskIndex2:(unsigned)index {
    [[self getRetroArch] setDiskIndex2:index];
}

- (LibretroDisk *_Nullable)getDiskInfo {
    return [[self getRetroArch] getDiskInfo];
}

- (BOOL)insertDisk:(NSString *_Nonnull)path {
    return [[self getRetroArch] insertDisk:path];
}

- (void)setPSXAnalog:(BOOL)isAnalog {
    [[self getRetroArch] setPSXAnalog:isAnalog];
}

- (void)setReloadDelay:(double)delay {
    [[self getRetroArch] setReloadDelay:delay];
}

+ (CheevosAchievement *)convertAchievement:(rc_client_achievement_t *)a {
    if ([[NSString stringWithUTF8String:a->badge_name] isEqualToString:@"00000"]) {
        return nil;
    }
    CheevosAchievement* obj = [CheevosAchievement new];
    obj.title = a->title ? [NSString stringWithUTF8String:a->title] : nil;
    obj._description = a->description ? [NSString stringWithUTF8String:a->description] : nil;
    obj.badgeName = [NSString stringWithUTF8String:a->badge_name];
    obj.measuredProgress = [NSString stringWithUTF8String:a->measured_progress];
    obj.measuredPercent = (CGFloat)a->measured_percent;
    obj._id = (NSInteger)a->id;
    obj.points = (NSInteger)a->points;
    obj.unlockTime = (a->unlock_time ? [NSDate dateWithTimeIntervalSince1970:a->unlock_time] : nil);
    obj.state = (NSInteger)a->state;
    obj.category = (NSInteger)a->state;
    obj.bucket = (NSInteger)a->bucket;
    obj.unlocked = (a->unlocked != 0);
    obj.rarity = (CGFloat)a->rarity;
    obj.rarityHardcore = (CGFloat)a->rarity_hardcore;
    obj.type = (NSInteger)a->type;
    char url1[256];
    if (rc_client_achievement_get_image_url(a, RC_CLIENT_ACHIEVEMENT_STATE_UNLOCKED, url1, sizeof(url1)) == RC_OK) {
        obj.unlockedBadgeUrl = [NSString stringWithCString:url1 encoding:NSUTF8StringEncoding];
    }
    char url2[256];
    if (rc_client_achievement_get_image_url(a, RC_CLIENT_ACHIEVEMENT_STATE_UNLOCKED, url2, sizeof(url2)) == RC_OK) {
        obj.activeBadgeUrl = [NSString stringWithCString:url2 encoding:NSUTF8StringEncoding];
    }
    return obj;
}

static void cheevosDidTrigger(uint32_t type, void* object1, void* object2) {
    if (type == RC_CLIENT_EVENT_ACHIEVEMENT_TRIGGERED) {
        //获得成就
        if (object1) {
            rc_client_achievement_t *a = (rc_client_achievement_t *)object1;
            CheevosAchievement *achievement = [LibretroCore convertAchievement:a];
            if (!achievement) {
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:RetroAchievementsNotification object:achievement];
            });
        }
        
    } else if (type == 8888) {
        //启动游戏
        if (object1 && object2) {
            rc_client_game_t *g = (rc_client_game_t *)object1;
            rc_client_user_game_summary_t *s = (rc_client_user_game_summary_t *)object2;
            
            CheevosSummary* summary = [CheevosSummary new];
            summary.title = g->title ? [NSString stringWithUTF8String:g->title] : nil;
            summary.coreAchievementsNum = (NSInteger)s->num_core_achievements;
            summary.unofficialAchievementsNum = (NSInteger)s->num_unofficial_achievements;
            summary.unlockedAchievementsNum = (NSInteger)s->num_unlocked_achievements;
            summary.unsupportedAchievementsNum = (NSInteger)s->num_unsupported_achievements;
            summary.corePoints = (NSInteger)s->points_core;
            summary.unlockedPoints = (NSInteger)s->points_unlocked;
            char url[256];
            if (rc_client_game_get_image_url(g, url, sizeof(url)) == RC_OK) {
                summary.badgeUrl = [NSString stringWithCString:url encoding:NSUTF8StringEncoding];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:RetroAchievementsNotification object:summary];
            });
            
        }
    } else if (type == RC_CLIENT_EVENT_GAME_COMPLETED) {
        //所有成就收集完成
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:RetroAchievementsNotification object:[CheevosCompletion new]];
        });
        
    } else if (type == RC_CLIENT_EVENT_SERVER_ERROR) {
        //发生错误
        if (object1) {
            rc_client_server_error_t *error = (rc_client_server_error_t *)object1;
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:RetroAchievementsNotification object:error->error_message ? [NSString stringWithUTF8String:error->error_message] : @"RetroAchievements Server Error"];
            });
        }
    } else if (type == RC_CLIENT_EVENT_ACHIEVEMENT_CHALLENGE_INDICATOR_SHOW) {
        //挑战提示
        if (object1) {
            rc_client_achievement_t *a = (rc_client_achievement_t *)object1;
            CheevosAchievement *achievement = [LibretroCore convertAchievement:a];
            if (!achievement) {
                return;
            }
            achievement.isChallengeAchievement = YES;
            achievement.show = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:RetroAchievementsNotification object:achievement];
            });
        }
    } else if (type == RC_CLIENT_EVENT_ACHIEVEMENT_CHALLENGE_INDICATOR_HIDE) {
        //挑战隐藏
        if (object1) {
            rc_client_achievement_t *a = (rc_client_achievement_t *)object1;
            CheevosAchievement *achievement = [LibretroCore convertAchievement:a];
            if (!achievement) {
                return;
            }
            achievement.isChallengeAchievement = YES;
            achievement.show = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:RetroAchievementsNotification object:achievement];
            });
        }
    } else if (type == RC_CLIENT_EVENT_LEADERBOARD_TRACKER_SHOW) {
        //排行榜追踪展示
        if (object1) {
            rc_client_leaderboard_tracker_t *a = (rc_client_leaderboard_tracker_t *)object1;
            CheevosLeaderboardTracker* obj = [CheevosLeaderboardTracker new];
            obj.show = YES;
            obj._id = a->id;
            obj.display = [NSString stringWithUTF8String:a->display];
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:RetroAchievementsNotification object:obj];
            });
        }
        
    } else if (type == RC_CLIENT_EVENT_LEADERBOARD_TRACKER_HIDE) {
        //排行榜追踪隐藏
        if (object1) {
            rc_client_leaderboard_tracker_t *a = (rc_client_leaderboard_tracker_t *)object1;
            CheevosLeaderboardTracker* obj = [CheevosLeaderboardTracker new];
            obj.show = NO;
            obj._id = a->id;
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:RetroAchievementsNotification object:obj];
            });
        }
    } else if (type == RC_CLIENT_EVENT_LEADERBOARD_TRACKER_UPDATE) {
        //排行榜追踪更新
        if (object1) {
            rc_client_leaderboard_tracker_t *a = (rc_client_leaderboard_tracker_t *)object1;
            CheevosLeaderboardTracker* obj = [CheevosLeaderboardTracker new];
            obj.show = YES;
            obj._id = a->id;
            obj.display = [NSString stringWithUTF8String:a->display];
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:RetroAchievementsNotification object:obj];
            });
        }
    } else if (type == RC_CLIENT_EVENT_LEADERBOARD_STARTED) {
        //排行榜开始
        if (object1) {
            rc_client_leaderboard_t *a = (rc_client_leaderboard_t *)object1;
            CheevosLeaderboard* obj = [CheevosLeaderboard new];
            obj.title = a->title ? [NSString stringWithUTF8String:a->title] : nil;
            obj._description = a->description ? [NSString stringWithUTF8String:a->description] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:RetroAchievementsNotification object:obj];
            });
        }
    } else if (type == RC_CLIENT_EVENT_ACHIEVEMENT_PROGRESS_INDICATOR_SHOW) {
        //进度展示
        if (object1) {
            rc_client_achievement_t *a = (rc_client_achievement_t *)object1;
            
            CheevosAchievement *achievement = [LibretroCore convertAchievement:a];
            if (!achievement) {
                return;
            }
            
            achievement.isProgressAchievement = YES;
            achievement.show = YES;

            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:RetroAchievementsNotification object:achievement];
            });
        }
        
    } else if (type == RC_CLIENT_EVENT_ACHIEVEMENT_PROGRESS_INDICATOR_HIDE) {
        //进度隐藏
        CheevosAchievement *achievement = [CheevosAchievement new];
        achievement.isProgressAchievement = YES;
        achievement.show = NO;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:RetroAchievementsNotification object:achievement];
        });
        
    } else if (type == RC_CLIENT_EVENT_ACHIEVEMENT_PROGRESS_INDICATOR_UPDATE) {
        //进度更新
        if (object1) {
            rc_client_achievement_t *a = (rc_client_achievement_t *)object1;
            
            CheevosAchievement *achievement = [LibretroCore convertAchievement:a];
            if (!achievement) {
                return;
            }
            
            achievement.isProgressAchievement = YES;
            achievement.show = YES;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:RetroAchievementsNotification object:achievement];
            });
        }
    }
}

- (void)turnOffHardcode {
    [[self getRetroArch] turnOffHardcode];
}

- (void)resetRetroAchievements {
    [[self getRetroArch] resetRetroAchievements];
}

- (void)setCustomSaveExtension:(NSString *_Nullable)customSaveExtension {
    [[self getRetroArch] setCustomSaveExtension:customSaveExtension];
}

- (void)setEnableRumble:(BOOL)enable {
    [[self getRetroArch] setEnableRumble:enable];
}

- (BOOL)getSensorEnable:(int)playerIndex {
    return [[self getRetroArch] getSensorEnable:playerIndex];
}

static void shutdownCallback(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:LibretroDidShutdownNotification object:nil];
    });
}

- (void)startWFCStatusMonitor {
    wfc_status_register_callback(wfcStatusCallback);
}

static void wfcStatusCallback(bool isConnect) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (isConnect) {
            [[NSNotificationCenter defaultCenter] postNotificationName:DidConnectToWFCNotification object:nil];
        } else {
            [[NSNotificationCenter defaultCenter] postNotificationName:DidDisconnectFromWFCNotification object:nil];
        }
    });
}

static BOOL g_enableMonitorLibretroLog = NO;
- (void)setLibretroLogMonitor:(BOOL)enable {
    g_enableMonitorLibretroLog = enable;
}

static NSString *g_mameMissingFileLog = nil;
static void libretroLogCallback(enum retro_log_level level, const char *fmt, va_list args) {
    if (!g_enableMonitorLibretroLog) {
        return;
    }
    // 使用 va_list 格式化字符串
    char buffer[4096];
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    
    // 根据日志级别输出
    NSString *logMessage = [NSString stringWithUTF8String:buffer];
    
    if ([logMessage containsString:@" NOT FOUND (tried in "]) {
        if (g_mameMissingFileLog && g_mameMissingFileLog.length > 0) {
            g_mameMissingFileLog = [g_mameMissingFileLog stringByAppendingFormat:@"\n%@", logMessage];
        } else {
            g_mameMissingFileLog = logMessage;
        }
    }
    
    switch (level) {
        case RETRO_LOG_ERROR:
            if ([logMessage containsString:@"Required files are missing,"]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter] postNotificationName:MAMEGameFileMissingNotification object:g_mameMissingFileLog];
                    g_mameMissingFileLog = nil;
                });
            }
            break;
        default:
            break;
    }
}

- (void)setNDSCustomLayout:(NSString *_Nullable)layout {
    if (layout) {
        if ([layout componentsSeparatedByString:@","].count == 10) {
            set_melonds_custom_layout([layout cStringUsingEncoding:NSUTF8StringEncoding]);
            set_desmume_custom_layout([layout cStringUsingEncoding:NSUTF8StringEncoding]);
            [self setCoreOptionNeedsUpdate];
        }
    } else {
        set_melonds_custom_layout(NULL);
        set_desmume_custom_layout(NULL);
        [self setCoreOptionNeedsUpdate];
    }
}

- (void)set3DSCustomLayout:(NSString *_Nullable)layout {
    if (layout) {
        if ([layout componentsSeparatedByString:@","].count == 10) {
            set_azahar_custom_layout([layout cStringUsingEncoding:NSUTF8StringEncoding]);
            [self setCoreOptionNeedsUpdate];
        }
    } else {
        set_azahar_custom_layout(NULL);
        [self setCoreOptionNeedsUpdate];
    }
}

- (void)setNDSWFCDNS:(NSString *_Nullable)nds {
    if (nds) {
        set_melonds_wfc_dns([nds cStringUsingEncoding:NSUTF8StringEncoding]);
        [self setCoreOptionNeedsUpdate];
    } else {
        set_melonds_wfc_dns(NULL);
        [self setCoreOptionNeedsUpdate];
    }
}

- (void)setPSPCustomServerAddress:(NSString *_Nullable)address {
    if (address) {
        set_psp_custom_server_address([address cStringUsingEncoding:NSUTF8StringEncoding]);
    } else {
        set_psp_custom_server_address(NULL);
    }
}

- (void)setPSPCustomServerPort:(NSString *_Nullable)port {
    if (port) {
        set_psp_custom_server_port([port cStringUsingEncoding:NSUTF8StringEncoding]);
    } else {
        set_psp_custom_server_port(NULL);
    }
}

- (void)setCoreOptionNeedsUpdate {
    // 通知核心配置已更新
    runloop_state_t *runloop_st = runloop_state_get_ptr();
    if (runloop_st->core_options) {
        runloop_st->core_options->updated = true;
    }
}

- (void)sendTouchEventX:(CGFloat)x y:(CGFloat)y {
    [[self getRetroArch] sendTouchEventX:x y:y];
}

- (void)releaseTouchEvent {
    [[self getRetroArch] releaseTouchEvent];
}

- (void)sendMultiTouchEvent:(NSArray<NSDictionary *> *)points {
    [[self getRetroArch] sendMultiTouchEvent:points];
}

- (NSString *_Nullable)getCoreConfigs:(NSString *_Nonnull)coreName {
    return [[self getRetroArch] getCoreConfigs:coreName];
}

- (void)updateFBNeoCheatCode:(NSArray<NSString *> *_Nonnull)keys enable:(BOOL)enable {
    [[self getRetroArch] updateFBNeoCheatCode:keys enable:enable];
}

- (void)setFastforwardFrameSkip:(BOOL)frameSkip {
    [[self getRetroArch] setFastforwardFrameSkip:frameSkip];
}

- (void)loadAmiibo:(NSString *_Nonnull)path {
    [[self getRetroArch] loadAmiibo:path];
}

- (BOOL)isSearchingAmiibo {
    return [[self getRetroArch] isSearchingAmiibo];
}

- (void)setFullScreen:(BOOL)isFullScreen {
    [[self getRetroArch] setFullScreen:isFullScreen];
}

#pragma mark - Azahar Keyboard Support

/* ABI layout must match azahar core (libretro_azahar.h); loaded via dylib_proc only. */
struct retro_azahar_keyboard_config_local {
    int button_config;
    int accept_mode;
    bool multiline_mode;
    int max_text_length;
    int max_digits;
    const char* _Nullable hint_text;
    const char* _Nonnull* _Nullable button_text;
    int button_text_count;
    bool prevent_digit;
    bool prevent_at;
    bool prevent_percent;
    bool prevent_backslash;
    bool prevent_profanity;
    bool enable_callback;
};

// Static storage for the keyboard callback
static void (^_Nullable s_azahar_keyboard_callback)(AzaharKeyboardConfig * _Nullable config) = nil;

// C callback that will be called by the Azahar core
static void azahar_keyboard_request_callback(
    const struct retro_azahar_keyboard_config_local* _Nullable config) {
    if (!s_azahar_keyboard_callback || !config) {
        return;
    }
    
    AzaharKeyboardConfig *objcConfig = [[AzaharKeyboardConfig alloc] init];
    objcConfig.buttonConfig = (AzaharButtonConfig)config->button_config;
    objcConfig.acceptedInput = (AzaharAcceptedInput)config->accept_mode;
    objcConfig.multilineMode = config->multiline_mode;
    objcConfig.maxTextLength = config->max_text_length;
    objcConfig.maxDigits = config->max_digits;
    objcConfig.hintText = config->hint_text ? [NSString stringWithUTF8String:config->hint_text] : nil;
    
    // Convert button text array
    if (config->button_text && config->button_text_count > 0) {
        NSMutableArray<NSString *> *buttonTexts = [NSMutableArray arrayWithCapacity:config->button_text_count];
        for (int i = 0; i < config->button_text_count; i++) {
            if (config->button_text[i]) {
                [buttonTexts addObject:[NSString stringWithUTF8String:config->button_text[i]]];
            } else {
                [buttonTexts addObject:@""];
            }
        }
        objcConfig.buttonText = buttonTexts;
    }
    
    // Set filters
    objcConfig.preventDigit = config->prevent_digit;
    objcConfig.preventAt = config->prevent_at;
    objcConfig.preventPercent = config->prevent_percent;
    objcConfig.preventBackslash = config->prevent_backslash;
    objcConfig.preventProfanity = config->prevent_profanity;
    objcConfig.enableCallback = config->enable_callback;
    
    s_azahar_keyboard_callback(objcConfig);
}

- (void)registerAzaharKeyboard:(void(^ _Nullable)(AzaharKeyboardConfig *_Nonnull config))callback {
#ifdef HAVE_DYNAMIC
    runloop_state_t *runloop_st = runloop_state_get_ptr();
    if (!runloop_st || !runloop_st->lib_handle) {
        return;
    }
    
    // Store the callback
    s_azahar_keyboard_callback = [callback copy];
    
    typedef void (*retro_azahar_set_keyboard_callback_t)(
        void (*)(const struct retro_azahar_keyboard_config_local*));
    retro_azahar_set_keyboard_callback_t set_callback =
        (retro_azahar_set_keyboard_callback_t)dylib_proc(runloop_st->lib_handle,
                                                         "retro_azahar_set_keyboard_callback");
    
    if (set_callback) {
        if (callback) {
            set_callback(azahar_keyboard_request_callback);
        } else {
            set_callback(NULL);
        }
    }
#endif
}

- (void)inputAzaharKeyboard:(NSString *_Nullable)text buttonType:(AzaharButtonType)buttonType {
#ifdef HAVE_DYNAMIC
    runloop_state_t *runloop_st = runloop_state_get_ptr();
    if (!runloop_st || !runloop_st->lib_handle) {
        return;
    }
    
    typedef void (*retro_azahar_keyboard_input_t)(const char*, int);
    retro_azahar_keyboard_input_t keyboard_input =
        (retro_azahar_keyboard_input_t)dylib_proc(runloop_st->lib_handle, "retro_azahar_keyboard_input");
    
    if (keyboard_input) {
        const char* text_cstr = text ? [text UTF8String] : NULL;
        int button = 0;
        
        // Map AzaharButtonType to button index
        // For Single: 0=Ok
        // For Dual: 0=Cancel, 1=Ok
        // For Triple: 0=Cancel, 1=Forgot, 2=Ok
        switch (buttonType) {
            case AzaharButtonTypeOk:
                button = 2; // Ok is always the highest index for Triple, adjusted in core
                break;
            case AzaharButtonTypeCancel:
                button = 0;
                break;
            case AzaharButtonTypeForgot:
                button = 1;
                break;
            case AzaharButtonTypeNoButton:
            default:
                button = 0;
                break;
        }
        
        keyboard_input(text_cstr, button);
    }
#endif
}

- (void)installAzaharCIA:(NSString *_Nonnull)path {
    NSString *corePath = [[NSBundle mainBundle] pathForResource:@"azahar.libretro" ofType:@"framework" inDirectory:@"Frameworks"];
    if (!corePath) {
        return;
    }
    
    NSString *dylibPath = [corePath stringByAppendingPathComponent:@"azahar.libretro"];
    dylib_t lib = dylib_load([dylibPath UTF8String]);
    if (!lib) {
        return;
    }
    
    typedef void (*retro_azahar_install_cia_t)(const char*);
    retro_azahar_install_cia_t install_cia =
        (retro_azahar_install_cia_t)dylib_proc(lib, "retro_azahar_install_cia");
    
    if (install_cia) {
        const char* path_cstr = [path UTF8String];
        install_cia(path_cstr);
    }
}

+ (NSString *_Nullable)getPSPGameIDWithRomPath:(NSString *_Nonnull)romPath {
    NSString *corePath = [[NSBundle mainBundle] pathForResource:@"ppsspp.libretro" ofType:@"framework" inDirectory:@"Frameworks"];
    if (!corePath) {
        return nil;
    }
    
    NSString *dylibPath = [corePath stringByAppendingPathComponent:@"ppsspp.libretro"];
    dylib_t lib = dylib_load([dylibPath UTF8String]);
    if (!lib) {
        return nil;
    }
    
    typedef const char* (*retro_get_psp_gameid_t)(const char*);
    retro_get_psp_gameid_t get_psp_gameid = (retro_get_psp_gameid_t)dylib_proc(lib, "retro_get_psp_gameid");
    if (!get_psp_gameid) {
        dylib_close(lib);
        return nil;
    }
    
    const char *romPath_cstr = [romPath UTF8String];
    const char* gameid = get_psp_gameid(romPath_cstr);
    NSString *result = nil;
    if (gameid) {
        result = [NSString stringWithUTF8String:gameid];
    }
    dylib_close(lib);
    
    return result;
}

+ (LibretroPSPGame *_Nullable)installPSPGameWithZipPath:(NSString *_Nonnull)zipPath destDir:(NSString *_Nonnull)destDir {
    NSString *corePath = [[NSBundle mainBundle] pathForResource:@"ppsspp.libretro" ofType:@"framework" inDirectory:@"Frameworks"];
    if (!corePath) {
        return nil;
    }

    NSString *dylibPath = [corePath stringByAppendingPathComponent:@"ppsspp.libretro"];
    dylib_t lib = dylib_load([dylibPath UTF8String]);
    if (!lib) {
        return nil;
    }

    typedef struct {
        int success;
        const char *title;
        const char *gameID;
        const char *gamePath;
        const void *iconData;
        int iconSize;
    } PSPZipInstallResult;

    typedef const PSPZipInstallResult* (*retro_install_psp_zip_t)(const char*, const char*);
    retro_install_psp_zip_t install_psp_zip = (retro_install_psp_zip_t)dylib_proc(lib, "retro_install_psp_zip");
    if (!install_psp_zip) {
        dylib_close(lib);
        return nil;
    }

    const PSPZipInstallResult *result = install_psp_zip([zipPath UTF8String], [destDir UTF8String]);
    LibretroPSPGame *game = nil;

    if (result && result->success) {
        game = [[LibretroPSPGame alloc] init];

        if (result->title) {
            game.title = [NSString stringWithUTF8String:result->title];
        }
        if (result->gameID) {
            game.gameID = [NSString stringWithUTF8String:result->gameID];
        }
        if (result->gamePath) {
            game.gamePath = [NSString stringWithUTF8String:result->gamePath];
        }
        if (result->iconData && result->iconSize > 0) {
            NSData *iconData = [NSData dataWithBytes:result->iconData length:result->iconSize];
            game.icon = [UIImage imageWithData:iconData];
        }
    }

    dylib_close(lib);
    return game;
}

@end
