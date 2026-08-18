//
//  LibretroShaderPreview.m
//  Libretro
//
//  Copyright © 2025 Manic EMU. All rights reserved.
//

#import "LibretroShaderPreview.h"
#import "LibretroShaderPreviewCommon.h"
#import "LibretroShaderPreviewGL.h"

#import <Metal/Metal.h>
#import <CoreImage/CoreImage.h>
#import <simd/simd.h>

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#include "../../configuration.h"
#include "../../gfx/video_shader_parse.h"
#include "../../gfx/drivers_shader/slang_process.h"
#include "../../gfx/common/metal_common.h"
#include "../../gfx/common/metal/metal_common.h"
#include "../../gfx/common/metal/metal_shader_types.h"
#include "../../gfx/video_driver.h"
#include "../../runloop.h"
#include <formats/image.h>
#include "../../verbosity.h"

#if defined(HAVE_COCOATOUCH)
#define LSP_RESOURCE_STORAGE MTLResourceStorageModeShared
#else
#define LSP_RESOURCE_STORAGE MTLResourceStorageModeManaged
#endif

typedef struct
{
   float x;
   float y;
   float z;
   float w;
} lsp_float4_t;

typedef struct
{
   __unsafe_unretained id<MTLTexture> view;
   lsp_float4_t size_data;
} lsp_texture_t;

typedef struct
{
   matrix_float4x4 mvp;
   matrix_float4x4 projection;

   struct
   {
      lsp_texture_t texture[GFX_MAX_FRAME_HISTORY + 1];
      MTLViewport viewport;
      lsp_float4_t output_size;
   } frame;

   struct
   {
      __unsafe_unretained id<MTLBuffer> buffers[SLANG_CBUFFER_MAX];
      lsp_texture_t rt;
      lsp_texture_t feedback;
      uint32_t frame_count;
      int32_t frame_direction;
      int32_t frame_time_delta;
      float original_fps;
      uint32_t rotation;
      float core_aspect;
      float core_aspect_rot;
      pass_semantics_t semantics;
      MTLViewport viewport;
      __unsafe_unretained id<MTLRenderPipelineState> pipeline;
   } pass[GFX_MAX_SHADERS];

   lsp_texture_t luts[GFX_MAX_TEXTURES];
} lsp_engine_t;

@interface LibretroShaderPreviewContext : NSObject
{
   id<MTLSamplerState> _samplers[RARCH_FILTER_MAX][RARCH_WRAP_MAX];
   VertexSlang _vertices[4];
}
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> queue;
@property (nonatomic, copy) NSString *shaderPath;
@property (nonatomic, assign) NSUInteger imageWidth;
@property (nonatomic, assign) NSUInteger imageHeight;
@property (nonatomic, assign) struct video_shader *shader;
@property (nonatomic, assign) lsp_engine_t engine;
@property (nonatomic, assign) video_viewport_t viewport;
@property (nonatomic, strong) NSMutableArray<id> *metalObjects;
@end

@implementation LibretroShaderPreviewContext

- (void)dealloc
{
   [self freeShader];
}

- (void)trackObject:(id)obj
{
   if (obj)
      [_metalObjects addObject:obj];
}

- (void)freeShader
{
   if (!_shader)
      return;

   _metalObjects = [NSMutableArray array];
   memset(&_engine, 0, sizeof(_engine));
   memset(_samplers, 0, sizeof(_samplers));

   free(_shader);
   _shader = NULL;

   if (_device)
      [self initSamplers];
}

