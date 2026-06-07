//
//  LibretroKeyboardCode.m
//  Libretro
//
//  Created by Daiuno on 2026/1/24.
//  Copyright © 2026 Manic EMU. All rights reserved.
//

#import "LibretroKeyboardCode.h"
#include "../../../libretro-common/include/libretro.h"

@interface LibretroKeyboardCode()

@property(nonatomic, copy) NSString *label;
@property(assign) unsigned code;

@end

@implementation LibretroKeyboardCode

+ (NSArray<NSString *> *)getAllKeyboarLabels {
    return @[
        @"1",
        @"2",
        @"3",
        @"4",
        @"5",
        @"6",
        @"7",
        @"8",
        @"9",
        @"0",
        @"a",
        @"b",
        @"c",
        @"d",
        @"e",
        @"f",
        @"g",
        @"h",
        @"i",
        @"j",
        @"k",
        @"l",
        @"m",
        @"n",
        @"o",
        @"p",
        @"q",
        @"r",
        @"s",
        @"t",
        @"u",
        @"v",
        @"w",
        @"x",
        @"y",
        @"z",
        @"f1",
        @"f2",
        @"f3",
        @"f4",
        @"f5",
        @"f6",
        @"f7",
        @"f8",
        @"f9",
        @"f10",
        @"f11",
        @"f12",
        @"escape",
        @"backspace",
        @"backquote",
        @"minus",
        @"equals",
        @"insert",
        @"home",
        @"end",
        @"pageup",
        @"pagedown",
        @"print",
        @"scrolllock",
        @"pause",
        @"delete",
        @"tab",
        @"backslash",
        @"rightbracket",
        @"leftbracket",
        @"capslock",
        @"quote",
        @"semicolon",
        @"return",
        @"shift",
        @"lshift",
        @"rshift",
        @"period",
        @"slash",
        @"comma",
        @"ctrl",
        @"lctrl",
        @"rctrl",
        @"meta",
        @"lmeta",
        @"rmeta",
        @"alt",
        @"lalt",
        @"ralt",
        @"up",
        @"space",
        @"down",
        @"left",
        @"right"
    ];
}

+ (instancetype)createCodeWithLabel:(NSString *)label code:(unsigned)code {
    LibretroKeyboardCode *keyboardCode = [LibretroKeyboardCode new];
    keyboardCode.label = label;
    keyboardCode.code = code;
    return keyboardCode;
}

