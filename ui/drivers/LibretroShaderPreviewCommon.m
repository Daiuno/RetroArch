//
//  LibretroShaderPreviewCommon.m
//  Libretro
//
//  Copyright © 2025 Manic EMU. All rights reserved.
//

#import "LibretroShaderPreviewCommon.h"

#include "../../configuration.h"
#include "../../gfx/video_driver.h"
#include "../../runloop.h"

static bool lsp_preview_bootstrapped_config;
static const void *kLspPreviewQueueKey = &kLspPreviewQueueKey;

dispatch_queue_t lsp_preview_queue(void)
{
   static dispatch_queue_t queue;
   static dispatch_once_t once;
   dispatch_once(&once, ^{
      queue = dispatch_queue_create("com.manicemu.shader-preview", DISPATCH_QUEUE_SERIAL);
      dispatch_queue_set_specific(queue, kLspPreviewQueueKey, (void *)kLspPreviewQueueKey, NULL);
   });
   return queue;
}

void lsp_preview_ensure_config(void)
{
   if (config_get_ptr())
      return;

   retroarch_config_init();
   lsp_preview_bootstrapped_config = true;
}

static bool lsp_preview_libretro_runtime_active(void)
{
   runloop_state_t *runloop_st = runloop_state_get_ptr();
   if (runloop_st && (runloop_st->flags & RUNLOOP_FLAG_IS_INITED))
      return true;

   video_driver_state_t *video_st = video_state_get_ptr();
   if (video_st && (video_st->flags & VIDEO_FLAG_ACTIVE))
      return true;

   return false;
}

void lsp_preview_teardown_config(void)
{
   if (!lsp_preview_bootstrapped_config)
      return;

   if (lsp_preview_libretro_runtime_active())
      return;

   retroarch_config_deinit();
   lsp_preview_bootstrapped_config = false;
}

uint8_t *lsp_preview_copy_bgra_from_image(UIImage *image, NSUInteger *outW, NSUInteger *outH, NSUInteger *outBPR)
{
   CGImageRef cg = image.CGImage;
   if (!cg)
      return NULL;

   NSUInteger width  = CGImageGetWidth(cg);
   NSUInteger height = CGImageGetHeight(cg);
   if (width == 0 || height == 0)
      return NULL;

   NSUInteger bpr    = width * 4;
   uint8_t *pixels   = (uint8_t *)calloc(height, bpr);
   if (!pixels)
      return NULL;

   CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
   CGContextRef cx = CGBitmapContextCreate(pixels, width, height, 8, bpr, cs,
         kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
   CGColorSpaceRelease(cs);
   if (!cx)
   {
      free(pixels);
      return NULL;
   }

   CGContextDrawImage(cx, CGRectMake(0, 0, width, height), cg);
   CGContextRelease(cx);

   *outW   = width;
   *outH   = height;
   *outBPR = bpr;
   return pixels;
}
