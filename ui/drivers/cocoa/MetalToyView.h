//
//  MetalToyView.h
//  Libretro
//
//  Copyright © 2026 Manic EMU. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

/// Single-pass Shadertoy Image shader preview in UIKit.
///
/// Does not touch the active game video driver, RetroArch shader state, or core runloop.
/// Create and use on the main thread only. Call `pause` or remove from hierarchy before gameplay.
@interface MetalToyView : UIView

@property (nonatomic, readonly, getter=isShaderReady) BOOL shaderReady;
@property (nonatomic, readonly, copy, nullable) NSString *lastCompileError;

/// Shadertoy `iMouse` (pixels, origin bottom-left). Default `(-1,-1,-1,-1)`.
@property (nonatomic) simd_float4 mouse;

@property (nonatomic) NSInteger preferredFramesPerSecond;

/// Internal shader resolution as a fraction of the drawable size (0.25–1.0). Default `1.0`.
/// Values below `1.0` render at lower resolution and upscale to fill the view, reducing GPU load.
@property (nonatomic) CGFloat renderScale;

/// Frame-based: `initWithFrame:glslSource:` then `addSubview:` (default autoresizing mask).
/// Auto Layout: `initWithGlslSource:` or `CGRectZero`, set `translatesAutoresizingMaskIntoConstraints = NO`, add constraints.
- (instancetype)initWithFrame:(CGRect)frame glslSource:(NSString *)glslSource;
- (instancetype)initWithGlslSource:(NSString *)glslSource;

- (void)start;
- (void)pause;
- (void)stop;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
