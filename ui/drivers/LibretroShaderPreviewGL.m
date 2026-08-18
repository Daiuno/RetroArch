//
//  LibretroShaderPreviewGL.m
//  Libretro
//
//  Copyright © 2025 Manic EMU. All rights reserved.
//

#import "LibretroShaderPreviewGL.h"
#import "LibretroShaderPreviewCommon.h"

#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/ES3/glext.h>

#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "../../configuration.h"
#include "../../gfx/video_shader_parse.h"
#include "../../gfx/video_driver.h"
#include "../../gfx/common/gl2_common.h"
#include "../../gfx/drivers_shader/shader_glsl.h"
#include "../../verbosity.h"
#include <retro_math.h>
#include <glsym/glsym.h>

#if defined(HAVE_GLSL) && defined(HAVE_OPENGLES)

#define LSPG_SET_TEXTURE_COORDS(coords, xamt, yamt) \
   coords[2] = xamt; \
   coords[6] = xamt; \
   coords[5] = yamt; \
   coords[7] = yamt

typedef struct lspg_chain
{
   int fbo_pass;
   GLuint fbo[GFX_MAX_SHADERS];
   GLuint fbo_texture[GFX_MAX_SHADERS];
   struct gfx_fbo_scale fbo_scale[GFX_MAX_SHADERS];
} lspg_chain_t;

static const struct video_ortho lspg_default_ortho = {0, 1, 0, 1, -1, 1};

static const GLfloat lspg_vertexes_fbo[8] = {
   0, 0, 1, 0, 0, 1, 1, 1
};

static const GLfloat lspg_vertexes_flipped[8] = {
   0, 1, 1, 1, 0, 0, 1, 0
};

static const GLfloat lspg_tex_coords[8] = {
   0, 0, 1, 0, 0, 1, 1, 1
};

static const GLfloat lspg_white_color[16] = {
   1.0f, 1.0f, 1.0f, 1.0f,
   1.0f, 1.0f, 1.0f, 1.0f,
   1.0f, 1.0f, 1.0f, 1.0f,
   1.0f, 1.0f, 1.0f, 1.0f
};

static unsigned lspg_alignment(unsigned len)
{
   if (len % 4 == 0)
      return 4;
   if (len % 2 == 0)
      return 2;
   return 1;
}

static void lspg_set_projection(gl2_t *gl, bool allow_rotate)
{
   matrix_4x4_ortho(gl->mvp_no_rot,
         lspg_default_ortho.left, lspg_default_ortho.right,
         lspg_default_ortho.bottom, lspg_default_ortho.top,
         lspg_default_ortho.znear, lspg_default_ortho.zfar);

   if (!allow_rotate)
   {
      gl->mvp = gl->mvp_no_rot;
      return;
   }

   {
      static math_matrix_4x4 rot = {
         { 0.0f, 0.0f, 0.0f, 0.0f,
           0.0f, 0.0f, 0.0f, 0.0f,
           0.0f, 0.0f, 0.0f, 0.0f,
           0.0f, 0.0f, 0.0f, 1.0f }
      };
      float radians = (float)(M_PI * gl->rotation / 180.0);
      float cosine  = cosf(radians);
      float sine    = sinf(radians);

      MAT_ELEM_4X4(rot, 0, 0) = cosine;
      MAT_ELEM_4X4(rot, 0, 1) = -sine;
      MAT_ELEM_4X4(rot, 1, 0) = sine;
      MAT_ELEM_4X4(rot, 1, 1) = cosine;
      matrix_4x4_multiply(gl->mvp, rot, gl->mvp_no_rot);
   }
}

static void lspg_set_viewport(gl2_t *gl,
      unsigned vp_width, unsigned vp_height,
      bool force_full, bool allow_rotate)
{
   gl->vp.x      = 0;
   gl->vp.y      = 0;
   gl->vp.width  = vp_width;
   gl->vp.height = vp_height;

   if (!force_full)
   {
      gl->out_vp_width  = vp_width;
      gl->out_vp_height = vp_height;
   }

   glViewport(gl->vp.x, gl->vp.y, gl->vp.width, gl->vp.height);
   lspg_set_projection(gl, allow_rotate);
}

static void lspg_shader_scale(gl2_t *gl, struct gfx_fbo_scale *scale, unsigned idx)
{
   if (scale)
   {
      scale->flags &= ~FBO_SCALE_FLAG_VALID;
      gl->shader->shader_scale(gl->shader_data, idx, scale);
   }
}

static void lspg_update_input_tex_coords(gl2_t *gl, unsigned width, unsigned height)
{
   float xamt = (float)width / (float)gl->tex_w;
   float yamt = (float)height / (float)gl->tex_h;

   memcpy(gl->tex_info.coord, lspg_tex_coords, sizeof(lspg_tex_coords));
   LSPG_SET_TEXTURE_COORDS(gl->tex_info.coord, xamt, yamt);
}

