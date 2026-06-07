//
//  LibretroCoreOptions.h
//  Libretro
//
//  Created by Daiuno on 2026/3/18.
//  Copyright © 2026 Manic EMU. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Options : NSObject
@property (nonatomic, copy) NSString *value;
@property (nonatomic, copy) NSString *label;
@end

@interface CoreOption : NSObject

@property (nonatomic, copy) NSString *key;
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, copy) NSString *desc;
@property (nonatomic, copy) NSString *info;
@property (nonatomic, copy) NSString *value;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSArray<Options *> *options;
@property (nonatomic, assign) BOOL visible;

@end

@interface CoreOptionCategory : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *desc;
@property (nonatomic, copy) NSString *info;
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, copy) NSArray<CoreOption *> *options;
@property (nonatomic, assign) BOOL visible;

@end

NS_ASSUME_NONNULL_END
