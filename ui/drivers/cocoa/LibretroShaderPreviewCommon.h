//
//  LibretroShaderPreviewCommon.h
//  Libretro
//
//  Copyright © 2025 Manic EMU. All rights reserved.
//

#import <UIKit/UIKit.h>

#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/// Shared serial queue for all shader preview backends (.slangp / .glslp).
dispatch_queue_t lsp_preview_queue(void);

/// Bootstrap / tear down temporary RetroArch config for off-app preview.
void lsp_preview_ensure_config(void);
void lsp_preview_teardown_config(void);

uint8_t *_Nullable lsp_preview_copy_bgra_from_image(UIImage *image,
      NSUInteger *outW, NSUInteger *outH, NSUInteger *outBPR);

NS_ASSUME_NONNULL_END