static void lspg_recompute_pass_sizes(gl2_t *gl, lspg_chain_t *chain,
      unsigned width, unsigned height,
      unsigned vp_width, unsigned vp_height)
{
   size_t i;
   bool size_modified       = false;
   GLint max_size           = 0;
   unsigned last_width      = width;
   unsigned last_height     = height;
   unsigned last_max_width  = gl->tex_w;
   unsigned last_max_height = gl->tex_h;

   glGetIntegerv(GL_MAX_TEXTURE_SIZE, &max_size);

   for (i = 0; i < (size_t)chain->fbo_pass; i++)
   {
      struct video_fbo_rect *fbo_rect = &gl->fbo_rect[i];
      struct gfx_fbo_scale *fbo_scale = &chain->fbo_scale[i];

      switch (fbo_scale->type_x)
      {
         case RARCH_SCALE_INPUT:
            fbo_rect->img_width     = (unsigned)(fbo_scale->scale_x * last_width);
            fbo_rect->max_img_width = (unsigned)(last_max_width * fbo_scale->scale_x);
            break;
         case RARCH_SCALE_ABSOLUTE:
            fbo_rect->img_width = fbo_rect->max_img_width = fbo_scale->abs_x;
            break;
         case RARCH_SCALE_VIEWPORT:
            if (gl->rotation % 180 == 90)
               fbo_rect->img_width = fbo_rect->max_img_width =
                  (unsigned)(fbo_scale->scale_x * vp_height);
            else
               fbo_rect->img_width = fbo_rect->max_img_width =
                  (unsigned)(fbo_scale->scale_x * vp_width);
            break;
      }

      switch (fbo_scale->type_y)
      {
         case RARCH_SCALE_INPUT:
            fbo_rect->img_height     = (unsigned)(last_height * fbo_scale->scale_y);
            fbo_rect->max_img_height = (unsigned)(last_max_height * fbo_scale->scale_y);
            break;
         case RARCH_SCALE_ABSOLUTE:
            fbo_rect->img_height = fbo_rect->max_img_height = fbo_scale->abs_y;
            break;
         case RARCH_SCALE_VIEWPORT:
            if (gl->rotation % 180 == 90)
               fbo_rect->img_height = fbo_rect->max_img_height =
                  (unsigned)(fbo_scale->scale_y * vp_width);
            else
               fbo_rect->img_height = fbo_rect->max_img_height =
                  (unsigned)(fbo_scale->scale_y * vp_height);
            break;
      }

      if (fbo_rect->img_width > (unsigned)max_size)
      {
         size_modified       = true;
         fbo_rect->img_width = (unsigned)max_size;
      }
      if (fbo_rect->img_height > (unsigned)max_size)
      {
         size_modified        = true;
         fbo_rect->img_height = (unsigned)max_size;
      }
      if (fbo_rect->max_img_width > (unsigned)max_size)
      {
         size_modified           = true;
         fbo_rect->max_img_width = (unsigned)max_size;
      }
      if (fbo_rect->max_img_height > (unsigned)max_size)
      {
         size_modified            = true;
         fbo_rect->max_img_height = (unsigned)max_size;
      }

      if (size_modified)
         RARCH_WARN("[ShaderPreviewGL]: FBO exceeded GPU max size (%d). Resizing.\n", max_size);

      last_width      = fbo_rect->img_width;
      last_height     = fbo_rect->img_height;
      last_max_width  = fbo_rect->max_img_width;
      last_max_height = fbo_rect->max_img_height;
   }
}

static void lspg_apply_fbo_storage_sizes(gl2_t *gl, lspg_chain_t *chain)
{
   unsigned i;

   for (i = 0; i < (unsigned)chain->fbo_pass; i++)
   {
      /* Keep intermediate pass FBOs exact so multipass chains (e.g. Cartoom)
       * preserve full-bleed sizing through the pipeline. */
      gl->fbo_rect[i].width  = gl->fbo_rect[i].img_width;
      gl->fbo_rect[i].height = gl->fbo_rect[i].img_height;
   }

   if (chain->fbo_pass > 0)
   {
      unsigned last = (unsigned)chain->fbo_pass - 1;

      /* Match gl2: the last FBO before the screen pass uses pow2 storage so
       * final-pass TexCoord stays in 0..img/pow2 (light Film vignette). */
      gl->fbo_rect[last].width  = next_pow2(gl->fbo_rect[last].img_width);
      gl->fbo_rect[last].height = next_pow2(gl->fbo_rect[last].img_height);
   }
}