- (void)initSamplers
{
   MTLSamplerDescriptor *sd = [MTLSamplerDescriptor new];

   for (int i = 0; i < RARCH_WRAP_MAX; i++)
   {
      switch (i)
      {
         case RARCH_WRAP_BORDER:
#if defined(HAVE_COCOATOUCH)
            sd.sAddressMode = MTLSamplerAddressModeClampToZero;
#else
            sd.sAddressMode = MTLSamplerAddressModeClampToBorderColor;
#endif
            break;
         case RARCH_WRAP_EDGE:
            sd.sAddressMode = MTLSamplerAddressModeClampToEdge;
            break;
         case RARCH_WRAP_REPEAT:
            sd.sAddressMode = MTLSamplerAddressModeRepeat;
            break;
         case RARCH_WRAP_MIRRORED_REPEAT:
            sd.sAddressMode = MTLSamplerAddressModeMirrorRepeat;
            break;
         default:
            continue;
      }
      sd.tAddressMode = sd.sAddressMode;
      sd.rAddressMode = sd.sAddressMode;
      sd.minFilter    = MTLSamplerMinMagFilterLinear;
      sd.magFilter    = MTLSamplerMinMagFilterLinear;
      id<MTLSamplerState> linear = [_device newSamplerStateWithDescriptor:sd];
      _samplers[RARCH_FILTER_LINEAR][i] = linear;
      [self trackObject:linear];

      sd.minFilter = MTLSamplerMinMagFilterNearest;
      sd.magFilter = MTLSamplerMinMagFilterNearest;
      id<MTLSamplerState> nearest = [_device newSamplerStateWithDescriptor:sd];
      _samplers[RARCH_FILTER_NEAREST][i] = nearest;
      [self trackObject:nearest];
   }

   for (int i = 0; i < RARCH_WRAP_MAX; i++)
      _samplers[RARCH_FILTER_UNSPEC][i] = _samplers[RARCH_FILTER_LINEAR][i];
}

- (void)setupDefaultVertices
{
   VertexSlang v[4] = {
      {simd_make_float4(0, 1, 0, 1), simd_make_float2(0, 1)},
      {simd_make_float4(1, 1, 0, 1), simd_make_float2(1, 1)},
      {simd_make_float4(0, 0, 0, 1), simd_make_float2(0, 0)},
      {simd_make_float4(1, 0, 0, 1), simd_make_float2(1, 0)},
   };
   memcpy(_vertices, v, sizeof(v));
}

- (void)initTexture:(lsp_texture_t *)t descriptor:(MTLTextureDescriptor *)td
{
   id<MTLTexture> tex = [_device newTextureWithDescriptor:td];
   t->view        = tex;
   [self trackObject:tex];
   t->size_data.x = (float)td.width;
   t->size_data.y = (float)td.height;
   t->size_data.z = 1.0f / (float)td.width;
   t->size_data.w = 1.0f / (float)td.height;
}

