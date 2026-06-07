//
//  LibretroShaders.h
//  Libretro
//
//  Created by Daiuno on 2025/12/13.
//  Copyright © 2025 Manic EMU. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Shader参数
@interface ShaderParameter : NSObject
@property (nonatomic, copy) NSString *identifier;    // 参数标识符
@property (nonatomic, copy) NSString *desc;   // 参数描述
@property (nonatomic, assign) float current;         // 当前值
@property (nonatomic, assign) float minimum;         // 最小值
@property (nonatomic, assign) float maximum;         // 最大值
@property (nonatomic, assign) float step;            // 步长
@property (nonatomic, assign) unsigned pass;         // 所属pass
@end

NS_ASSUME_NONNULL_END