static void lspg_create_fbo_texture(gl2_t *gl, lspg_chain_t *chain,
      unsigned i, GLuint texture, bool video_smooth)
{
   bool smooth        = false;
   unsigned mip_level = i + 2;
   bool mipmapped     = gl->shader->mipmap_input(gl->shader_data, mip_level);
   GLuint base_filt   = video_smooth ? GL_LINEAR : GL_NEAREST;
   GLuint base_mip    = video_smooth ? GL_LINEAR_MIPMAP_LINEAR : GL_NEAREST_MIPMAP_NEAREST;
   GLenum min_filter  = mipmapped ? (GLenum)base_mip : (GLenum)base_filt;
   enum gfx_wrap_type wrap_type;
   GLenum wrap_enum;

   (void)chain;

   if (gl->shader->filter_type(gl->shader_data, i + 2, &smooth))
   {
      min_filter = mipmapped
         ? (GLenum)(smooth ? GL_LINEAR_MIPMAP_LINEAR : GL_NEAREST_MIPMAP_NEAREST)
         : (GLenum)(smooth ? GL_LINEAR : GL_NEAREST);
   }

   wrap_type = gl->shader->wrap_type(gl->shader_data, i + 2);
   switch (wrap_type)
   {
      case RARCH_WRAP_REPEAT:
         wrap_enum = GL_REPEAT;
         break;
      case RARCH_WRAP_MIRRORED_REPEAT:
         wrap_enum = GL_MIRRORED_REPEAT;
         break;
      default:
         wrap_enum = GL_CLAMP_TO_EDGE;
         break;
   }

   GL2_BIND_TEXTURE(texture, wrap_enum, min_filter, min_filter);
   glTexImage2D(GL_TEXTURE_2D, 0, RARCH_GL_INTERNAL_FORMAT32,
         gl->fbo_rect[i].width, gl->fbo_rect[i].height, 0,
         RARCH_GL_TEXTURE_TYPE32, RARCH_GL_FORMAT32, NULL);
}

static bool lspg_create_fbo_targets(lspg_chain_t *chain)
{
   size_t i;

   glBindTexture(GL_TEXTURE_2D, 0);
   glGenFramebuffers(chain->fbo_pass, chain->fbo);

   for (i = 0; i < (size_t)chain->fbo_pass; i++)
   {
      glBindFramebuffer(RARCH_GL_FRAMEBUFFER, chain->fbo[i]);
      glFramebufferTexture2D(RARCH_GL_FRAMEBUFFER,
            RARCH_GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
            chain->fbo_texture[i], 0);
      if (glCheckFramebufferStatus(RARCH_GL_FRAMEBUFFER) != RARCH_GL_FRAMEBUFFER_COMPLETE)
         return false;
   }

   return true;
}

static void lspg_deinit_fbo(gl2_t *gl, lspg_chain_t *chain)
{
   if (chain->fbo_pass > 0)
   {
      glDeleteFramebuffers(chain->fbo_pass, chain->fbo);
      glDeleteTextures(chain->fbo_pass, chain->fbo_texture);
      memset(chain->fbo, 0, sizeof(chain->fbo));
      memset(chain->fbo_texture, 0, sizeof(chain->fbo_texture));
      chain->fbo_pass = 0;
   }

   gl->flags &= ~GL2_FLAG_FBO_INITED;
}

static bool lspg_init_fbo(gl2_t *gl, lspg_chain_t *chain,
      unsigned src_width, unsigned src_height, bool video_smooth)
{
   int i;
   unsigned shader_info_num;
   struct gfx_fbo_scale scale, scale_last;

   shader_info_num = gl->shader->num_shaders(gl->shader_data);
   if (shader_info_num == 0)
      return false;

   lspg_shader_scale(gl, &scale, 1);
   lspg_shader_scale(gl, &scale_last, shader_info_num);

   if (shader_info_num == 1 && (!(scale.flags & FBO_SCALE_FLAG_VALID)))
      return false;

   chain->fbo_pass = (int)shader_info_num - 1;
   if (scale_last.flags & FBO_SCALE_FLAG_VALID)
      chain->fbo_pass++;

   if (!(scale.flags & FBO_SCALE_FLAG_VALID))
   {
      scale.scale_x  = 1.0f;
      scale.scale_y  = 1.0f;
      scale.type_x   = RARCH_SCALE_INPUT;
      scale.type_y   = RARCH_SCALE_INPUT;
      scale.flags   |= FBO_SCALE_FLAG_VALID;
   }

   chain->fbo_scale[0] = scale;
   for (i = 1; i < chain->fbo_pass; i++)
   {
      lspg_shader_scale(gl, &chain->fbo_scale[i], (unsigned)(i + 1));
      if (!(chain->fbo_scale[i].flags & FBO_SCALE_FLAG_VALID))
      {
         chain->fbo_scale[i].scale_x = chain->fbo_scale[i].scale_y = 1.0f;
         chain->fbo_scale[i].type_x  = chain->fbo_scale[i].type_y  = RARCH_SCALE_INPUT;
         chain->fbo_scale[i].flags  |= FBO_SCALE_FLAG_VALID;
      }
   }

   lspg_recompute_pass_sizes(gl, chain, src_width, src_height,
         gl->video_width, gl->video_height);

   lspg_apply_fbo_storage_sizes(gl, chain);

   glGenTextures(chain->fbo_pass, chain->fbo_texture);
   for (i = 0; i < chain->fbo_pass; i++)
      lspg_create_fbo_texture(gl, chain, (unsigned)i, chain->fbo_texture[i], video_smooth);

   if (!lspg_create_fbo_targets(chain))
   {
      glDeleteTextures(chain->fbo_pass, chain->fbo_texture);
      chain->fbo_pass = 0;
      return false;
   }

   gl->flags |= GL2_FLAG_FBO_INITED;
   return true;
}