- (BOOL)loadShaderFromPath:(NSString *)path
{
   [self freeShader];

   struct video_shader *shader = (struct video_shader *)calloc(1, sizeof(*shader));
   if (!shader)
      return NO;

   if (!video_shader_load_preset_into_shader(path.UTF8String, shader))
   {
      free(shader);
      return NO;
   }

   if (!config_get_ptr())
   {
      free(shader);
      return NO;
   }

   /* Pipeline labels only; preset/shader file resolution uses conf->path in
    * video_shader_parse_pass(), not directory_video_shader. */
   NSString *shadersPath = [[path stringByDeletingLastPathComponent] stringByAppendingString:@"/"];

   _engine.mvp        = matrix_proj_ortho(0, 1, 0, 1);
   _engine.projection = matrix_proj_ortho(0, 1, 0, 1);
   lsp_texture_t *source = &_engine.frame.texture[0];

   for (int i = 0; i < shader->passes; source = &_engine.pass[i++].rt)
   {
      matrix_float4x4 *mvp = (i == shader->passes - 1)
         ? &_engine.projection
         : &_engine.mvp;

      semantics_map_t semantics_map = {
         {
            {&_engine.frame.texture[0].view, 0,
             &_engine.frame.texture[0].size_data, 0},
            {&source->view, 0, &source->size_data, 0},
            {&_engine.frame.texture[0].view, (size_t)sizeof(_engine.frame.texture[0]),
             &_engine.frame.texture[0].size_data, (size_t)sizeof(_engine.frame.texture[0])},
            {&_engine.pass[0].rt.view, (size_t)sizeof(_engine.pass[0]),
             &_engine.pass[0].rt.size_data, (size_t)sizeof(_engine.pass[0])},
            {&_engine.pass[0].feedback.view, (size_t)sizeof(_engine.pass[0]),
             &_engine.pass[0].feedback.size_data, (size_t)sizeof(_engine.pass[0])},
            {&_engine.luts[0].view, (size_t)sizeof(_engine.luts[0]),
             &_engine.luts[0].size_data, (size_t)sizeof(_engine.luts[0])},
         },
         {
            mvp,
            &_engine.pass[i].rt.size_data,
            &_engine.frame.output_size,
            &_engine.pass[i].frame_count,
            &_engine.pass[i].frame_direction,
            &_engine.pass[i].frame_time_delta,
            &_engine.pass[i].original_fps,
            &_engine.pass[i].rotation,
            &_engine.pass[i].core_aspect,
            &_engine.pass[i].core_aspect_rot,
         }
      };

      if (!slang_process(shader, (unsigned)i, RARCH_SHADER_METAL, 20000, &semantics_map, &_engine.pass[i].semantics))
      {
         [self freeShader];
         return NO;
      }

      char *vs_src_c = shader->pass[i].source.string.vertex;
      char *fs_src_c = shader->pass[i].source.string.fragment;
      if (!vs_src_c || !fs_src_c)
      {
         [self freeShader];
         return NO;
      }

      NSString *vs_src = [NSString stringWithUTF8String:vs_src_c];
      NSString *fs_src = [NSString stringWithUTF8String:fs_src_c];

      MTLVertexDescriptor *vd = [MTLVertexDescriptor new];
      vd.attributes[0].offset    = offsetof(VertexSlang, position);
      vd.attributes[0].format      = MTLVertexFormatFloat4;
      vd.attributes[0].bufferIndex = 4;
      vd.attributes[1].offset      = offsetof(VertexSlang, texCoord);
      vd.attributes[1].format      = MTLVertexFormatFloat2;
      vd.attributes[1].bufferIndex = 4;
      vd.layouts[4].stride         = sizeof(VertexSlang);
      vd.layouts[4].stepFunction   = MTLVertexStepFunctionPerVertex;

      MTLRenderPipelineDescriptor *psd = [MTLRenderPipelineDescriptor new];
      psd.label = [[NSString stringWithUTF8String:shader->pass[i].source.path]
                   stringByReplacingOccurrencesOfString:shadersPath withString:@""];

      MTLRenderPipelineColorAttachmentDescriptor *ca = psd.colorAttachments[0];
      ca.pixelFormat     = SelectOptimalPixelFormat(glslang_format_to_metal(_engine.pass[i].semantics.format));
      ca.blendingEnabled = NO;
      psd.sampleCount      = 1;
      psd.vertexDescriptor = vd;

      NSError *err = nil;
      id<MTLLibrary> lib = [_device newLibraryWithSource:vs_src options:nil error:&err];
      if (!lib)
      {
         RARCH_ERR("[ShaderPreview]: vertex shader compile failed: %s\n",
                   err.localizedDescription.UTF8String ?: "unknown");
         [self freeShader];
         return NO;
      }
      psd.vertexFunction = [lib newFunctionWithName:@"main0"];

      lib = [_device newLibraryWithSource:fs_src options:nil error:&err];
      if (!lib)
      {
         RARCH_ERR("[ShaderPreview]: fragment shader compile failed: %s\n",
                   err.localizedDescription.UTF8String ?: "unknown");
         [self freeShader];
         return NO;
      }
      psd.fragmentFunction = [lib newFunctionWithName:@"main0"];

      id<MTLRenderPipelineState> pipeline = [_device newRenderPipelineStateWithDescriptor:psd error:&err];
      _engine.pass[i].pipeline = pipeline;
      [self trackObject:pipeline];
      if (!_engine.pass[i].pipeline)
      {
         RARCH_ERR("[ShaderPreview]: pipeline creation failed pass %d: %s\n", i,
                   err.localizedDescription.UTF8String ?: "unknown");
         [self freeShader];
         return NO;
      }

      for (unsigned j = 0; j < SLANG_CBUFFER_MAX; j++)
      {
         unsigned size = _engine.pass[i].semantics.cbuffers[j].size;
         if (size == 0)
            continue;
         id<MTLBuffer> buf = [_device newBufferWithLength:size options:LSP_RESOURCE_STORAGE];
         _engine.pass[i].buffers[j] = buf;
         [self trackObject:buf];
      }

      free(shader->pass[i].source.string.vertex);
      free(shader->pass[i].source.string.fragment);
      shader->pass[i].source.string.vertex   = NULL;
      shader->pass[i].source.string.fragment = NULL;
   }

   for (int i = 0; i < shader->luts; i++)
   {
      struct texture_image image;
      image.pixels        = NULL;
      image.width         = 0;
      image.height        = 0;
      image.supports_rgba = true;

      if (!image_texture_load(&image, shader->lut[i].path))
      {
         [self freeShader];
         return NO;
      }

      MTLTextureDescriptor *td =
         [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                            width:image.width
                                                           height:image.height
                                                        mipmapped:shader->lut[i].mipmap];
      td.usage = MTLTextureUsageShaderRead;
      [self initTexture:&_engine.luts[i] descriptor:td];
      [_engine.luts[i].view replaceRegion:MTLRegionMake2D(0, 0, image.width, image.height)
                              mipmapLevel:0
                                withBytes:image.pixels
                              bytesPerRow:4 * image.width];
      image_texture_free(&image);
   }

   _shader     = shader;
   _shaderPath = [path copy];
   return YES;
}

