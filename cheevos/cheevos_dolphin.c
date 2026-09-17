/* RetroArch - A frontend for libretro.
 *
 * Loads dolphin_ra_volume_* from dolphin.libretro and binds them as
 * per-client rcheevos hash callbacks. Never touches the global filereader.
 */

#ifdef HAVE_CONFIG_H
#include "../config.h"
#endif

#include "cheevos_dolphin.h"

#include <string.h>

#include <dynamic/dylib.h>
#include <file/file_path.h>
#include <string/stdstring.h>

#include "../deps/rcheevos/include/rc_consoles.h"
#include "../deps/rcheevos/include/rc_hash.h"
#include "../paths.h"
#include "../runloop.h"
#include "../verbosity.h"

#include "cheevos_locals.h"

typedef void *(*dolphin_ra_open_t)(const char *path);
typedef void (*dolphin_ra_seek_t)(void *handle, int64_t offset, int origin);
typedef int64_t (*dolphin_ra_tell_t)(void *handle);
typedef size_t (*dolphin_ra_read_t)(void *handle, void *buffer, size_t requested_bytes);
typedef void (*dolphin_ra_close_t)(void *handle);
typedef uint32_t (*dolphin_ra_console_id_t)(void *handle);

static struct
{
   dolphin_ra_open_t open;
   dolphin_ra_seek_t seek;
   dolphin_ra_tell_t tell;
   dolphin_ra_read_t read;
   dolphin_ra_close_t close;
   dolphin_ra_console_id_t console_id;
   dylib_t lib;
   bool lib_owned;
} s_dolphin_ra;

static char s_dolphin_core_path[PATH_MAX_LENGTH];

void rcheevos_dolphin_set_core_path(const char *path)
{
   if (!path)
   {
      s_dolphin_core_path[0] = '\0';
      return;
   }
   strlcpy(s_dolphin_core_path, path, sizeof(s_dolphin_core_path));
}

bool rcheevos_is_dolphin_core(void)
{
   const struct retro_system_info *sysinfo = &runloop_state_get_ptr()->system.info;
   const char *name = sysinfo->library_name;

   if (string_is_empty(name))
      return false;

   return string_is_equal(name, "dolphin-emu") || string_is_equal(name, "Dolphin");
}

static bool dolphin_ra_resolve_from(dylib_t lib)
{
   dolphin_ra_open_t open;

   if (!lib)
      return false;

   open = (dolphin_ra_open_t)dylib_proc(lib, "dolphin_ra_volume_open");
   if (!open)
      return false;

   s_dolphin_ra.open = open;
   s_dolphin_ra.seek = (dolphin_ra_seek_t)dylib_proc(lib, "dolphin_ra_volume_seek");
   s_dolphin_ra.tell = (dolphin_ra_tell_t)dylib_proc(lib, "dolphin_ra_volume_tell");
   s_dolphin_ra.read = (dolphin_ra_read_t)dylib_proc(lib, "dolphin_ra_volume_read");
   s_dolphin_ra.close = (dolphin_ra_close_t)dylib_proc(lib, "dolphin_ra_volume_close");
   s_dolphin_ra.console_id = (dolphin_ra_console_id_t)dylib_proc(lib, "dolphin_ra_volume_console_id");

   if (!s_dolphin_ra.seek || !s_dolphin_ra.tell || !s_dolphin_ra.read ||
         !s_dolphin_ra.close || !s_dolphin_ra.console_id)
   {
      memset(&s_dolphin_ra, 0, sizeof(s_dolphin_ra));
      return false;
   }

   return true;
}

static bool dolphin_ra_resolve(void)
{
   dylib_t lib;

   if (s_dolphin_ra.open)
      return true;

   /* Independent dlopen so pointers stay valid after the running core unloads. */
   if (string_is_empty(s_dolphin_core_path))
   {
      const char *core_path = path_get(RARCH_PATH_CORE);
      if (!string_is_empty(core_path) && rcheevos_is_dolphin_core())
         strlcpy(s_dolphin_core_path, core_path, sizeof(s_dolphin_core_path));
   }

   if (string_is_empty(s_dolphin_core_path))
      return false;

   lib = dylib_load(s_dolphin_core_path);
   if (!lib)
   {
      CHEEVOS_LOG(RCHEEVOS_TAG "Dolphin RA hash: failed to load %s\n", s_dolphin_core_path);
      return false;
   }

   if (!dolphin_ra_resolve_from(lib))
   {
      CHEEVOS_LOG(RCHEEVOS_TAG "Dolphin RA hash: core lacks dolphin_ra_volume_* exports\n");
      dylib_close(lib);
      return false;
   }

   s_dolphin_ra.lib = lib;
   s_dolphin_ra.lib_owned = true;
   return true;
}

static void dolphin_ra_install_filereader(rc_client_t *client)
{
   rc_hash_callbacks_t callbacks;

   memset(&callbacks, 0, sizeof(callbacks));
   callbacks.filereader.open = s_dolphin_ra.open;
   callbacks.filereader.seek = s_dolphin_ra.seek;
   callbacks.filereader.tell = s_dolphin_ra.tell;
   callbacks.filereader.read = s_dolphin_ra.read;
   callbacks.filereader.close = s_dolphin_ra.close;
   rc_client_set_hash_callbacks(client, &callbacks);
}

uint32_t rcheevos_dolphin_prepare_client(rc_client_t *client, const char *path,
      uint32_t requested_console_id)
{
   void *volume;
   uint32_t disc_id;

   if (!client || string_is_empty(path))
      return requested_console_id;

   if (!dolphin_ra_resolve())
      return requested_console_id;

   volume = s_dolphin_ra.open(path);
   if (!volume)
      return requested_console_id;

   disc_id = s_dolphin_ra.console_id(volume);
   s_dolphin_ra.close(volume);

   if (disc_id != RC_CONSOLE_GAMECUBE && disc_id != RC_CONSOLE_WII)
      return requested_console_id;

   dolphin_ra_install_filereader(client);
   CHEEVOS_LOG(RCHEEVOS_TAG "Dolphin RA hash: DiscIO filereader console=%u path=%s\n",
         disc_id, path);
   return disc_id;
}

void rcheevos_dolphin_finish_client(rc_client_t *client)
{
   rc_hash_callbacks_t callbacks;

   if (!client)
      return;

   memset(&callbacks, 0, sizeof(callbacks));
   rc_client_set_hash_callbacks(client, &callbacks);
}