static void lspg_render_pass(gl2_t *gl, unsigned pass_idx,
      const struct video_tex_info *tex_info,
      const struct video_tex_info *feedback_info,
      const struct video_tex_info *fbo_info,
      unsigned fbo_info_cnt,
      unsigned frame_width, unsigned frame_height,
      unsigned tex_width, unsigned tex_height,
      unsigned out_width, unsigned out_height,
      bool to_fbo)
{
   video_shader_ctx_params_t params;

   if (to_fbo)
      lspg_set_viewport(gl, out_width, out_height, true, false);
   else
      lspg_set_viewport(gl, out_width, out_height, false, true);

   gl->shader->use(gl, gl->shader_data, pass_idx, true);

   params.data          = gl;
   params.width         = frame_width;
   params.height        = frame_height;
   params.tex_width     = tex_width;
   params.tex_height    = tex_height;
   params.out_width     = gl->vp.width;
   params.out_height    = gl->vp.height;
   params.frame_counter = 1;
   params.info          = tex_info;
   params.prev_info     = gl->prev_info;
   params.feedback_info = feedback_info;
   params.fbo_info      = fbo_info;
   params.fbo_info_cnt  = fbo_info_cnt;

   gl->shader->set_params(&params, gl->shader_data);
   gl->coords.vertices = 4;
   gl->shader->set_coords(gl->shader_data, &gl->coords);
   gl->shader->set_mvp(gl->shader_data, &gl->mvp);

   glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}

static void lspg_prepare_render(gl2_t *gl, lspg_chain_t *chain,
      unsigned frame_width, unsigned frame_height)
{
   gl->out_vp_width  = gl->video_width;
   gl->out_vp_height = gl->video_height;

   if (gl->flags & GL2_FLAG_FBO_INITED)
      lspg_recompute_pass_sizes(gl, chain, frame_width, frame_height,
            gl->out_vp_width, gl->out_vp_height);
}

