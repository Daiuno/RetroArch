//
//  MetalToyView.mm
//  Libretro
//
//  Copyright © 2026 Manic EMU. All rights reserved.
//

#import "MetalToyView.h"

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>

#include <TargetConditionals.h>
#include <string.h>
#include <mutex>
#include <string>
#include <vector>

#ifdef HAVE_BUILTINGLSLANG
#include "../../deps/glslang/glslang/glslang/Public/ShaderLang.h"
#include "../../deps/glslang/glslang/StandAlone/ResourceLimits.h"
#include "../../deps/glslang/glslang/SPIRV/GlslangToSpv.h"
#include "../../deps/glslang/glslang/StandAlone/ResourceLimits.cpp"
#endif

#include "../../deps/SPIRV-Cross/spirv_msl.hpp"

#pragma mark - Shadertoy uniforms (std140, matches MSL `Uniforms` / Swift Uniforms.swift)

typedef struct
{
   float iResolution_x;
   float iResolution_y;
   float iResolution_z;
   float _pad0;
   float iTime;
   float _pad1;
   float _pad2;
   float _pad3;
   simd_float4 iMouse;
   simd_float2 iOffset;
   float _pad4;
   float _pad5;
   int32_t iFrame;
   float _pad6;
   float _pad7;
   float _pad8;
   float iTimeDelta;
   float _pad9;
   float _pad10;
   float _pad11;
   simd_float4 iDate;
   float iSampleRate;
   float _pad12;
   float _pad13;
   float _pad14;
   simd_float4 iChannelResolution[4];
   simd_float4 iChannelTime;
} mt_uniforms_t;

static_assert(sizeof(mt_uniforms_t) == 208, "mt_uniforms_t must match MetalToyKit Uniforms std140 layout");

#pragma mark - glslang compile guard

static std::mutex mt_glslang_mutex;

struct MTGlslangProcessHolder
{
   MTGlslangProcessHolder(void)
   {
      mt_glslang_mutex.lock();
#ifdef HAVE_BUILTINGLSLANG
      glslang::InitializeProcess();
#endif
   }

   ~MTGlslangProcessHolder(void)
   {
#ifdef HAVE_BUILTINGLSLANG
      glslang::FinalizeProcess();
#endif
      mt_glslang_mutex.unlock();
   }
};

#pragma mark - Shadertoy GLSL -> MSL transpiler

static BOOL mt_detect_texture_channel(NSString *source, int index)
{
   return [source containsString:[NSString stringWithFormat:@"iChannel%d", index]];
}