- (void)updateRenderTargets
{
   if (!_shader)
      return;

   NSUInteger width  = _imageWidth;
   NSUInteger height = _imageHeight;

   for (int i = 0; i < _shader->passes; i++)
   {
      _engine.pass[i].rt.view       = nil;
      _engine.pass[i].feedback.view = nil;
   }

   for (int i = 0; i < _shader->passes; i++)
   {
      struct video_shader_pass *shader_pass = &_shader->pass[i];

      if (shader_pass->fbo.flags & FBO_SCALE_FLAG_VALID)
      {
         switch (shader_pass->fbo.type_x)
         {
            case RARCH_SCALE_INPUT:
               width = (NSUInteger)((float)width * shader_pass->fbo.scale_x);
               break;
            case RARCH_SCALE_VIEWPORT:
               width = (NSUInteger)(_viewport.width * shader_pass->fbo.scale_x);
               break;
            case RARCH_SCALE_ABSOLUTE:
               width = shader_pass->fbo.abs_x;
               break;
            default:
               break;
         }
         if (!width)
            width = _viewport.width;

         switch (shader_pass->fbo.type_y)
         {
            case RARCH_SCALE_INPUT:
               height = (NSUInteger)((float)height * shader_pass->fbo.scale_y);
               break;
            case RARCH_SCALE_VIEWPORT:
               height = (NSUInteger)(_viewport.height * shader_pass->fbo.scale_y);
               break;
            case RARCH_SCALE_ABSOLUTE:
               height = shader_pass->fbo.abs_y;
               break;
            default:
               break;
         }
         if (!height)
            height = _viewport.height;
      }
      else if (i == (_shader->passes - 1))
      {
         width  = _viewport.width;
         height = _viewport.height;
      }

      MTLPixelFormat fmt = SelectOptimalPixelFormat(glslang_format_to_metal(_engine.pass[i].semantics.format));

      _engine.pass[i].viewport.originX = 0;
      _engine.pass[i].viewport.originY = 0;
      _engine.pass[i].viewport.width   = width;
      _engine.pass[i].viewport.height  = height;
      _engine.pass[i].viewport.znear   = 0.0;
      _engine.pass[i].viewport.zfar    = 1.0;

      MTLTextureDescriptor *td =
         [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:fmt
                                                            width:width
                                                           height:height
                                                        mipmapped:NO];
      td.storageMode = LSP_RESOURCE_STORAGE;
      td.usage       = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
      [self initTexture:&_engine.pass[i].rt descriptor:td];

      if (shader_pass->feedback)
         [self initTexture:&_engine.pass[i].feedback descriptor:td];
   }
}