static void lspg_render_chain(gl2_t *gl, lspg_chain_t *chain,
      const struct video_tex_info *tex_info,
      const struct video_tex_info *feedback_info,
      GLuint output_fbo, unsigned output_width, unsigned output_height)
{
   int i;

   (void)output_width;
   (void)output_height;

   glDisable(GL_BLEND);
   glDisable(GL_DEPTH_TEST);
   glDisable(GL_CULL_FACE);
   glDisable(GL_DITHER);

   gl->coords.tex_coord = (float *)tex_info->coord;
   gl->coords.color     = (float *)lspg_white_color;

   if (gl->flags & GL2_FLAG_FBO_INITED)
   {
      static GLfloat fbo_tex_coords[8];
      struct video_tex_info fbo_tex_info[GFX_MAX_SHADERS];
      unsigned fbo_tex_info_cnt = 0;

      glBindTexture(GL_TEXTURE_2D, gl->texture[gl->tex_index]);
      glBindFramebuffer(RARCH_GL_FRAMEBUFFER, chain->fbo[0]);
      glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
      glClear(GL_COLOR_BUFFER_BIT);
      gl->coords.vertex = (float *)lspg_vertexes_fbo;
      lspg_render_pass(gl, 1, tex_info, feedback_info, NULL, 0,
            (unsigned)tex_info->input_size[0], (unsigned)tex_info->input_size[1],
            gl->tex_w, gl->tex_h,
            gl->fbo_rect[0].img_width, gl->fbo_rect[0].img_height,
            true);

      gl->coords.tex_coord = fbo_tex_coords;

      for (i = 1; i < chain->fbo_pass; i++)
      {
         const struct video_fbo_rect *rect      = &gl->fbo_rect[i];
         const struct video_fbo_rect *prev_rect = &gl->fbo_rect[i - 1];
         struct video_tex_info *fbo_info        = &fbo_tex_info[i - 1];
         GLfloat xamt = (GLfloat)prev_rect->img_width / prev_rect->width;
         GLfloat yamt = (GLfloat)prev_rect->img_height / prev_rect->height;

         memcpy(fbo_tex_coords, lspg_tex_coords, sizeof(lspg_tex_coords));
         LSPG_SET_TEXTURE_COORDS(fbo_tex_coords, xamt, yamt);
         fbo_info->tex           = chain->fbo_texture[i - 1];
         fbo_info->input_size[0] = prev_rect->img_width;
         fbo_info->input_size[1] = prev_rect->img_height;
         fbo_info->tex_size[0]   = prev_rect->width;
         fbo_info->tex_size[1]   = prev_rect->height;
         memcpy(fbo_info->coord, fbo_tex_coords, sizeof(fbo_tex_coords));
         fbo_tex_info_cnt++;

         glBindFramebuffer(RARCH_GL_FRAMEBUFFER, chain->fbo[i]);
         glBindTexture(GL_TEXTURE_2D, chain->fbo_texture[i - 1]);
         glClear(GL_COLOR_BUFFER_BIT);
         gl->coords.vertex = (float *)lspg_vertexes_fbo;
         lspg_render_pass(gl, (unsigned)(i + 1), tex_info, feedback_info,
               fbo_tex_info, fbo_tex_info_cnt,
               prev_rect->img_width, prev_rect->img_height,
               prev_rect->width, prev_rect->height,
               rect->img_width, rect->img_height,
               true);
      }

      {
         const struct video_fbo_rect *prev_rect = &gl->fbo_rect[chain->fbo_pass - 1];
         struct video_tex_info *fbo_info        = &fbo_tex_info[chain->fbo_pass - 1];
         GLfloat xamt = (GLfloat)prev_rect->img_width / prev_rect->width;
         GLfloat yamt = (GLfloat)prev_rect->img_height / prev_rect->height;

         memcpy(fbo_tex_coords, lspg_tex_coords, sizeof(lspg_tex_coords));
         LSPG_SET_TEXTURE_COORDS(fbo_tex_coords, xamt, yamt);
         fbo_info->tex           = chain->fbo_texture[chain->fbo_pass - 1];
         fbo_info->input_size[0] = prev_rect->img_width;
         fbo_info->input_size[1] = prev_rect->img_height;
         fbo_info->tex_size[0]   = prev_rect->width;
         fbo_info->tex_size[1]   = prev_rect->height;
         memcpy(fbo_info->coord, fbo_tex_coords, sizeof(fbo_tex_coords));
         fbo_tex_info_cnt++;

         glActiveTexture(GL_TEXTURE0);
         glBindFramebuffer(RARCH_GL_FRAMEBUFFER, output_fbo);
         glBindTexture(GL_TEXTURE_2D, chain->fbo_texture[chain->fbo_pass - 1]);
         glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
         glClear(GL_COLOR_BUFFER_BIT);
         gl->coords.vertex    = (float *)gl->vertex_ptr;
         gl->coords.tex_coord = fbo_tex_coords;
         lspg_render_pass(gl, (unsigned)(chain->fbo_pass + 1), tex_info, feedback_info,
               fbo_tex_info, fbo_tex_info_cnt,
               prev_rect->img_width, prev_rect->img_height,
               prev_rect->width, prev_rect->height,
               gl->video_width, gl->video_height,
               false);
      }

      gl->coords.tex_coord = (float *)tex_info->coord;
   }
   else
   {
      glBindFramebuffer(RARCH_GL_FRAMEBUFFER, output_fbo);
      glBindTexture(GL_TEXTURE_2D, gl->texture[gl->tex_index]);
      glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
      glClear(GL_COLOR_BUFFER_BIT);
      gl->coords.vertex = (float *)gl->vertex_ptr;
      gl->coords.tex_coord = (float *)tex_info->coord;
      lspg_render_pass(gl, 1, tex_info, feedback_info, NULL, 0,
            (unsigned)tex_info->input_size[0], (unsigned)tex_info->input_size[1],
            gl->tex_w, gl->tex_h,
            gl->video_width, gl->video_height,
            false);
   }

   glFinish();
}

@interface LibretroShaderPreviewGLContext : NSObject
@property (nonatomic, strong) EAGLContext *glContext;
@property (nonatomic, copy) NSString *shaderPath;
@property (nonatomic, assign) unsigned imageWidth;
@property (nonatomic, assign) unsigned imageHeight;
@property (nonatomic, assign) gl2_t glHost;
@property (nonatomic, assign) lspg_chain_t chain;
@property (nonatomic, assign) void *shaderData;
@property (nonatomic, assign) GLuint sourceTexture;
@property (nonatomic, assign) GLuint outputFBO;
@property (nonatomic, assign) GLuint outputTexture;
@property (nonatomic, assign) uint8_t *convBuffer;
@property (nonatomic, assign) size_t convBufferSize;
@end

