// A minimal C interface over CascLib for reading files from a local WoW install.
#ifndef CASC_BRIDGE_H
#define CASC_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CascBridgeStorage CascBridgeStorage;

/// Opens local storage. `path` is the install folder, optionally followed by
/// "*product" (e.g. "/Applications/World of Warcraft*wowf"). Returns NULL on
/// failure and sets *error to the CascLib error code.
CascBridgeStorage *casc_bridge_open(const char *path, int *error);

/// Reads a whole file by FileDataID into a malloc'd buffer (free with
/// casc_bridge_free). Returns 0 on success, otherwise a CascLib error code.
int casc_bridge_read(CascBridgeStorage *storage, uint32_t file_data_id, uint8_t **data, size_t *size);

void casc_bridge_free(uint8_t *data);
void casc_bridge_close(CascBridgeStorage *storage);

#ifdef __cplusplus
}
#endif

#endif