+ (LibretroKeyboardCode *_Nullable)createCodeWithLabel:(NSString *_Nonnull)label {
    if ([label isEqualToString:@"1"]) { return [self createCodeWithLabel:label code:RETROK_1]; }
    else if ([label isEqualToString:@"2"]) { return [self createCodeWithLabel:label code:RETROK_2]; }
    else if ([label isEqualToString:@"3"]) { return [self createCodeWithLabel:label code:RETROK_3]; }
    else if ([label isEqualToString:@"4"]) { return [self createCodeWithLabel:label code:RETROK_4]; }
    else if ([label isEqualToString:@"5"]) { return [self createCodeWithLabel:label code:RETROK_5]; }
    else if ([label isEqualToString:@"6"]) { return [self createCodeWithLabel:label code:RETROK_6]; }
    else if ([label isEqualToString:@"7"]) { return [self createCodeWithLabel:label code:RETROK_7]; }
    else if ([label isEqualToString:@"8"]) { return [self createCodeWithLabel:label code:RETROK_8]; }
    else if ([label isEqualToString:@"9"]) { return [self createCodeWithLabel:label code:RETROK_9]; }
    else if ([label isEqualToString:@"0"]) { return [self createCodeWithLabel:label code:RETROK_0]; }
    else if ([label isEqualToString:@"a"]) { return [self createCodeWithLabel:label code:RETROK_a]; }
    else if ([label isEqualToString:@"b"]) { return [self createCodeWithLabel:label code:RETROK_b]; }
    else if ([label isEqualToString:@"c"]) { return [self createCodeWithLabel:label code:RETROK_c]; }
    else if ([label isEqualToString:@"d"]) { return [self createCodeWithLabel:label code:RETROK_d]; }
    else if ([label isEqualToString:@"e"]) { return [self createCodeWithLabel:label code:RETROK_e]; }
    else if ([label isEqualToString:@"f"]) { return [self createCodeWithLabel:label code:RETROK_f]; }
    else if ([label isEqualToString:@"g"]) { return [self createCodeWithLabel:label code:RETROK_g]; }
    else if ([label isEqualToString:@"h"]) { return [self createCodeWithLabel:label code:RETROK_h]; }
    else if ([label isEqualToString:@"i"]) { return [self createCodeWithLabel:label code:RETROK_i]; }
    else if ([label isEqualToString:@"j"]) { return [self createCodeWithLabel:label code:RETROK_j]; }
    else if ([label isEqualToString:@"k"]) { return [self createCodeWithLabel:label code:RETROK_k]; }
    else if ([label isEqualToString:@"l"]) { return [self createCodeWithLabel:label code:RETROK_l]; }
    else if ([label isEqualToString:@"m"]) { return [self createCodeWithLabel:label code:RETROK_m]; }
    else if ([label isEqualToString:@"n"]) { return [self createCodeWithLabel:label code:RETROK_n]; }
    else if ([label isEqualToString:@"o"]) { return [self createCodeWithLabel:label code:RETROK_o]; }
    else if ([label isEqualToString:@"p"]) { return [self createCodeWithLabel:label code:RETROK_p]; }
    else if ([label isEqualToString:@"q"]) { return [self createCodeWithLabel:label code:RETROK_q]; }
    else if ([label isEqualToString:@"r"]) { return [self createCodeWithLabel:label code:RETROK_r]; }
    else if ([label isEqualToString:@"s"]) { return [self createCodeWithLabel:label code:RETROK_s]; }
    else if ([label isEqualToString:@"t"]) { return [self createCodeWithLabel:label code:RETROK_t]; }
    else if ([label isEqualToString:@"u"]) { return [self createCodeWithLabel:label code:RETROK_u]; }
    else if ([label isEqualToString:@"v"]) { return [self createCodeWithLabel:label code:RETROK_v]; }
    else if ([label isEqualToString:@"w"]) { return [self createCodeWithLabel:label code:RETROK_w]; }
    else if ([label isEqualToString:@"x"]) { return [self createCodeWithLabel:label code:RETROK_x]; }
    else if ([label isEqualToString:@"y"]) { return [self createCodeWithLabel:label code:RETROK_y]; }
    else if ([label isEqualToString:@"z"]) { return [self createCodeWithLabel:label code:RETROK_z]; }
    else if ([label isEqualToString:@"f1"]) { return [self createCodeWithLabel:label code:RETROK_F1]; }
    else if ([label isEqualToString:@"f2"]) { return [self createCodeWithLabel:label code:RETROK_F2]; }
    else if ([label isEqualToString:@"f3"]) { return [self createCodeWithLabel:label code:RETROK_F3]; }
    else if ([label isEqualToString:@"f4"]) { return [self createCodeWithLabel:label code:RETROK_F4]; }
    else if ([label isEqualToString:@"f5"]) { return [self createCodeWithLabel:label code:RETROK_F5]; }
    else if ([label isEqualToString:@"f6"]) { return [self createCodeWithLabel:label code:RETROK_F6]; }
    else if ([label isEqualToString:@"f7"]) { return [self createCodeWithLabel:label code:RETROK_F7]; }
    else if ([label isEqualToString:@"f8"]) { return [self createCodeWithLabel:label code:RETROK_F8]; }
    else if ([label isEqualToString:@"f9"]) { return [self createCodeWithLabel:label code:RETROK_F9]; }
    else if ([label isEqualToString:@"f10"]) { return [self createCodeWithLabel:label code:RETROK_F10]; }
    else if ([label isEqualToString:@"f11"]) { return [self createCodeWithLabel:label code:RETROK_F11]; }
    else if ([label isEqualToString:@"f12"]) { return [self createCodeWithLabel:label code:RETROK_F12]; }
    else if ([label isEqualToString:@"escape"]) { return [self createCodeWithLabel:label code:RETROK_ESCAPE]; }
    else if ([label isEqualToString:@"backspace"]) { return [self createCodeWithLabel:label code:RETROK_BACKSPACE]; }
    else if ([label isEqualToString:@"backquote"]) { return [self createCodeWithLabel:label code:RETROK_BACKQUOTE]; }
    else if ([label isEqualToString:@"minus"]) { return [self createCodeWithLabel:label code:RETROK_MINUS]; }
    else if ([label isEqualToString:@"equals"]) { return [self createCodeWithLabel:label code:RETROK_EQUALS]; }
    else if ([label isEqualToString:@"insert"]) { return [self createCodeWithLabel:label code:RETROK_INSERT]; }
    else if ([label isEqualToString:@"home"]) { return [self createCodeWithLabel:label code:RETROK_HOME]; }
    else if ([label isEqualToString:@"end"]) { return [self createCodeWithLabel:label code:RETROK_END]; }
    else if ([label isEqualToString:@"pageup"]) { return [self createCodeWithLabel:label code:RETROK_PAGEUP]; }
    else if ([label isEqualToString:@"pagedown"]) { return [self createCodeWithLabel:label code:RETROK_PAGEDOWN]; }
    else if ([label isEqualToString:@"print"]) { return [self createCodeWithLabel:label code:RETROK_PRINT]; }
    else if ([label isEqualToString:@"scrolllock"]) { return [self createCodeWithLabel:label code:RETROK_SCROLLOCK]; }
    else if ([label isEqualToString:@"pause"]) { return [self createCodeWithLabel:label code:RETROK_PAUSE]; }
    else if ([label isEqualToString:@"delete"]) { return [self createCodeWithLabel:label code:RETROK_DELETE]; }
    else if ([label isEqualToString:@"tab"]) { return [self createCodeWithLabel:label code:RETROK_TAB]; }
    else if ([label isEqualToString:@"backslash"]) { return [self createCodeWithLabel:label code:RETROK_BACKSLASH]; }
    else if ([label isEqualToString:@"rightbracket"]) { return [self createCodeWithLabel:label code:RETROK_RIGHTBRACKET]; }
    else if ([label isEqualToString:@"leftbracket"]) { return [self createCodeWithLabel:label code:RETROK_LEFTBRACKET]; }
    else if ([label isEqualToString:@"capslock"]) { return [self createCodeWithLabel:label code:RETROK_CAPSLOCK]; }
    else if ([label isEqualToString:@"quote"]) { return [self createCodeWithLabel:label code:RETROK_QUOTE]; }
    else if ([label isEqualToString:@"semicolon"]) { return [self createCodeWithLabel:label code:RETROK_SEMICOLON]; }
    else if ([label isEqualToString:@"return"]) { return [self createCodeWithLabel:label code:RETROK_RETURN]; }
    else if ([label isEqualToString:@"shift"]) { return [self createCodeWithLabel:label code:RETROK_LSHIFT]; }
    else if ([label isEqualToString:@"lshift"]) { return [self createCodeWithLabel:label code:RETROK_LSHIFT]; }
    else if ([label isEqualToString:@"rshift"]) { return [self createCodeWithLabel:label code:RETROK_RSHIFT]; }
    else if ([label isEqualToString:@"period"]) { return [self createCodeWithLabel:label code:RETROK_PERIOD]; }
    else if ([label isEqualToString:@"slash"]) { return [self createCodeWithLabel:label code:RETROK_SLASH]; }
    else if ([label isEqualToString:@"comma"]) { return [self createCodeWithLabel:label code:RETROK_COMMA]; }
    else if ([label isEqualToString:@"up"]) { return [self createCodeWithLabel:label code:RETROK_UP]; }
    else if ([label isEqualToString:@"ctrl"]) { return [self createCodeWithLabel:label code:RETROK_LCTRL]; }
    else if ([label isEqualToString:@"lctrl"]) { return [self createCodeWithLabel:label code:RETROK_LCTRL]; }
    else if ([label isEqualToString:@"rctrl"]) { return [self createCodeWithLabel:label code:RETROK_RCTRL]; }
    else if ([label isEqualToString:@"meta"]) { return [self createCodeWithLabel:label code:RETROK_LMETA]; }
    else if ([label isEqualToString:@"lmeta"]) { return [self createCodeWithLabel:label code:RETROK_LMETA]; }
    else if ([label isEqualToString:@"rmeta"]) { return [self createCodeWithLabel:label code:RETROK_RMETA]; }
    else if ([label isEqualToString:@"alt"]) { return [self createCodeWithLabel:label code:RETROK_LALT]; }
    else if ([label isEqualToString:@"lalt"]) { return [self createCodeWithLabel:label code:RETROK_LALT]; }
    else if ([label isEqualToString:@"ralt"]) { return [self createCodeWithLabel:label code:RETROK_RALT]; }
    else if ([label isEqualToString:@"space"]) { return [self createCodeWithLabel:label code:RETROK_SPACE]; }
    else if ([label isEqualToString:@"down"]) { return [self createCodeWithLabel:label code:RETROK_DOWN]; }
    else if ([label isEqualToString:@"left"]) { return [self createCodeWithLabel:label code:RETROK_LEFT]; }
    else if ([label isEqualToString:@"right"]) { return [self createCodeWithLabel:label code:RETROK_RIGHT]; }
    return nil;
}

@end