@implementation LibretroShaderPreviewGLContext

- (void)dealloc
{
   EAGLContext *prev = [EAGLContext currentContext];

   if (_glContext)
      [EAGLContext setCurrentContext:_glContext];

   if (_shaderData)
   {
      gl_glsl_backend.deinit(_shaderData);
      _shaderData = NULL;
   }

   lspg_deinit_fbo(&_glHost, &_chain);

   if (_outputFBO)
   {
      glDeleteFramebuffers(1, &_outputFBO);
      _outputFBO = 0;
   }
   if (_outputTexture)
   {
      glDeleteTextures(1, &_outputTexture);
      _outputTexture = 0;
   }
   if (_glHost.textures > 0)
   {
      glDeleteTextures(_glHost.textures, _glHost.texture);
      _glHost.textures = 0;
      _sourceTexture = 0;
   }
   else if (_sourceTexture)
   {
      glDeleteTextures(1, &_sourceTexture);
      _sourceTexture = 0;
   }

   glFinish();

   if (prev != _glContext)
      [EAGLContext setCurrentContext:prev];
   else
      [EAGLContext setCurrentContext:nil];

   _glContext = nil;
   free(_convBuffer);
}

- (void)teardownGLResources
{
   EAGLContext *prev = [EAGLContext currentContext];
   if (_glContext)
      [EAGLContext setCurrentContext:_glContext];

   lspg_deinit_fbo(&_glHost, &_chain);

   if (_outputFBO)
   {
      glDeleteFramebuffers(1, &_outputFBO);
      _outputFBO = 0;
   }
   if (_outputTexture)
   {
      glDeleteTextures(1, &_outputTexture);
      _outputTexture = 0;
   }
   if (_glHost.textures > 0)
   {
      glDeleteTextures(_glHost.textures, _glHost.texture);
      _glHost.textures = 0;
      _sourceTexture = 0;
   }
   else if (_sourceTexture)
   {
      glDeleteTextures(1, &_sourceTexture);
      _sourceTexture = 0;
   }

   glFinish();

   if (prev != _glContext)
      [EAGLContext setCurrentContext:prev];
   else if ([EAGLContext currentContext] == _glContext)
      [EAGLContext setCurrentContext:nil];
}

- (BOOL)ensureGLContext
{
   if (!_glContext)
   {
      _glContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
      if (!_glContext)
         _glContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
      if (!_glContext)
         return NO;
   }

   if ([EAGLContext currentContext] != _glContext)
      [EAGLContext setCurrentContext:_glContext];

   return YES;
}

- (BOOL)ensureOutputTargetWidth:(unsigned)width height:(unsigned)height
{
   if (_outputFBO && _imageWidth == width && _imageHeight == height)
      return YES;

   if (_outputFBO)
   {
      glDeleteFramebuffers(1, &_outputFBO);
      glDeleteTextures(1, &_outputTexture);
      _outputFBO = 0;
      _outputTexture = 0;
   }

   glGenTextures(1, &_outputTexture);
   GL2_BIND_TEXTURE(_outputTexture, GL_CLAMP_TO_EDGE, GL_LINEAR, GL_LINEAR);
   glTexImage2D(GL_TEXTURE_2D, 0, RARCH_GL_INTERNAL_FORMAT32,
         width, height, 0,
         RARCH_GL_TEXTURE_TYPE32, RARCH_GL_FORMAT32, NULL);

   glGenFramebuffers(1, &_outputFBO);
   glBindFramebuffer(RARCH_GL_FRAMEBUFFER, _outputFBO);
   glFramebufferTexture2D(RARCH_GL_FRAMEBUFFER,
         RARCH_GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, _outputTexture, 0);
   if (glCheckFramebufferStatus(RARCH_GL_FRAMEBUFFER) != RARCH_GL_FRAMEBUFFER_COMPLETE)
      return NO;

   _imageWidth  = width;
   _imageHeight = height;
   return YES;
}