static NSString *_Nullable mt_compile_shadertoy_to_msl(NSString *shadertoyGLSL,
                                                      NSString *_Nullable *_Nullable errorOut)
{
#ifndef HAVE_BUILTINGLSLANG
   if (errorOut)
      *errorOut = @"Libretro was built without glslang support.";
   return nil;
#else
   MTGlslangProcessHolder process_holder;

   BOOL usedChannels[4];
   for (int i = 0; i < 4; i++)
      usedChannels[i] = mt_detect_texture_channel(shadertoyGLSL, i);

   NSMutableString *vulkanGLSL = [NSMutableString string];
   [vulkanGLSL appendString:@"#version 450\n\n"];
   [vulkanGLSL appendString:@"layout(location = 0) in vec2 vFragCoord;\n"];
   [vulkanGLSL appendString:@"layout(location = 0) out vec4 outColor;\n\n"];
   [vulkanGLSL appendString:@"layout(std140, set = 0, binding = 0) uniform ShadertoyUniforms {\n"];
   [vulkanGLSL appendString:@"    vec3 iResolution; float _pad0;\n"];
   [vulkanGLSL appendString:@"    float iTime; float _pad1; float _pad2; float _pad3;\n"];
   [vulkanGLSL appendString:@"    vec4 iMouse;\n"];
   [vulkanGLSL appendString:@"    vec2 iOffset; float _pad4; float _pad5;\n"];
   [vulkanGLSL appendString:@"    int iFrame; float _pad6; float _pad7; float _pad8;\n"];
   [vulkanGLSL appendString:@"    float iTimeDelta; float _pad9; float _pad10; float _pad11;\n"];
   [vulkanGLSL appendString:@"    vec4 iDate;\n"];
   [vulkanGLSL appendString:@"    float iSampleRate; float _pad12; float _pad13; float _pad14;\n"];
   [vulkanGLSL appendString:@"    vec4 iChannelResolution[4];\n"];
   [vulkanGLSL appendString:@"    vec4 iChannelTime;\n"];
   [vulkanGLSL appendString:@"};\n\n"];

   for (int i = 0; i < 4; i++)
   {
      if (usedChannels[i])
         [vulkanGLSL appendFormat:@"layout(set = 0, binding = %d) uniform sampler2D iChannel%d;\n", i + 1, i];
   }
   [vulkanGLSL appendString:@"\n"];
   [vulkanGLSL appendString:shadertoyGLSL];
   [vulkanGLSL appendString:@"\n\n"];
   [vulkanGLSL appendString:@"void main() {\n"];
   [vulkanGLSL appendString:@"    vec4 fragColor;\n"];
   [vulkanGLSL appendString:@"    mainImage(fragColor, vFragCoord);\n"];
   [vulkanGLSL appendString:@"    outColor = fragColor;\n"];
   [vulkanGLSL appendString:@"}\n"];

   std::string glslSource = [vulkanGLSL UTF8String];

   EShLanguage stage = EShLangFragment;
   glslang::TShader shader(stage);

   const char *shaderStrings[1] = { glslSource.c_str() };
   shader.setStrings(shaderStrings, 1);
   shader.setEnvInput(glslang::EShSourceGlsl, stage, glslang::EShClientVulkan, 100);
   shader.setEnvClient(glslang::EShClientVulkan, glslang::EShTargetVulkan_1_1);
   shader.setEnvTarget(glslang::EShTargetSpv, glslang::EShTargetSpv_1_3);

   const TBuiltInResource *resources = &glslang::DefaultTBuiltInResource;
   EShMessages messages = (EShMessages)(EShMsgSpvRules | EShMsgVulkanRules);

   if (!shader.parse(resources, 100, false, messages))
   {
      if (errorOut)
      {
         NSMutableString *errorMsg = [NSMutableString stringWithString:@"GLSL compilation failed:\n"];
         [errorMsg appendFormat:@"%s\n", shader.getInfoLog()];
         [errorMsg appendFormat:@"%s", shader.getInfoDebugLog()];
         *errorOut = errorMsg;
      }
      return nil;
   }

   glslang::TProgram program;
   program.addShader(&shader);

   if (!program.link(messages))
   {
      if (errorOut)
      {
         NSMutableString *errorMsg = [NSMutableString stringWithString:@"GLSL linking failed:\n"];
         [errorMsg appendFormat:@"%s\n", program.getInfoLog()];
         [errorMsg appendFormat:@"%s", program.getInfoDebugLog()];
         *errorOut = errorMsg;
      }
      return nil;
   }

   std::vector<uint32_t> spirv;
   glslang::SpvOptions spvOptions;
   spvOptions.generateDebugInfo = false;
   spvOptions.optimizeSize       = true;
   spvOptions.disableOptimizer   = false;
   glslang::GlslangToSpv(*program.getIntermediate(stage), spirv, &spvOptions);

   if (spirv.empty())
   {
      if (errorOut)
         *errorOut = @"Failed to generate SPIR-V";
      return nil;
   }

   try
   {
      spirv_cross::CompilerMSL msl(std::move(spirv));

      spirv_cross::CompilerMSL::Options mslOptions;
#if TARGET_OS_IPHONE
      mslOptions.platform = spirv_cross::CompilerMSL::Options::iOS;
#else
      mslOptions.platform = spirv_cross::CompilerMSL::Options::macOS;
#endif
      mslOptions.msl_version              = spirv_cross::CompilerMSL::Options::make_msl_version(2, 1);
      mslOptions.enable_decoration_binding = true;
      msl.set_msl_options(mslOptions);

      spirv_cross::MSLResourceBinding uboBinding;
      uboBinding.stage       = spv::ExecutionModelFragment;
      uboBinding.desc_set    = 0;
      uboBinding.binding     = 0;
      uboBinding.msl_buffer  = 0;
      msl.add_msl_resource_binding(uboBinding);

      for (int i = 0; i < 4; i++)
      {
         if (usedChannels[i])
         {
            spirv_cross::MSLResourceBinding texBinding;
            texBinding.stage        = spv::ExecutionModelFragment;
            texBinding.desc_set     = 0;
            texBinding.binding      = i + 1;
            texBinding.msl_texture  = i;
            texBinding.msl_sampler  = i;
            msl.add_msl_resource_binding(texBinding);
         }
      }

      std::string fragmentMSL = msl.compile();

      NSMutableString *completeMSL = [NSMutableString string];
      [completeMSL appendString:@"#include <metal_stdlib>\n"];
      [completeMSL appendString:@"using namespace metal;\n\n"];
      [completeMSL appendString:@"struct Uniforms {\n"];
      [completeMSL appendString:@"    packed_float3 iResolution; float _pad0;\n"];
      [completeMSL appendString:@"    float iTime; float _pad1; float _pad2; float _pad3;\n"];
      [completeMSL appendString:@"    float4 iMouse;\n"];
      [completeMSL appendString:@"    float2 iOffset; float _pad4; float _pad5;\n"];
      [completeMSL appendString:@"    int iFrame; float _pad6; float _pad7; float _pad8;\n"];
      [completeMSL appendString:@"    float iTimeDelta; float _pad9; float _pad10; float _pad11;\n"];
      [completeMSL appendString:@"    float4 iDate;\n"];
      [completeMSL appendString:@"    float iSampleRate; float _pad12; float _pad13; float _pad14;\n"];
      [completeMSL appendString:@"    float4 iChannelResolution[4];\n"];
      [completeMSL appendString:@"    float4 iChannelTime;\n"];
      [completeMSL appendString:@"};\n\n"];
      [completeMSL appendString:@"struct VertexOut {\n"];
      [completeMSL appendString:@"    float4 position [[position]];\n"];
      [completeMSL appendString:@"    float2 vFragCoord [[user(locn0)]];\n"];
      [completeMSL appendString:@"};\n\n"];
      [completeMSL appendString:@"vertex VertexOut vertexShader(uint vertexID [[vertex_id]],\n"];
      [completeMSL appendString:@"                               constant float2 *vertices [[buffer(0)]],\n"];
      [completeMSL appendString:@"                               constant Uniforms &uniforms [[buffer(1)]]) {\n"];
      [completeMSL appendString:@"    VertexOut out;\n"];
      [completeMSL appendString:@"    float2 pos = vertices[vertexID];\n"];
      [completeMSL appendString:@"    out.position = float4(pos, 0.0, 1.0);\n"];
      [completeMSL appendString:@"    out.vFragCoord = (pos * 0.5 + 0.5) * float2(uniforms.iResolution.x, uniforms.iResolution.y) + uniforms.iOffset;\n"];
      [completeMSL appendString:@"    return out;\n"];
      [completeMSL appendString:@"}\n\n"];
      [completeMSL appendString:@"inline float mod(float x, float y) { return x - y * floor(x / y); }\n"];
      [completeMSL appendString:@"inline float2 mod(float2 x, float2 y) { return x - y * floor(x / y); }\n"];
      [completeMSL appendString:@"inline float2 mod(float2 x, float y) { return x - y * floor(x / y); }\n"];
      [completeMSL appendString:@"inline float3 mod(float3 x, float3 y) { return x - y * floor(x / y); }\n"];
      [completeMSL appendString:@"inline float3 mod(float3 x, float y) { return x - y * floor(x / y); }\n"];
      [completeMSL appendString:@"inline float4 mod(float4 x, float4 y) { return x - y * floor(x / y); }\n"];
      [completeMSL appendString:@"inline float4 mod(float4 x, float y) { return x - y * floor(x / y); }\n\n"];
      [completeMSL appendFormat:@"// --- SPIRV-Cross generated fragment shader ---\n%s\n", fragmentMSL.c_str()];

      return [completeMSL stringByReplacingOccurrencesOfString:@"fragment main0_out main0("
                                                    withString:@"fragment main0_out fragmentShader("];
   }
   catch (const spirv_cross::CompilerError& e)
   {
      if (errorOut)
         *errorOut = [NSString stringWithFormat:@"SPIRV-Cross error: %s", e.what()];
      return nil;
   }
   catch (const std::exception& e)
   {
      if (errorOut)
         *errorOut = [NSString stringWithFormat:@"Exception: %s", e.what()];
      return nil;
   }
#endif
}

