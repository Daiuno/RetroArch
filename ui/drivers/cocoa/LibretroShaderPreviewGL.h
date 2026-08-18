//
//  LibretroShaderPreviewGL.h
//  Libretro
//
//  Copyright © 2025 Manic EMU. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Independent offscreen glslp (.glslp) preview renderer.
/// Uses a private EAGLContext and does not touch the active game GL state.
@interface LibretroShaderPreviewGL : NSObject

+ (UIImage *_Nullable)renderImage:(UIImage *_Nonnull)image
                        shaderPath:(NSString *_Nonnull)shaderPath;

@end

NS_ASSUME_NONNULL_END