- (BOOL)setupHostForWidth:(unsigned)width height:(unsigned)height
{
   settings_t *settings = config_get_ptr();
   bool video_smooth    = settings ? settings->bools.video_smooth : true;
   unsigned tex_w       = next_pow2(width);
   unsigned tex_h       = next_pow2(height);
   unsigned tex_count;
   unsigned i;

   memset(&_glHost, 0, sizeof(_glHost));
   _glHost.shader       = &gl_glsl_backend;
   _glHost.shader_data  = _shaderData;
   _glHost.renderchain_data = &_chain;
   _glHost.video_width  = width;
   _glHost.video_height = height;
   _glHost.out_vp_width = width;
   _glHost.out_vp_height = height;
   _glHost.tex_w        = tex_w;
   _glHost.tex_h        = tex_h;
   _glHost.base_size    = 4;
   _glHost.rotation     = 0;
   _glHost.vertex_ptr   = (const float *)lspg_vertexes_flipped;
   _glHost.internal_fmt = RARCH_GL_INTERNAL_FORMAT32;
   _glHost.texture_type = RARCH_GL_TEXTURE_TYPE32;
   _glHost.texture_fmt  = RARCH_GL_FORMAT32;
   _glHost.wrap_mode    = GL_CLAMP_TO_EDGE;
   _glHost.tex_mag_filter = video_smooth ? GL_LINEAR : GL_NEAREST;
   _glHost.tex_min_filter = video_smooth ? GL_LINEAR : GL_NEAREST;
   _glHost.flags       |= (GL2_FLAG_HAVE_FBO | GL2_FLAG_HAVE_MIPMAP);

   tex_count = _glHost.shader->get_prev_textures(_shaderData) + 1;
   if (tex_count < 1)
      tex_count = 1;
   _glHost.textures = tex_count;

   glGenTextures(_glHost.textures, _glHost.texture);
   for (i = 0; i < _glHost.textures; i++)
   {
      GL2_BIND_TEXTURE(_glHost.texture[i], _glHost.wrap_mode,
            _glHost.tex_mag_filter, _glHost.tex_min_filter);
      glTexImage2D(GL_TEXTURE_2D, 0, _glHost.internal_fmt,
            tex_w, tex_h, 0, _glHost.texture_type, _glHost.texture_fmt, NULL);
      _glHost.prev_info[i].tex = _glHost.texture[i];
      _glHost.prev_info[i].input_size[0] = (float)tex_w;
      _glHost.prev_info[i].input_size[1] = (float)tex_h;
      _glHost.prev_info[i].tex_size[0]   = (float)tex_w;
      _glHost.prev_info[i].tex_size[1]   = (float)tex_h;
      memcpy(_glHost.prev_info[i].coord, lspg_tex_coords, sizeof(lspg_tex_coords));
   }

   _glHost.tex_index = 0;
   _sourceTexture    = _glHost.texture[_glHost.tex_index];

   _glHost.coords.vertex    = (float *)lspg_vertexes_fbo;
   _glHost.coords.color     = (float *)lspg_white_color;
   lspg_update_input_tex_coords(&_glHost, width, height);
   _glHost.coords.tex_coord = _glHost.tex_info.coord;

   lspg_set_projection(&_glHost, true);

   memset(&_chain, 0, sizeof(_chain));
   if (lspg_init_fbo(&_glHost, &_chain, width, height, video_smooth))
      return YES;

   /* Single-pass presets without FBO scaling render directly. */
   return _glHost.shader->num_shaders(_shaderData) >= 1;
}

- (BOOL)loadShaderFromPath:(NSString *)path width:(unsigned)width height:(unsigned)height
{
   [self teardownGLResources];

   if (![self ensureGLContext])
      return NO;

   gl_glsl_set_context_type(false, 3, 0);

   _shaderData = gl_glsl_backend.init(NULL, path.UTF8String);
   if (!_shaderData)
      return NO;

   _shaderPath = [path copy];
   return [self setupHostForWidth:width height:height]
      && [self ensureOutputTargetWidth:width height:height];
}

- (BOOL)resizeForWidth:(unsigned)width height:(unsigned)height
{
   if (_shaderData
         && _imageWidth == width && _imageHeight == height
         && _outputFBO && (_glHost.flags & GL2_FLAG_FBO_INITED))
      return YES;

   if (!_shaderData || ![self ensureGLContext])
      return NO;

   [self teardownGLResources];
   return [self setupHostForWidth:width height:height]
      && [self ensureOutputTargetWidth:width height:height];
}

- (BOOL)uploadSourcePixels:(const uint8_t *)pixels
                     width:(unsigned)width
                    height:(unsigned)height
               bytesPerRow:(unsigned)bpr
{
   if (!pixels || !_sourceTexture)
      return NO;

   if (![self ensureGLContext])
      return NO;

   glBindTexture(GL_TEXTURE_2D, _sourceTexture);
   glPixelStorei(GL_UNPACK_ALIGNMENT, (GLint)lspg_alignment(width * 4));

   if (width * 4 != bpr)
   {
      size_t needed = (size_t)width * height * 4;
      if (_convBufferSize < needed)
      {
         free(_convBuffer);
         _convBuffer = (uint8_t *)malloc(needed);
         _convBufferSize = needed;
      }
      if (!_convBuffer)
         return NO;

      for (unsigned y = 0; y < height; y++)
         memcpy(_convBuffer + y * width * 4, pixels + y * bpr, width * 4);

      glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, width, height,
            _glHost.texture_type, _glHost.texture_fmt, _convBuffer);
   }
   else
   {
      glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, width, height,
            _glHost.texture_type, _glHost.texture_fmt, pixels);
   }

   _glHost.tex_info.tex           = _sourceTexture;
   _glHost.tex_info.input_size[0] = width;
   _glHost.tex_info.input_size[1] = height;
   _glHost.tex_info.tex_size[0]   = _glHost.tex_w;
   _glHost.tex_info.tex_size[1]   = _glHost.tex_h;
   lspg_update_input_tex_coords(&_glHost, width, height);
   _glHost.coords.tex_coord = _glHost.tex_info.coord;
   return YES;
}