static const CGFloat kMTMinRenderScale = 0.25f;
static const CGFloat kMTMaxRenderScale = 1.0f;

static CGFloat mt_clamp_render_scale(CGFloat scale)
{
   if (scale < kMTMinRenderScale)
      return kMTMinRenderScale;
   if (scale > kMTMaxRenderScale)
      return kMTMaxRenderScale;
   return scale;
}

static BOOL mt_uses_offscreen_render_scale(CGFloat scale)
{
   return scale < (kMTMaxRenderScale - 0.001f);
}

static CGSize mt_shader_pixel_size(CGSize drawableSize, CGFloat renderScale)
{
   renderScale = mt_clamp_render_scale(renderScale);
   if (!mt_uses_offscreen_render_scale(renderScale))
      return drawableSize;

   const CGFloat w = fmax(1.0, floor(drawableSize.width * renderScale));
   const CGFloat h = fmax(1.0, floor(drawableSize.height * renderScale));
   return CGSizeMake(w, h);
}

static NSString * const mt_blit_msl =
@"#include <metal_stdlib>\n"
"using namespace metal;\n\n"
"struct BlitVertexOut {\n"
"    float4 position [[position]];\n"
"    float2 texCoord;\n"
"};\n\n"
"vertex BlitVertexOut blitVertex(uint vertexID [[vertex_id]],\n"
"                              constant float2 *vertices [[buffer(0)]]) {\n"
"    float2 pos = vertices[vertexID];\n"
"    BlitVertexOut out;\n"
"    out.position = float4(pos, 0.0, 1.0);\n"
"    // Metal textures are top-left origin; NDC +Y is up. Flip V so low-res\n"
"    // offscreen (Shadertoy bottom-left fragCoord) presents upright.\n"
"    out.texCoord = float2((pos.x + 1.0) * 0.5, (1.0 - pos.y) * 0.5);\n"
"    return out;\n"
"}\n\n"
"fragment float4 blitFragment(BlitVertexOut in [[stage_in]],\n"
"                             texture2d<float> source [[texture(0)]],\n"
"                             sampler sourceSampler [[sampler(0)]]) {\n"
"    return source.sample(sourceSampler, in.texCoord);\n"
"}\n";