- (BOOL)uploadSourcePixels:(const uint8_t *)pixels width:(NSUInteger)width height:(NSUInteger)height bytesPerRow:(NSUInteger)bytesPerRow
{
   if (!_shader)
      return NO;

   BOOL sizeChanged = (_imageWidth != width || _imageHeight != height);
   _imageWidth  = width;
   _imageHeight = height;
   _viewport.x  = 0;
   _viewport.y  = 0;
   _viewport.width       = width;
   _viewport.height      = height;
   _viewport.full_width  = width;
   _viewport.full_height = height;

   _engine.frame.viewport.originX = 0;
   _engine.frame.viewport.originY = 0;
   _engine.frame.viewport.width   = width;
   _engine.frame.viewport.height  = height;
   _engine.frame.viewport.znear   = 0.0;
   _engine.frame.viewport.zfar    = 1.0;
   _engine.frame.output_size.x    = (float)width;
   _engine.frame.output_size.y    = (float)height;
   _engine.frame.output_size.z    = 1.0f / (float)width;
   _engine.frame.output_size.w    = 1.0f / (float)height;

   float aspect = (height > 0) ? ((float)width / (float)height) : 1.0f;
   for (int i = 0; i < _shader->passes; i++)
   {
      _engine.pass[i].frame_count      = 0;
      _engine.pass[i].frame_direction  = 1;
      _engine.pass[i].frame_time_delta = 16667;
      _engine.pass[i].original_fps     = 60.0f;
      _engine.pass[i].rotation         = 0;
      _engine.pass[i].core_aspect      = aspect;
      _engine.pass[i].core_aspect_rot  = aspect;
   }

   MTLTextureDescriptor *td =
      [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                         width:width
                                                        height:height
                                                     mipmapped:NO];
   td.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;

   if (sizeChanged || !_engine.pass[0].rt.view)
   {
      if (sizeChanged)
      {
         for (int i = 0; i < _shader->passes; i++)
         {
            _engine.pass[i].rt.view       = nil;
            _engine.pass[i].feedback.view = nil;
         }
         _engine.frame.texture[0].view = nil;
      }
      [self updateRenderTargets];
   }

   if (!_engine.frame.texture[0].view || sizeChanged)
      [self initTexture:&_engine.frame.texture[0] descriptor:td];
   [_engine.frame.texture[0].view replaceRegion:MTLRegionMake2D(0, 0, width, height)
                                    mipmapLevel:0
                                      withBytes:pixels
                                    bytesPerRow:bytesPerRow];

   return YES;
}

