//
//  LibretroKeyboardCode.h
//  Libretro
//
//  Created by Daiuno on 2026/1/24.
//  Copyright © 2026 Manic EMU. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/**
 Labels accepted by `createCodeWithLabel:` (canonical names match KeyboardGameController).

 "0"–"9" RETROK_0–9
 "a"–"z" RETROK_a–z
 "f1"–"f15" RETROK_F1–F15
 "escape" RETROK_ESCAPE
 "backspace" RETROK_BACKSPACE
 "tab" RETROK_TAB
 "return" RETROK_RETURN
 "space" RETROK_SPACE
 "delete" RETROK_DELETE
 "insert" RETROK_INSERT
 "home" RETROK_HOME
 "end" RETROK_END
 "pageup" RETROK_PAGEUP
 "pagedown" RETROK_PAGEDOWN
 "print" RETROK_PRINT
 "scrolllock" RETROK_SCROLLOCK
 "pause" RETROK_PAUSE
 "numlock" RETROK_NUMLOCK
 "capslock" RETROK_CAPSLOCK
 "up"/"down"/"left"/"right" RETROK_UP/DOWN/LEFT/RIGHT
 "comma" RETROK_COMMA
 "period" RETROK_PERIOD
 "slash" RETROK_SLASH
 "semicolon" RETROK_SEMICOLON
 "quote" RETROK_QUOTE
 "leftbracket" RETROK_LEFTBRACKET
 "rightbracket" RETROK_RIGHTBRACKET
 "backslash" RETROK_BACKSLASH
 "minus" RETROK_MINUS
 "equals" RETROK_EQUALS
 "backquote" RETROK_BACKQUOTE
 "plus" RETROK_PLUS
 "asterisk" RETROK_ASTERISK
 "bar" RETROK_BAR
 "oem102" RETROK_OEM_102
 "shift"/"lshift" RETROK_LSHIFT
 "rshift" RETROK_RSHIFT
 "ctrl"/"lctrl" RETROK_LCTRL
 "rctrl" RETROK_RCTRL
 "alt"/"lalt" RETROK_LALT
 "ralt" RETROK_RALT
 "meta"/"lmeta" RETROK_LMETA
 "rmeta" RETROK_RMETA
 "kp0"–"kp9" RETROK_KP0–9
 "kpperiod" RETROK_KP_PERIOD
 "kpdivide" RETROK_KP_DIVIDE
 "kpmultiply" RETROK_KP_MULTIPLY
 "kpminus" RETROK_KP_MINUS
 "kpplus" RETROK_KP_PLUS
 "kpenter" RETROK_KP_ENTER
 "kpequals" RETROK_KP_EQUALS
 */

@interface LibretroKeyboardCode : NSObject

@property(assign, readonly) unsigned code;

+ (NSArray<NSString *> *)getAllKeyboarLabels;
+ (LibretroKeyboardCode *_Nullable)createCodeWithLabel:(NSString *_Nonnull)label;

@end

NS_ASSUME_NONNULL_END