static NSString *mt_compile_failure_message(NSString *glslSource)
{
   NSString *trimmed = [glslSource stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
   if (trimmed.length == 0)
      return @"GLSL source is empty.";

   NSString *error = nil;
   mt_compile_shadertoy_to_msl(trimmed, &error);
   return error ?: @"Failed to compile shader.";
}

#pragma mark - Private renderer

@interface MetalToyImagePassRenderer : NSObject <MTKViewDelegate>

@property (nonatomic, readonly) id<MTLDevice> device;
@property (nonatomic) simd_float4 mouse;
@property (nonatomic) CGFloat renderScale;

- (nullable instancetype)initWithMTKView:(MTKView *)mtkView
                              glslSource:(NSString *)glslSource
                                   error:(NSString *_Nullable *_Nullable)errorOut;

- (void)resetPlaybackClock;
- (void)resumePlaybackClock;

@end

@implementation MetalToyImagePassRenderer
{
   id<MTLCommandQueue> _queue;
   __weak MTKView *_mtkView;
   id<MTLRenderPipelineState> _pipeline;
   id<MTLRenderPipelineState> _blitPipeline;
   id<MTLTexture> _dummyTexture;
   id<MTLTexture> _offscreenTexture;
   id<MTLBuffer> _vertexBuffer;
   id<MTLBuffer> _uniformBuffer;
   id<MTLSamplerState> _channelSampler;
   CGSize _lastOffscreenSize;
   CFTimeInterval _startTime;
   CFTimeInterval _lastFrameTime;
   int32_t _frameIndex;
}

@synthesize device       = _device;
@synthesize mouse        = _mouse;
@synthesize renderScale  = _renderScale;

- (nullable instancetype)initWithMTKView:(MTKView *)mtkView
                              glslSource:(NSString *)glslSource
                                   error:(NSString *_Nullable *_Nullable)errorOut
{
   NSString *source = [glslSource stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
   if (source.length == 0)
   {
      if (errorOut)
         *errorOut = @"GLSL source is empty.";
      return nil;
   }

   id<MTLDevice> device = mtkView.device ?: MTLCreateSystemDefaultDevice();
   id<MTLCommandQueue> queue = [device newCommandQueue];
   if (!device || !queue)
   {
      if (errorOut)
         *errorOut = @"Failed to create Metal device or command queue.";
      return nil;
   }

   MTLTextureDescriptor *texDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                     width:1
                                                                                    height:1
                                                                                 mipmapped:NO];
   texDesc.usage = MTLTextureUsageShaderRead;
   id<MTLTexture> dummy = [device newTextureWithDescriptor:texDesc];
   if (!dummy)
   {
      if (errorOut)
         *errorOut = @"Failed to create dummy channel texture.";
      return nil;
   }

   const uint8_t black[4] = {0, 0, 0, 255};
   [dummy replaceRegion:MTLRegionMake2D(0, 0, 1, 1)
            mipmapLevel:0
              withBytes:black
            bytesPerRow:4];

   const simd_float2 vertices[4] = {
      simd_make_float2(-1.f, -1.f),
      simd_make_float2( 1.f, -1.f),
      simd_make_float2(-1.f,  1.f),
      simd_make_float2( 1.f,  1.f),
   };

   id<MTLBuffer> vbuf = [device newBufferWithBytes:vertices
                                             length:sizeof(vertices)
                                            options:MTLResourceStorageModeShared];
   id<MTLBuffer> ubuf = [device newBufferWithLength:sizeof(mt_uniforms_t)
                                            options:MTLResourceStorageModeShared];
   if (!vbuf || !ubuf)
   {
      if (errorOut)
         *errorOut = @"Failed to create Metal buffers.";
      return nil;
   }

   MTLSamplerDescriptor *samplerDesc = [MTLSamplerDescriptor new];
   samplerDesc.minFilter     = MTLSamplerMinMagFilterLinear;
   samplerDesc.magFilter     = MTLSamplerMinMagFilterLinear;
   samplerDesc.sAddressMode  = MTLSamplerAddressModeClampToEdge;
   samplerDesc.tAddressMode  = MTLSamplerAddressModeClampToEdge;
   id<MTLSamplerState> sampler = [device newSamplerStateWithDescriptor:samplerDesc];
   if (!sampler)
   {
      if (errorOut)
         *errorOut = @"Failed to create sampler state.";
      return nil;
   }

   NSString *msl = mt_compile_shadertoy_to_msl(source, errorOut);
   if (!msl)
      return nil;

   NSError *metalError = nil;
   id<MTLLibrary> library = [device newLibraryWithSource:msl options:nil error:&metalError];
   if (!library)
   {
      if (errorOut)
         *errorOut = metalError.localizedDescription ?: @"Metal library compilation failed.";
      return nil;
   }

   id<MTLFunction> vfn = [library newFunctionWithName:@"vertexShader"];
   id<MTLFunction> ffn = [library newFunctionWithName:@"fragmentShader"];
   if (!vfn || !ffn)
   {
      if (errorOut)
         *errorOut = @"Missing vertexShader/fragmentShader entry points.";
      return nil;
   }

   MTLRenderPipelineDescriptor *pipeDesc = [MTLRenderPipelineDescriptor new];
   pipeDesc.vertexFunction   = vfn;
   pipeDesc.fragmentFunction = ffn;
   pipeDesc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;

   id<MTLRenderPipelineState> pipeline = [device newRenderPipelineStateWithDescriptor:pipeDesc error:&metalError];
   if (!pipeline)
   {
      if (errorOut)
         *errorOut = metalError.localizedDescription ?: @"Failed to create render pipeline.";
      return nil;
   }

   id<MTLLibrary> blitLibrary = [device newLibraryWithSource:mt_blit_msl options:nil error:&metalError];
   id<MTLFunction> blitVertex = [blitLibrary newFunctionWithName:@"blitVertex"];
   id<MTLFunction> blitFragment = [blitLibrary newFunctionWithName:@"blitFragment"];
   if (!blitLibrary || !blitVertex || !blitFragment)
   {
      if (errorOut)
         *errorOut = metalError.localizedDescription ?: @"Failed to compile upscale blit shader.";
      return nil;
   }

   MTLRenderPipelineDescriptor *blitDesc = [MTLRenderPipelineDescriptor new];
   blitDesc.vertexFunction   = blitVertex;
   blitDesc.fragmentFunction = blitFragment;
   blitDesc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
   id<MTLRenderPipelineState> blitPipeline = [device newRenderPipelineStateWithDescriptor:blitDesc error:&metalError];
   if (!blitPipeline)
   {
      if (errorOut)
         *errorOut = metalError.localizedDescription ?: @"Failed to create upscale blit pipeline.";
      return nil;
   }

   self = [super init];
   if (!self)
      return nil;

   _device         = device;
   _queue          = queue;
   _mtkView        = mtkView;
   _pipeline       = pipeline;
   _blitPipeline   = blitPipeline;
   _dummyTexture   = dummy;
   _offscreenTexture = nil;
   _vertexBuffer   = vbuf;
   _uniformBuffer  = ubuf;
   _channelSampler = sampler;
   _renderScale    = kMTMaxRenderScale;
   _lastOffscreenSize = CGSizeZero;
   _mouse          = simd_make_float4(-1.f, -1.f, -1.f, -1.f);
   _startTime      = CACurrentMediaTime();
   _lastFrameTime  = _startTime;
   _frameIndex     = 0;

   mtkView.device                     = device;
   mtkView.colorPixelFormat           = MTLPixelFormatBGRA8Unorm;
   mtkView.clearColor                 = MTLClearColorMake(0, 0, 0, 1);
   mtkView.framebufferOnly            = YES;
   mtkView.preferredFramesPerSecond   = 60;
   mtkView.enableSetNeedsDisplay      = NO;
   mtkView.paused                   = YES;
   mtkView.delegate                   = self;

   return self;
}

- (void)resetPlaybackClock
{
   CFTimeInterval now = CACurrentMediaTime();
   _startTime     = now;
   _lastFrameTime = now;
   _frameIndex    = 0;
}

- (void)resumePlaybackClock
{
   CFTimeInterval now = CACurrentMediaTime();
   _startTime += now - _lastFrameTime;
   _lastFrameTime = now;
}

- (void)setRenderScale:(CGFloat)renderScale
{
   renderScale = mt_clamp_render_scale(renderScale);
   if (_renderScale == renderScale)
      return;

   _renderScale = renderScale;
   _offscreenTexture = nil;
   _lastOffscreenSize = CGSizeZero;
}

- (void)mt_ensureOffscreenTextureForShaderSize:(CGSize)shaderSize pixelFormat:(MTLPixelFormat)pixelFormat
{
   if (shaderSize.width < 1.0 || shaderSize.height < 1.0)
      return;

   const NSUInteger width  = (NSUInteger)shaderSize.width;
   const NSUInteger height = (NSUInteger)shaderSize.height;
   if (_offscreenTexture &&
       _offscreenTexture.width == width &&
       _offscreenTexture.height == height &&
       _offscreenTexture.pixelFormat == pixelFormat)
      return;

   MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pixelFormat
                                                                                   width:width
                                                                                  height:height
                                                                               mipmapped:NO];
   desc.usage       = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
   desc.storageMode = MTLStorageModePrivate;
   _offscreenTexture = [_device newTextureWithDescriptor:desc];
   _lastOffscreenSize = shaderSize;
}