- (id<MTLTexture> _Nullable)renderPasses
{
   if (!_shader || _shader->passes == 0)
      return nil;

   for (int i = 0; i < _shader->passes; i++)
   {
      if (_shader->pass[i].feedback)
      {
         lsp_texture_t tmp        = _engine.pass[i].feedback;
         _engine.pass[i].feedback = _engine.pass[i].rt;
         _engine.pass[i].rt       = tmp;
      }
   }

   id<MTLCommandBuffer> cb = [_queue commandBuffer];
   MTLRenderPassDescriptor *rpd = [MTLRenderPassDescriptor new];
   rpd.colorAttachments[0].loadAction  = MTLLoadActionDontCare;
   rpd.colorAttachments[0].storeAction = MTLStoreActionStore;

   id<MTLTexture> output = nil;

   for (int i = 0; i < _shader->passes; i++)
   {
      rpd.colorAttachments[0].texture = _engine.pass[i].rt.view;
      id<MTLRenderCommandEncoder> rce = [cb renderCommandEncoderWithDescriptor:rpd];

      [rce setRenderPipelineState:_engine.pass[i].pipeline];
      [rce setViewport:_engine.pass[i].viewport];

      for (unsigned j = 0; j < SLANG_CBUFFER_MAX; j++)
      {
         id<MTLBuffer> buffer      = _engine.pass[i].buffers[j];
         cbuffer_sem_t *buffer_sem = &_engine.pass[i].semantics.cbuffers[j];
         if (!(buffer_sem->stage_mask && buffer_sem->uniforms))
            continue;

         void *data             = buffer.contents;
         uniform_sem_t *uniform = buffer_sem->uniforms;
         while (uniform->size)
         {
            if (uniform->data)
               memcpy((uint8_t *)data + uniform->offset, uniform->data, uniform->size);
            uniform++;
         }

         if (buffer_sem->stage_mask & SLANG_STAGE_VERTEX_MASK)
            [rce setVertexBuffer:buffer offset:0 atIndex:buffer_sem->binding];
         if (buffer_sem->stage_mask & SLANG_STAGE_FRAGMENT_MASK)
            [rce setFragmentBuffer:buffer offset:0 atIndex:buffer_sem->binding];
      }

      __unsafe_unretained id<MTLTexture> textures[SLANG_NUM_BINDINGS] = {NULL};
      id<MTLSamplerState> samplers[SLANG_NUM_BINDINGS] = {NULL};

      texture_sem_t *texture_sem = _engine.pass[i].semantics.textures;
      while (texture_sem->stage_mask)
      {
         int binding        = (int)texture_sem->binding;
         id<MTLTexture> tex = (__bridge id<MTLTexture>)*(void **)texture_sem->texture_data;
         textures[binding]  = tex;
         samplers[binding]  = _samplers[texture_sem->filter][texture_sem->wrap];
         texture_sem++;
      }

      [rce setFragmentTextures:textures withRange:NSMakeRange(0, SLANG_NUM_BINDINGS)];
      [rce setFragmentSamplerStates:samplers withRange:NSMakeRange(0, SLANG_NUM_BINDINGS)];
      [rce setVertexBytes:_vertices length:sizeof(_vertices) atIndex:4];
      [rce drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
      [rce endEncoding];

      output = _engine.pass[i].rt.view;
   }

   [cb commit];
   [cb waitUntilCompleted];
   return output;
}

@end

#pragma mark - Public API

@implementation LibretroShaderPreview

+ (void)clearCache
{
   /* Preview pipelines are ephemeral (created/destroyed per call). Nothing to clear. */
}

static LibretroShaderPreviewContext *lsp_make_context(void)
{
   id<MTLDevice> device = MTLCreateSystemDefaultDevice();
   if (!device)
      return nil;

   LibretroShaderPreviewContext *ctx = [LibretroShaderPreviewContext new];
   ctx.device        = device;
   ctx.queue         = [device newCommandQueue];
   ctx.metalObjects  = [NSMutableArray array];
   [ctx initSamplers];
   [ctx setupDefaultVertices];
   return ctx;
}

static NSUInteger lsp_aligned_bytes_per_row(NSUInteger width, NSUInteger bytesPerPixel)
{
   NSUInteger row = width * bytesPerPixel;
   return ((row + 255u) / 256u) * 256u;
}

static BOOL lsp_texture_supports_direct_readback(id<MTLTexture> texture)
{
   if (texture.storageMode != MTLStorageModeShared)
      return NO;

   switch (texture.pixelFormat)
   {
      case MTLPixelFormatBGRA8Unorm:
      case MTLPixelFormatBGRA8Unorm_sRGB:
      case MTLPixelFormatRGBA8Unorm:
      case MTLPixelFormatRGBA8Unorm_sRGB:
         return YES;
      default:
         return NO;
   }
}

static CGBitmapInfo lsp_bitmap_info_for_texture(id<MTLTexture> texture)
{
   if (texture.pixelFormat == MTLPixelFormatRGBA8Unorm ||
       texture.pixelFormat == MTLPixelFormatRGBA8Unorm_sRGB)
      return kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big;

   return kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little;
}

static UIImage *lsp_image_from_bgra_pixels(const uint8_t *pixels, NSUInteger width, NSUInteger height, NSUInteger bpr, CGBitmapInfo bitmapInfo)
{
   CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
   CGContextRef cx = CGBitmapContextCreate((void *)pixels, width, height, 8, bpr, cs, bitmapInfo);
   CGColorSpaceRelease(cs);
   if (!cx)
      return nil;

   CGImageRef cg = CGBitmapContextCreateImage(cx);
   CGContextRelease(cx);
   if (!cg)
      return nil;

   UIImage *result = [UIImage imageWithCGImage:cg scale:1.0 orientation:UIImageOrientationUp];
   CGImageRelease(cg);
   return result;
}

static CIContext *lsp_preview_ci_context(void)
{
   static CIContext *context;
   static dispatch_once_t once;
   dispatch_once(&once, ^{
      context = [CIContext contextWithOptions:@{
         kCIContextCacheIntermediates : @NO,
         kCIContextUseSoftwareRenderer : @NO,
      }];
   });
   return context;
}

static UIImage *lsp_image_from_texture_via_core_image(id<MTLTexture> texture)
{
   CIImage *ciImage = [CIImage imageWithMTLTexture:texture
                                         options:@{ kCIImageColorSpace : [NSNull null] }];
   if (!ciImage)
      return nil;

   CGRect rect = CGRectMake(0, 0, texture.width, texture.height);
   CGImageRef cgImage = [lsp_preview_ci_context() createCGImage:ciImage fromRect:rect];
   if (!cgImage)
      return nil;

   UIImage *result = [UIImage imageWithCGImage:cgImage scale:1.0 orientation:UIImageOrientationUp];
   CGImageRelease(cgImage);
   return result;
}

static UIImage *lsp_image_from_texture(id<MTLTexture> texture)
{
   if (!texture || texture.width == 0 || texture.height == 0)
      return nil;

   if (!lsp_texture_supports_direct_readback(texture))
      return lsp_image_from_texture_via_core_image(texture);

   NSUInteger width  = texture.width;
   NSUInteger height = texture.height;
   CGBitmapInfo bitmapInfo = lsp_bitmap_info_for_texture(texture);
   NSUInteger bpr    = lsp_aligned_bytes_per_row(width, 4);
   uint8_t *pixels   = (uint8_t *)calloc(height, bpr);
   if (!pixels)
      return lsp_image_from_texture_via_core_image(texture);

   [texture getBytes:pixels
          bytesPerRow:bpr
           fromRegion:MTLRegionMake2D(0, 0, width, height)
          mipmapLevel:0];

   UIImage *result = lsp_image_from_bgra_pixels(pixels, width, height, bpr, bitmapInfo);
   free(pixels);
   if (result)
      return result;

   return lsp_image_from_texture_via_core_image(texture);
}

+ (UIImage *_Nullable)renderImage:(UIImage *_Nonnull)image shaderPath:(NSString *_Nonnull)shaderPath
{
   if (!image || shaderPath.length == 0)
      return nil;

   enum rarch_shader_type type = video_shader_parse_type(shaderPath.UTF8String);
   if (type == RARCH_SHADER_GLSL)
      return [LibretroShaderPreviewGL renderImage:image shaderPath:shaderPath];
   if (type != RARCH_SHADER_SLANG)
   {
      RARCH_WARN("[ShaderPreview]: Unsupported shader preview type %d\n", (int)type);
      return nil;
   }

   __block UIImage *result = nil;
   dispatch_sync(lsp_preview_queue(), ^{
      lsp_preview_ensure_config();

      NSUInteger width = 0, height = 0, bpr = 0;
      uint8_t *pixels = lsp_preview_copy_bgra_from_image(image, &width, &height, &bpr);
      if (pixels)
      {
         @autoreleasepool {
            LibretroShaderPreviewContext *ctx = lsp_make_context();
            if (ctx && [ctx loadShaderFromPath:shaderPath]
                  && [ctx uploadSourcePixels:pixels width:width height:height bytesPerRow:bpr])
            {
               id<MTLTexture> out = [ctx renderPasses];
               if (out)
                  result = lsp_image_from_texture(out);
            }
         }

         free(pixels);
      }

      lsp_preview_teardown_config();
   });

   return result;
}

@end
