//
//  LibretroShaders.h
//  Libretro
//
//  Created by Daiuno on 2025/12/13.
//  Copyright © 2025 Manic EMU. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Shader parameters
@interface ShaderParameter : NSObject
@property (nonatomic, copy) NSString *identifier;    // Parameter identifier
@property (nonatomic, copy) NSString *desc;   // Parameter description
@property (nonatomic, assign) float current;         // Current value
@property (nonatomic, assign) float initial;         // Initial value
@property (nonatomic, assign) float minimum;         // Minimum value
@property (nonatomic, assign) float maximum;         // Maximum value
@property (nonatomic, assign) float step;            // Step
@property (nonatomic, assign) unsigned pass;         // Associated pass
@end

NS_ASSUME_NONNULL_END