- (mt_uniforms_t)mt_makeUniformsForShaderSize:(CGSize)shaderSize
                                    mouseScale:(CGFloat)mouseScale
                                         elapsed:(CFTimeInterval)elapsed
                                              dt:(CFTimeInterval)dt
{
   mt_uniforms_t u;
   memset(&u, 0, sizeof(u));
   u.iResolution_x = (float)shaderSize.width;
   u.iResolution_y = (float)shaderSize.height;
   u.iResolution_z = 1.f;
   u.iTime       = (float)elapsed;
   u.iTimeDelta  = (float)dt;
   u.iFrame      = _frameIndex;
   u.iMouse      = simd_make_float4(_mouse.x * mouseScale,
                                    _mouse.y * mouseScale,
                                    _mouse.z * mouseScale,
                                    _mouse.w * mouseScale);
   u.iOffset     = simd_make_float2(0.f, 0.f);
   u.iSampleRate = 44100.f;
   u.iChannelTime = simd_make_float4((float)elapsed, (float)elapsed, (float)elapsed, (float)elapsed);

   const simd_float4 channelRes = simd_make_float4(1.f, 1.f, 1.f, 1.f);
   u.iChannelResolution[0] = channelRes;
   u.iChannelResolution[1] = channelRes;
   u.iChannelResolution[2] = channelRes;
   u.iChannelResolution[3] = channelRes;
   return u;
}

