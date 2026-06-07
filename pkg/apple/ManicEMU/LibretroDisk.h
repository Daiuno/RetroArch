//
//  LibretroDisk.h
//  Libretro
//
//  Created by Daiuno on 2026/3/19.
//  Copyright © 2026 Manic EMU. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LibretroDisk : NSObject
@property (nonatomic, assign) NSInteger currentDiskIndex;
@property (nonatomic, assign) NSInteger diskCount;
@property (nonatomic, assign) BOOL ejected;
@property (nonatomic, copy) NSArray<NSString *> *diskPaths;
@property (nonatomic, copy) NSArray<NSString *> *diskLabels;

@end

NS_ASSUME_NONNULL_END
