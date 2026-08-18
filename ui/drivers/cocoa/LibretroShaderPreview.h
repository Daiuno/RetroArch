//
//  LibretroShaderPreview.h
//  Libretro
//
//  Copyright © 2025 Manic EMU. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Offscreen shader preview router (.slangp via Metal, .glslp via GL).
/// Does not touch the active game video driver or shader state.
@interface LibretroShaderPreview : NSObject

+ (UIImage *_Nullable)renderImage:(UIImage *_Nonnull)image
                        shaderPath:(NSString *_Nonnull)shaderPath;

/// Release cached offscreen Metal/GL preview pipelines and GPU resources.
+ (void)clearCache;

@end

NS_ASSUME_NONNULL_END