- (UIImage *)renderToImage
{
   if (![self ensureGLContext])
      return nil;

   unsigned frame_width  = (unsigned)_glHost.tex_info.input_size[0];
   unsigned frame_height = (unsigned)_glHost.tex_info.input_size[1];
   lspg_prepare_render(&_glHost, &_chain, frame_width, frame_height);

   struct video_tex_info feedback = _glHost.tex_info;
   lspg_render_chain(&_glHost, &_chain, &_glHost.tex_info, &feedback,
         _outputFBO, _imageWidth, _imageHeight);

   {
      unsigned width  = _imageWidth;
      unsigned height = _imageHeight;
      unsigned bpr    = width * 4;
      uint8_t *pixels = (uint8_t *)calloc(height, bpr);
      uint8_t *flipped;
      CGColorSpaceRef cs;
      CGContextRef cx;
      CGImageRef cg;
      UIImage *result;

      if (!pixels)
         return nil;

      glBindFramebuffer(RARCH_GL_FRAMEBUFFER, _outputFBO);
      glReadPixels(0, 0, (GLsizei)width, (GLsizei)height,
            GL_RGBA, GL_UNSIGNED_BYTE, pixels);

      flipped = (uint8_t *)malloc((size_t)bpr * height);
      if (!flipped)
      {
         free(pixels);
         return nil;
      }

      for (unsigned y = 0; y < height; y++)
         memcpy(flipped + (size_t)(height - 1 - y) * bpr,
               pixels + (size_t)y * bpr, bpr);
      free(pixels);

      cs = CGColorSpaceCreateDeviceRGB();
      cx = CGBitmapContextCreate(flipped, width, height, 8, bpr, cs,
            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
      CGColorSpaceRelease(cs);
      if (!cx)
      {
         free(flipped);
         return nil;
      }

      cg = CGBitmapContextCreateImage(cx);
      CGContextRelease(cx);
      free(flipped);
      if (!cg)
         return nil;

      result = [UIImage imageWithCGImage:cg scale:1.0 orientation:UIImageOrientationUp];
      CGImageRelease(cg);
      return result;
   }
}

@end

#endif /* HAVE_GLSL && HAVE_OPENGLES */

@implementation LibretroShaderPreviewGL

+ (void)clearCache
{
   /* Preview pipelines are ephemeral (created/destroyed per call). Nothing to clear. */
}

+ (UIImage *_Nullable)renderImage:(UIImage *_Nonnull)image shaderPath:(NSString *_Nonnull)shaderPath
{
#if defined(HAVE_GLSL) && defined(HAVE_OPENGLES)
   if (!image || shaderPath.length == 0)
      return nil;

   enum rarch_shader_type type = video_shader_parse_type(shaderPath.UTF8String);
   if (type != RARCH_SHADER_GLSL)
      return nil;

   __block UIImage *result = nil;
   EAGLContext *previousContext = [EAGLContext currentContext];

   @autoreleasepool {
   dispatch_sync(lsp_preview_queue(), ^{
      lsp_preview_ensure_config();

      NSUInteger width = 0, height = 0, bpr = 0;
      uint8_t *pixels = lsp_preview_copy_bgra_from_image(image, &width, &height, &bpr);
      if (pixels)
      {
         @autoreleasepool {
            LibretroShaderPreviewGLContext *ctx = [LibretroShaderPreviewGLContext new];
            if (ctx
                  && [ctx loadShaderFromPath:shaderPath
                                       width:(unsigned)width
                                      height:(unsigned)height]
                  && [ctx uploadSourcePixels:pixels
                                       width:(unsigned)width
                                      height:(unsigned)height
                                 bytesPerRow:(unsigned)bpr])
               result = [ctx renderToImage];
         }

         free(pixels);
      }

      lsp_preview_teardown_config();
   });
   }

   if (previousContext)
      [EAGLContext setCurrentContext:previousContext];
   else
      [EAGLContext setCurrentContext:nil];

   return result;
#else
   (void)image;
   (void)shaderPath;
   RARCH_WARN("[ShaderPreviewGL]: GLSL preview is unavailable in this build.\n");
   return nil;
#endif
}

@end
