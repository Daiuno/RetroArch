//
//  AzaharKeyboardConfig.h
//  Libretro
//
//  Created by Daiuno on 2025/12/11.
//  Copyright © 2025 Manic EMU. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, AzaharButtonConfig) {
    AzaharButtonConfigSingle,
    AzaharButtonConfigDual,
    AzaharButtonConfigTriple,
    AzaharButtonConfigNone,
};

typedef NS_ENUM(NSUInteger, AzaharAcceptedInput) {
    AzaharAcceptedInputAnything,
    AzaharAcceptedInputNotEmpty,
    AzaharAcceptedInputNotEmptyAndNotBlank,
    AzaharAcceptedInputNotBlank,
    AzaharAcceptedInputFixedLength,
};

typedef NS_ENUM(NSUInteger, AzaharButtonType) {
    AzaharButtonTypeOk,
    AzaharButtonTypeCancel,
    AzaharButtonTypeForgot,
    AzaharButtonTypeNoButton,
};

@interface AzaharKeyboardConfig : NSObject

@property (nonatomic, assign) AzaharButtonConfig buttonConfig;
@property (nonatomic, assign) AzaharAcceptedInput acceptedInput;
@property (nonatomic, assign) BOOL multilineMode;
@property (nonatomic, assign) NSInteger maxTextLength;
@property (nonatomic, assign) NSInteger maxDigits;
@property (nonatomic, copy) NSString *_Nullable hintText;
@property (nonatomic, copy) NSArray<NSString *> *_Nullable buttonText;
@property (nonatomic, assign) BOOL preventDigit;
@property (nonatomic, assign) BOOL preventAt;
@property (nonatomic, assign) BOOL preventPercent;
@property (nonatomic, assign) BOOL preventBackslash;
@property (nonatomic, assign) BOOL preventProfanity;
@property (nonatomic, assign) BOOL enableCallback;


@end

NS_ASSUME_NONNULL_END
