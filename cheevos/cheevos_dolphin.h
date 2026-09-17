/* RetroArch - A frontend for libretro.
 *
 * DiscIO hashing for Dolphin cores only. Other systems must keep the default
 * rcheevos filereader (fopen / CD hooks).
 */

#ifndef __RARCH_CHEEVOS_DOLPHIN_H
#define __RARCH_CHEEVOS_DOLPHIN_H

#include <boolean.h>
#include <stdint.h>

#include <retro_common_api.h>

#include "../deps/rcheevos/include/rc_client.h"

RETRO_BEGIN_DECLS

void rcheevos_dolphin_set_core_path(const char *path);

bool rcheevos_is_dolphin_core(void);

/// Installs a DiscIO filereader on this client only when a GC/Wii disc opens.
/// Returns the console id to pass to identify (16/19, or requested_console_id).
uint32_t rcheevos_dolphin_prepare_client(rc_client_t *client, const char *path,
      uint32_t requested_console_id);

/// Clears hash callbacks on this client so later identifies use default I/O.
void rcheevos_dolphin_finish_client(rc_client_t *client);

RETRO_END_DECLS

#endif