- (void)mt_encodeShaderPass:(id<MTLRenderCommandEncoder>)enc uniforms:(const mt_uniforms_t *)uniforms
{
   memcpy([_uniformBuffer contents], uniforms, sizeof(mt_uniforms_t));
   [enc setRenderPipelineState:_pipeline];
   [enc setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
   [enc setVertexBuffer:_uniformBuffer offset:0 atIndex:1];
   [enc setFragmentBuffer:_uniformBuffer offset:0 atIndex:0];
   for (NSUInteger i = 0; i < 4; i++)
   {
      [enc setFragmentTexture:_dummyTexture atIndex:i];
      [enc setFragmentSamplerState:_channelSampler atIndex:i];
   }
   [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

- (void)mt_encodeBlitPass:(id<MTLRenderCommandEncoder>)enc
{
   [enc setRenderPipelineState:_blitPipeline];
   [enc setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
   [enc setFragmentTexture:_offscreenTexture atIndex:0];
   [enc setFragmentSamplerState:_channelSampler atIndex:0];
   [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
{
   (void)view;
   if (size.width < 1.0 || size.height < 1.0)
      return;

   const CGSize shaderSize = mt_shader_pixel_size(size, _renderScale);
   if (!CGSizeEqualToSize(shaderSize, _lastOffscreenSize))
   {
      _offscreenTexture = nil;
      _lastOffscreenSize = CGSizeZero;
   }
}

- (void)drawInMTKView:(MTKView *)view
{
   if (!_pipeline || !_blitPipeline)
      return;

   id<CAMetalDrawable> drawable = view.currentDrawable;
   id<MTLCommandBuffer> cmd = [_queue commandBuffer];
   MTLRenderPassDescriptor *drawableRPD = view.currentRenderPassDescriptor;
   if (!drawable || !cmd || !drawableRPD)
      return;

   const CGSize drawableSize = view.drawableSize;
   if (drawableSize.width < 1.0 || drawableSize.height < 1.0)
      return;

   CFTimeInterval now     = CACurrentMediaTime();
   CFTimeInterval elapsed = now - _startTime;
   CFTimeInterval dt      = now - _lastFrameTime;
   _lastFrameTime         = now;
   _frameIndex++;

   const CGFloat renderScale = mt_clamp_render_scale(_renderScale);
   const CGSize shaderSize   = mt_shader_pixel_size(drawableSize, renderScale);
   const BOOL useOffscreen   = mt_uses_offscreen_render_scale(renderScale);
   const mt_uniforms_t uniforms = [self mt_makeUniformsForShaderSize:shaderSize
                                                          mouseScale:useOffscreen ? renderScale : 1.f
                                                             elapsed:elapsed
                                                                  dt:dt];

   if (useOffscreen)
   {
      [self mt_ensureOffscreenTextureForShaderSize:shaderSize pixelFormat:view.colorPixelFormat];
      if (!_offscreenTexture)
         return;

      MTLRenderPassDescriptor *shaderRPD = [MTLRenderPassDescriptor renderPassDescriptor];
      shaderRPD.colorAttachments[0].texture     = _offscreenTexture;
      shaderRPD.colorAttachments[0].loadAction  = MTLLoadActionClear;
      shaderRPD.colorAttachments[0].storeAction = MTLStoreActionStore;
      shaderRPD.colorAttachments[0].clearColor  = view.clearColor;

      id<MTLRenderCommandEncoder> shaderEnc = [cmd renderCommandEncoderWithDescriptor:shaderRPD];
      if (!shaderEnc)
         return;
      [self mt_encodeShaderPass:shaderEnc uniforms:&uniforms];
      [shaderEnc endEncoding];

      id<MTLRenderCommandEncoder> blitEnc = [cmd renderCommandEncoderWithDescriptor:drawableRPD];
      if (!blitEnc)
         return;
      [self mt_encodeBlitPass:blitEnc];
      [blitEnc endEncoding];
   }
   else
   {
      id<MTLRenderCommandEncoder> enc = [cmd renderCommandEncoderWithDescriptor:drawableRPD];
      if (!enc)
         return;
      [self mt_encodeShaderPass:enc uniforms:&uniforms];
      [enc endEncoding];
   }

   [cmd presentDrawable:drawable];
   [cmd commit];
}

- (void)teardown
{
   _mtkView.delegate = nil;
   _mtkView.paused = YES;
   _pipeline         = nil;
   _blitPipeline     = nil;
   _dummyTexture     = nil;
   _offscreenTexture = nil;
   _vertexBuffer     = nil;
   _uniformBuffer    = nil;
   _channelSampler   = nil;
   _queue            = nil;
}

- (void)dealloc
{
   [self teardown];
}

@end

#pragma mark - MetalToyView

@implementation MetalToyView
{
   MTKView *_metalView;
   MetalToyImagePassRenderer *_renderer;
   BOOL _shaderReady;
   NSString *_lastCompileError;
   CGFloat _renderScale;
}

@synthesize shaderReady = _shaderReady;
@synthesize lastCompileError = _lastCompileError;

- (instancetype)initWithFrame:(CGRect)frame glslSource:(NSString *)glslSource
{
   self = [super initWithFrame:frame];
   if (!self)
      return nil;

   _renderScale = kMTMaxRenderScale;
   self.backgroundColor = UIColor.blackColor;

   id<MTLDevice> device = MTLCreateSystemDefaultDevice();
   MTKView *mtkView = [[MTKView alloc] initWithFrame:self.bounds device:device];
   _metalView = mtkView;

   NSString *compileError = nil;
   MetalToyImagePassRenderer *renderer = [[MetalToyImagePassRenderer alloc] initWithMTKView:mtkView
                                                                                 glslSource:glslSource
                                                                                      error:&compileError];
   _renderer = renderer;
   if (renderer)
   {
      _shaderReady      = YES;
      _lastCompileError = nil;
      _renderer.renderScale = _renderScale;
   }
   else
   {
      _shaderReady      = NO;
      _lastCompileError = compileError ?: mt_compile_failure_message(glslSource);
      mtkView.paused    = YES;
      mtkView.delegate  = nil;
   }

   mtkView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
   [self addSubview:mtkView];

   return self;
}

- (instancetype)initWithGlslSource:(NSString *)glslSource
{
   return [self initWithFrame:CGRectZero glslSource:glslSource];
}

- (simd_float4)mouse
{
   return _renderer ? _renderer.mouse : simd_make_float4(-1.f, -1.f, -1.f, -1.f);
}

- (void)setMouse:(simd_float4)mouse
{
   if (_renderer)
      _renderer.mouse = mouse;
}

- (NSInteger)preferredFramesPerSecond
{
   return _metalView.preferredFramesPerSecond;
}

- (void)setPreferredFramesPerSecond:(NSInteger)preferredFramesPerSecond
{
   _metalView.preferredFramesPerSecond = preferredFramesPerSecond;
}

- (CGFloat)renderScale
{
   return _renderScale;
}

- (void)setRenderScale:(CGFloat)renderScale
{
   renderScale = mt_clamp_render_scale(renderScale);
   if (_renderScale == renderScale)
      return;

   _renderScale = renderScale;
   _renderer.renderScale = renderScale;
}

- (void)layoutSubviews
{
   [super layoutSubviews];
   _metalView.frame = self.bounds;
}

- (void)start
{
   if (!_shaderReady)
      return;
   [_renderer resumePlaybackClock];
   _metalView.paused = NO;
}

- (void)pause
{
   _metalView.paused = YES;
}

- (void)stop
{
   _metalView.paused = YES;
   [_renderer resetPlaybackClock];
}

- (void)removeFromSuperview
{
   [self pause];
   [super removeFromSuperview];
}

- (void)willMoveToSuperview:(UIView *)newSuperview
{
   if (!newSuperview)
      [self pause];
   [super willMoveToSuperview:newSuperview];
}

- (void)dealloc
{
   [_renderer teardown];
   _metalView.delegate = nil;
   _metalView.paused = YES;
}

@end
